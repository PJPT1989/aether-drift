class_name Hazards
extends Node3D
## World events: every track throws its own complications at the racers during a race, so the
## outcome is never only about driving. Each track lists two event kinds (Tracks.LIST "events");
## one fires every 15-25 seconds somewhere ahead of a random racer, is announced on the HUD and the
## minimap, and hits whoever is caught in it (AI and player alike).
##
## Event types:
##   zone      a stretch of road that changes grip / top speed / aether, may spin cars entering it
##   global    the whole track: crosswind pushing cars sideways, a sandstorm
##   obstacles things lying on the road for a while; hitting one stops you dead, maybe spins you
##   walker    one big obstacle crossing the road
##   blasts    spots on the road that glow, then go off and throw cars about
##   strikes   bolts from the sky that hit random racers
## Online, the host picks the events and sends kind, place and seed (Net.send_event), so every
## player builds the same one; each machine applies them to the cars it drives itself.

const KINDS := {
	"thopter_swarm": {"title": "THOPTER SWARM", "hint": "a flock of thopters dives on the road",
		"type": "zone", "len": 80.0, "dur": 14.0, "grip": 0.8, "top": 0.9, "spin": 0.3, "buffet": 7.0},
	"pipe_burst": {"title": "AETHER PIPE BURST", "hint": "slick with aether: no grip, but it fills your meter",
		"type": "zone", "len": 60.0, "dur": 16.0, "grip": 0.3, "top": 1.0, "spin": 0.15, "aether": 0.35, "color": Color(0.3, 0.95, 1.0, 0.75)},
	"harvester": {"title": "RUNAWAY HARVESTER", "hint": "an automaton is crossing the road",
		"type": "walker", "dur": 13.0, "radius": 4.0},
	"crosswind": {"title": "CROSSWIND", "hint": "gusts push every car sideways",
		"type": "global", "dur": 9.0, "push": 10.0, "grip": 0.9},
	"river_surge": {"title": "RIVER SURGE", "hint": "the river floods the road",
		"type": "zone", "len": 100.0, "dur": 16.0, "grip": 0.7, "top": 0.62, "spin": 0.1, "color": Color(0.2, 0.5, 0.65, 0.7)},
	"scarabs": {"title": "SCARAB SWARM", "hint": "beetles on the road eat your aether",
		"type": "zone", "len": 70.0, "dur": 15.0, "grip": 0.85, "top": 0.8, "spin": 0.2, "aether": -0.5, "color": Color(0.12, 0.16, 0.08, 0.6)},
	"geysers": {"title": "GEYSER ERUPTION", "hint": "watch the steaming vents",
		"type": "blasts", "count": 5, "dur": 8.0, "radius": 5.5, "color": Color(0.8, 1.0, 0.85)},
	"branches": {"title": "FALLING BRANCHES", "hint": "the canopy drops logs on the track",
		"type": "obstacles", "count": 5, "dur": 18.0, "radius": 1.0},
	"sandstorm": {"title": "SANDSTORM", "hint": "blinding sand, loose grip, gusts",
		"type": "global", "dur": 13.0, "push": 6.0, "grip": 0.78, "fog": 6.0},
	"sand_drift": {"title": "DRIFTING SAND", "hint": "a dune spills across half the road",
		"type": "zone", "len": 120.0, "dur": 18.0, "grip": 0.75, "top": 0.5, "spin": 0.15, "half": true, "color": Color(0.74, 0.47, 0.24, 0.95)},
	"fireworks": {"title": "FIREWORKS MISFIRE", "hint": "rockets are landing on the track",
		"type": "blasts", "count": 6, "dur": 7.0, "radius": 5.0, "color": Color(1.0, 0.5, 0.9)},
	"aether_lightning": {"title": "AETHER LIGHTNING", "hint": "bolts strike random racers",
		"type": "strikes", "count": 3, "dur": 4.0},
}
const FIRST_EVENT := Vector2(9.0, 14.0)
const BETWEEN := Vector2(15.0, 25.0)
## How likely an AI driver is to see an obstacle in time and steer round it.
const AI_NOTICE := 0.6

var race: Race
var track: Track
var kinds: Array = []
var events: Array = []          # active events (dictionaries)
var banner := ""
var banner_hint := ""
var banner_t := 0.0
var fired := 0                  # events so far this race (the sim test reports it)
var spins := 0                  # cars spun out or stopped by events
var _next := 0.0
var rng := RandomNumberGenerator.new()   # seeded per event, so all players build the same one
var _strip_mat: StandardMaterial3D
var _thopter: ArrayMesh
var _log: ArrayMesh
var _beetle: ArrayMesh


