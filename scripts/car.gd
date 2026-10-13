class_name Car
extends Node3D
## One racer: arcade driving physics on the track's centre line, drifting that charges aether,
## aether boost, lap counting, and the AI driver that steers the other seven cars.
##
## Controls set by the race each frame (player) or by think() (AI): throttle, brake, steer
## (-1 left .. 1 right), drift, boost.

const TOP_SPEED := 74.0       # m/s, about 266 km/h
const ACCEL := 21.0
const BRAKE := 38.0
const REVERSE_TOP := 14.0
const GRIP := 9.0
const DRIFT_GRIP := 3.2
const STEER_RATE := 2.3
const BOOST_ACCEL := 16.0
const BOOST_TOP := 1.28
const AETHER_DRAIN := 0.32    # per second while boosting
const CAR_HALF_WIDTH := 1.0

var team: Dictionary
var team_idx := 0
var is_player := false
var track: Track

# state
var idx := 0
var yaw := 0.0
var vel := Vector3.ZERO
var speed := 0.0              # forward speed, m/s
var aether := 0.3             # 0..1 boost meter
var drifting := false
var drift_time := 0.0
var mini_boost := 0.0         # seconds of free boost left after a drift
var boosting := false
var offroad := false
var wall_hit := 0.0           # impact of the last wall hit this frame, for sound and shake
var wrong_way := 0.0

# input
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var drift_input := false
var boost_input := false

# race bookkeeping
var laps_done := -1
var lap_start := 0.0
var lap_times: Array[float] = []
var best_lap := INF
var finished := false
var finish_time := 0.0
var s_prev := 0.0
var s_max := 0.0
var total := 0.0              # laps_done * length + distance into the lap
var place := 1

# AI
var skill := 1.0
var lane := 0.0
var lane_target := 0.0
var _think_t := 0.0
var rubber := 1.0
var alert := true             # sees obstacles from world events in time (re-rolled per event)

# world events (Hazards): modifiers set before each step, and the spin-out state
var fx_grip := 1.0
var fx_top := 1.0
var fx_push := Vector3.ZERO
var spin_t := 0.0
var hop_t := 0.0
var _spin_rate := 0.0

# online races (Net): a remote car is driven on another machine and follows its messages
var remote := false
var peer := 0                 # the player's peer id, 0 for a bot
var driver := ""              # the player's name, "" for a bot
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_yaw := 0.0
var _net_age := -1.0

# visuals
var body: Node3D
var _wheels: Array[MeshInstance3D] = []
var _flames: Array[MeshInstance3D] = []
var _wheel_spin := 0.0
var _steer_vis := 0.0
var _tilt := Vector2.ZERO
var _hover := false
var _engine: Node
var _trail: CPUParticles3D


