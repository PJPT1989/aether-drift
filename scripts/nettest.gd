extends Node
## Automated online test (Net.test_args, from `-- --net=...` or the web page's `?aenet=...`):
##   host[=CODE]  open a room (CODE fixes the web room code)     join=CODE  join one
##   start=N      host: start once N players are in               laps=N, track=N
##   bot          the AI drives this player's car                 quit       quit after the results
##   shots=DIR    save screenshots (lobby, race, results) there
## Prints NETTEST lines; in the browser it also puts the latest one in the page title.

var main: Node
var _started := false
var _shot_t := -1.0
var _shots := ""
var _race_shots := 0


func _ready() -> void:
	_shots = Net.test_flag("shots")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	Net.race_start.connect(func(_cfg): _say("race starting"))
	Net.results_in.connect(_on_results)
	Net.left.connect(func(r: String): _say("left: " + r))
	_run.call_deferred()


func _say(s: String) -> void:
	var line := "NETTEST %s %s" % [Net.my_name, s]
	print(line)
	if Game.web:
		JavaScriptBridge.eval("document.title = %s" % JSON.stringify(line))


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var name := "Host" if Net.test_flag("host") != "" else "Guest%d" % (randi() % 100)
	Net.set_player_name(name)
	if Net.test_flag("host") != "":
		Net.host()
		if Net.test_flag("laps") != "":
			Net.laps = int(Net.test_flag("laps"))
		if Net.test_flag("track") != "":
			Net.track = int(Net.test_flag("track"))
		main.show_lobby()
		_say("hosting " + Net.code)
	elif Net.test_flag("join") != "":
		main.show_multiplayer()
		Net.join(Net.test_flag("join"))
		_say("joining " + Net.test_flag("join"))


func _shot(name: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))
	_say("shot " + name)


func _process(dt: float) -> void:
	if Net.is_host() and not _started and Net.test_flag("start") != "":
		if Net.players.size() >= int(Net.test_flag("start")):
			_started = true
			_say("lobby full: %s" % str(Net.players.values().map(func(p): return p.name)))
			await _shot("lobby_host")
			await get_tree().create_timer(1.0).timeout
			Net.start_race()
	if Net.is_client() and not Net.players.is_empty() and _shot_t < -0.5:
		_shot_t = 0.0
		_say("in lobby with %s" % str(Net.players.values().map(func(p): return p.name)))
		get_tree().create_timer(1.5).timeout.connect(func(): _shot("lobby_" + Net.my_name))
	var r: Race = main.race
	if r and Net.test_flag("bot") != "":
		r.autopilot = true
	if r and r.state == Race.RACING:
		_shot_t += dt
		if _race_shots < 2 and _shot_t > 12.0 + _race_shots * 25.0:
			_race_shots += 1
			_say("events so far %d, now %s" % [r.hazards.fired, str(r.hazards.events.map(func(e): return "%s@%.1f" % [e.kind, e.s0]))])
			_say("racing: place %d, lap %d, total %.0f m, cars %s" % [r.player.place, r.player.laps_done + 1, r.player.total,
				str(r.cars.map(func(c): return "%s%s" % [c.driver if c.driver != "" else c.team.name.left(6), "*" if c.remote else ""]))])
			_shot("race%d_%s" % [_race_shots, Net.my_name])


func _on_results(res: Array) -> void:
	var lines := []
	for x in res:
		lines.append("%d %s %s %.2f" % [x.place, x.driver if x.driver != "" else "bot", x.name, x.time])
	_say("results: " + " | ".join(lines))
	await get_tree().create_timer(1.5).timeout
	await _shot("results_" + Net.my_name)
	if Net.test_flag("quit") != "":
		await get_tree().create_timer(2.0).timeout
		get_tree().quit()