func setup(r: Race) -> void:
	race = r
	track = r.track
	kinds = track.def.get("events", [])
	_next = randf_range(FIRST_EVENT.x, FIRST_EVENT.y)


## Ends every event at once (the smoke test uses it to show one event at a time).
func clear() -> void:
	for e in events:
		for n in e.nodes:
			if is_instance_valid(n):
				n.queue_free()
	events.clear()
	track.fog_mul = 1.0


## Starts an event now. `kind` empty picks one of the track's; `focus` is the car it lands ahead of.
func trigger(kind := "", focus: Car = null, ahead := -1.0) -> void:
	if kind == "":
		if kinds.is_empty():
			return
		kind = kinds[randi() % kinds.size()]
	if focus == null:
		# the player is picked more often than any one rival, so events are felt
		var live := race.cars.filter(func(c: Car) -> bool: return not c.finished)
		if live.is_empty():
			return
		var humans := live.filter(func(c: Car) -> bool: return c == race.player or c.peer != 0)
		focus = humans[randi() % humans.size()] if randf() < 0.4 and not humans.is_empty() else live[randi() % live.size()]
	if ahead < 0.0:
		ahead = randf_range(170.0, 300.0)
	var s0 := _clear_of_indoor(fposmod(fposmod(focus.total, track.length) + ahead, track.length), 170.0)
	var seed_v := randi()
	start_event(kind, s0, seed_v)
	Net.send_event(kind, s0, seed_v)


## `s0`, moved past any indoor stretch that the `span` metres after it would reach.
func _clear_of_indoor(s0: float, span: float) -> float:
	for st: Dictionary in track.indoor:
		var x := 0.0
		while x <= span:
			var i := track.idx_at(s0 + x)
			if i >= st.i0 - 15 and i <= st.i1 + 15:
				s0 = fposmod(track.S[st.i1] + 45.0, track.length)
				break
			x += 10.0
	return s0


## Builds event `kind` starting `s0` metres into the lap; everything random in it comes from
## `seed_v`, so the same call on another player's machine gives the same event.
func start_event(kind: String, s0: float, seed_v: int, quiet := false) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	rng.seed = seed_v
	var e := {"kind": kind, "def": k, "type": k.type, "t": 0.0, "dur": k.dur, "s0": s0,
		"idx": track.idx_at(s0), "inside": {}, "nodes": [], "items": []}
	fired += 1
	for c in race.cars:
		c.alert = rng.randf() < AI_NOTICE
	match k.type:
		"zone":
			e.len = k.len
			e.side = (1.0 if rng.randf() < 0.5 else -1.0) if k.get("half", false) else 0.0
			_zone_visual(e)
		"global":
			e.wind = Vector3.ZERO
			e.dir = 1.0 if rng.randf() < 0.5 else -1.0
			_global_visual(e)
		"obstacles":
			_drop_logs(e)
		"walker":
			_walker(e)
		"blasts":
			_blasts(e)
		"strikes":
			e.next_strike = 1.2
			e.left = k.count
	if quiet:
		fired -= 1
		return e
	events.append(e)
	banner = k.title
	banner_hint = k.hint
	banner_t = 3.2
	Game.play("alarm", -6.0)
	return e


## Draws, behind the loading screen, everything that would otherwise make the browser stop and
## compile shaders in the middle of the race. A shader is compiled the first time something is
## drawn with a new combination of material and light, which in the browser froze the race for a
## moment whenever an event appeared, a spire's light came into reach or the game switched itself
## to Low quality. So each of the track's events, a copy of every particle effect and a stand-in
## for every distinct mesh and material in the scene are drawn close up (in the player's
## headlights at night) and far beyond them, each time with and without a nearby lamp and with
## and without glow (Low quality has none).
func warm_up() -> void:
	var cam := race.camera
	var lamp := OmniLight3D.new()
	lamp.omni_range = 500.0
	lamp.light_energy = 0.2
	race.add_child(lamp)
	lamp.global_position = cam.global_position + Vector3(0, 8.0, 0)
	# one of each kind of particle effect already in the scene (fireworks, steam, spray...)
	var effects := {}
	for p: CPUParticles3D in race.find_children("*", "CPUParticles3D", true, false):
		var key := "%d/%s/%s" % [p.mesh.get_instance_id() if p.mesh else 0, p.color_ramp != null, p.local_coords]
		if not effects.has(key):
			effects[key] = p
	var stand_ins := _stand_ins()
	var glow0 := track.env.glow_enabled
	for glow: bool in [glow0, not glow0]:
		track.env.glow_enabled = glow
		for lit: bool in [false, true]:
			lamp.visible = lit
			for dist: float in [14.0, 110.0]:
				await _warm_pass(cam, dist, effects.values(), stand_ins)
	track.env.glow_enabled = glow0
	lamp.queue_free()
	for g: Node in stand_ins:
		g.queue_free()


