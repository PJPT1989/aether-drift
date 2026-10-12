extends Node
## Runs the game: title screen, track and team choice, the race with its HUD, pause menu,
## results and the six-leg Grand Prix. Also applies the graphics quality, and hands over to
## scripts/autotest.gd (smoke test) or a headless simulation (--simtest) when asked.

const POINTS := [10, 8, 6, 5, 4, 3, 2, 1]
const CYAN := Color(0.4, 0.92, 1.0)
const PINK := Color(1.0, 0.4, 0.7)
const GOLD := Color(1.0, 0.78, 0.35)

var ui: CanvasLayer
var screen: Control
var showcase: Showcase
var race: Race
var hud: Hud
var mode := "quick"
var sel_track := 0
var sel_team := 0
var gp_round := 0
var gp_points: Array[int] = []
var last_results: Array = []
var _fps_watch := -1.0
var _fps_frames := 0
var _theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	Game.quality_changed.connect(_apply_quality)
	get_tree().root.size_changed.connect(_apply_quality)
	_apply_quality()
	var args := OS.get_cmdline_user_args()
	if "--simtest" in args:
		_simtest.call_deferred()
		return
	if "--lineup" in args:
		add_child(load("res://tools/car_lineup.gd").new())
		return
	showcase = Showcase.new()
	add_child(showcase)
	show_title()
	if "--autotest" in args:
		var t := Node.new()
		t.set_script(load("res://scripts/autotest.gd"))
		t.set("main", self)
		add_child(t)


# --- quality --------------------------------------------------------------------------

func _apply_quality() -> void:
	# The menus and HUD always draw at the window's own resolution, so text stays crisp. The 3D
	# view draws at full resolution on High, at up to 1080 lines on Medium and up to 720 on Low,
	# with multisampling smoothing the edges on High and Medium.
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var lines := float(maxi(root.size.y, 1))
	match Game.quality:
		Game.HIGH:
			root.scaling_3d_scale = 1.0
			root.msaa_3d = Viewport.MSAA_4X
		Game.MEDIUM:
			root.scaling_3d_scale = minf(1.0, 1080.0 / lines)
			root.msaa_3d = Viewport.MSAA_2X
		_:
			root.scaling_3d_scale = minf(1.0, 720.0 / lines)
			root.msaa_3d = Viewport.MSAA_DISABLED
	if race:
		race.apply_quality()
	if screen and screen.has_meta("quality_button"):
		var b: Button = screen.get_meta("quality_button")
		if is_instance_valid(b):
			b.text = "GRAPHICS: " + Game.QUALITY_NAMES[Game.quality].to_upper()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("quality"):
		Game.cycle_quality()
		if race:
			race.show_message("Graphics: " + Game.QUALITY_NAMES[Game.quality], 1.5)
	elif e.is_action_pressed("mute"):
		Game.toggle_mute()
	elif race and race.state != Race.DONE:
		if e.is_action_pressed("pause"):
			if get_tree().paused:
				_resume()
			else:
				_pause()
		elif e.is_action_pressed("reset") and not get_tree().paused:
			race.reset_player()
		elif e.is_action_pressed("camera"):
			race.cam_mode = (race.cam_mode + 1) % Race.CAM_MODES


func _process(dt: float) -> void:
	# In the browser, drop to low quality once if the start of the first race runs slowly.
	if race and race.state == Race.RACING and Game.web and not Game.quality_chosen and Game.quality != Game.LOW:
		if _fps_watch < 0.0:
			_fps_watch = 0.0
			_fps_frames = 0
		_fps_watch += dt
		_fps_frames += 1
		if _fps_watch > 5.0:
			if _fps_frames / _fps_watch < 24.0:
				Game.set_quality(Game.LOW, false)
				Game.quality_chosen = true
				race.show_message("Low graphics for speed - L to change", 4.0)
			else:
				Game.quality_chosen = true


