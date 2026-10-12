class_name Showcase
extends Node3D
## The menu backdrop: the chosen team's car turning on a glowing aether platform under the
## chosen track's sky, with the camera slowly circling.

var _sky: ShaderMaterial
var _env: Environment
var _sun: DirectionalLight3D
var _car_root: Node3D
var _ring: MeshInstance3D
var _cam: Camera3D
var _t := 0.0
var _team := -1


func _ready() -> void:
	_env = Environment.new()
	var sky := Sky.new()
	_sky = ShaderMaterial.new()
	_sky.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = _sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_hdr_threshold = 0.9
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(_sun)
	var k := MeshKit.new()
	k.cyl(Vector3(0, -0.6, 0), Vector3(0, 0, 0), 5.2, 5.0, Color(0.15, 0.13, 0.18), 32)
	k.cyl(Vector3(0, -4, 0), Vector3(0, -0.6, 0), 3.0, 5.2, Color(0.2, 0.16, 0.16), 32)
	for i in 12:
		var a := TAU * i / 12.0
		k.box(Vector3(cos(a) * 4.4, 0.02, sin(a) * 4.4), Vector3(0.9, 0.06, 0.2), Props.COPPER, false, -a)
	var plat := MeshInstance3D.new()
	plat.mesh = k.commit()
	add_child(plat)
	_ring = MeshInstance3D.new()
	add_child(_ring)
	_car_root = Node3D.new()
	add_child(_car_root)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.environment = _env
	_cam.h_offset = -2.3
	add_child(_cam)
	_cam.current = true
	set_track(0)


func set_track(i: int) -> void:
	var d: Dictionary = Tracks.LIST[i]
	_sky.set_shader_parameter("top_color", d.sky_top)
	_sky.set_shader_parameter("horizon_color", d.sky_horizon)
	_sky.set_shader_parameter("ground_color", d.sky_ground)
	_sky.set_shader_parameter("stars", d.stars)
	_sky.set_shader_parameter("aurora", d.aurora)
	_sky.set_shader_parameter("shattered", 1.0 if d.get("shattered", false) else 0.0)
	_sun.rotation_degrees = Vector3(-maxf(d.sun_elev, 20.0), d.sun_az, 0)
	var sd := _sun.transform.basis.z
	_sky.set_shader_parameter("sun_dir", sd)
	_sky.set_shader_parameter("sun_color", d.sun_color if d.sun_disc > 0.0 else Color.BLACK)
	_sky.set_shader_parameter("sun_disc", d.sun_disc)
	_sky.set_shader_parameter("moon_color", d.get("moon", Color.BLACK))
	_sky.set_shader_parameter("moon_dir", Vector3(-0.4, 0.35, -1.0).normalized())
	_sun.light_color = d.sun_color
	_sun.light_energy = maxf(d.sun_energy, 0.9)
	_env.ambient_light_color = d.ambient
	_env.ambient_light_energy = d.ambient_energy + 0.2
	var k := MeshKit.new()
	k.ring(Vector3(0, 0.05, 0), Vector3.UP, 4.9, 0.07, d.line_col * 0.6, 48, 3, true)
	k.ring(Vector3(0, 0.05, 0), Vector3.UP, 3.8, 0.04, d.line_col * 0.6, 48, 3, true)
	_ring.mesh = k.commit()


func set_team(i: int) -> void:
	if i == _team:
		return
	_team = i
	for c in _car_root.get_children():
		c.queue_free()
	var model := CarModels.build(Game.TEAMS[i])
	var mi := MeshInstance3D.new()
	mi.mesh = model.mesh
	mi.scale = Vector3.ONE * 1.25
	_car_root.add_child(mi)
	for w in model.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = model.wheel
		wm.position = w * 1.25
		wm.scale = Vector3.ONE * 1.25
		_car_root.add_child(wm)


func _process(dt: float) -> void:
	_t += dt
	_car_root.rotation.y = _t * 0.35
	var a := _t * 0.06 + 0.6
	_cam.look_at_from_position(Vector3(cos(a) * 9.5, 2.6, sin(a) * 9.5), Vector3(0, 0.9, 0), Vector3.UP)
