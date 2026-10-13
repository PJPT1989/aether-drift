class_name Race
extends Node3D
## One race: builds the track, puts eight cars on the grid, runs the countdown, reads the
## player's controls, steps every car, handles car-to-car bumps, orbs and the track's world
## events (Hazards), follows the player with the camera and reports the results when the player
## crosses the line on the last lap. In an online race (Net) only some cars are driven here: the
## host drives its own car and the bots, every other player their own car, and the rest follow
## the other machines' messages.

signal race_over(results: Array)

enum { COUNTDOWN, RACING, FINISHED, DONE, WAITING }
const COUNTDOWN_TIME := 3.6
const CAM_MODES := 2
## Online: once the first player finishes, the others get this long before the results.
const NET_FINISH_WAIT := 45.0

var track: Track
var hazards: Hazards
var track_index := 0
var cars: Array[Car] = []
var player: Car
var camera: Camera3D
var state := COUNTDOWN
var time := 0.0                # race clock, starts at GO
var countdown := COUNTDOWN_TIME
var cam_mode := 0
var autopilot := false         # the smoke test lets the AI drive the player's car
var free_cam := false          # the smoke test places the camera itself
var message := ""
var message_t := 0.0
var shake := 0.0
var _after_finish := 0.0
var _last_count := 4
var _ambient: CPUParticles3D
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _first_finish := -1.0


## `grid` (online races) lists the cars from pole: {"team", "peer" (0 for a bot), "name"}.
func setup(t_index: int, team_index: int, grid: Array = []) -> void:
	track_index = t_index
	track = Track.new()
	add_child(track)
	track.build(Tracks.LIST[t_index])
	# grid: the player starts fifth of eight
	var order: Array[int] = []
	if grid.is_empty():
		for i in Game.TEAMS.size():
			if i != team_index:
				order.append(i)
		order.shuffle()
		order.insert(4, team_index)
	else:
		for g in grid:
			order.append(int(g.team))
		state = WAITING
		show_message("WAITING FOR PLAYERS", 999.0)
	for k in order.size():
		var car := Car.new()
		add_child(car)
		var is_player := order[k] == team_index
		if not grid.is_empty():
			car.peer = int(grid[k].peer)
			car.driver = str(grid[k].name)
			is_player = car.peer == Net.my_id()
			car.remote = not is_player and not (Net.is_host() and car.peer == 0)
		car.setup(track, order[k], is_player)
		car.place_at(-12.0 - k * 8.0, (track.hw * 0.42) * (-1.0 if k % 2 == 0 else 1.0))
		car.skill = 1.0 if is_player else 0.9 + 0.012 * ((k * 5 + t_index * 3) % 8)
		car.lane = (track.hw * 0.42) * (-1.0 if k % 2 == 0 else 1.0)
		car.lane_target = car.lane
		cars.append(car)
		if is_player:
			player = car
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.2
	camera.far = 2600.0
	# each camera carries its own environment, so a menu backdrop or an earlier race never leaks in
	camera.environment = track.env
	add_child(camera)
	camera.current = true
	_ambient = track.make_ambient()
	add_child(_ambient)
	hazards = Hazards.new()
	add_child(hazards)
	hazards.setup(self)
	_snap_camera()
	apply_quality()


func apply_quality() -> void:
	track.apply_quality()
	_ambient.visible = Game.quality != Game.LOW
	_ambient.emitting = Game.quality != Game.LOW


## Online: everyone has loaded, start the countdown.
func go() -> void:
	if state == WAITING:
		state = COUNTDOWN
		message_t = 0.0


## Online (host): a player left mid-race; a bot takes over their car.
func peer_left(id: int, who: String) -> void:
	for car in cars:
		if car.peer == id:
			car.remote = false
			car.peer = 0
			car.driver = ""
			show_message("%s left - a bot drives on" % who, 3.0)


func show_message(text: String, secs := 2.0) -> void:
	message = text
	message_t = secs


func _physics_process(dt: float) -> void:
	simulate(dt)