# --- ui helpers ----------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Game.font_body
	t.default_font_size = 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.04, 0.1, 0.82)
	normal.border_color = Color(CYAN, 0.35)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.12, 0.25, 0.92)
	hover.border_color = CYAN
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.25, 0.08, 0.2, 0.95)
	pressed.border_color = PINK
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_font("font", "Button", Game.font_title)
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Button", Color(0.9, 0.95, 1.0))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.02, 0.06, 0.82)
	panel.border_color = Color(CYAN, 0.25)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


func _new_screen() -> Control:
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.theme = _theme
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	return screen


func _label(text: String, size: int, font: Font = null, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Game.play("click", -6.0)
		cb.call())
	return b


func _title_label() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_override("normal_font", Game.font_title)
	r.add_theme_font_size_override("normal_font_size", 30)
	r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	r.add_theme_constant_override("shadow_offset_x", 3)
	r.add_theme_constant_override("shadow_offset_y", 3)
	r.text = "[color=#cfe8ff]NEED FOR SPEED:[/color]\n[font_size=64][color=#ff5a7a][s]TOKYO[/s][/color] [color=#66ebff]AETHER[/color] [color=#ffffff]DRIFT[/color][/font_size]"
	return r


func _box(at_preset: int, margin: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.set_anchors_preset(at_preset)
	v.position = margin
	screen.add_child(v)
	return v


# --- screens -----------------------------------------------------------------------

func show_title() -> void:
	_back_to_showcase()
	_new_screen()
	showcase.set_track(sel_track)
	showcase.set_team(sel_team)
	var v := _box(Control.PRESET_TOP_LEFT, Vector2(60, 50))
	v.add_child(_title_label())
	var tag := _label(Game.TAGLINE, 20, Game.font_bold, Color(1.0, 0.85, 0.5))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(840, 0)
	v.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	v.add_child(gap)
	var bw := 340.0
	for b in [_button("QUICK RACE", func(): mode = "quick"; show_tracks()),
			_button("GRAND PRIX - 6 LEGS", func(): mode = "gp"; show_teams()),
			_button("GRAPHICS: " + Game.QUALITY_NAMES[Game.quality].to_upper(), func(): Game.cycle_quality()),
			_button("SOUND: " + ("OFF" if Game.muted else "ON"), func(): Game.toggle_mute(); show_title())]:
		b.custom_minimum_size = Vector2(bw, 48)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
	screen.set_meta("quality_button", v.get_child(5))
	var help := PanelContainer.new()
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 60
	help.offset_top = -190
	help.offset_bottom = -50
	var hv := VBoxContainer.new()
	help.add_child(hv)
	hv.add_child(_label("CONTROLS", 15, Game.font_title, CYAN))
	hv.add_child(_label("W or Up accelerate   ·   S or Down brake, reverse   ·   A D or Left Right steer", 16))
	hv.add_child(_label("SPACE drift: hold through a corner to charge aether, let go for a burst", 16))
	hv.add_child(_label("SHIFT aether boost   ·   R reset   ·   C camera   ·   L graphics   ·   M sound", 16))
	screen.add_child(help)
	var foot := _label("Fan-made racing game inspired by the multiverse Grand Prix of Aetherdrift. Original art and teams.", 13, null, Color(1, 1, 1, 0.55))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.position = Vector2(-700, -34)
	screen.add_child(foot)


func show_tracks() -> void:
	_new_screen()
	var v := _box(Control.PRESET_TOP_LEFT, Vector2(50, 36))
	v.add_child(_label("CHOOSE A TRACK", 34, Game.font_title, CYAN))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var blurb := _label("", 18)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(760, 80)
	for i in Tracks.LIST.size():
		var d: Dictionary = Tracks.LIST[i]
		var b := _button("%d  %s\n%s - %s" % [i + 1, d.name.to_upper(), d.plane, d.leg.get_slice(" - ", 1).strip_edges()], func():
			sel_track = i
			show_teams())
		b.custom_minimum_size = Vector2(250, 92)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		var sb: StyleBoxFlat = _theme.get_stylebox("normal", "Button").duplicate()
		sb.bg_color = Color(d.sky_horizon.darkened(0.55), 0.9)
		sb.border_color = Color(d.line_col, 0.6)
		b.add_theme_stylebox_override("normal", sb)
		b.mouse_entered.connect(func():
			showcase.set_track(i)
			blurb.text = d.blurb)
		b.focus_entered.connect(func():
			showcase.set_track(i)
			blurb.text = d.blurb)
		grid.add_child(b)
	v.add_child(blurb)
	var back := _button("BACK", show_title)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	(grid.get_child(sel_track) as Button).grab_focus()


func show_teams() -> void:
	_new_screen()
	var v := _box(Control.PRESET_TOP_LEFT, Vector2(50, 36))
	v.add_child(_label("CHOOSE YOUR TEAM", 34, Game.font_title, CYAN))
	if mode == "gp":
		v.add_child(_label("Grand Prix: all six legs in race order, points 10-8-6-5-4-3-2-1.", 17, null, Color(1, 1, 1, 0.8)))
	else:
		v.add_child(_label("Track: " + Tracks.LIST[sel_track].name, 17, null, Color(1, 1, 1, 0.8)))
	var info := PanelContainer.new()
	info.anchor_left = 1.0
	info.anchor_right = 1.0
	info.offset_left = -480
	info.offset_right = -40
	info.offset_top = 90
	var iv := VBoxContainer.new()
	info.add_child(iv)
	screen.add_child(info)
	var show_info := func(i: int) -> void:
		sel_team = i
		showcase.set_team(i)
		for c in iv.get_children():
			c.queue_free()
		var t: Dictionary = Game.TEAMS[i]
		iv.add_child(_label(t.name.to_upper(), 24, Game.font_title, t.glow))
		iv.add_child(_label("from " + t.home, 15, null, Color(1, 1, 1, 0.7)))
		var d := _label(t.desc, 16)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(390, 0)
		iv.add_child(d)
		for stat in [["TOP SPEED", t.speed], ["ACCELERATION", t.accel], ["GRIP", t.grip]]:
			var row := HBoxContainer.new()
			var l := _label(stat[0], 13, Game.font_title, Color(1, 1, 1, 0.7))
			l.custom_minimum_size = Vector2(140, 0)
			row.add_child(l)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.min_value = 0.88
			bar.max_value = 1.08
			bar.value = stat[1]
			bar.custom_minimum_size = Vector2(220, 12)
			var fill := StyleBoxFlat.new()
			fill.bg_color = t.glow
			bar.add_theme_stylebox_override("fill", fill)
			row.add_child(bar)
			iv.add_child(row)
	for i in Game.TEAMS.size():
		var t: Dictionary = Game.TEAMS[i]
		var b := _button(t.name.to_upper(), func(): show_info.call(i))
		b.custom_minimum_size = Vector2(330, 40)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", t.glow.lerp(Color.WHITE, 0.4))
		b.mouse_entered.connect(func(): show_info.call(i))
		v.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_button("BACK", show_tracks if mode == "quick" else show_title))
	var go := _button("RACE!", func():
		if mode == "gp":
			gp_round = 0
			gp_points.clear()
			for k in Game.TEAMS.size():
				gp_points.append(0)
			sel_track = 0
		start_race(sel_track, sel_team))
	go.custom_minimum_size = Vector2(200, 48)
	row.add_child(go)
	v.add_child(row)
	show_info.call(sel_team)
	go.grab_focus()