func setup(t: Track, team_index: int, player: bool) -> void:
	track = t
	team_idx = team_index
	team = Game.TEAMS[team_index]
	is_player = player
	var model := CarModels.build(team)
	_hover = model.hover
	body = Node3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = model.mesh
	body.add_child(mi)
	for w in model.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = model.wheel
		wm.position = w
		body.add_child(wm)
		_wheels.append(wm)
	var fk := MeshKit.new()
	fk.cyl(Vector3.ZERO, Vector3(0, 0, 1.6), 0.28, 0.0, team.glow, 8, true)
	var flame_mesh := fk.commit()
	for e in model.exhausts:
		var f := MeshInstance3D.new()
		f.mesh = flame_mesh
		f.position = e
		f.scale = Vector3(1, 1, 0.01)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(f)
		_flames.append(f)
	# soft shadow blob so cars sit on the road even with shadows off
	var blob := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 5.2)
	q.orientation = PlaneMesh.FACE_Y
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0, 0, 0, 0.55)
	bm.albedo_texture = Props.soft_dot()
	q.material = bm
	blob.mesh = q
	blob.position.y = 0.12
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)
	if is_player or Game.quality == Game.HIGH:
		_trail = Props.particles(24, 0.6, Color(team.glow.r, team.glow.g, team.glow.b, 0.7), 0.25, 0.6)
		_trail.local_coords = false
		_trail.emitting = false
		_trail.gravity = Vector3(0, 1.0, 0)
		_trail.position = model.exhausts[0]
		body.add_child(_trail)
	if is_player:
		var p := AudioStreamPlayer.new()
		p.stream = Game.sounds["engine"]
		p.volume_db = -12.0
		p.autoplay = false
		add_child(p)
		_engine = p
		var sk := AudioStreamPlayer.new()
		sk.name = "Skid"
		sk.stream = Game.sounds["skid"]
		sk.volume_db = -80.0
		add_child(sk)
	elif Game.quality != Game.LOW:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = Game.sounds["engine"]
		p3.volume_db = -6.0
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		add_child(p3)
		_engine = p3
	if track.night and is_player and Game.quality != Game.LOW:
		var hl := SpotLight3D.new()
		hl.position = Vector3(0, 1.0, -2.3)
		hl.rotation_degrees = Vector3(-8, 0, 0)
		hl.spot_range = 55.0
		hl.spot_angle = 32.0
		hl.light_energy = 2.5
		hl.light_color = Color(1.0, 0.95, 0.85)
		body.add_child(hl)


func start_engine() -> void:
	if _engine and not _engine.playing:
		_engine.play()
		var sk := get_node_or_null("Skid")
		if sk:
			sk.play()


## Puts the car on the grid `dist` metres along the lap (negative = behind the line).
func place_at(dist: float, lateral_off: float) -> void:
	idx = track.idx_at(dist)
	var p := track.P[idx] + track.R[idx] * lateral_off
	position = Vector3(p.x, track.P[idx].y, p.z)
	var t := track.T[idx]
	yaw = atan2(-t.x, -t.z)
	vel = Vector3.ZERO
	speed = 0.0
	s_prev = track.along(position, idx)
	s_max = s_prev
	total = s_prev - track.length
	_update_visuals(0.0)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func top_speed() -> float:
	var top: float = TOP_SPEED * team.speed * rubber
	if boosting:
		top *= BOOST_TOP
	if offroad:
		top *= 0.55
	return top * fx_top


## Knocked into a full spin by a world event: the car loses most of its speed, slides round
## once and ends up facing the way it was going. `power` scales the speed lost.
func spin_out(power := 1.0) -> void:
	spin_t = 1.1
	_spin_rate = TAU / spin_t * (1.0 if randf() < 0.5 else -1.0)
	vel *= 1.0 - 0.5 * power
	drifting = false
	drift_time = 0.0
	mini_boost = 0.0