## One hidden copy of each distinct mesh-and-material combination in the race (road, terrain,
## scenery, tunnels, cars...), sharing its mesh and materials.
func _stand_ins() -> Array:
	var seen := {}
	var out: Array = []
	for g: GeometryInstance3D in race.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = g.mesh
		elif g is MultiMeshInstance3D and g.multimesh:
			mesh = g.multimesh.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var multi := g is MultiMeshInstance3D
		var fmt: String = str((mesh as ArrayMesh).surface_get_format(0)) if mesh is ArrayMesh else mesh.get_class()
		var key := "%s/%d/%d/%s" % [multi, g.material_override.get_instance_id() if g.material_override else 0, g.cast_shadow, fmt]
		for q in mesh.get_surface_count():
			var m := mesh.surface_get_material(q)
			key += "/%d" % (m.get_instance_id() if m else 0)
		if seen.has(key):
			continue
		seen[key] = true
		var c: GeometryInstance3D
		if multi:
			var src: MultiMesh = g.multimesh
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = src.use_colors
			mm.use_custom_data = src.use_custom_data
			mm.mesh = mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D())
			c = MultiMeshInstance3D.new()
			c.multimesh = mm
		else:
			c = MeshInstance3D.new()
			c.mesh = mesh
		c.material_override = g.material_override
		c.cast_shadow = g.cast_shadow
		c.set_meta("centre", mesh.get_aabb().get_center())
		c.visible = false
		add_child(c)
		out.append(c)
	return out


func _warm_pass(cam: Camera3D, dist: float, effects: Array, stand_ins: Array) -> void:
	var front := cam.global_position - cam.global_basis.z * dist + Vector3(0, -2.0, 0)
	var s0 := fposmod(fposmod(race.player.total, track.length) + dist + 6.0, track.length)
	var nodes: Array = []
	for kind: String in kinds:
		var e := start_event(kind, s0, randi(), true)
		if e.type == "strikes":
			var bolt := _bolt(race.player.position - cam.global_basis.z * dist)
			add_child(bolt)
			e.nodes.append(bolt)
		nodes.append_array(e.nodes)
	for n: Node3D in nodes:
		# meshes built in world space (road strips, sand, beetles, the bolt) are already in view
		if n.position != Vector3.ZERO or n.has_meta("phase"):
			n.global_position = front
	for p: CPUParticles3D in effects:
		var c: CPUParticles3D = p.duplicate()
		add_child(c)
		c.global_position = front + Vector3(0, 3.0, 0)
		c.visible = true
		nodes.append(c)
	for n: Node3D in nodes:
		if n is CPUParticles3D:
			n.emitting = true
			n.restart()
	for g: GeometryInstance3D in stand_ins:
		g.global_position = front - g.get_meta("centre")
		g.visible = true
	for i in 2:
		await RenderingServer.frame_post_draw
	for n: Node3D in nodes:
		n.queue_free()
	for g: GeometryInstance3D in stand_ins:
		g.visible = false


func update(dt: float, racing: bool) -> void:
	banner_t -= dt
	if racing and not kinds.is_empty() and not Net.is_client():
		_next -= dt
		if _next <= 0.0 and events.size() < 2:
			trigger()
			_next = randf_range(BETWEEN.x, BETWEEN.y)
	var fog_mul := 1.0
	for e in events.duplicate():
		e.t += dt
		match e.type:
			"global":
				if e.def.has("fog"):
					fog_mul = maxf(fog_mul, lerpf(1.0, e.def.fog, _fade(e)))
				var gust := 0.6 + 0.4 * sin(e.t * 2.3) * sin(e.t * 0.9 + 1.0)
				e.wind = e.dir * e.def.push * gust * _fade(e)
			"walker":
				_move_walker(e, dt)
			"obstacles":
				_animate_logs(e, dt)
			"blasts":
				_tick_blasts(e, dt)
			"strikes":
				_tick_strikes(e, dt)
			"zone":
				_animate_zone(e, dt)
		if e.t >= e.dur:
			for n in e.nodes:
				if is_instance_valid(n):
					n.queue_free()
			events.erase(e)
	track.fog_mul = fog_mul


func _fade(e: Dictionary) -> float:
	return clampf(minf(e.t / 1.5, (e.dur - e.t) / 1.5), 0.0, 1.0)