func _back_to_showcase() -> void:
	get_tree().paused = false
	if race:
		race.queue_free()
		race = null
	if hud:
		hud.queue_free()
		hud = null
	if showcase:
		showcase.visible = true
		showcase.process_mode = Node.PROCESS_MODE_INHERIT
		showcase.get_child(showcase.get_child_count() - 1).current = true


func start_race(t_index: int, team_index: int) -> void:
	sel_track = t_index
	sel_team = team_index
	_new_screen()
	var d: Dictionary = Tracks.LIST[t_index]
	var v := _box(Control.PRESET_CENTER_LEFT, Vector2(60, -60))
	v.add_child(_label(d.leg.to_upper(), 18, Game.font_title, CYAN))
	v.add_child(_label(d.name.to_upper(), 40, Game.font_title))
	v.add_child(_label(d.plane, 20, Game.font_bold, Color(1, 1, 1, 0.8)))
	v.add_child(_label("Loading…", 16, null, Color(1, 1, 1, 0.6)))
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	if race:
		race.queue_free()
	if hud:
		hud.queue_free()
	if showcase:
		showcase.visible = false
		showcase.process_mode = Node.PROCESS_MODE_DISABLED
	var t0 := Time.get_ticks_msec()
	race = Race.new()
	add_child(race)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE
	race.setup(t_index, team_index)
	race.race_over.connect(_on_race_over)
	print("track %d built in %d ms" % [t_index, Time.get_ticks_msec() - t0])
	_new_screen()
	hud = Hud.new()
	ui.add_child(hud)
	ui.move_child(hud, 0)
	hud.setup(race)
	_fps_watch = -1.0


