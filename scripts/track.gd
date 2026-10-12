class_name Track
extends Node3D
## Builds one track from its entry in Tracks.LIST: the smoothed racing line, road, curbs and
## rails, terrain, river, sky and light, scenery, arches, landmarks, aether orbs and ambient
## particles. Also answers the questions the cars ask every frame: where along the lap am I,
## how far from the centre line, how high is the road here.

const SPACING := 2.0          # metres between centre-line samples
const CURB := 1.3             # curb width beyond the road edge
const STRETCH := 1.3          # horizontal scale applied to the layouts in tracks.gd
const ORB_RESPAWN := 8.0

var def: Dictionary
var night := false
var elevated := false
var P := PackedVector3Array()   # centre line
var T := PackedVector3Array()   # unit tangent (direction of travel)
var R := PackedVector3Array()   # unit right vector, horizontal
var S := PackedFloat32Array()   # distance from the start line
var n := 0
var length := 0.0
var hw := 8.0                   # half the road width
var limit := 12.0               # how far from the centre the walls are
var sun_dir := Vector3.UP
var env: Environment
var sun: DirectionalLight3D
var density := 1.0

var _grid := {}                 # Vector2i cell -> PackedInt32Array of sample indices (every 3rd)
const CELL := 40.0
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _river := PackedVector3Array()
var _river_w := 0.0
var _spin: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _dinos: Array = []          # [node, origin, dir, phase]
var _flyers: Array = []         # [node, centre, radius, height, speed, phase]
var _fireworks: Array[CPUParticles3D] = []
var _firework_t := 0.0
var orbs: Array = []            # [idx, position, respawn_timer]
var _orb_mm: MultiMesh
var _t := 0.0


func build(track_def: Dictionary) -> void:
	def = track_def
	night = def.get("night", false)
	elevated = def.get("elevated", false)
	hw = def.width * 0.5
	match def.edge:
		"none": limit = hw + CURB + 14.0
		"glowrail": limit = hw + CURB + (0.6 if elevated else 2.0)
		_: limit = hw + CURB + 3.5
	density = [0.45, 0.75, 1.0][Game.quality]
	_noise.seed = hash(def.name)
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 3
	_noise2.seed = hash(def.name) + 1
	_noise2.frequency = 0.012
	_river = PackedVector3Array(def.get("river", []))
	_river_w = def.get("river_width", 0.0)
	_build_line()
	_build_grid()
	_build_environment()
	_build_road()
	_build_edges()
	_build_terrain()
	if _river.size() > 1:
		_build_river()
	if elevated:
		_build_supports()
	if def.get("ley", false):
		_build_ley_lines()
	_build_start_gantry()
	_build_props()
	_build_arches()
	_build_landmarks()
	_build_flyers()
	_build_orbs()
	if def.particles == "fireworks":
		_build_fireworks()


# --- the racing line --------------------------------------------------------------

func _build_line() -> void:
	# layouts are drawn small in tracks.gd and stretched here so a lap takes about 40 seconds
	var cp: Array = []
	for q: Vector3 in def.points:
		cp.append(Vector3(q.x * STRETCH, q.y, q.z * STRETCH))
	var m := cp.size()
	var dense := PackedVector3Array()
	for i in m:
		var p0: Vector3 = cp[(i - 1 + m) % m]
		var p1: Vector3 = cp[i]
		var p2: Vector3 = cp[(i + 1) % m]
		var p3: Vector3 = cp[(i + 2) % m]
		for k in 40:
			var t := k / 40.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	# resample at even spacing
	var total := 0.0
	for i in dense.size():
		total += dense[i].distance_to(dense[(i + 1) % dense.size()])
	n = int(total / SPACING)
	var step := total / n
	length = total
	var seg := 0
	var seg_start := 0.0
	var seg_len := dense[0].distance_to(dense[1])
	for i in n:
		var want := i * step
		while want > seg_start + seg_len:
			seg_start += seg_len
			seg += 1
			seg_len = dense[seg % dense.size()].distance_to(dense[(seg + 1) % dense.size()])
		var f := (want - seg_start) / maxf(seg_len, 0.0001)
		P.append(dense[seg % dense.size()].lerp(dense[(seg + 1) % dense.size()], f))
		S.append(want)
	for i in n:
		var t := (P[(i + 1) % n] - P[(i - 1 + n) % n]).normalized()
		T.append(t)
		R.append(Vector3(t.x, 0, t.z).normalized().cross(Vector3.UP).normalized())


