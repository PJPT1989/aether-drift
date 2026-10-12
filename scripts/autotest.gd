extends Node
## Smoke test (tools/smoke_test.sh): walks through the menus, drives a lap of every track with
## the AI at the wheel, pauses, fast-forwards one race to the results and saves screenshots.

var main: Node
var shots := "/tmp/aether-shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(shots)
	_run.call_deferred()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots.path_join(name + ".png"))
	print("AUTOTEST shot ", name, " fps ", Engine.get_frames_per_second())


func _run() -> void:
	await _wait(20)
	await _shot("00_title")
	main.show_tracks()
	await _wait(5)
	await _shot("01_tracks")
	main.sel_track = 3
	main.show_teams()
	await _wait(5)
	await _shot("02_teams")
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			only = int(a.get_slice("=", 1))
	for t in Tracks.LIST.size():
		if only >= 0 and t != only:
			continue
		main.start_race(t, t % Game.TEAMS.size())
		await _wait(4)
		while main.race == null:
			await _wait(1)
		main.race.autopilot = true
		await _wait(3)
		await _shot("t%d_grid" % t)
		# fast-forward into the race, then let it run a little for natural motion
		for i in 60 * (14 + t * 3):
			main.race.simulate(1.0 / 60.0)
		await _wait(30)
		await _shot("t%d_race" % t)
		for i in 60 * 9:
			main.race.simulate(1.0 / 60.0)
		main.race.cam_mode = 1 if t % 2 == 0 else 0
		await _wait(20)
		await _shot("t%d_race2" % t)
		# a view from the side, looking across the track at the pack
		var r: Race = main.race
		r.free_cam = true
		var p: Car = r.player
		var side := r.track.R[p.idx]
		r.camera.look_at_from_position(p.position + side * 38.0 - p.forward() * 30.0 + Vector3(0, 14, 0), p.position + p.forward() * 20.0, Vector3.UP)
		await _wait(4)
		await _shot("t%d_side" % t)
		r.free_cam = false
		print("AUTOTEST track %d ok: place %d, speed %d km/h" % [t, main.race.player.place, int(main.race.player.speed * 3.6)])
	# pause menu, then fast-forward to the results
	main._pause()
	await _wait(5)
	await _shot("90_pause")
	main._resume()
	main.race.autopilot = true
	var steps := 0
	while main.race.state != Race.DONE and steps < 60 * 300:
		main.race.simulate(1.0 / 60.0)
		steps += 1
	await _wait(60)
	await _shot("91_results")
	print("AUTOTEST done")
	get_tree().quit()
