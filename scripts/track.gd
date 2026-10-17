class_name Track
extends Node3D
## Builds one track from its entry in Tracks.LIST: the smoothed racing line, road, curbs and
## rails, terrain, river, sky and light, scenery, arches, landmarks, aether orbs and ambient
## particles. Also answers the questions the cars ask every frame: where along the lap am I,
## how far from the centre line, how high is the road here.

const SPACING := 2.0          # metres between centre-line samples
const CURB := 1.3             # curb width beyond the road edge
const ORB_RESPAWN := 8.0
## Indoor stretches (Tracks.LIST "indoor"): how each looks and the light inside. shape "hall" is
## a built tunnel with flat walls and ribs, "cave" a rough rock (or wood) bore. outside "rock"
## wraps it in a lumpy hill, "block" in a building, "log" in a hollow trunk (elevated track).
const INDOOR := {
	"foundry": {"shape": "hall", "outside": "block", "wall": Color(0.26, 0.2, 0.19), "trim": Color(0.78, 0.45, 0.22),
		"lamp": Color(1.0, 0.5, 0.15), "ambient": Color(0.8, 0.55, 0.45), "ambient_energy": 0.6, "fog": Color(0.35, 0.15, 0.08), "fog_density": 0.012, "sun": 0.1},
	"cave": {"shape": "cave", "outside": "rock", "wall": Color(0.42, 0.36, 0.3), "trim": Color(0.45, 0.32, 0.2),
		"lamp": Color(1.0, 0.75, 0.4), "ambient": Color(0.85, 0.72, 0.6), "ambient_energy": 0.8, "fog": Color(0.2, 0.16, 0.12), "fog_density": 0.01, "sun": 0.1},
	"temple": {"shape": "hall", "outside": "block", "wall": Color(0.72, 0.6, 0.42), "trim": Color(0.95, 0.75, 0.3),
		"lamp": Color(1.0, 0.6, 0.25), "ambient": Color(0.85, 0.65, 0.45), "ambient_energy": 0.5, "fog": Color(0.4, 0.3, 0.2), "fog_density": 0.008, "sun": 0.15},
	"hollow": {"shape": "cave", "outside": "log", "wall": Color(0.36, 0.25, 0.15), "trim": Color(0.25, 0.18, 0.1),
		"lamp": Color(0.5, 1.0, 0.45), "ambient": Color(0.55, 0.8, 0.5), "ambient_energy": 0.75, "fog": Color(0.1, 0.2, 0.08), "fog_density": 0.012, "sun": 0.1},
	"tomb": {"shape": "hall", "outside": "rock", "wall": Color(0.62, 0.45, 0.3), "trim": Color(0.95, 0.75, 0.3),
		"lamp": Color(0.35, 0.6, 1.0), "ambient": Color(0.7, 0.68, 0.8), "ambient_energy": 0.8, "fog": Color(0.12, 0.12, 0.2), "fog_density": 0.01, "sun": 0.1},
	"conduit": {"shape": "hall", "outside": "block", "wall": Color(0.16, 0.15, 0.2), "trim": Color(0.85, 0.66, 0.3),
		"lamp": Color(0.35, 0.9, 1.0), "ambient": Color(0.35, 0.6, 0.9), "ambient_energy": 0.6, "fog": Color(0.05, 0.15, 0.25), "fog_density": 0.01, "sun": 0.1},
}
## Metres over which the light changes at a tunnel mouth.
const INDOOR_FADE := 30.0

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
var indoor: Array = []          # {kind, def, i0, i1} per indoor stretch
var inside := PackedFloat32Array()   # per sample: 0 outdoors, 1 under a roof (eased at the mouths)
var _inside_of := PackedInt32Array() # per sample: which indoor stretch is nearest (-1 none)
var fog_mul := 1.0              # set by world events (sandstorm)
var _view_i := 0
var _orb_mm: MultiMesh
var _t := 0.0


func build(track_def: Dictionary) -> void:
	def = track_def
	Game.set_paint_sky(def)
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
	_mark_indoor()
	_build_grid()
	_build_environment()
	_build_road()
	_build_edges()
	_build_indoor()
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
	# drive the layout a metre at a time
	var dense := PackedVector3Array()
	var pos := Vector3.ZERO
	var head := 0.0
	dense.append(pos)
	for c: Array in def.layout:
		if c[0] == "S":
			var k := maxi(1, ceili(c[1]))
			for q in k:
				pos += Vector3(cos(head), 0, -sin(head)) * (c[1] / k)
				dense.append(pos)
		else:
			var ang := deg_to_rad(c[2]) * (1.0 if c[0] == "L" else -1.0)
			var arc: float = c[1] * absf(ang)
			var k := maxi(1, ceili(arc))
			for q in k:
				head += ang / k * 0.5
				pos += Vector3(cos(head), 0, -sin(head)) * (arc / k)
				head += ang / k * 0.5
				dense.append(pos)
	# close the loop: spread the gap between the end and the start over the lap, then add heights
	var cum := PackedFloat32Array([0.0])
	for i in range(1, dense.size()):
		cum.append(cum[i - 1] + dense[i - 1].distance_to(dense[i]))
	var gap := dense[dense.size() - 1]
	var lap := cum[cum.size() - 1]
	dense.resize(dense.size() - 1)
	for i in dense.size():
		var f := cum[i] / lap
		dense[i] = dense[i] - gap * f + Vector3(0, _height_at(f), 0)
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