func _build_grid() -> void:
	for i in range(0, n, 3):
		var c := Vector2i(floori(P[i].x / CELL), floori(P[i].z / CELL))
		if not _grid.has(c):
			_grid[c] = PackedInt32Array()
		_grid[c].append(i)


## Nearest centre-line sample to a point on the ground plane within `reach` metres: [dist, index].
func nearest(x: float, z: float, reach := 120.0) -> Array:
	var best := INF
	var bi := -1
	var cr := int(ceil(reach / CELL))
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	for gx in range(cx - cr, cx + cr + 1):
		for gz in range(cz - cr, cz + cr + 1):
			var c := Vector2i(gx, gz)
			if _grid.has(c):
				for i in _grid[c]:
					var dx := P[i].x - x
					var dz := P[i].z - z
					var d := dx * dx + dz * dz
					if d < best:
						best = d
						bi = i
	return [sqrt(best), bi]


## Sample index nearest to `pos`, searching around the previous index `hint` (so bridges and
## close loops never confuse it). Heights count double.
func locate(pos: Vector3, hint: int) -> int:
	var best := INF
	var bi := hint
	for k in range(-24, 25):
		var i := (hint + k + n) % n
		var d := P[i] - pos
		var dd := d.x * d.x + d.z * d.z + d.y * d.y * 4.0
		if dd < best:
			best = dd
			bi = i
	return bi


func locate_global(pos: Vector3) -> int:
	var best := INF
	var bi := 0
	for i in n:
		var d := P[i].distance_squared_to(pos)
		if d < best:
			best = d
			bi = i
	return bi


## Distance along the lap at `pos` near sample i (continuous between samples).
func along(pos: Vector3, i: int) -> float:
	return S[i] + (pos - P[i]).dot(T[i])


func lateral(pos: Vector3, i: int) -> float:
	return (pos - P[i]).dot(R[i])


## Road height at `pos` near sample i.
func road_y(pos: Vector3, i: int) -> float:
	var d := (pos - P[i]).dot(T[i])
	var j := (i + (1 if d >= 0.0 else -1) + n) % n
	var f := clampf(absf(d) / SPACING, 0.0, 1.0)
	return lerpf(P[i].y, P[j].y, f)


func idx_at(dist: float) -> int:
	return int(fposmod(dist, length) / length * n) % n


# --- environment ---------------------------------------------------------------

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = def.ambient
	env.ambient_light_energy = def.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = def.fog
	env.fog_density = def.fog_density
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.9 if night else 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-def.sun_elev, def.sun_az, 0)
	sun.light_color = def.sun_color
	sun.light_energy = def.sun_energy
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 160.0
	sun.shadow_blur = 1.5
	add_child(sun)
	sun_dir = sun.transform.basis.z
	sm.set_shader_parameter("top_color", def.sky_top)
	sm.set_shader_parameter("horizon_color", def.sky_horizon)
	sm.set_shader_parameter("ground_color", def.sky_ground)
	sm.set_shader_parameter("stars", def.stars)
	sm.set_shader_parameter("aurora", def.aurora)
	sm.set_shader_parameter("shattered", 1.0 if def.get("shattered", false) else 0.0)
	if def.sun_disc > 0.0:
		sm.set_shader_parameter("sun_dir", sun_dir)
		sm.set_shader_parameter("sun_color", def.sun_color)
		sm.set_shader_parameter("sun_disc", def.sun_disc)
	else:
		sm.set_shader_parameter("sun_color", Color(0, 0, 0))
		sm.set_shader_parameter("sun_disc", 0.0)
	if def.has("moon"):
		var md := sun_dir if def.sun_disc == 0.0 else Basis(Vector3.UP, 2.2) * Vector3(sun_dir.x, 0.35, sun_dir.z).normalized()
		sm.set_shader_parameter("moon_dir", md)
		sm.set_shader_parameter("moon_color", def.moon)
	apply_quality()


func apply_quality() -> void:
	env.glow_enabled = Game.quality != Game.LOW
	sun.shadow_enabled = Game.quality == Game.HIGH
	for p in _fireworks:
		p.visible = Game.quality != Game.LOW


# --- road and edges -------------------------------------------------------------