## Sets the car's event modifiers for this physics step (called before car.step).
func affect(car: Car, dt: float) -> void:
	var s := fposmod(car.total, track.length)
	for e in events:
		match e.type:
			"zone":
				if e.t < 1.0 or e.t > e.dur - 0.5:
					continue
				var d := fposmod(s - e.s0, track.length)
				var inside: bool = d < e.len
				if inside and e.side != 0.0:
					inside = track.lateral(car.position, car.idx) * e.side > -1.0
				if inside:
					car.fx_grip *= e.def.grip
					car.fx_top *= e.def.top
					car.aether = clampf(car.aether + e.def.get("aether", 0.0) * dt, 0.0, 1.0)
					if e.def.has("buffet"):
						car.fx_push += track.R[car.idx] * sin(e.t * 9.0 + car.team_idx * 1.7) * e.def.buffet
					if not e.inside.has(car):
						e.inside[car] = true
						if randf() < e.def.spin and car.speed > 25.0:
							_spin(car)
				elif e.inside.has(car) and d > e.len + 20.0:
					e.inside.erase(car)
			"global":
				if track.inside[car.idx] > 0.5:
					continue
				car.fx_grip *= lerpf(1.0, e.def.grip, _fade(e))
				car.fx_push += track.R[car.idx] * e.wind
			"obstacles", "walker":
				for it in e.items:
					if it.get("live", true):
						_obstacle_hit(car, it.pos, e.def.radius)


## Obstacles the AI may steer round: [position, radius, offset from the centre line].
func dangers() -> Array:
	var out := []
	for e in events:
		if e.type == "obstacles" or e.type == "walker":
			for it in e.items:
				if it.get("live", true):
					var ctr: Vector3 = it.get("ground", it.pos)
					out.append([it.pos, e.def.radius, track.lateral(ctr, int(it.idx))])
	return out


## Where events are, for the minimap.
func markers() -> Array:
	var out := []
	for e in events:
		if e.type == "global" or e.type == "strikes":
			continue
		var i: int = e.idx
		if e.type == "zone":
			i = track.idx_at(e.s0 + e.len * 0.5)
		out.append(track.P[i])
	return out


## Metres from the car to the nearest event ahead of it on the lap, or -1.
func distance_ahead(car: Car) -> float:
	var best := -1.0
	var s := fposmod(car.total, track.length)
	for e in events:
		if e.type == "global" or e.type == "strikes":
			continue
		var d := fposmod(e.s0 - s, track.length)
		if d < 900.0 and (best < 0.0 or d < best):
			best = d
	return best


func _spin(car: Car, power := 1.0) -> void:
	if car.spin_t > 0.0 or car.finished:
		return
	car.spin_out(power)
	spins += 1
	if car == race.player:
		Game.play("hit", -4.0, 0.8)
		race.shake = maxf(race.shake, 0.6)


func _obstacle_hit(car: Car, pos: Vector3, r: float) -> void:
	var d := car.position - pos
	d.y = 0.0
	var reach := r + Car.CAR_HALF_WIDTH + 0.2
	var dist := d.length()
	if dist >= reach or dist < 0.001:
		return
	var nrm := d / dist
	car.position += nrm * (reach - dist)
	var into := -car.vel.dot(nrm)
	car.alert = true   # once bitten, every driver steers round it
	if into > 0.0:
		car.vel += nrm * into * 1.4
		car.vel *= 0.35
		car.speed *= 0.35
		if into > 20.0:
			spins += 1
		if car == race.player:
			Game.play("hit", -8.0)
			race.shake = maxf(race.shake, 0.4)


# --- zones ---------------------------------------------------------------------------