## Road height at fraction `f` of the lap from the track's "heights" keys, eased between them.
func _height_at(f: float) -> float:
	var keys: Array = def.heights
	var m := keys.size()
	for q in m:
		var a: Array = keys[q]
		var b: Array = keys[(q + 1) % m]
		var fa: float = a[0]
		var fb: float = b[0] + (1.0 if q == m - 1 else 0.0)
		var ff := f if f >= fa else f + 1.0
		if ff >= fa and ff <= fb:
			var t := (ff - fa) / maxf(fb - fa, 0.0001)
			return lerpf(a[1], b[1], (1.0 - cos(t * PI)) * 0.5)
	return keys[0][1]


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

## Road surface, one texture repeat (u across the road, v along 10 m of it): the track's own
## pattern (tile, pavers, stone slabs or planks) with bevelled joints, fine aggregate grain,
## rubbered racing lines and crisp painted lines. 1024 px on High, 512 otherwise. Everything that
## depends on only u or only v is worked out once per column or row.
func _road_texture() -> ImageTexture:
	var sz := 1024 if Game.quality == Game.HIGH else 512
	var px := sz / 1024.0
	var base: Color = def.road_col
	var line: Color = def.line_col
	var style: String = def.road
	# fine grain repeats every 256 px; the large blotches are made at half size (both are slow)
	var fine := FastNoiseLite.new()
	fine.seed = hash(def.name) + 4
	fine.frequency = 0.3
	var blot := FastNoiseLite.new()
	blot.seed = hash(def.name) + 5
	blot.frequency = 0.024 / px
	blot.fractal_octaves = 3
	var fd := fine.get_seamless_image(256, 256).get_data()
	var hs := sz / 2
	var bd := blot.get_seamless_image(hs, hs).get_data()
	var joint := Color(0.55, 0.32, 0.18) if style == "tile" else base.darkened(0.45 if style != "planks" else 0.65)
	# the pattern: blocks per row of the texture (cols), rows, and how far each row is shifted
	var cols := 6.0
	var rows := 4.0
	var shift := 0.0
	var tone_amp := 0.08
	match style:
		"pavers":
			cols = 10.0
			rows = 16.0
			shift = 0.5
			tone_amp = 0.15
		"stone":
			cols = 4.0
			rows = 3.0
			shift = 0.37
			tone_amp = 0.12
		"planks":
			cols = 1.0
			rows = 12.0
			tone_amp = 0.15
	var nrows := int(rows)
	# per row of blocks: joint distance and block index for every column
	var du: Array = []
	var cu: Array = []
	for br in nrows:
		var dd := PackedFloat32Array()
		var cc := PackedInt32Array()
		dd.resize(sz)
		cc.resize(sz)
		var off := fposmod(br * shift, 1.0)
		for x in sz:
			var c := (x + 0.5) / sz * cols + off
			var fr := fposmod(c, 1.0)
			dd[x] = 99.0 if style == "planks" else minf(fr, 1.0 - fr) * sz / cols
			cc[x] = int(floorf(c))
		du.append(dd)
		cu.append(cc)
	var tone := {}
	# per column: rubber on the racing lines, grime at the edges, painted lines
	var wear := PackedFloat32Array()
	var grime := PackedFloat32Array()
	var edge := PackedFloat32Array()
	var dash := PackedFloat32Array()
	var nail_x := PackedByteArray()
	wear.resize(sz)
	grime.resize(sz)
	edge.resize(sz)
	dash.resize(sz)
	nail_x.resize(sz)
	for x in sz:
		var u := (x + 0.5) / sz
		wear[x] = exp(-pow((u - 0.33) / 0.07, 2.0)) + exp(-pow((u - 0.67) / 0.07, 2.0))
		grime[x] = 1.0 - clampf(1.0 - minf(u, 1.0 - u) / 0.08, 0.0, 1.0) * 0.12
		edge[x] = clampf(minf(u - 0.025, 0.045 - u) * sz + 0.5, 0.0, 1.0) + clampf(minf(u - 0.955, 0.975 - u) * sz + 0.5, 0.0, 1.0)
		dash[x] = clampf((0.007 - absf(u - 0.5)) * sz + 0.5, 0.0, 1.0) * 0.85
		nail_x[x] = 1 if style == "planks" and (absf(u - 0.07) * sz < 2.5 * px + 0.8 or absf(u - 0.5) * sz < 2.5 * px + 0.8 or absf(u - 0.93) * sz < 2.5 * px + 0.8) else 0
	var jw := 3.0 * px + 1.0
	var plank_wear := style == "planks"
	var stone := style == "stone"
	var lr := line.r
	var lg := line.g
	var lb := line.b
	var data := PackedByteArray()
	data.resize(sz * sz * 3)
	for y in sz:
		var v := (y + 0.5) / sz
		var rv := v * rows
		var br := int(floorf(rv)) % nrows
		var fr := fposmod(rv, 1.0)
		var dv := minf(fr, 1.0 - fr) * sz / rows * (1.3 if plank_wear else 1.0)
		var nail_y := plank_wear and absf(absf(fr - 0.5) - 0.28) * sz / rows < 2.5 * px + 0.8
		var dash_v := clampf(minf(v - 0.02, 0.5 - v) * sz + 0.5, 0.0, 1.0)
		var row_du: PackedFloat32Array = du[br]
		var row_cu: PackedInt32Array = cu[br]
		var last_cell := -999
		var t := 0.0
		for x in sz:
			var i := y * sz + x
			var f := fd[(y & 255) * 256 + (x & 255)] / 255.0 - 0.5
			var b := bd[(y >> 1) * hs + (x >> 1)] / 255.0 - 0.5
			var cell := row_cu[x]
			if cell != last_cell:
				var key := cell * 64 + br
				if not tone.has(key):
					tone[key] = (_hash01(float(cell), float(br)) * 2.0 - 1.0) * tone_amp
				t = tone[key]
				last_cell = cell
			var m := 1.0 + t + f * 0.2 + b * 0.12
			if plank_wear:
				m += sin(x * 170.0 / sz + b * 30.0 + br * 2.0) * 0.035
				if nail_y and nail_x[x] == 1:
					m -= 0.35
			var d := minf(row_du[x], dv)
			if stone and absf(b) < 0.0025 and f > 0.05:
				d = 0.0
			var cr: float
			var cg: float
			var cb: float
			if d < jw:
				var jm := 1.0 - f * 0.3
				cr = joint.r * jm
				cg = joint.g * jm
				cb = joint.b * jm
			else:
				if d < jw * 3.0:
					m *= 1.0 - (1.0 - (d - jw) / (jw * 2.0)) * 0.2
				if plank_wear:
					m += wear[x] * 0.06 * (0.6 + b)
				else:
					m *= 1.0 - wear[x] * 0.13 * clampf(0.6 + b * 1.5, 0.0, 1.2)
				m *= grime[x]
				cr = base.r * m
				cg = base.g * m
				cb = base.b * m
			var cov := maxf(edge[x], dash[x] * dash_v)
			if cov > 0.0:
				var lm := 1.0 - clampf(f * 0.25 + 0.05, 0.0, 0.2)
				cr = lerpf(cr, lr * lm, cov)
				cg = lerpf(cg, lg * lm, cov)
				cb = lerpf(cb, lb * lm, cov)
			data[i * 3] = int(clampf(cr, 0.0, 1.0) * 255.0)
			data[i * 3 + 1] = int(clampf(cg, 0.0, 1.0) * 255.0)
			data[i * 3 + 2] = int(clampf(cb, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Repeatable pseudo-random 0..1 for a pair of cell coordinates.
static func _hash01(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


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
	# curbs: alternating colour blocks with a rounded, raised profile (outward offset, height)
	var k := MeshKit.new()
	var ca: Color = def.curb[0]
	var cb: Color = def.curb[1]
	var prof := [Vector2(0.0, 0.065), Vector2(0.12, 0.12), Vector2(0.32, 0.15), Vector2(CURB - 0.32, 0.15), Vector2(CURB - 0.1, 0.09), Vector2(CURB, 0.02)]
	for i in n:
		var j := (i + 1) % n
		var col := ca if (i / 2) % 2 == 0 else cb
		for s: float in [-1.0, 1.0]:
			for q in prof.size() - 1:
				var pa: Vector2 = prof[q]
				var pb: Vector2 = prof[q + 1]
				var a0 := P[i] + R[i] * s * (hw + pa.x) + Vector3(0, pa.y, 0)
				var a1 := P[j] + R[j] * s * (hw + pa.x) + Vector3(0, pa.y, 0)
				var b0 := P[i] + R[i] * s * (hw + pb.x) + Vector3(0, pb.y, 0)
				var b1 := P[j] + R[j] * s * (hw + pb.x) + Vector3(0, pb.y, 0)
				var shade := col.lightened(0.06) if q == 2 else (col if q % 2 == 1 else col.darkened(0.12))
				Props.quad_f(k, a0, b0, b1, a1, Vector3.UP, shade)
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
	var kind: String = def.edge
	if kind == "none":
		return
	var k := MeshKit.new()
	var glow := kind == "glowrail"
	var post := Color(0.3, 0.25, 0.25) if not elevated else Color(0.35, 0.26, 0.18)
	var gcol: Color = def.line_col
	for s: float in [-1.0, 1.0]:
		if glow:
			# copper tube rail, a flat lower bar and an aether strip on top
			_sweep(k, s, _circle(Vector2(0.0, 0.92), 0.11, 8), Props.COPPER, 3)
			_sweep(k, s, PackedVector2Array([Vector2(-0.04, 0.42), Vector2(0.04, 0.42), Vector2(0.05, 0.56), Vector2(0.04, 0.7), Vector2(-0.04, 0.7), Vector2(-0.05, 0.56)]), Props.COPPER.darkened(0.3), 3)
			_sweep(k, s, _circle(Vector2(0.0, 1.1), 0.055, 5), gcol, 3, true)
		else:
			# a rounded crash barrier on posts
			_sweep(k, s, PackedVector2Array([Vector2(-0.05, 0.5), Vector2(0.06, 0.53), Vector2(0.11, 0.62), Vector2(0.07, 0.72), Vector2(0.11, 0.83), Vector2(0.06, 0.92), Vector2(-0.05, 0.95), Vector2(-0.08, 0.72)]), Color(0.75, 0.72, 0.7), 3)
		for i in range(0, n, 6):
			var a := P[i] + R[i] * s * (limit + 0.18)
			if glow:
				k.cyl(a + Vector3(0, -0.1, 0), a + Vector3(0, 1.0, 0), 0.09, 0.08, post, 8, false, true, false)
				k.sphere(a + Vector3(0, 1.1, 0), Vector3(0.13, 0.13, 0.13), Props.BRASS, 8, 4)
			else:
				var yaw := atan2(R[i].x, R[i].z)
				k.box(a + Vector3(0, 0.45, 0), Vector3(0.2, 1.1, 0.2), post, false, yaw)
				k.taper(a + Vector3(0, 1.0, 0), Vector2(0.28, 0.28), Vector2(0.04, 0.04), 0.18, Props.BRASS.darkened(0.2), false, yaw)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	add_child(mi)


## Points round a circle in the (outward, height) plane, for `_sweep`.
func _circle(c: Vector2, r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for q in segs:
		var a := TAU * q / segs
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Extrudes the closed profile `prof` (x: outward from the wall line, y: height) along side `s`
## of the track, a section every `step` samples. Normals point away from the profile's centre.
func _sweep(k: MeshKit, s: float, prof: PackedVector2Array, col: Color, step: int, glow := false) -> void:
	var cen := Vector2.ZERO
	for p in prof:
		cen += p
	cen /= prof.size()
	var m := prof.size()
	var idxs: Array = range(0, n, step)
	idxs.append(0)
	var prev := PackedVector3Array()
	var prevn := PackedVector3Array()
	for ii in idxs.size():
		var i: int = idxs[ii]
		var out := R[i] * s
		var cur := PackedVector3Array()
		var curn := PackedVector3Array()
		for p in prof:
			cur.append(P[i] + out * (limit + p.x) + Vector3(0, p.y, 0))
			var d := (p - cen).normalized()
			curn.append((out * d.x + Vector3(0, d.y, 0)).normalized())
		if ii > 0:
			for j in m:
				var j1 := (j + 1) % m
				Props.tri_n(k, prev[j], cur[j], cur[j1], prevn[j], curn[j], curn[j1], col, glow)
				Props.tri_n(k, prev[j], cur[j1], prev[j1], prevn[j], curn[j1], prevn[j1], col, glow)
		prev = cur
		prevn = curn


# --- indoor stretches --------------------------------------------------------------

func _mark_indoor() -> void:
	inside.resize(n)
	_inside_of.resize(n)
	_inside_of.fill(-1)
	var fade := int(INDOOR_FADE / SPACING)
	for spec: Array in def.get("indoor", []):
		var i0 := idx_at(float(spec[1]) * length)
		var i1 := idx_at(float(spec[2]) * length)
		indoor.append({"kind": spec[0], "def": INDOOR[spec[0]], "i0": i0, "i1": i1})
		# the light starts to change a little before the mouth and is fully inside soon after it
		for k in range(i0 - fade, i1 + fade + 1):
			var i := (k + n) % n
			var f := smoothstep(float(i0 - fade), float(i0 + fade * 0.5), float(k)) * (1.0 - smoothstep(float(i1 - fade * 0.5), float(i1 + fade), float(k)))
			if f >= inside[i]:
				inside[i] = f
				_inside_of[i] = indoor.size() - 1


## True if sample i is under a roof (props, arches and events keep out).
func is_indoor(i: int, margin := 0) -> bool:
	for st: Dictionary in indoor:
		if i >= st.i0 - margin and i <= st.i1 + margin:
			return true
	return false


## Called every frame with the camera position: blends the sky light, fog and sun towards the
## indoor stretch's own light as the camera goes in.
func update_view(cam: Vector3) -> void:
	var nr := nearest(cam.x, cam.z, 60.0)
	_view_i = locate(cam, nr[1] if nr[1] >= 0 else _view_i)
	var f := inside[_view_i]
	var amb: Color = def.ambient
	var amb_e: float = def.ambient_energy
	var fog: Color = def.fog
	var fog_d: float = def.fog_density
	var sun_e: float = def.sun_energy
	if f > 0.0:
		var d: Dictionary = indoor[_inside_of[_view_i]].def
		amb = amb.lerp(d.ambient, f)
		amb_e = lerpf(amb_e, d.ambient_energy, f)
		fog = fog.lerp(d.fog, f)
		fog_d = lerpf(fog_d, d.fog_density, f)
		sun_e = lerpf(sun_e, sun_e * d.sun, f)
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.fog_light_color = fog
	env.fog_density = fog_d * fog_mul
	sun.light_energy = sun_e


func _build_indoor() -> void:
	for st: Dictionary in indoor:
		var k := MeshKit.new()
		var d: Dictionary = st.def
		var rings: Array[int] = []
		var i: int = st.i0
		while i < st.i1:
			rings.append(i)
			i += 2
		rings.append(st.i1)
		var w := limit + 1.0
		var inner := _hall_profile(w, false) if d.shape == "hall" else _cave_profile(w, false)
		var outer: PackedVector2Array
		match d.outside:
			"rock": outer = _cave_profile(w + 14.0, true)
			"log": outer = _cave_profile(w + 3.0, true, true)
			_: outer = _hall_profile(w, true)
		var rough: bool = d.shape == "cave"
		# inner walls and roof, outer shell, both mouths
		_shell(k, rings, inner, d.wall, true, 0.18 if rough else 0.0, 7)
		_shell(k, rings, outer, d.wall.darkened(0.15) if d.outside != "rock" else _rock_col(), false, 0.3 if d.outside != "block" else 0.0, 8)
		for end in [rings[0], rings[rings.size() - 1]]:
			_mouth(k, end, inner, outer, 0.18 if rough else 0.0, 0.3 if d.outside != "block" else 0.0, d.trim if not rough else d.wall.darkened(0.3), end == rings[0])
		# a floor from the curbs to the walls
		for q in rings.size() - 1:
			var a: int = rings[q]
			var b: int = rings[q + 1]
			for sd: float in [-1.0, 1.0]:
				Props.quad_f(k, P[a] + R[a] * sd * (hw + CURB) + Vector3(0, 0.03, 0), P[b] + R[b] * sd * (hw + CURB) + Vector3(0, 0.03, 0),
					P[b] + R[b] * sd * (w + 0.5) + Vector3(0, 0.03, 0), P[a] + R[a] * sd * (w + 0.5) + Vector3(0, 0.03, 0), Vector3.UP, d.wall.darkened(0.45))
		_indoor_details(k, st, w)
		var mi := MeshInstance3D.new()
		mi.mesh = k.commit()
		add_child(mi)


func _rock_col() -> Color:
	var cols: Array = def.ground
	return (cols[0] as Color).lerp(Color(0.45, 0.4, 0.36), 0.75).darkened(0.3)


## Cross-section of a built hall from the right foot round to the left foot (x outward, y up).
func _hall_profile(w: float, outside: bool) -> PackedVector2Array:
	var t := 1.6 if outside else 0.0
	var pts := PackedVector2Array([Vector2(w + t, -0.3 - t * 2.0), Vector2(w + t, 4.0), Vector2(w + t, 8.0 + t * 0.5),
		Vector2(w - 1.8 + t, 10.2 + t), Vector2(w * 0.5, 11.6 + t), Vector2(0, 12.0 + t)])
	for q in range(pts.size() - 2, -1, -1):
		pts.append(Vector2(-pts[q].x, pts[q].y))
	return pts


## Cross-section of a rough bore (or, with `outside`, the hill or trunk round it).
func _cave_profile(w: float, outside: bool, log_shell := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := 10.5 + (w - limit) * (0.4 if not log_shell else 1.0)
	var segs := 12
	for q in segs + 1:
		var a := PI * q / segs
		pts.append(Vector2(cos(a) * w, -0.4 + sin(a) * h))
	if outside:
		# the hill runs down into the ground; the trunk closes under the deck
		var foot := -9.0 if not log_shell else -3.5
		pts.insert(0, Vector2(w * (1.15 if not log_shell else 0.9), foot))
		pts.append(Vector2(-w * (1.15 if not log_shell else 0.9), foot))
	return pts


## Pseudo-random bump (-1..1) for rough surfaces, fixed per place.
func _bump(p: Vector3, q: int) -> float:
	return _noise2.get_noise_3d(p.x * 3.0, p.z * 3.0, q * 37.0)


func _ring(i: int, prof: PackedVector2Array, rough: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in prof.size():
		var v := prof[q]
		var b := 1.0 + _bump(P[i], q) * rough if q > 0 and q < prof.size() - 1 else 1.0
		out.append(P[i] + R[i] * v.x * b + Vector3(0, v.y * b, 0))
	return out


## Sweeps a cross-section along the samples in `rings`; `inward` faces it towards the road.
func _shell(k: MeshKit, rings: Array[int], prof: PackedVector2Array, col: Color, inward: bool, rough: float, shade_every: int) -> void:
	var prev := _ring(rings[0], prof, rough)
	for r in range(1, rings.size()):
		var i: int = rings[r]
		var cur := _ring(i, prof, rough)
		var mid := P[i] + Vector3(0, 5.0, 0)
		for q in prof.size() - 1:
			var c := (prev[q] + cur[q + 1]) * 0.5
			var face := (mid - c) if inward else (c - mid)
			var tone := col.darkened(0.1 * float((q + int(r / float(shade_every))) % 3)) if rough > 0.0 else col.darkened(0.06 * float(q % 2))
			Props.quad_f(k, prev[q], cur[q], cur[q + 1], prev[q + 1], face, tone)
		prev = cur


## The wall face at a tunnel mouth, between the inner bore and the outer shell: the two outlines
## are walked together by how far round each one is.
func _mouth(k: MeshKit, i: int, inner: PackedVector2Array, outer: PackedVector2Array, ri: float, ro: float, col: Color, entry: bool) -> void:
	var a := _ring(i, inner, ri)
	var b := _ring(i, outer, ro)
	var face := -T[i] if entry else T[i]
	var na := a.size() - 1
	var nb := b.size() - 1
	var p := 0
	var q := 0
	while p < na or q < nb:
		var ta := float(p + 1) / na if p < na else 9.0
		var tb := float(q + 1) / nb if q < nb else 9.0
		if ta <= tb:
			Props.tri_n(k, a[p], a[p + 1], b[q], face, face, face, col)
			p += 1
		else:
			Props.tri_n(k, a[p], b[q + 1], b[q], face, face, face, col)
			q += 1


## Ribs, pillars, lamps and the like inside each kind of indoor stretch.
func _indoor_details(k: MeshKit, st: Dictionary, w: float) -> void:
	var d: Dictionary = st.def
	var kind: String = st.kind
	var lamp: Color = d.lamp
	var every := 7 if d.shape == "hall" else 9
	var cnt := 0
	for i in range(st.i0 + 3, st.i1 - 2, every):
		cnt += 1
		var yaw := atan2(R[i].x, R[i].z)
		var up := Vector3.UP
		for sd: float in [-1.0, 1.0]:
			var wall := P[i] + R[i] * sd * (w - 0.35)
			match kind:
				"temple":
					k.cyl(wall + R[i] * sd * -0.6, wall + R[i] * sd * -0.6 + up * 9.6, 0.75, 0.65, d.wall.lightened(0.1), 10)
					k.box(wall + R[i] * sd * -0.6 + up * 9.8, Vector3(1.9, 0.5, 1.9), d.trim, false, yaw)
					if cnt % 2 == 0:
						k.cyl(wall + R[i] * sd * -2.2, wall + R[i] * sd * -2.2 + up * 1.4, 0.35, 0.5, d.trim.darkened(0.3), 8)
						k.sphere(wall + R[i] * sd * -2.2 + up * 1.7, Vector3(0.45, 0.6, 0.45), lamp, 6, 4, true)
				"foundry":
					k.box(wall + up * 4.5, Vector3(0.7, 9.0, 0.7), d.trim.darkened(0.25), false, yaw)
					if cnt % 3 == 1:
						k.box(wall + R[i] * sd * 0.25 + up * 2.6, Vector3(0.1, 3.2, 4.5), lamp, true, yaw)
					k.cyl(wall + R[i] * sd * -0.5 + up * 6.6 - T[i] * SPACING * every * 0.5, wall + R[i] * sd * -0.5 + up * 6.6 + T[i] * SPACING * every * 0.5, 0.45, 0.45, d.trim, 10, false, true, false)
				"conduit":
					k.box(wall + up * 4.5, Vector3(0.6, 9.0, 0.9), d.trim.darkened(0.2), false, yaw)
					k.box(wall + R[i] * sd * 0.2 + up * 1.2, Vector3(0.12, 0.25, SPACING * every - 1.0), lamp, true, yaw)
				"tomb":
					k.box(wall + up * 4.5, Vector3(1.4, 9.0, 1.4), d.wall.darkened(0.15), false, yaw)
					k.box(wall + R[i] * sd * -0.75 + up * 6.8, Vector3(0.15, 0.3, 1.0), d.trim, false, yaw)
					k.sphere(wall + R[i] * sd * -0.9 + up * 4.2, Vector3(0.45, 0.65, 0.45), lamp, 6, 4, true)
					k.box(wall + R[i] * sd * -0.75 + up * 2.0, Vector3(0.12, 0.25, SPACING * every - 2.0), d.trim, true, yaw)
				"cave":
					k.cyl(wall + R[i] * sd * -0.6 + up * 3.6, wall + R[i] * sd * -0.6 + up * 4.8, 0.2, 0.2, d.trim, 6)
					k.sphere(wall + R[i] * sd * -0.6 + up * 4.2, Vector3(0.45, 0.6, 0.45), lamp, 6, 4, true)
					k.box(wall + R[i] * sd * -0.5 + up * 3.0, Vector3(0.45, 6.0, 0.45), d.trim, false, yaw)
				"hollow":
					var r := _bump(P[i], int(sd * 3.0))
					k.sphere(wall + R[i] * sd * -0.6 + up * (2.5 + r * 2.0), Vector3(0.5, 0.25, 0.5) * (1.0 + absf(r)), lamp, 6, 3, true)
		match kind:
			"cave":
				k.box(P[i] + up * 11.0, Vector3((w - 0.5) * 2.0, 0.45, 0.45), d.trim, false, yaw)
			"foundry", "tomb":
				k.box(P[i] + up * 11.2, Vector3((w - 1.5) * 2.0, 0.6, 0.7), d.trim.darkened(0.2), false, yaw)
			"temple":
				k.box(P[i] + up * 11.3, Vector3((w - 1.5) * 2.0, 0.5, 0.9), d.trim, false, yaw)
			"conduit":
				k.box(P[i] + up * 11.0, Vector3((w - 1.5) * 2.0, 0.5, 0.6), d.trim.darkened(0.3), false, yaw)
	# continuous lights along the roof
	if kind in ["conduit", "foundry", "tomb"]:
		for i in range(st.i0, st.i1, 2):
			var j := mini(i + 2, st.i1)
			k.cyl(P[i] + Vector3(0, 11.4, 0), P[j] + Vector3(0, 11.4, 0), 0.22, 0.22, d.lamp, 6, true, true, false)


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
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


## Grey ground detail multiplied over the terrain's vertex colours: soft patches, fine grit and
## dark specks; wind ripples on the dunes. Tiles seamlessly every 9 m.
func _detail_texture() -> ImageTexture:
	var sz := 512 if Game.quality != Game.LOW else 256
	var n1 := FastNoiseLite.new()
	n1.seed = 9
	n1.frequency = 8.0 / sz
	n1.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = 10
	n2.frequency = 64.0 / sz
	var d1 := n1.get_seamless_image(sz, sz).get_data()
	var d2 := n2.get_seamless_image(sz, sz).get_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var dunes: bool = def.get("dunes", false)
	var data := PackedByteArray()
	data.resize(sz * sz)
	for y in sz:
		for x in sz:
			var i := y * sz + x
			var a := d1[i] / 255.0 - 0.5
			var b := d2[i] / 255.0 - 0.5
			var v := 0.84 + a * 0.24 + b * 0.12 + rng.randf_range(-0.04, 0.04)
			if dunes:
				v += sin(TAU * (x * 18.0 / sz + y * 4.0 / sz) + a * 6.0) * 0.05
			elif rng.randf() < 0.025:
				v -= 0.14
			data[i] = int(clampf(v, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_L8, data)
	img.convert(Image.FORMAT_RGB8)
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
			k.cyl(Vector3(top.x, g - 1.0, top.z), top, 1.3, 0.8, stone, 10)
			k.cyl(top - Vector3(0, 0.5, 0), top, 1.1, 1.1, Props.BRASS.darkened(0.3), 10)
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
	var nr := nearest(pos.x, pos.z, rad + limit + 24.0)
	if nr[1] >= 0 and nr[0] < limit + rad + 1.0:
		return false
	# keep clear of the hills and buildings over indoor stretches
	if nr[1] >= 0 and nr[0] < limit + rad + 22.0 and is_indoor(nr[1], 6):
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
			var lite := Game.quality == Game.LOW or dmin >= 100.0
			var key := "%s/%d/%d" % [kind, rng.randi() % Props.VARIANTS, 1 if lite else 0]
			if not by_mesh.has(key):
				by_mesh[key] = []
			by_mesh[key].append(xf)
	for key in by_mesh:
		var parts: PackedStringArray = key.split("/")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Props.prop(parts[0], int(parts[1]), night, parts[2] == "1")
		mm.instance_count = by_mesh[key].size()
		for i in by_mesh[key].size():
			mm.set_instance_transform(i, by_mesh[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if parts[0] in ["city", "giant_tree", "palm", "obelisk", "column"] and parts[2] == "0" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _animated_prop(kind: String, xf: Transform3D, v: int) -> void:
	var node := Node3D.new()
	node.transform = xf
	var mi := MeshInstance3D.new()
	mi.mesh = Props.prop(kind, v, night, Game.quality == Game.LOW)
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
	# pillars stand just outside the walls
	var mesh := Props.arch(def.arch, maxf(hw * 2.0 + CURB * 2.0, (limit - 1.2) * 2.0), night)
	var pos := 90.0
	while pos < length - 60.0:
		var i := idx_at(pos)
		if is_indoor(i, 12):
			pos += 40.0
			continue
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
		if kind == "stands":
			while is_indoor(i, 30):
				i = (i + 20) % n
		var pos := P[i] + R[i] * side * (limit + dist)
		if kind not in ["moonrocks", "stands"]:
			pos = _clear_spot(i, side, dist, _radius(node) * sc + (40.0 if kind == "dino" else 0.0))
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


## Where a landmark of radius `rad` can stand beside sample i: `dist` metres out, or further out
## (then the other side) until it is clear of every part of the road and the indoor stretches.
func _clear_spot(i: int, side: float, dist: float, rad: float) -> Vector3:
	for sd: float in [side, -side]:
		var d := maxf(dist, rad * 0.8)
		for attempt in 16:
			var pos := P[i] + R[i] * sd * (limit + d)
			var nr := nearest(pos.x, pos.z, limit + rad + 30.0)
			if nr[1] < 0 or (nr[0] > limit + rad * 0.8 + 4.0 and not (nr[0] < limit + rad + 22.0 and is_indoor(nr[1], 6))):
				return pos
			d += 30.0
	return P[i] + R[i] * side * (limit + dist)


## Horizontal reach of a node's meshes from its origin (before its own scale).
func _radius(node: Node3D) -> float:
	var r := 0.0
	for c in node.get_children():
		if c is MeshInstance3D and c.mesh:
			var bb: AABB = c.transform * c.mesh.get_aabb()
			for x: float in [bb.position.x, bb.end.x]:
				for z: float in [bb.position.z, bb.end.z]:
					r = maxf(r, Vector2(x, z).length())
		if c is Node3D:
			r = maxf(r, _radius(c) * c.scale.x)
	return r


func _build_pipeline(i0: int, side: float, dist: float) -> void:
	var k := MeshKit.new()
	var steps := 34
	var prev := Vector3.ZERO
	for s in steps:
		var i := (i0 - steps * 4 + s * 8 + n) % n
		var p := P[i] + R[i] * side * (limit + dist)
		p.y = maxf(ground_y(p.x, p.z), P[i].y) + 9.0
		if s > 0:
			k.cyl(prev, p, 1.1, 1.1, Props.COPPER, 14, false, true, false)
			k.cyl(prev.lerp(p, 0.42), prev.lerp(p, 0.58), 1.18, 1.18, Props.AETHER, 14, true)
			k.cyl(prev.lerp(p, 0.4), prev.lerp(p, 0.42), 1.32, 1.32, Props.BRASS, 14)
			k.cyl(prev.lerp(p, 0.58), prev.lerp(p, 0.6), 1.32, 1.32, Props.BRASS, 14)
			var fl := (p - prev).normalized() * 0.25
			k.cyl(p - fl, p + fl, 1.35, 1.35, Props.BRASS.darkened(0.15), 14)
		if s % 2 == 0:
			var g := Vector3(p.x, ground_y(p.x, p.z) - 1.0, p.z)
			k.cyl(g, p - Vector3(0, 1.0, 0), 0.5, 0.4, Props.BRASS.darkened(0.3), 10)
			k.cyl(g, g + Vector3(0, 1.6, 0), 1.0, 0.8, Color(0.5, 0.45, 0.4), 10)
			k.cyl(p - Vector3(0, 1.2, 0), p - Vector3(0, 0.9, 0), 0.9, 0.9, Props.BRASS.darkened(0.2), 10)
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