func _road_texture() -> ImageTexture:
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var base: Color = def.road_col
	var line: Color = def.line_col
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.name) + 3
	var style: String = def.road
	for y in sz:
		for x in sz:
			var u := x / float(sz)
			var v := y / float(sz)
			var c := base
			var grain := rng.randf_range(-0.04, 0.04)
			match style:
				"tile":
					var tu := fposmod(u * 6.0, 1.0)
					var tv := fposmod(v * 4.0, 1.0)
					if tu < 0.04 or tv < 0.05:
						c = Color(0.55, 0.32, 0.18)
					else:
						c = base.lightened(_noise2.get_noise_2d(floor(u * 6.0) * 13.0, floor(v * 4.0) * 7.0) * 0.12)
				"pavers":
					var row := floori(v * 16.0)
					var tu := fposmod(u * 10.0 + (0.5 if row % 2 == 1 else 0.0), 1.0)
					var tv := fposmod(v * 16.0, 1.0)
					c = base.lightened(_noise2.get_noise_2d(floor(u * 10.0 + row * 0.5) * 11.0, row * 5.0) * 0.18)
					if tu < 0.06 or tv < 0.1:
						c = base.darkened(0.35)
				"stone":
					var row := floori(v * 3.0)
					var tu := fposmod(u * 4.0 + row * 0.37, 1.0)
					var tv := fposmod(v * 3.0, 1.0)
					c = base.lightened(_noise2.get_noise_2d(floor(u * 4.0 + row * 0.37) * 17.0, row * 9.0) * 0.15)
					if tu < 0.02 or tv < 0.025:
						c = base.darkened(0.3)
				"planks":
					var tv := fposmod(v * 12.0, 1.0)
					var plank := floori(v * 12.0)
					c = base.lightened(_noise2.get_noise_2d(plank * 31.0, 0) * 0.2 + sin(u * 90.0 + plank) * 0.03)
					if tv < 0.08:
						c = base.darkened(0.6)
			c = c.lightened(grain) if grain > 0.0 else c.darkened(-grain)
			# edge lines and a dashed centre line
			if (u > 0.025 and u < 0.045) or (u > 0.955 and u < 0.975):
				c = line
			elif absf(u - 0.5) < 0.008 and v < 0.5:
				c = line.lerp(base, 0.25)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n + 1:
		var k := i % n
		var v := (S[k] if i < n else length) / 10.0
		var up := Vector3(0, 0.06, 0)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, v))
		st.add_vertex(P[k] - R[k] * hw + up)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, v))
		st.add_vertex(P[k] + R[k] * hw + up)
	for i in n:
		var a := i * 2
		# quad a(left), a+1(right), a+3(right next), a+2(left next); clockwise from above
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _road_texture()
	mat.roughness = 0.55 if night else 0.85
	mat.metallic_specular = 0.6 if night else 0.3
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	# curbs: alternating colour blocks, a little raised
	var k := MeshKit.new()
	var ca: Color = def.curb[0]
	var cb: Color = def.curb[1]
	for i in n:
		var j := (i + 1) % n
		var col := ca if (i / 2) % 2 == 0 else cb
		for s: float in [-1.0, 1.0]:
			var a0 := P[i] + R[i] * s * hw + Vector3(0, 0.08, 0)
			var a1 := P[j] + R[j] * s * hw + Vector3(0, 0.08, 0)
			var b0 := P[i] + R[i] * s * (hw + CURB) + Vector3(0, 0.02, 0)
			var b1 := P[j] + R[j] * s * (hw + CURB) + Vector3(0, 0.02, 0)
			if s > 0:
				k.quad(a0, b0, b1, a1, col)
			else:
				k.quad(a0, a1, b1, b0, col)
	# chequered start line
	for c in 8:
		for row in 2:
			var u0 := -hw + c * (hw * 2.0 / 8.0)
			var base := P[0] + T[0] * (row * 1.0 - 1.0) + Vector3(0, 0.09, 0)
			var col := Color.WHITE if (c + row) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var p0 := base + R[0] * u0
			var p1 := base + R[0] * (u0 + hw * 2.0 / 8.0)
			k.quad(p0, p1, p1 + T[0], p0 + T[0], col)
	var cm := MeshInstance3D.new()
	cm.mesh = k.commit()
	add_child(cm)


func _build_edges() -> void:
	var k := MeshKit.new()
	var kind: String = def.edge
	if kind == "none":
		return
	var glow := kind == "glowrail"
	var post := Color(0.3, 0.25, 0.25) if not elevated else Color(0.35, 0.26, 0.18)
	var rail := Color(0.75, 0.72, 0.7) if not glow else Props.COPPER
	var gcol: Color = def.line_col
	for s: float in [-1.0, 1.0]:
		for i in range(0, n, 3):
			var j := (i + 3) % n
			var a := P[i] + R[i] * s * limit
			var b := P[j] + R[j] * s * limit
			# rail band: two faces so it shows from both sides
			var h0 := Vector3(0, 0.45, 0)
			var h1 := Vector3(0, 1.0, 0)
			k.quad(a + h0, b + h0, b + h1, a + h1, rail)
			k.quad(a + h0, a + h1, b + h1, b + h0, rail)
			if glow:
				var g0 := Vector3(0, 1.0, 0)
				var g1 := Vector3(0, 1.18, 0)
				k.quad(a + g0, b + g0, b + g1, a + g1, gcol, true)
				k.quad(a + g0, a + g1, b + g1, b + g0, gcol, true)
			if i % 6 == 0:
				k.box(a + Vector3(0, 0.6, 0), Vector3(0.25, 1.2, 0.25), post)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