func _pause() -> void:
	get_tree().paused = true
	_new_screen()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var v := _box(Control.PRESET_CENTER, Vector2(-170, -150))
	v.add_child(_label("PAUSED", 40, Game.font_title, CYAN))
	for b in [_button("RESUME", _resume), _button("RESTART RACE", func(): start_race(sel_track, sel_team)),
			_button("GRAPHICS: " + Game.QUALITY_NAMES[Game.quality].to_upper(), func(): Game.cycle_quality()),
			_button("QUIT TO MENU", show_title)]:
		b.custom_minimum_size = Vector2(340, 46)
		v.add_child(b)
	screen.set_meta("quality_button", v.get_child(3))
	(v.get_child(1) as Button).grab_focus()


func _resume() -> void:
	get_tree().paused = false
	_new_screen()


func _on_race_over(results: Array) -> void:
	last_results = results
	if mode == "gp":
		for r in results:
			gp_points[r.team] += POINTS[r.place - 1]
	await get_tree().create_timer(0.6).timeout
	show_results()


func show_results() -> void:
	_new_screen()
	if hud:
		hud.visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var me := 0
	for r in last_results:
		if r.player:
			me = r.place
	v.add_child(_label(Tracks.LIST[sel_track].name.to_upper(), 16, Game.font_title, CYAN))
	v.add_child(_label("YOU FINISHED " + Race.ordinal(me).to_upper(), 36, Game.font_title, GOLD if me <= 3 else Color.WHITE))
	var grid := GridContainer.new()
	grid.columns = 5 if mode == "gp" else 4
	grid.add_theme_constant_override("h_separation", 26)
	for h in ["", "TEAM", "TIME", "BEST LAP"] + (["POINTS"] if mode == "gp" else []):
		grid.add_child(_label(h, 13, Game.font_title, Color(1, 1, 1, 0.6)))
	for r in last_results:
		var col: Color = GOLD if r.player else Color.WHITE
		grid.add_child(_label(Race.ordinal(r.place), 18, Game.font_title, col))
		grid.add_child(_label(r.name, 18, Game.font_bold, Game.TEAMS[r.team].glow.lerp(Color.WHITE, 0.3) if not r.player else GOLD))
		grid.add_child(_label(Race.fmt_time(r.time), 18, null, col))
		grid.add_child(_label(Race.fmt_time(r.best), 18, null, col))
		if mode == "gp":
			grid.add_child(_label("+%d" % POINTS[r.place - 1], 18, null, col))
	v.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if mode == "gp":
		if gp_round < Tracks.LIST.size() - 1:
			row.add_child(_button("STANDINGS", show_standings))
		else:
			row.add_child(_button("FINAL STANDINGS", show_standings))
	else:
		row.add_child(_button("RACE AGAIN", func(): start_race(sel_track, sel_team)))
		row.add_child(_button("OTHER TRACK", func(): _back_to_showcase(); show_tracks()))
	row.add_child(_button("MAIN MENU", show_title))
	v.add_child(row)
	(row.get_child(0) as Button).grab_focus()


