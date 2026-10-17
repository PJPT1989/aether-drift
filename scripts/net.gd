extends Node
## Autoload `Net`: online races with friends. One player hosts a room and runs the race (the
## bots, the world events, the results); friends join with the room code or an invite link and
## drive their own car on their own computer. Cars and events travel between the players over
## Godot's high-level multiplayer:
##   in the browser  WebRTC, peer to peer. The players' browsers find each other through a
##                   signalling channel (tools/web/aether-net.js: on the shop page a Supabase
##                   Realtime channel per room, elsewhere a BroadcastChannel between tabs).
##   on a computer   ENet; the room code is the host's address (IP).
## Each player is the authority for their own car and sends its state 20 times a second; the
## host sends everyone a snapshot of all cars, starts world events and declares the results.

signal lobby_changed
signal status_changed
signal race_start(cfg: Dictionary)
signal go
signal results_in(results: Array)
signal lobby_again
signal left(reason: String)

enum { OFF, HOST, CLIENT }
const PORT := 24680
const MAX_PLAYERS := 8
const SEND_RATE := 20.0
const STRIDE := 18                  # floats per car in a state message (Car.net_pack)
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478"]}]}
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const LAP_CHOICES := [1, 2, 3, 5]

var role := OFF
var code := ""
var my_name := "Racer"
var status := ""
var players := {}                   # peer id -> {"name": String, "team": int}
var track := 0
var bots := true
var laps := 3
var in_race := false
var race: Race
var test_args: PackedStringArray = []   # automated tests: host, join=CODE, bot, start=N, laps=N

var _js: JavaScriptObject
var _peer: MultiplayerPeer
var _conns := {}                    # WebRTC connections by peer id
var _hello_t := 0.0
var _join_wait := 0.0
var _send_t := 0.0
var _loaded := {}
var _go_wait := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _fail("The host left the room."))
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("AetherNet")
	var cfg := ConfigFile.new()
	if cfg.load(Game.SETTINGS_PATH) == OK:
		my_name = str(cfg.get_value("net", "name", my_name))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net="):
			test_args = a.substr(6).split(",")
	if _js and test_args.is_empty():
		var t := str(_js.testArgs())
		if t != "":
			test_args = t.split(",")


func active() -> bool:
	return role != OFF


func is_host() -> bool:
	return role == HOST


func is_client() -> bool:
	return role == CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1


## The room code from an invite link the page was opened with, or "".
func invite_code() -> String:
	return str(_js.roomFromUrl()) if _js else ""


## Copies the room code (friends type it on the multiplayer screen).
func copy_invite() -> void:
	if _js:
		_js.copy(code)
	else:
		DisplayServer.clipboard_set(code)


func test_flag(name: String) -> String:
	for a in test_args:
		if a == name:
			return "1"
		if a.begins_with(name + "="):
			return a.get_slice("=", 1)
	return ""


func set_player_name(n: String) -> void:
	n = n.strip_edges().substr(0, 16)
	my_name = n if n != "" else "Racer"
	var cfg := ConfigFile.new()
	cfg.load(Game.SETTINGS_PATH)
	cfg.set_value("net", "name", my_name)
	cfg.save(Game.SETTINGS_PATH)


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


# --- rooms ------------------------------------------------------------------------------

func host() -> void:
	leave()
	role = HOST
	players = {1: {"name": my_name, "team": Game.TEAMS.size() - 1 - randi() % 3}}
	if _js:
		code = ""
		for i in 5:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		# automated tests can fix the code (host=CODE); a real host keeps the random one
		var fixed := test_flag("host")
		if fixed != "" and fixed != "1":
			code = fixed
		var p := WebRTCMultiplayerPeer.new()
		p.create_server()
		_peer = p
		_js.open(code)
	else:
		var p := ENetMultiplayerPeer.new()
		var err := p.create_server(PORT, MAX_PLAYERS)
		if err != OK:
			role = OFF
			_set_status("Could not open a room on port %d." % PORT)
			return
		_peer = p
		code = _local_ip()
	multiplayer.multiplayer_peer = _peer
	_set_status("Room open. Share the code with your friends.")
	lobby_changed.emit()


func join(room: String) -> void:
	leave()
	room = room.strip_edges()
	if room == "":
		_set_status("Type the room code first.")
		return
	role = CLIENT
	players = {}
	if _js:
		code = room.to_upper()
		var id := randi_range(2, 2147483646)
		var p := WebRTCMultiplayerPeer.new()
		p.create_client(id)
		_peer = p
		multiplayer.multiplayer_peer = _peer
		_js.open(code)
		_new_conn(1)
		_hello_t = 0.0
		_join_wait = 20.0
	else:
		code = room
		var p := ENetMultiplayerPeer.new()
		if p.create_client(room, PORT) != OK:
			role = OFF
			_set_status("That is not an address.")
			return
		_peer = p
		multiplayer.multiplayer_peer = _peer
		_join_wait = 12.0
	_set_status("Looking for room %s..." % code)