## A see-through strip over the stretch of road the zone covers.
func _strip(e: Dictionary, col: Color, lift: float, side: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(e.len / Track.SPACING)
	var w := track.hw + Track.CURB * 0.5
	var a := -w
	var b := w
	if side > 0.0:
		a = -1.0
	elif side < 0.0:
		b = 1.0
	for k in steps + 1:
		var i: int = (e.idx + k) % track.n
		var p := track.P[i] + Vector3(0, lift, 0)
		var fade := clampf(minf(k, steps - k) / 6.0, 0.2, 1.0)
		st.set_normal(Vector3.UP)
		st.set_color(Color(col.r, col.g, col.b, col.a * fade))
		st.set_uv(Vector2(0, k * 0.25))
		st.add_vertex(p + track.R[i] * a)
		st.set_normal(Vector3.UP)
		st.set_color(Color(col.r, col.g, col.b, col.a * fade))
		st.set_uv(Vector2(1, k * 0.25))
		st.add_vertex(p + track.R[i] * b)
	for k in steps:
		var q := k * 2
		for v in [q, q + 2, q + 1, q + 1, q + 2, q + 3]:
			st.add_index(v)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if e.kind == "pipe_burst":
		m.emission_enabled = true
		m.emission = Color(col.r, col.g, col.b) * 1.6
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _zone_visual(e: Dictionary) -> void:
	var k: Dictionary = e.def
	var mid := track.idx_at(e.s0 + e.len * 0.5)
	if k.has("color"):
		var strip := _strip(e, k.color, 0.32 if e.kind != "sand_drift" else 0.4, e.side)
		strip.scale = Vector3.ONE
		add_child(strip)
		e.nodes.append(strip)
		strip.set_meta("fade", true)
	match e.kind:
		"thopter_swarm":
			if _thopter == null:
				var mk := MeshKit.new()
				mk.sphere(Vector3.ZERO, Vector3(0.45, 0.35, 1.0), Props.BRASS, 10, 6)
				mk.quad(Vector3(0.3, 0.1, -0.3), Vector3(2.0, 0.4, 0.1), Vector3(1.8, 0.4, 0.7), Vector3(0.3, 0.1, 0.4), Color(0.6, 0.9, 1.0), true)
				mk.quad(Vector3(-0.3, 0.1, -0.3), Vector3(-0.3, 0.1, 0.4), Vector3(-1.8, 0.4, 0.7), Vector3(-2.0, 0.4, 0.1), Color(0.6, 0.9, 1.0), true)
				mk.cyl(Vector3(0, 0, 0.9), Vector3(0, 0, 2.0), 0.13, 0.04, Props.COPPER, 6)
				mk.sphere(Vector3(0, 0.05, -0.95), Vector3(0.15, 0.15, 0.15), Color(1.0, 0.5, 0.2), 6, 4, true)
				_thopter = mk.commit()
			for i in 14:
				var mi := MeshInstance3D.new()
				mi.mesh = _thopter
				mi.set_meta("phase", rng.randf() * TAU)
				mi.set_meta("along", rng.randf() * e.len)
				mi.set_meta("speed", rng.randf_range(1.5, 2.6))
				add_child(mi)
				e.nodes.append(mi)
		"pipe_burst":
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var at := track.P[mid] + track.R[mid] * side * (track.limit + 1.0)
			var jet := Props.particles(60 if Game.quality != Game.LOW else 20, 1.4, Color(0.5, 1.0, 1.0, 0.8), 1.2, 3.0)
			jet.position = at + Vector3(0, 1.0, 0)
			jet.direction = (-track.R[mid] * side + Vector3(0, 0.6, 0)).normalized()
			jet.spread = 18.0
			jet.initial_velocity_min = 14.0
			jet.initial_velocity_max = 22.0
			jet.gravity = Vector3(0, -6, 0)
			add_child(jet)
			e.nodes.append(jet)
			var pipe := MeshKit.new()
			pipe.cyl(Vector3(0, 0, -6), Vector3(0, 0, 6), 0.9, 0.9, Props.COPPER, 14)
			pipe.ring(Vector3(0, 0, 0), Vector3(0, 0, 1), 0.95, 0.2, Props.BRASS, 16, 4)
			pipe.ring(Vector3(0, 0, 0.6), Vector3(0, 0, 1), 0.6, 0.12, Props.AETHER, 16, 3, true)
			var pm := MeshInstance3D.new()
			pm.mesh = pipe.commit()
			pm.position = at + Vector3(0, 0.9, 0)
			pm.basis = Basis.looking_at(track.T[mid], Vector3.UP)
			add_child(pm)
			e.nodes.append(pm)
		"river_surge":
			var spray := Props.particles(70 if Game.quality != Game.LOW else 24, 1.6, Color(0.75, 0.9, 1.0, 0.7), 1.0, 2.6)
			spray.position = track.P[mid] + Vector3(0, 0.5, 0)
			spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			spray.emission_box_extents = Vector3(track.hw, 0.2, e.len * 0.45)
			spray.basis = Basis.looking_at(track.T[mid], Vector3.UP)
			spray.direction = Vector3.UP
			spray.initial_velocity_min = 2.0
			spray.initial_velocity_max = 6.0
			spray.gravity = Vector3(0, -5, 0)
			add_child(spray)
			e.nodes.append(spray)
		"scarabs":
			if _beetle == null:
				var bk := MeshKit.new()
				bk.sphere(Vector3(0, 0.12, 0), Vector3(0.22, 0.14, 0.3), Color(0.15, 0.3, 0.2), 8, 4)
				bk.sphere(Vector3(0, 0.12, -0.3), Vector3(0.12, 0.1, 0.1), Props.GOLD, 6, 3)
				bk.box(Vector3(0, 0.27, 0.0), Vector3(0.02, 0.01, 0.4), Props.GOLD, true)
				_beetle = bk.commit()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _beetle
			var count := 260 if Game.quality != Game.LOW else 120
			mm.instance_count = count
			for i in count:
				var k2: int = (e.idx + rng.randi() % int(e.len / Track.SPACING)) % track.n
				var p := track.P[k2] + track.R[k2] * rng.randf_range(-track.hw, track.hw) + Vector3(0, 0.1, 0)
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 2.2)), p))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			e.nodes.append(mmi)
		"sand_drift":
			var dust := Props.particles(50 if Game.quality != Game.LOW else 16, 2.0, Color(0.9, 0.75, 0.5, 0.5), 2.0, 5.0)
			dust.position = track.P[mid] + track.R[mid] * e.side * track.hw * 0.6 + Vector3(0, 0.6, 0)
			dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			dust.emission_sphere_radius = e.len * 0.4
			dust.direction = -track.R[mid] * e.side
			dust.initial_velocity_min = 3.0
			dust.initial_velocity_max = 7.0
			dust.gravity = Vector3.ZERO
			add_child(dust)
			e.nodes.append(dust)
			# a few mounds of sand on the covered half
			var dk := MeshKit.new()
			for i in 7:
				var k3: int = (e.idx + int((i + 0.5) / 7.0 * e.len / Track.SPACING)) % track.n
				var p: Vector3 = track.P[k3] + track.R[k3] * e.side * rng.randf_range(2.0, track.hw - 1.0)
				dk.sphere(p, Vector3(rng.randf_range(2.2, 3.6), rng.randf_range(0.7, 1.1), rng.randf_range(3.5, 5.5)), Color(0.8, 0.55, 0.3).darkened(rng.randf() * 0.12), 10, 4)
			var dm := MeshInstance3D.new()
			dm.mesh = dk.commit()
			add_child(dm)
			e.nodes.append(dm)


