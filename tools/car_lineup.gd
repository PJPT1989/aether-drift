extends Node3D
## Art check: every team's car side by side, saved as screenshots from a few angles.
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 -- --lineup [--out=dir]

func _ready() -> void:
	var out := "/tmp/aether-cars"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var d: Dictionary = Tracks.LIST[1]
	Game.set_paint_sky(d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.55, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.38)
	ground.material_override = gm
	add_child(ground)
	for i in Game.TEAMS.size():
		var model := CarModels.build(Game.TEAMS[i])
		var root := Node3D.new()
		root.position = Vector3((i % 4) * 3.2 - 4.8, 0, (i / 4) * 6.0 - 3.0)
		root.rotation.y = 0.0
		add_child(root)
		var mi := MeshInstance3D.new()
		mi.mesh = model.mesh
		root.add_child(mi)
		for w in model.wheels:
			var wm := MeshInstance3D.new()
			wm.mesh = model.wheel
			wm.position = w
			root.add_child(wm)
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 40
	add_child(cam)
	cam.current = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var views := [[Vector3(-10, 4.5, -14), Vector3(0, 0.5, 0)], [Vector3(14, 3.0, -1), Vector3(0, 0.6, 0)], [Vector3(6, 6, 14), Vector3(0, 0.5, 0)]]
	for v in views.size():
		cam.look_at_from_position(views[v][0], views[v][1], Vector3.UP)
		for f in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/lineup_%d.png" % [out, v])
	# close-ups of each car
	for i in Game.TEAMS.size():
		var p := Vector3((i % 4) * 3.2 - 4.8, 0, (i / 4) * 6.0 - 3.0)
		cam.look_at_from_position(p + Vector3(-3.6, 1.8, -4.2), p + Vector3(0, 0.6, 0), Vector3.UP)
		for f in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/car_%d.png" % [out, i])
	print("LINEUP done")
	get_tree().quit()