## Advances the physics by dt. `racing` false holds the car still (countdown).
func step(dt: float, racing: bool, time_now: float) -> void:
	if not racing:
		throttle = 0.0
		brake = 1.0
	var spinning := spin_t > 0.0
	if spinning:
		spin_t -= dt
		throttle = 0.0
		brake = 0.0
		steer = 0.0
		drift_input = false
		boost_input = false
		yaw += _spin_rate * dt
	# steering turns the car; the velocity only follows through tyre grip, so letting go of
	# grip (drifting) makes the car slide
	var vf0 := vel.dot(forward())
	var turn := STEER_RATE * clampf(absf(vf0) / 9.0, 0.0, 1.0) / (1.0 + absf(vf0) / 55.0)
	if drifting:
		turn *= 1.25
	yaw -= steer * turn * signf(vf0) * dt
	var fwd := forward()
	var rgt := right()
	var vf := vel.dot(fwd)
	var vs := vel.dot(rgt)
	# drift: hold the drift key while turning at speed
	var want_drift := drift_input and vf > 16.0 and absf(steer) > 0.15
	if want_drift:
		drifting = true
		drift_time += dt
		aether = minf(1.0, aether + dt * (0.08 + absf(vs) * 0.006))
	elif drifting:
		drifting = false
		if drift_time > 0.6:
			mini_boost = clampf(drift_time * 0.55, 0.3, 1.6)
			if is_player:
				Game.play("boost", -8.0, 1.2)
		drift_time = 0.0
	boosting = mini_boost > 0.0 or (boost_input and aether > 0.0 and racing)
	if mini_boost > 0.0:
		mini_boost -= dt
	elif boosting:
		aether = maxf(0.0, aether - AETHER_DRAIN * dt)
	var top := top_speed()
	# engine and brakes
	if throttle > 0.0 and vf < top:
		var a: float = ACCEL * team.accel * (1.0 - clampf(vf / top, 0.0, 1.0) ** 2) + 3.0
		vf += a * throttle * dt
	if boosting and racing:
		vf += BOOST_ACCEL * dt
	if brake > 0.0:
		if vf > 0.5:
			vf -= BRAKE * brake * dt
		elif racing:
			vf = maxf(vf - ACCEL * 0.6 * brake * dt, -REVERSE_TOP)
		else:
			vf = 0.0
	if throttle <= 0.0 and brake <= 0.0:
		vf -= signf(vf) * minf(absf(vf), (3.0 + absf(vf) * 0.02) * dt)
	if vf > top:
		vf = lerpf(vf, top, clampf(dt * (2.5 if offroad else 0.8), 0.0, 1.0))
	vf -= vf * 0.002 * absf(vf) * dt * 0.1
	# sideways grip
	var g: float = (DRIFT_GRIP if drifting else GRIP) * team.grip
	if offroad:
		g *= 0.7
	g *= fx_grip
	if spinning:
		g = 0.6
	vs *= exp(-g * dt)
	if drifting:
		# arcade drift: the slide feeds back into forward speed instead of scrubbing it all off
		vf += absf(vs) * 1.4 * dt
	vel = fwd * vf + rgt * vs + fx_push * dt
	speed = vf
	fx_grip = 1.0
	fx_top = 1.0
	fx_push = Vector3.ZERO
	position += vel * dt
	# where are we on the track
	idx = track.locate(position, idx)
	var lat := track.lateral(position, idx)
	offroad = absf(lat) > track.hw + Track.CURB
	wall_hit = 0.0
	var lim := track.limit - CAR_HALF_WIDTH
	if absf(lat) > lim:
		var out := track.R[idx] * signf(lat)
		var into := vel.dot(out)
		position -= out * (absf(lat) - lim)
		if into > 0.0:
			vel -= out * into * 1.3
			wall_hit = into
			vel *= 1.0 - clampf(into / 60.0, 0.03, 0.35)
			# turn the nose a little along the wall
			var t := track.T[idx]
			var along_yaw := atan2(-t.x, -t.z)
			yaw = lerp_angle(yaw, along_yaw, clampf(into / 40.0, 0.05, 0.4))
	position.y = track.road_y(position, idx)
	# lap counting
	var s := track.along(position, idx)
	var L := track.length
	if s_prev > L * 0.75 and s < L * 0.25:
		if s_max > L * 0.5:
			laps_done += 1
			if laps_done >= 1:
				var lt := time_now - lap_start
				lap_times.append(lt)
				best_lap = minf(best_lap, lt)
			lap_start = time_now
			if laps_done >= Game.laps and not finished:
				finished = true
				finish_time = time_now
		s_max = s
	elif s_prev < L * 0.25 and s > L * 0.75:
		# backed over the line: undo that lap
		laps_done -= 1
		s_max = s
	s_max = maxf(s_max, s)
	s_prev = s
	total = laps_done * L + s
	# wrong way?
	if fwd.dot(track.T[idx]) < -0.3 and absf(vf) > 4.0:
		wrong_way += dt
	else:
		wrong_way = 0.0
	_update_visuals(dt)