func _animate_zone(e: Dictionary, _dt: float) -> void:
	var a := _fade(e)
	for n in e.nodes:
		if n is MeshInstance3D and n.has_meta("fade"):
			var m: StandardMaterial3D = n.material_override
			m.albedo_color = Color(1, 1, 1, a)
		elif e.kind == "thopter_swarm" and n is MeshInstance3D and n.has_meta("phase"):
			var ph: float = n.get_meta("phase") + e.t * float(n.get_meta("speed"))
			var along: float = n.get_meta("along")
			var i := track.idx_at(e.s0 + along + sin(ph * 0.7) * 12.0)
			var dive := 2.2 + absf(sin(ph)) * 9.0 * (1.0 - a * 0.3) + (1.0 - a) * 25.0
			var pos := track.P[i] + track.R[i] * cos(ph) * track.hw * 0.9 + Vector3(0, dive, 0)
			var dir := (track.R[i] * -sin(ph) + track.T[i] * 0.4).normalized()
			n.look_at_from_position(pos, pos + dir, Vector3.UP)


# --- global --------------------------------------------------------------------------

func _global_visual(_e: Dictionary) -> void:
	# a sandstorm shows as thick fog (see update); wind shows in how the cars slide
	pass


# --- obstacles -----------------------------------------------------------------------