func leave() -> void:
	if _js:
		_js.close()
	for c in _conns.values():
		c.close()
	_conns.clear()
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = OFF
	in_race = false
	race = null
	players = {}
	_join_wait = 0.0
	_go_wait = -1.0


func _fail(reason: String) -> void:
	if role == OFF:
		return
	leave()
	_set_status(reason)
	left.emit(reason)


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"


func taken_teams() -> Array:
	var out := []
	for p in players.values():
		out.append(int(p.team))
	return out


func _free_team(prefer := -1) -> int:
	var used := taken_teams()
	if prefer >= 0 and prefer not in used:
		return prefer
	for t in Game.TEAMS.size():
		if t not in used:
			return t
	return 0


func pick_team(t: int) -> void:
	if is_host():
		_req_team(t)
	elif is_client():
		_req_team.rpc_id(1, t)


func set_track(t: int) -> void:
	track = posmod(t, Tracks.LIST.size())
	_push_lobby()


func set_bots(on: bool) -> void:
	bots = on
	_push_lobby()


func set_laps(n: int) -> void:
	laps = n
	_push_lobby()


func _push_lobby() -> void:
	if not is_host():
		return
	lobby_changed.emit()
	if not multiplayer.get_peers().is_empty():
		_lobby.rpc(players, track, bots, laps, code)