# --- terrain ---------------------------------------------------------------------

func _base_height(x: float, z: float) -> float:
	var amp: float = def.terrain_amp
	var h := _noise.get_noise_2d(x, z)
	if def.get("dunes", false):
		h = (1.0 - absf(_noise.get_noise_2d(x * 1.4, z * 0.6))) * 1.4 - 0.7 + h * 0.4
	return h * amp


## Ground height anywhere: noise hills, flattened to the road near it, dipped for the river.
func ground_y(x: float, z: float) -> float:
	var h := _base_height(x, z)
	if elevated:
		return h * 0.6 + 1.0
	var nr := nearest(x, z, 130.0)
	if nr[1] >= 0:
		var t := smoothstep(hw + 18.0, hw + 110.0, nr[0])
		h = lerpf(P[nr[1]].y - 0.3, h, t)
	if _river.size() > 1:
		var rd := _river_dist(x, z)
		h = lerpf(-5.0, h, smoothstep(_river_w * 0.5 - 6.0, _river_w * 0.5 + 35.0, rd))
	return h


func _river_dist(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for i in _river.size() - 1:
		var a := Vector2(_river[i].x, _river[i].z)
		var b := Vector2(_river[i + 1].x, _river[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _build_terrain() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in P:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(900, 900)
	hi += Vector2(900, 900)
	var res := 150 if Game.quality != Game.LOW else 110
	var step := (hi - lo) / res
	var cols: Array = def.ground
	var low: Color = cols[0]
	var high: Color = cols[1]
	var accent: Color = cols[2]
	var fields := [Color(0.55, 0.65, 0.2), Color(0.85, 0.7, 0.3), Color(0.55, 0.45, 0.65), Color(0.85, 0.5, 0.25), Color(0.3, 0.55, 0.3)]
	var amp := maxf(def.terrain_amp, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in res + 1:
		for xi in res + 1:
			var x := lo.x + xi * step.x
			var z := lo.y + zi * step.y
			var h := ground_y(x, z)
			var t := clampf(h / amp * 0.5 + 0.5, 0.0, 1.0)
			var c := low.lerp(high, t)
			var nz := _noise2.get_noise_2d(x, z)
			c = c.lerp(accent, clampf(nz * 1.5, 0.0, 0.6))
			if def.get("fields", false):
				var cell := _noise2.get_noise_2d(floorf(x / 45.0) * 9.1, floorf(z / 30.0) * 7.3)
				var idx := int(floor((cell * 0.5 + 0.5) * fields.size())) % fields.size()
				var far := smoothstep(hw + 25.0, hw + 60.0, nearest(x, z, 70.0)[0])
				c = c.lerp(fields[idx], 0.55 * far)
			if _river.size() > 1:
				var rd := _river_dist(x, z)
				c = c.lerp(Color(0.25, 0.5, 0.15), clampf(1.0 - (rd - _river_w * 0.5) / 60.0, 0.0, 1.0) * 0.7)
				c = c.lerp(Color(0.45, 0.4, 0.3), clampf(1.0 - (rd - _river_w * 0.5 + 5.0) / 10.0, 0.0, 1.0))
			st.set_color(c)
			st.set_uv(Vector2(x, z) / 9.0)
			st.add_vertex(Vector3(x, h, z))
	var w := res + 1
	for zi in res:
		for xi in res:
			var a := zi * w + xi
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + w)
			st.add_index(a + 1)
			st.add_index(a + w + 1)
			st.add_index(a + w)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _detail_texture()
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _detail_texture() -> ImageTexture:
	var nz := FastNoiseLite.new()
	nz.seed = 9
	nz.frequency = 0.09
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := 0.82 + nz.get_noise_2d(x, y) * 0.15 + randf() * 0.06
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_river() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := PackedVector3Array()
	for i in _river.size() - 1:
		for k in 10:
			pts.append(_river[i].lerp(_river[i + 1], k / 10.0))
	pts.append(_river[_river.size() - 1])
	for i in pts.size():
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var r := d.cross(Vector3.UP).normalized() * (_river_w * 0.5 + 8.0)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(pts[i].x, -1.2, pts[i].z) - r)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(pts[i].x, -1.2, pts[i].z) + r)
	for i in pts.size() - 1:
		var a := i * 2
		for idx in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(idx)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.35, 0.45)
	mat.roughness = 0.08
	mat.metallic = 0.3
	mat.metallic_specular = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _build_supports() -> void:
	var k := MeshKit.new()
	var wood := Color(0.35, 0.26, 0.18)
	var stone := Color(0.4, 0.38, 0.33)
	# deck under the road
	for i in n:
		var j := (i + 1) % n
		var w := limit + 0.3
		var a0 := P[i] - R[i] * w
		var a1 := P[i] + R[i] * w
		var b0 := P[j] - R[j] * w
		var b1 := P[j] + R[j] * w
		var dn := Vector3(0, -1.4, 0)
		k.quad(a0 + dn, b0 + dn, b1 + dn, a1 + dn, wood.darkened(0.3))
		k.quad(a0, b0, b0 + dn, a0 + dn, wood)
		k.quad(a1, a1 + dn, b1 + dn, b1, wood)
	for i in range(0, n, 16):
		var g := ground_y(P[i].x, P[i].z)
		for s: float in [-1.0, 1.0]:
			var top := P[i] + R[i] * s * (limit - 1.0) + Vector3(0, -1.2, 0)
			k.cyl(Vector3(top.x, g - 1.0, top.z), top, 1.3, 0.8, stone, 7)
		k.cyl(P[i] - R[i] * (limit - 1.0) + Vector3(0, -1.3, 0), P[i] + R[i] * (limit - 1.0) + Vector3(0, -1.3, 0), 0.5, 0.5, wood, 5)
		if i % 48 == 0:
			k.ring(Vector3(P[i].x, g + 4.0, P[i].z) + R[i] * (limit - 1.0), Vector3.UP, 1.8, 0.2, def.line_col, 12, 3, true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


func _build_ley_lines() -> void:
	var k := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for line in 14:
		var p := Vector3(rng.randf_range(-600, 600), 0, rng.randf_range(-700, 400))
		var dir := rng.randf() * TAU
		for s in 30:
			dir += rng.randf_range(-0.35, 0.35)
			var q := p + Vector3(cos(dir), 0, sin(dir)) * 12.0
			var a := Vector3(p.x, ground_y(p.x, p.z) + 0.25, p.z)
			var b := Vector3(q.x, ground_y(q.x, q.z) + 0.25, q.z)
			var sd := (b - a).cross(Vector3.UP).normalized() * 0.7
			k.quad(a - sd, a + sd, b + sd, b - sd, Color(0.45, 1.0, 0.5), true)
			p = q
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


func _build_start_gantry() -> void:
	var k := MeshKit.new()
	var w := limit + 0.5
	var p := P[0]
	var b := Basis(R[0], Vector3.UP, R[0].cross(Vector3.UP))
	k.xf = Transform3D(b, p)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * w, 4.5, 0), Vector3(0.8, 9.0, 0.8), Color(0.2, 0.2, 0.24))
	k.box(Vector3(0, 8.6, 0), Vector3(w * 2.0 + 0.8, 1.6, 1.0), Color(0.15, 0.15, 0.2))
	for c in 16:
		var x := -w + (c + 0.5) * w * 2.0 / 16.0
		k.box(Vector3(x, 8.6, 0.52), Vector3(w * 2.0 / 16.0, 0.8, 0.05), Color.WHITE if c % 2 == 0 else Color(0.05, 0.05, 0.05))
	for c in 5:
		k.sphere(Vector3(-2.4 + c * 1.2, 7.4, 0.55), Vector3.ONE * 0.35, Props.AETHER, 6, 3, true)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