## AI driver: choose a lane, look ahead for corners and set the controls. `dangers` are
## [position, radius, offset from the centre line] obstacles from world events; an alert driver
## steers round them.
func think(dt: float, others: Array, dangers: Array = []) -> void:
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = randf_range(1.5, 3.5)
		lane_target = clampf(lane_target + randf_range(-0.25, 0.25) * track.hw, -0.55 * track.hw, 0.55 * track.hw)
	# move over for a car right in front
	var fwd := forward()
	for o in others:
		if o == self:
			continue
		var d: Vector3 = o.position - position
		var ahead := d.dot(fwd)
		if ahead > 0.0 and ahead < 16.0:
			var side := d.dot(right())
			if absf(side) < 2.6:
				lane_target = clampf(lane + (-3.5 if side > 0.0 else 3.5), -0.7 * track.hw, 0.7 * track.hw)
	var first := INF
	var avoid_brake := false
	if alert:
		# the nearest obstacle in our way: pass it on the wider side, braking if it is too late
		for dg in dangers:
			var d: Vector3 = dg[0] - position
			var ahead := d.dot(fwd)
			if ahead > 2.0 and ahead < 30.0 + maxf(speed, 0.0) * 1.7 and ahead < first:
				var dlat: float = dg[2]
				if absf(dlat - lane) < dg[1] + 3.5 or absf(dlat - track.lateral(position, idx)) < dg[1] + 3.5:
					first = ahead
					lane_target = (-1.0 if dlat > 0.0 else 1.0) * track.hw * 0.72
					if absf(dlat - track.lateral(position, idx)) < dg[1] + 2.4 and ahead < maxf(speed, 0.0) * 0.7 + 8.0:
						avoid_brake = true
	lane = move_toward(lane, lane_target, dt * (2.5 if dangers.is_empty() else 10.0))
	var n := track.n
	var look := 9.0 + maxf(speed, 0.0) * (0.42 if first == INF else 0.2)
	var ti := (idx + int(look / Track.SPACING)) % n
	var target := track.P[ti] + track.R[ti] * lane
	var to := target - position
	to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	steer = clampf(-ang * 2.4, -1.0, 1.0)
	# corner speed: the tightest bend in the braking distance ahead
	var top := top_speed()
	var want := top * skill
	var grip_acc: float = 26.0 * team.grip * skill
	var scan := int((maxf(speed, 10.0) * 1.8 + 30.0) / Track.SPACING)
	var j := 4
	while j < scan:
		var a := (idx + j) % n
		var b := (idx + j + 6) % n
		var bend := track.T[a].angle_to(track.T[b]) / (6.0 * Track.SPACING)
		if bend > 0.0005:
			var vmax := sqrt(grip_acc / bend)
			var dist := j * Track.SPACING
			var allowed := sqrt(vmax * vmax + 2.0 * BRAKE * 0.7 * dist)
			want = minf(want, allowed)
		j += 3
	if avoid_brake:
		want = minf(want, 24.0)
	throttle = 1.0 if speed < want - 1.5 else (0.3 if speed < want + 1.0 else 0.0)
	brake = 1.0 if speed > want + 5.0 else 0.0
	drift_input = false
	boost_input = aether > 0.35 and want > speed + 8.0 and absf(steer) < 0.3
	# a trickle of aether so AI keeps boosting through a race
	aether = minf(1.0, aether + dt * 0.02)


## This car's state for the other players (Net.STRIDE floats).
func net_pack() -> PackedFloat32Array:
	var flags := (1 if boosting else 0) | (2 if drifting else 0) | (4 if finished else 0) | (8 if offroad else 0)
	return PackedFloat32Array([position.x, position.y, position.z, yaw, vel.x, vel.y, vel.z, speed,
		total, laps_done, flags, steer, throttle, finish_time, best_lap if best_lap != INF else -1.0,
		aether, hop_t, spin_t])