func _drop_logs(e: Dictionary) -> void:
	if _log == null:
		var lk := MeshKit.new()
		var bark := Color(0.32, 0.22, 0.14)
		lk.cyl(Vector3(-1.8, 0, 0), Vector3(1.8, 0, 0), 0.7, 0.55, bark, 12)
		lk.cyl(Vector3(0.6, 0.3, 0), Vector3(1.6, 1.3, 0.4), 0.22, 0.1, bark, 8)
		lk.sphere(Vector3(1.7, 1.5, 0.4), Vector3(1.2, 0.9, 1.2), Color(0.18, 0.42, 0.14), 10, 5)
		lk.sphere(Vector3(-1.2, 0.8, -0.3), Vector3(0.9, 0.7, 0.9), Color(0.24, 0.48, 0.16), 10, 5)
		for x: float in [-1.8, 1.8]:
			lk.cyl(Vector3(x, 0, 0), Vector3(x * 1.01, 0, 0), 0.6, 0.6, Color(0.6, 0.45, 0.28), 12)
		_log = lk.commit()
	var span := 140.0
	for i in e.def.count:
		var s: float = e.s0 + span * (i + rng.randf_range(0.1, 0.9)) / e.def.count
		var k := track.idx_at(s)
		# each log lies across one side of the road, leaving the other side open
		var lat := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.5, maxf(track.hw - 2.5, 1.6))
		var pos := track.P[k] + track.R[k] * lat
		var mi := MeshInstance3D.new()
		mi.mesh = _log
		mi.basis = Basis.looking_at(track.T[k], Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		mi.position = pos + Vector3(0, 30.0, 0)
		add_child(mi)
		e.nodes.append(mi)
		# a log is about 5 m long: three overlapping circles along it
		var across := mi.basis.x
		for o: float in [-1.0, 0.0, 1.0]:
			e.items.append({"pos": pos + across * o, "live": false, "node": mi, "drop": rng.randf_range(0.0, 1.2), "ground": pos, "idx": k})


func _animate_logs(e: Dictionary, _dt: float) -> void:
	for it in e.items:
		var mi: MeshInstance3D = it.node
		var t: float = e.t - it.drop
		if t < 0.0:
			continue
		var y := maxf(0.6, 30.0 - t * t * 14.0)
		mi.position.y = it.ground.y + y
		if y <= 0.6 and not it.live:
			it.live = true
			if mi.position.distance_to(race.camera.global_position) < 80.0:
				race.shake = maxf(race.shake, 0.25)
		if e.t > e.dur - 1.0:
			it.live = false
			mi.position.y = it.ground.y + 0.6 - (e.t - (e.dur - 1.0)) * 2.0


func _walker(e: Dictionary) -> void:
	var wk := MeshKit.new()
	wk.paint = true
	wk.sphere(Vector3(0, 4.2, 0), Vector3(2.2, 1.6, 2.6), Props.BRASS, 16, 10)
	wk.paint = false
	wk.ring(Vector3(0, 4.2, 0), Vector3.UP, 2.2, 0.15, Props.COPPER, 24, 4)
	wk.sphere(Vector3(0, 4.4, -2.4), Vector3(0.5, 0.5, 0.3), Props.AETHER, 12, 6, true)
	wk.box(Vector3(0, 5.8, 0), Vector3(0.3, 1.2, 0.3), Props.COPPER)
	for i in 6:
		var a := TAU * i / 6.0
		var hip := Vector3(cos(a) * 1.8, 3.6, sin(a) * 2.0)
		var knee := Vector3(cos(a) * 3.4, 4.6, sin(a) * 3.6)
		var foot := Vector3(cos(a) * 3.8, 0.0, sin(a) * 4.0)
		wk.cyl(hip, knee, 0.22, 0.18, Props.COPPER.darkened(0.2), 8)
		wk.cyl(knee, foot, 0.18, 0.1, Props.COPPER.darkened(0.3), 8)
		wk.sphere(knee, Vector3.ONE * 0.28, Props.BRASS, 8, 4)
	# harvester blades on the front
	for i in 5:
		wk.taper(Vector3(-1.6 + i * 0.8, 2.6, -2.6), Vector2(0.3, 0.1), Vector2(0.02, 0.02), 1.2, Color(0.75, 0.76, 0.8), false, 0.0, Vector3(0, 0, -0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = wk.commit()
	mi.scale = Vector3.ONE * 1.4
	add_child(mi)
	e.nodes.append(mi)
	e.side = 1.0 if rng.randf() < 0.5 else -1.0
	var start: Vector3 = track.P[e.idx] + track.R[e.idx] * e.side * (track.limit + 3.0)
	mi.position = start
	e.items.append({"pos": start, "live": true, "node": mi, "idx": e.idx})


func _move_walker(e: Dictionary, _dt: float) -> void:
	var it: Dictionary = e.items[0]
	var f := clampf(e.t / e.dur, 0.0, 1.0)
	var lat: float = e.side * lerpf(track.limit + 3.0, -(track.limit + 3.0), f)
	var p: Vector3 = track.P[e.idx] + track.R[e.idx] * lat
	it.pos = p
	var mi: MeshInstance3D = it.node
	mi.position = p + Vector3(0, absf(sin(e.t * 5.0)) * 0.3, 0)
	mi.basis = Basis.looking_at(-track.R[e.idx] * e.side, Vector3.UP).rotated(Vector3.UP, sin(e.t * 2.5) * 0.1)


# --- blasts and strikes ----------------------------------------------------------------

func _blasts(e: Dictionary) -> void:
	var span := 160.0
	for i in e.def.count:
		var s: float = e.s0 + span * (i + rng.randf_range(0.1, 0.9)) / e.def.count
		var k := track.idx_at(s)
		var pos := track.P[k] + track.R[k] * rng.randf_range(-track.hw + 2.5, track.hw - 2.5)
		var rk := MeshKit.new()
		rk.ring(Vector3.ZERO, Vector3.UP, e.def.radius, 0.18, e.def.color, 28, 3, true)
		rk.ring(Vector3.ZERO, Vector3.UP, e.def.radius * 0.5, 0.12, e.def.color, 20, 3, true)
		var ring := MeshInstance3D.new()
		ring.mesh = rk.commit()
		ring.position = pos + Vector3(0, 0.2, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		e.nodes.append(ring)
		var geyser: bool = e.kind == "geysers"
		var burst := Props.particles(80 if Game.quality != Game.LOW else 30, 1.8 if geyser else 1.0,
			Color(0.9, 1.0, 0.95, 0.8) if geyser else Color(1, 1, 1, 1), 1.5 if geyser else 0.5, 3.5 if geyser else 1.2)
		burst.one_shot = true
		burst.emitting = false
		burst.explosiveness = 0.9 if not geyser else 0.4
		burst.position = pos + Vector3(0, 0.5, 0)
		burst.direction = Vector3.UP
		burst.spread = 12.0 if geyser else 80.0
		burst.initial_velocity_min = 18.0 if geyser else 10.0
		burst.initial_velocity_max = 30.0 if geyser else 22.0
		burst.gravity = Vector3(0, -9, 0)
		if not geyser:
			burst.color_ramp = null
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0, 0.3, 1])
			g.colors = PackedColorArray([Color(1, 1, 0.8, 1), e.def.color, Color(1, 0.4, 0.2, 0)])
			burst.color_ramp = g
		add_child(burst)
		e.nodes.append(burst)
		e.items.append({"pos": pos, "fuse": rng.randf_range(2.0, e.dur - 1.5), "ring": ring, "burst": burst, "done": false})


func _tick_blasts(e: Dictionary, _dt: float) -> void:
	for it in e.items:
		var ring: MeshInstance3D = it.ring
		if it.done:
			continue
		var left: float = it.fuse - e.t
		var pulse := 1.0 + sin(e.t * (8.0 + 14.0 / maxf(left, 0.3))) * 0.08
		ring.scale = Vector3.ONE * pulse
		if left <= 0.0:
			it.done = true
			ring.visible = false
			var b: CPUParticles3D = it.burst
			b.emitting = true
			var close: float = it.pos.distance_to(race.camera.global_position)
			if close < 120.0:
				Game.play("boom", clampf(-2.0 - close * 0.12, -20.0, -2.0))
				race.shake = maxf(race.shake, clampf(0.7 - close / 100.0, 0.0, 0.7))
			for car in race.cars:
				if car.remote:
					continue
				var d: Vector3 = car.position - it.pos
				d.y = 0.0
				if d.length() < e.def.radius + 1.0:
					car.vel += (d.normalized() if d.length() > 0.1 else car.right()) * 9.0
					car.hop_t = 0.7
					_spin(car)


func _tick_strikes(e: Dictionary, dt: float) -> void:
	if Net.is_client():
		return
	e.next_strike -= dt
	if e.next_strike > 0.0 or e.left <= 0:
		return
	e.left -= 1
	e.next_strike = randf_range(0.5, 1.1)
	var live := race.cars.filter(func(c: Car) -> bool: return not c.finished and c.spin_t <= 0.0 and track.inside[c.idx] < 0.5)
	if live.is_empty():
		return
	var car: Car = live[randi() % live.size()]
	if Net.active():
		Net.send_strike(race.cars.find(car))
	else:
		strike_car(car)


## A bolt hits `car` (on every machine online; only the machine driving it spins it).
func strike_car(car: Car) -> void:
	var bolt := _bolt(car.position)
	add_child(bolt)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(bolt.queue_free)
	car.hop_t = 0.4
	if not car.remote:
		car.aether = 0.0
		_spin(car, 0.8)
	var close := car.position.distance_to(race.camera.global_position)
	if close < 150.0:
		Game.play("boom", clampf(-4.0 - close * 0.1, -20.0, -4.0), 1.5)


## A jagged bolt from the sky down to `at`.
func _bolt(at: Vector3) -> MeshInstance3D:
	var top := at + Vector3(randf_range(-8, 8), 60.0, randf_range(-8, 8))
	var bk := MeshKit.new()
	var a := top
	for i in 8:
		var b := top.lerp(at + Vector3(0, 1, 0), (i + 1) / 8.0)
		if i < 7:
			b += Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		bk.cyl(a, b, 0.35, 0.3, Color(0.7, 0.95, 1.0), 6, true)
		a = b
	var bolt := MeshInstance3D.new()
	bolt.mesh = bk.commit()
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bolt