@rpc("any_peer", "call_remote", "reliable")
func _hello(name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_race:
		_kick.rpc_id(id, "A race is already running in that room. Try again after it.")
		return
	if players.has(id):
		players[id].name = name.substr(0, 16)
	else:
		players[id] = {"name": name.substr(0, 16), "team": _free_team()}
	_push_lobby()


@rpc("authority", "call_remote", "reliable")
func _kick(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(p: Dictionary, t: int, b: bool, l: int, c: String) -> void:
	players = p
	track = t
	bots = b
	laps = l
	code = c
	_set_status("In room %s." % c)
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _req_team(t: int) -> void:
	var id := multiplayer.get_remote_sender_id() if multiplayer.get_remote_sender_id() != 0 else 1
	if not players.has(id) or t < 0 or t >= Game.TEAMS.size():
		return
	if t in taken_teams():
		return
	players[id].team = t
	_push_lobby()


func _on_peer_connected(id: int) -> void:
	if is_client() and id == 1:
		_on_connected()


func _on_connected() -> void:
	if not is_client():
		return
	_join_wait = 0.0
	_set_status("Connected, joining the room...")
	_hello.rpc_id(1, my_name)


func _on_peer_disconnected(id: int) -> void:
	if is_client():
		if id == 1:
			_fail("The host left the room.")
		return
	if not is_host():
		return
	if _conns.has(id):
		_conns.erase(id)
	if players.has(id):
		var who: String = players[id].name
		players.erase(id)
		_loaded.erase(id)
		if race and is_instance_valid(race):
			race.peer_left(id, who)
		if _go_wait > 0.0:
			_mark_loaded(1)
		_push_lobby()


# --- race --------------------------------------------------------------------------------

## Host: builds the grid (players plus bots, shuffled) and starts the race on every machine.
func start_race() -> void:
	if not is_host():
		return
	var grid := []
	for id in players:
		grid.append({"team": int(players[id].team), "peer": int(id), "name": str(players[id].name)})
	if bots:
		for t in Game.TEAMS.size():
			if t not in taken_teams():
				grid.append({"team": t, "peer": 0, "name": ""})
	grid.shuffle()
	var cfg := {"track": track, "grid": grid, "laps": laps}
	_start.rpc(cfg)
	_start(cfg)


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	in_race = true
	_loaded = {}
	_go_wait = 25.0 if is_host() else -1.0
	race_start.emit(cfg)


## Called by Main once this machine has built the race.
func loaded() -> void:
	if is_host():
		_mark_loaded(1)
	elif is_client():
		_report_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _report_loaded() -> void:
	_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	if not is_host():
		return
	_loaded[id] = true
	for p in players:
		if not _loaded.has(p):
			return
	_start_countdown()


func _start_countdown() -> void:
	_go_wait = -1.0
	_go.rpc()
	_go()


@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	go.emit()


## Called by the race every physics step: sends this machine's cars.
func race_tick(r: Race, dt: float) -> void:
	_send_t -= dt
	if _send_t > 0.0 or not active():
		return
	_send_t = 1.0 / SEND_RATE
	if is_host():
		if multiplayer.get_peers().is_empty():
			return
		var data := PackedFloat32Array()
		for car in r.cars:
			data.append_array(car.net_pack())
		_snapshot.rpc(data)
	else:
		var slot := r.cars.find(r.player)
		_car_state.rpc_id(1, slot, r.player.net_pack())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _car_state(slot: int, data: PackedFloat32Array) -> void:
	if not is_host() or race == null or not is_instance_valid(race):
		return
	if slot < 0 or slot >= race.cars.size():
		return
	var car := race.cars[slot]
	if car.peer == multiplayer.get_remote_sender_id() and car.remote:
		car.net_apply(data, 0)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(data: PackedFloat32Array) -> void:
	if race == null or not is_instance_valid(race):
		return
	for i in race.cars.size():
		var car := race.cars[i]
		if car.remote and (i + 1) * STRIDE <= data.size():
			car.net_apply(data, i * STRIDE)


## Host: a world event started; every player builds the same one from the seed.
func send_event(kind: String, s0: float, seed_v: int) -> void:
	if is_host():
		_event.rpc(kind, s0, seed_v)


@rpc("authority", "call_remote", "reliable")
func _event(kind: String, s0: float, seed_v: int) -> void:
	if race and is_instance_valid(race):
		race.hazards.start_event(kind, s0, seed_v)


## Host: lightning hits the car in grid slot `slot` on every machine.
func send_strike(slot: int) -> void:
	_strike.rpc(slot)
	_strike(slot)


@rpc("authority", "call_remote", "reliable")
func _strike(slot: int) -> void:
	if race and is_instance_valid(race) and slot >= 0 and slot < race.cars.size():
		race.hazards.strike_car(race.cars[slot])


## Host: the race is over; everyone gets the same classification.
func send_results(res: Array) -> void:
	_results.rpc(res)
	_results(res)


@rpc("authority", "call_remote", "reliable")
func _results(res: Array) -> void:
	in_race = false
	results_in.emit(res)


## Host: everyone back to the room to pick the next race.
func back_to_lobby() -> void:
	if not is_host():
		return
	in_race = false
	_lobby_again.rpc()
	_lobby_again()
	_push_lobby()


@rpc("authority", "call_remote", "reliable")
func _lobby_again() -> void:
	in_race = false
	race = null
	lobby_again.emit()


# --- WebRTC signalling ---------------------------------------------------------------------

func _new_conn(id: int) -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	c.initialize(ICE)
	c.session_description_created.connect(func(type: String, sdp: String):
		c.set_local_description(type, sdp)
		_sig({"t": "sdp", "o": id, "type": type, "sdp": sdp}))
	c.ice_candidate_created.connect(func(mid: String, index: int, cand: String):
		_sig({"t": "ice", "o": id, "mid": mid, "i": index, "c": cand}))
	(_peer as WebRTCMultiplayerPeer).add_peer(c, id)
	_conns[id] = c
	return c


func _sig(m: Dictionary) -> void:
	if _js == null:
		return
	m["f"] = multiplayer.get_unique_id()
	_js.send(JSON.stringify(m))


func _on_signal(m: Dictionary) -> void:
	var from := int(m.get("f", 0))
	var to := int(m.get("o", 0))
	if from == 0 or from == multiplayer.get_unique_id():
		return
	if to != 0 and to != multiplayer.get_unique_id():
		return
	match str(m.get("t", "")):
		"hello":
			if not is_host():
				return
			if in_race or players.size() >= MAX_PLAYERS:
				_sig({"t": "busy", "o": from, "full": players.size() >= MAX_PLAYERS})
				return
			if _conns.has(from):
				var old: WebRTCPeerConnection = _conns[from]
				if old.get_connection_state() != WebRTCPeerConnection.STATE_FAILED:
					return
				(_peer as WebRTCMultiplayerPeer).remove_peer(from)
				_conns.erase(from)
			var c := _new_conn(from)
			c.create_offer()
		"sdp":
			if _conns.has(from):
				_conns[from].set_remote_description(str(m.type), str(m.sdp))
		"ice":
			if _conns.has(from):
				_conns[from].add_ice_candidate(str(m.mid), int(m.i), str(m.c))
		"busy":
			if is_client():
				_fail("That room is full." if m.get("full", false) else "A race is already running in that room. Try again after it.")


func _process(dt: float) -> void:
	if _js and active():
		var raw := str(_js.poll())
		if raw != "[]" and raw != "":
			var arr = JSON.parse_string(raw)
			if arr is Array:
				for s in arr:
					var m = JSON.parse_string(str(s))
					if m is Dictionary:
						_on_signal(m)
	if is_client() and _join_wait > 0.0:
		_join_wait -= dt
		if _js:
			_hello_t -= dt
			if _hello_t <= 0.0 and bool(_js.ready()):
				_hello_t = 1.0
				_sig({"t": "hello", "o": 1})
		if _join_wait <= 0.0:
			var c: WebRTCPeerConnection = _conns.get(1)
			if c and c.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTING:
				_fail("Found the room, but could not connect to the host. One of your networks blocks direct connections.")
			else:
				_fail("No room %s found. Check the code, and that the host is still in the room." % code)
	if is_host() and _go_wait > 0.0:
		_go_wait -= dt
		if _go_wait <= 0.0:
			_start_countdown()