## One physics step of the whole race.
func simulate(dt: float) -> void:
	if state == WAITING:
		for car in cars:
			if car.remote:
				car.net_follow(dt)
		return
	if state == COUNTDOWN:
		countdown -= dt
		var c := int(ceil(countdown - 0.6))
		if c < _last_count and c >= 1:
			_last_count = c
			Game.play("beep", -4.0)
		if countdown <= 0.6:
			state = RACING
			show_message("GO!", 1.0)
			Game.play("go", -2.0)
			for car in cars:
				car.lap_start = 0.0
				car.start_engine()
	var racing := state != COUNTDOWN
	if racing:
		time += dt
	_read_player(dt)
	hazards.update(dt, state == RACING)
	var dangers := hazards.dangers()
	var humans := cars.filter(func(c: Car) -> bool: return c == player or c.peer != 0)
	for car in cars:
		if car.remote:
			car.net_follow(dt)
			if racing:
				track.collect_orb(car.position, car.idx)
			continue
		if car != player or autopilot or player.finished:
			car.think(dt, cars, dangers)
			# bots ease off when far ahead of the nearest human and push when far behind
			var diff := INF
			for h in humans:
				if absf(car.total - h.total) < absf(diff):
					diff = car.total - h.total
			car.rubber = clampf(1.0 - diff / 2500.0, 0.93, 1.07) if car != player and car.peer == 0 else 1.0
		var was_laps := car.laps_done
		if racing:
			hazards.affect(car, dt)
		car.step(dt, racing, time)
		if car == player:
			if car.laps_done > was_laps and car.laps_done >= 1 and not car.finished:
				Game.play("lap", -4.0)
				show_message("FINAL LAP" if car.laps_done == Game.laps - 1 else "LAP %d / %d" % [car.laps_done + 1, Game.laps], 2.0)
			if car.wall_hit > 6.0:
				Game.play("hit", clampf(-20.0 + car.wall_hit, -14.0, 0.0))
				shake = maxf(shake, clampf(car.wall_hit / 25.0, 0.1, 0.8))
		if racing and track.collect_orb(car.position, car.idx):
			car.aether = minf(1.0, car.aether + 0.15)
			if car == player:
				Game.play("orb", -8.0)
	_collide_cars()
	_rank()
	if state == RACING and player.finished:
		state = FINISHED
		show_message("FINISH!  %s" % ordinal(player.place), 4.0)
	if Net.active():
		Net.race_tick(self, dt)
		if Net.is_host() and state != DONE:
			_net_check_done(dt, humans)
		message_t -= dt
		return
	if state == FINISHED:
		_after_finish += dt
		var all_done := true
		for car in cars:
			all_done = all_done and car.finished
		if all_done or _after_finish > 6.0:
			state = DONE
			race_over.emit(results())
	message_t -= dt


## Online (host): the race ends when every player is home and the bots too (or a little after),
## or NET_FINISH_WAIT seconds after the first player finished.
func _net_check_done(dt: float, humans: Array) -> void:
	if humans.any(func(c: Car) -> bool: return c.finished):
		if _first_finish < 0.0:
			_first_finish = 0.0
		_first_finish += dt
	else:
		return
	var humans_done := humans.all(func(c: Car) -> bool: return c.finished)
	if humans_done:
		_after_finish += dt
	var all_done := cars.all(func(c: Car) -> bool: return c.finished)
	if (humans_done and (all_done or _after_finish > 6.0)) or _first_finish > NET_FINISH_WAIT:
		state = DONE
		Net.send_results(results())


## Online: the host's classification arrived.
func net_results(res: Array) -> void:
	state = DONE
	for r in res:
		r["player"] = int(r.peer) != 0 and int(r.peer) == Net.my_id()
	race_over.emit(res)


func _read_player(dt: float) -> void:
	if autopilot or player.finished:
		return
	var accel := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var st := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	player.throttle = accel
	player.brake = brk
	# keyboard steering eases in and snaps back, so small corrections are possible
	var rate := 4.5 if absf(st) > absf(player.steer) else 9.0
	player.steer = move_toward(player.steer, st, rate * dt)
	player.drift_input = Input.is_action_pressed("drift")
	player.boost_input = Input.is_action_pressed("boost")