# --- scenery ---------------------------------------------------------------------

func _place_ok(pos: Vector3, rad: float) -> bool:
	var nr := nearest(pos.x, pos.z, rad + limit + 4.0)
	if nr[1] >= 0 and nr[0] < limit + rad + 1.0:
		return false
	if _river.size() > 1 and _river_dist(pos.x, pos.z) < _river_w * 0.5 + rad + 2.0:
		return false
	return true


func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.name) + 11
	var by_mesh := {}   # "kind/variant" -> Array[Transform3D]
	for spec in def.props:
		var kind: String = spec[0]
		var count := int(spec[1] * density)
		var dmin: float = spec[2]
		var dmax: float = spec[3]
		var rad: float = Props.RADIUS.get(kind, 4.0)
		var edge := kind in ["lamp_tall", "banner"]
		for c in count:
			var pos := Vector3.ZERO
			var ok := false
			for attempt in 6:
				var i := rng.randi() % n
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				if edge:
					i = int(float(c) / count * n)
					side = -1.0 if c % 2 == 0 else 1.0
				var d := limit + rng.randf_range(dmin, dmax) if not edge else limit + dmin
				pos = P[i] + R[i] * side * d
				if edge:
					pos.y = P[i].y if elevated else ground_y(pos.x, pos.z)
					ok = true
					break
				if _place_ok(pos, rad):
					pos.y = ground_y(pos.x, pos.z)
					ok = true
					break
			if not ok:
				continue
			var s := rng.randf_range(0.85, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos)
			if kind in Props.ANIMATED:
				_animated_prop(kind, xf, rng.randi() % Props.VARIANTS)
				continue
			var key := "%s/%d" % [kind, rng.randi() % Props.VARIANTS]
			if not by_mesh.has(key):
				by_mesh[key] = []
			by_mesh[key].append(xf)
	for key in by_mesh:
		var parts: PackedStringArray = key.split("/")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Props.prop(parts[0], int(parts[1]), night)
		mm.instance_count = by_mesh[key].size()
		for i in by_mesh[key].size():
			mm.set_instance_transform(i, by_mesh[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if parts[0] in ["city", "giant_tree", "palm", "obelisk", "column"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _animated_prop(kind: String, xf: Transform3D, v: int) -> void:
	var node := Node3D.new()
	node.transform = xf
	var mi := MeshInstance3D.new()
	mi.mesh = Props.prop(kind, v, night)
	node.add_child(mi)
	match kind:
		"windmill":
			var rotor := MeshInstance3D.new()
			rotor.mesh = Props.windmill_rotor()
			rotor.position = Vector3(0, 16.5, 1.7)
			node.add_child(rotor)
			_rotors.append(rotor)
		"geyser":
			var steam := Props.particles(40 if Game.quality != Game.LOW else 15, 4.0, Color(0.85, 1.0, 0.9, 0.5), 3.0, 7.0)
			steam.direction = Vector3.UP
			steam.spread = 6.0
			steam.initial_velocity_min = 18.0
			steam.initial_velocity_max = 30.0
			steam.gravity = Vector3(0, -4, 0)
			steam.position = Vector3(0, 1.5, 0)
			node.add_child(steam)
	add_child(node)


func _orient_to_road(pos: Vector3, i: int) -> Basis:
	var to_road := P[i] - pos
	to_road.y = 0
	if to_road.length() < 0.1:
		return Basis(R[i], Vector3.UP, R[i].cross(Vector3.UP))
	return Basis.looking_at(-to_road.normalized(), Vector3.UP)


func _build_arches() -> void:
	var every: float = def.arch_every
	var mesh := Props.arch(def.arch, hw * 2.0 + CURB * 2.0, night)
	var pos := 90.0
	while pos < length - 60.0:
		var i := idx_at(pos)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = Transform3D(Basis(R[i], Vector3.UP, R[i].cross(Vector3.UP)), P[i])
		add_child(mi)
		pos += every


func _build_landmarks() -> void:
	for lm in def.landmarks:
		var kind: String = lm[0]
		var i := idx_at(float(lm[1]) * length)
		var side: float = lm[2]
		var dist: float = lm[3]
		var sc: float = lm[4]
		if kind == "omen":
			var o := MeshInstance3D.new()
			o.mesh = Props.arch("omen", hw * 2.0 + CURB * 2.0, night)
			var oi := idx_at(40.0)
			o.transform = Transform3D(Basis(R[oi], Vector3.UP, R[oi].cross(Vector3.UP)), P[oi])
			add_child(o)
			var swirl := Props.particles(50 if Game.quality != Game.LOW else 16, 2.5, Color(0.5, 0.9, 1.0, 0.7), 0.5, 1.4)
			swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			swirl.emission_ring_axis = Vector3(0, 0, 1)
			swirl.emission_ring_radius = hw + CURB + 4.0
			swirl.emission_ring_inner_radius = hw + CURB + 2.5
			swirl.emission_ring_height = 0.5
			swirl.gravity = Vector3.ZERO
			swirl.orbit_velocity_min = 0.1
			swirl.orbit_velocity_max = 0.2
			swirl.position = Vector3(0, (hw + CURB + 4.5) * 0.55, 0)
			o.add_child(swirl)
			continue
		if kind == "pipeline":
			_build_pipeline(i, side, dist)
			continue
		var node := Props.landmark(kind, sc, night)
		var pos := P[i] + R[i] * side * (limit + dist)
		if kind == "moonrocks":
			pos = Vector3.ZERO
		elif elevated:
			pos.y = ground_y(pos.x, pos.z) - 1.0
		else:
			pos.y = ground_y(pos.x, pos.z) - 0.5
		node.position = pos
		node.basis = _orient_to_road(pos, i).scaled(Vector3.ONE * sc)
		if kind == "stands":
			# the crowd faces the road (local -z); rows rise away from it
			var away := R[i] * side
			var along := Vector3(T[i].x, 0, T[i].z).normalized() * side
			node.position = P[i] + away * (limit + dist + 4.0)
			node.position.y = P[i].y if elevated else ground_y(node.position.x, node.position.z)
			node.basis = Basis(along, Vector3.UP, away).scaled(Vector3.ONE * sc)
		add_child(node)
		var spin := node.get_node_or_null("Spin")
		if spin:
			_spin.append(spin)
		if kind == "dino":
			_dinos.append([node, node.position, T[i] * (1.0 if randf() < 0.5 else -1.0), randf() * TAU])


func _build_pipeline(i0: int, side: float, dist: float) -> void:
	var k := MeshKit.new()
	var steps := 34
	var prev := Vector3.ZERO
	for s in steps:
		var i := (i0 - steps * 4 + s * 8 + n) % n
		var p := P[i] + R[i] * side * (limit + dist)
		p.y = maxf(ground_y(p.x, p.z), P[i].y) + 9.0
		if s > 0:
			k.cyl(prev, p, 1.1, 1.1, Props.COPPER, 8, false, true, false)
			k.cyl(prev.lerp(p, 0.45), prev.lerp(p, 0.55), 1.25, 1.25, Props.AETHER, 8, true)
		if s % 2 == 0:
			k.cyl(Vector3(p.x, ground_y(p.x, p.z) - 1.0, p.z), p, 0.5, 0.4, Props.BRASS.darkened(0.3), 6)
		prev = p
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


func _build_flyers() -> void:
	var kind: String = def.get("flyers", "")
	if kind == "":
		return
	var k := MeshKit.new()
	if kind == "thopter":
		k.sphere(Vector3.ZERO, Vector3(0.5, 0.4, 1.2), Props.BRASS, 6, 4)
		k.quad(Vector3(0.3, 0.1, -0.3), Vector3(2.4, 0.4, 0.2), Vector3(2.2, 0.4, 0.8), Vector3(0.3, 0.1, 0.5), Color(0.6, 0.9, 1.0), true)
		k.quad(Vector3(-0.3, 0.1, -0.3), Vector3(-0.3, 0.1, 0.5), Vector3(-2.2, 0.4, 0.8), Vector3(-2.4, 0.4, 0.2), Color(0.6, 0.9, 1.0), true)
		k.cyl(Vector3(0, 0, 1.0), Vector3(0, 0, 2.2), 0.15, 0.05, Props.COPPER, 4)
	else:
		k.quad(Vector3(0, 0, -0.3), Vector3(1.4, 0.3, 0.2), Vector3(0.2, 0, 0.3), Vector3(-0.2, 0, 0.3), Color(0.15, 0.12, 0.1))
		k.quad(Vector3(0, 0, -0.3), Vector3(-0.2, 0, 0.3), Vector3(-1.4, 0.3, 0.2), Vector3(0, 0, -0.3), Color(0.15, 0.12, 0.1))
	var mesh := k.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for f in int(16 * density):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var c := P[rng.randi() % n]
		add_child(mi)
		_flyers.append([mi, c, rng.randf_range(25, 120), c.y + rng.randf_range(14, 45), rng.randf_range(0.15, 0.4) * (1 if rng.randf() < 0.5 else -1), rng.randf() * TAU])


func _build_fireworks() -> void:
	for f in 4:
		var p := Props.particles(70, 1.8, Color(1, 1, 1, 1), 0.8, 1.6)
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 18.0
		p.initial_velocity_max = 26.0
		p.gravity = Vector3(0, -6, 0)
		p.damping_min = 4.0
		p.damping_max = 6.0
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0, 0.1, 0.6, 1])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
		p.color_ramp = g
		p.material_override = null
		add_child(p)
		_fireworks.append(p)
	apply_quality()


# --- aether orbs --------------------------------------------------------------------

func _build_orbs() -> void:
	var k := MeshKit.new()
	k.sphere(Vector3.ZERO, Vector3.ONE * 0.55, Color(0.55, 0.95, 1.0), 8, 5, true)
	k.ring(Vector3.ZERO, Vector3(0.3, 1, 0), 0.95, 0.07, Props.BRASS, 12, 3)
	_orb_mm = MultiMesh.new()
	_orb_mm.transform_format = MultiMesh.TRANSFORM_3D
	_orb_mm.mesh = k.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.name) + 5
	var d := 180.0
	while d < length - 80.0:
		var lane := rng.randf_range(-0.6, 0.6) * hw
		for c in 4:
			var i := idx_at(d + c * 7.0)
			orbs.append([i, P[i] + R[i] * lane + Vector3(0, 1.3, 0), 0.0])
		d += rng.randf_range(220.0, 320.0)
	_orb_mm.instance_count = orbs.size()
	for i in orbs.size():
		_orb_mm.set_instance_transform(i, Transform3D(Basis(), orbs[i][1]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _orb_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Called by a car near sample i; returns true if it picked up an orb.
func collect_orb(pos: Vector3, i: int) -> bool:
	for oi in orbs.size():
		var o: Array = orbs[oi]
		if o[2] > 0.0:
			continue
		var di := absi(o[0] - i)
		if di > 4 and di < n - 4:
			continue
		if pos.distance_squared_to(o[1]) < 6.0:
			o[2] = ORB_RESPAWN
			_orb_mm.set_instance_transform(oi, Transform3D(Basis().scaled(Vector3.ONE * 0.001), o[1]))
			return true
	return false


# --- ambient ------------------------------------------------------------------------

## Drifting particles around the camera: aether motes, pollen, spores or blowing sand.
func make_ambient() -> CPUParticles3D:
	var kind: String = def.particles
	var p: CPUParticles3D
	match kind:
		"sand":
			p = Props.particles(120, 2.5, Color(0.95, 0.8, 0.55, 0.45), 0.25, 0.7)
			p.gravity = Vector3(18, -1, 4)
		"spores":
			p = Props.particles(90, 6.0, Color(0.7, 1.0, 0.5, 0.8), 0.12, 0.3)
			p.gravity = Vector3(0, 0.4, 0)
		"pollen":
			p = Props.particles(60, 6.0, Color(1.0, 0.95, 0.75, 0.6), 0.08, 0.2)
			p.gravity = Vector3(0.8, 0.1, 0)
		_:
			p = Props.particles(90, 5.0, Color(0.5, 0.95, 1.0, 0.8), 0.1, 0.25)
			p.gravity = Vector3(0, 0.6, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(40, 12, 40)
	p.local_coords = false
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.5
	p.spread = 180.0
	p.preprocess = 3.0
	return p


func _process(dt: float) -> void:
	_t += dt
	for s in _spin:
		s.rotate_y(dt * 0.25)
	for r in _rotors:
		r.rotate_z(dt * 1.2)
	for d in _dinos:
		var node: Node3D = d[0]
		var ph: float = d[3] + _t * 0.04
		node.position = d[1] + d[2] * sin(ph) * 40.0
		node.position.y = d[1].y + absf(sin(_t * 1.6 + d[3])) * 0.4
		var heading: Vector3 = d[2] * (1.0 if cos(ph) >= 0.0 else -1.0)
		var sc := node.basis.get_scale()
		var yaw := lerp_angle(node.basis.get_euler().y, atan2(-heading.x, -heading.z), clampf(dt * 0.5, 0.0, 1.0))
		node.basis = Basis(Vector3.UP, yaw).scaled(sc)
	for f in _flyers:
		var a: float = f[5] + _t * f[4]
		var mi: Node3D = f[0]
		var c: Vector3 = f[1]
		mi.position = Vector3(c.x + cos(a) * f[2], f[3] + sin(_t * 0.7 + f[5]) * 3.0, c.z + sin(a) * f[2])
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(f[4])
		mi.basis = Basis.looking_at(tangent, Vector3.UP)
	for oi in orbs.size():
		var o: Array = orbs[oi]
		if o[2] > 0.0:
			o[2] -= dt
			if o[2] <= 0.0:
				o[2] = 0.0
				_orb_mm.set_instance_transform(oi, Transform3D(Basis(), o[1]))
	if _fireworks.size() > 0 and Game.quality != Game.LOW:
		_firework_t -= dt
		if _firework_t <= 0.0:
			_firework_t = randf_range(0.5, 1.4)
			var fw: CPUParticles3D = _fireworks[randi() % _fireworks.size()]
			var i := randi() % n
			fw.position = P[i] + R[i] * randf_range(-80, 80) + Vector3(0, randf_range(50, 90), 0)
			fw.color = Color.from_hsv(randf(), 0.6, 1.0) * 1.6
			fw.restart()