func net_apply(a: PackedFloat32Array, o: int) -> void:
	_net_pos = Vector3(a[o], a[o + 1], a[o + 2])
	_net_yaw = a[o + 3]
	_net_vel = Vector3(a[o + 4], a[o + 5], a[o + 6])
	speed = a[o + 7]
	total = a[o + 8]
	laps_done = int(a[o + 9])
	var flags := int(a[o + 10])
	boosting = flags & 1 != 0
	drifting = flags & 2 != 0
	finished = flags & 4 != 0
	offroad = flags & 8 != 0
	steer = a[o + 11]
	throttle = a[o + 12]
	finish_time = a[o + 13]
	best_lap = a[o + 14] if a[o + 14] > 0.0 else INF
	aether = a[o + 15]
	if a[o + 16] > hop_t + 0.05:
		hop_t = a[o + 16]
	spin_t = a[o + 17]
	# keep the lap bookkeeping current, in case this car has to be driven here later (a bot
	# takes over when its player leaves)
	s_prev = total - laps_done * track.length
	s_max = s_prev
	if _net_age < 0.0:
		position = _net_pos
		yaw = _net_yaw
	_net_age = 0.0


## A remote car glides towards where its last message says it is by now.
func net_follow(dt: float) -> void:
	if _net_age < 0.0:
		_update_visuals(dt)
		return
	_net_age += dt
	var target := _net_pos + _net_vel * minf(_net_age, 0.25)
	if position.distance_to(target) > 12.0:
		position = target
	else:
		position = position.lerp(target, clampf(dt * 10.0, 0.0, 1.0))
	yaw = lerp_angle(yaw, _net_yaw, clampf(dt * 12.0, 0.0, 1.0))
	vel = _net_vel
	idx = track.locate(position, idx)
	_update_visuals(dt)


func _update_visuals(dt: float) -> void:
	rotation = Vector3(0, yaw, 0)
	var t := track.T[idx]
	var pitch := asin(clampf(t.y, -1, 1)) * forward().dot(Vector3(t.x, 0, t.z).normalized())
	var lat_acc := steer * clampf(speed / 40.0, 0.0, 1.0)
	var want := Vector2(pitch, -lat_acc * (0.09 if not drifting else 0.14))
	_tilt = _tilt.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	body.rotation = Vector3(_tilt.x, 0, _tilt.y)
	var hop := 0.0
	if hop_t > 0.0:
		hop_t = maxf(0.0, hop_t - dt)
		hop = sin(hop_t / 0.7 * PI) * 1.6
	body.position.y = hop
	if _hover:
		body.position.y = hop + 0.15 + sin(Time.get_ticks_msec() * 0.004 + team_idx) * 0.05
	_wheel_spin += speed * dt / 0.42
	_steer_vis = lerpf(_steer_vis, -steer * 0.45, clampf(dt * 10.0, 0.0, 1.0))
	for i in _wheels.size():
		var w := _wheels[i]
		w.rotation = Vector3(-_wheel_spin if not _hover else 0.0, _steer_vis if i < 2 else 0.0, 0)
	var flame := 1.0 if boosting else (0.25 + throttle * 0.25)
	for f in _flames:
		f.scale = Vector3(1, 1, lerpf(f.scale.z, flame * randf_range(0.8, 1.2), clampf(dt * 12.0, 0.0, 1.0)))
	if _trail:
		_trail.emitting = boosting or drifting
	if _engine:
		var rev := clampf(absf(speed) / TOP_SPEED, 0.0, 1.3)
		_engine.pitch_scale = 0.55 + rev * 1.5 + throttle * 0.08 + (0.15 if boosting else 0.0)
		if is_player:
			var sk := get_node_or_null("Skid")
			if sk:
				sk.volume_db = -14.0 if drifting or (offroad and absf(speed) > 10.0) else -80.0