func reset_player() -> void:
	if state != RACING:
		return
	var i := player.idx
	player.position = track.P[i]
	var t := track.T[i]
	player.yaw = atan2(-t.x, -t.z)
	player.vel = Vector3.ZERO
	player.speed = 0.0


func _collide_cars() -> void:
	for a in cars.size():
		for b in range(a + 1, cars.size()):
			var ca := cars[a]
			var cb := cars[b]
			if ca.remote and cb.remote:
				continue
			var d := cb.position - ca.position
			if absf(d.y) > 2.5:
				continue
			d.y = 0.0
			var dist := d.length()
			if dist < 2.3 and dist > 0.001:
				var nrm := d / dist
				# a car driven on another machine is moved there; only the local one is pushed here
				var push := (2.3 - dist) * (1.0 if ca.remote or cb.remote else 0.5)
				if not ca.remote:
					ca.position -= nrm * push
				if not cb.remote:
					cb.position += nrm * push
				var rel := (cb.vel - ca.vel).dot(nrm)
				if rel < 0.0:
					var imp := -rel * 0.6
					if not ca.remote:
						ca.vel -= nrm * imp
					if not cb.remote:
						cb.vel += nrm * imp
					if ca == player or cb == player:
						if imp > 2.0:
							Game.play("hit", clampf(-22.0 + imp * 2.0, -16.0, -2.0), 1.3)
						shake = maxf(shake, clampf(imp / 20.0, 0.05, 0.5))


func _rank() -> void:
	var order := cars.duplicate()
	order.sort_custom(func(a: Car, b: Car) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.total > b.total)
	for i in order.size():
		order[i].place = i + 1


## Final classification; cars still racing get a time estimated from their remaining distance.
func results() -> Array:
	var out := []
	for car in cars:
		var t := car.finish_time
		if not car.finished:
			var left := Game.laps * track.length - car.total
			var avg := maxf(car.total / maxf(time, 1.0), 30.0)
			t = time + left / avg
		out.append({"team": car.team_idx, "name": car.team.name, "time": t, "best": car.best_lap, "player": car == player,
			"peer": car.peer, "driver": car.driver})
	out.sort_custom(func(a, b): return a.time < b.time)
	for i in out.size():
		out[i]["place"] = i + 1
	return out


static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suf]


static func fmt_time(t: float) -> String:
	if t == INF or t <= 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


# --- camera ------------------------------------------------------------------------

func _cam_target() -> Array:
	var f := player.forward()
	var vel_dir := player.vel.normalized() if player.vel.length() > 5.0 else f
	var dir := f.lerp(vel_dir, 0.4).normalized()
	var back := 7.8 if cam_mode == 0 else 5.2
	var up := 2.9 if cam_mode == 0 else 1.9
	var pos := player.position - dir * back + Vector3(0, up, 0)
	var look := player.position + dir * 6.0 + Vector3(0, 1.1, 0)
	return [pos, look]


func _snap_camera() -> void:
	var t := _cam_target()
	_cam_pos = t[0]
	_cam_look = t[1]
	camera.look_at_from_position(_cam_pos, _cam_look, Vector3.UP)


func _process(dt: float) -> void:
	if player == null or free_cam:
		return
	var t := _cam_target()
	var k := clampf(dt * 7.0, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(t[0], k)
	_cam_look = _cam_look.lerp(t[1], clampf(dt * 12.0, 0.0, 1.0))
	# never dip below the road
	var floor_y := track.road_y(_cam_pos, track.locate(_cam_pos, player.idx)) + 1.0
	if _cam_pos.y < floor_y:
		_cam_pos.y = floor_y
	shake = maxf(0.0, shake - dt * 1.5)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	if player.offroad and absf(player.speed) > 10.0:
		jitter += Vector3(0, randf_range(-1, 1), 0) * 0.04
	camera.look_at_from_position(_cam_pos + jitter, _cam_look, Vector3.UP)
	var spd := clampf(player.speed / Car.TOP_SPEED, 0.0, 1.3)
	camera.fov = lerpf(camera.fov, 68.0 + spd * 14.0 + (8.0 if player.boosting else 0.0), clampf(dt * 3.0, 0.0, 1.0))
	_ambient.position = camera.position + (-camera.basis.z) * 20.0