func show_standings() -> void:
	_new_screen()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	screen.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var last := gp_round >= Tracks.LIST.size() - 1
	v.add_child(_label("GRAND PRIX STANDINGS" if not last else "GRAND PRIX FINAL", 30, Game.font_title, CYAN))
	v.add_child(_label("after leg %d of %d" % [gp_round + 1, Tracks.LIST.size()], 16, null, Color(1, 1, 1, 0.7)))
	var order := range(Game.TEAMS.size())
	order.sort_custom(func(a, b): return gp_points[a] > gp_points[b])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	for i in order.size():
		var t: int = order[i]
		var mine := t == sel_team
		var col: Color = GOLD if mine else Color.WHITE
		grid.add_child(_label(Race.ordinal(i + 1), 20, Game.font_title, col))
		grid.add_child(_label(Game.TEAMS[t].name + ("  (you)" if mine else ""), 20, Game.font_bold, col))
		grid.add_child(_label("%d" % gp_points[t], 20, Game.font_title, col))
	v.add_child(grid)
	if last:
		var champ: int = order[0]
		var txt := "You win the Aetherspark!" if champ == sel_team else "%s take the Aetherspark." % Game.TEAMS[champ].name
		v.add_child(_label(txt, 26, Game.font_title, GOLD))
		v.add_child(_button("MAIN MENU", show_title))
	else:
		var nxt: Dictionary = Tracks.LIST[gp_round + 1]
		v.add_child(_label("Next: " + nxt.name + " (" + nxt.plane + ")", 18, null, CYAN))
		v.add_child(_button("NEXT LEG", func():
			gp_round += 1
			start_race(gp_round, sel_team)))
	(v.get_child(v.get_child_count() - 1) as Button).grab_focus()


# --- headless simulation test ---------------------------------------------------------

func _simtest() -> void:
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			only = int(a.get_slice("=", 1))
	for ti in Tracks.LIST.size():
		if only >= 0 and ti != only:
			continue
		var t0 := Time.get_ticks_msec()
		var r := Race.new()
		add_child(r)
		r.set_physics_process(false)
		r.setup(ti, 0)
		var built := Time.get_ticks_msec() - t0
		r.autopilot = true
		var res := []
		r.race_over.connect(func(x): res.append_array(x))
		var steps := 0
		var walls := 0
		var stuck := 0
		var last_total := {}
		while res.is_empty() and steps < 60 * 400:
			r.simulate(1.0 / 60.0)
			steps += 1
			for c in r.cars:
				if c.wall_hit > 6.0:
					walls += 1
			if steps % 600 == 0:
				for c in r.cars:
					if last_total.has(c) and c.total - last_total[c] < 50.0 and not c.finished:
						stuck += 1
					last_total[c] = c.total
		# keep going until the stragglers finish too, to prove nobody is stuck for good
		var extra := 0
		while r.cars.any(func(c): return not c.finished) and extra < 60 * 90:
			r.simulate(1.0 / 60.0)
			extra += 1
		var lap_best := INF
		for c in r.cars:
			lap_best = minf(lap_best, c.best_lap)
		print("SIMTEST %d %s: length %.0f m, built %d ms, race %.1f s, best lap %s, hard wall hits %d, stuck checks %d, events %d, spins %d, finished %s" % [
			ti, Tracks.LIST[ti].name, r.track.length, built, steps / 60.0, Race.fmt_time(lap_best), walls, stuck,
			r.hazards.fired, r.hazards.spins, str(r.cars.filter(func(c): return c.finished).size())])
		r.queue_free()
		await get_tree().process_frame
	print("SIMTEST done")
	get_tree().quit()
