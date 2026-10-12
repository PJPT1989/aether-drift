extends Node
## Autoload `Game`: settings (graphics quality, sound), the racing teams, fonts, shared
## materials and the generated sound effects.

signal quality_changed

enum { LOW, MEDIUM, HIGH }
const QUALITY_NAMES := ["Low", "Medium", "High"]
const SETTINGS_PATH := "user://settings.cfg"

## The title as BBCode: "Tokyo" is struck through, a nod to the racing game it parodies.
const TITLE_BB := "Need for Speed: [s][color=#ff5a7a]Tokyo[/color][/s] Aether Drift"
const TITLE_PLAIN := "Need for Speed: Aether Drift"
const TAGLINE := "It's time for planeswalkers to learn how to drive a stick, and the importance of family."
const LAPS := 3

## The ten-or-so teams of the multiversal Grand Prix, reimagined with original names and liveries.
## style picks the body shape in car_models.gd. Stats are small nudges around 1.0.
const TEAMS := [
	{"name": "Indigo Rangers", "home": "Avishkar", "style": "ramjet",
		"body": Color(0.16, 0.18, 0.55), "trim": Color(0.85, 0.52, 0.25), "glow": Color(0.3, 0.85, 1.0),
		"speed": 1.0, "accel": 1.0, "grip": 1.0,
		"desc": "Aether-ramjet streamliners from the plane of invention. Balanced and quick."},
	{"name": "Skyfire Racing", "home": "the cloud arenas", "style": "wedge",
		"body": Color(0.85, 0.16, 0.08), "trim": Color(0.95, 0.92, 0.85), "glow": Color(1.0, 0.55, 0.15),
		"speed": 1.04, "accel": 0.97, "grip": 0.97,
		"desc": "Last season's champions. Low drag, loud paint, highest top speed."},
	{"name": "Sunchariot Dynasty", "home": "Amonkhet", "style": "chariot",
		"body": Color(0.88, 0.68, 0.22), "trim": Color(0.12, 0.22, 0.6), "glow": Color(1.0, 0.85, 0.4),
		"speed": 0.98, "accel": 1.0, "grip": 1.05,
		"desc": "Living and risen charioteers of the desert river. Heavy, planted, sure-footed."},
	{"name": "Brasslight Pilgrims", "home": "a lost world", "style": "pod",
		"body": Color(0.72, 0.55, 0.3), "trim": Color(0.15, 0.45, 0.42), "glow": Color(0.4, 1.0, 0.75),
		"speed": 0.97, "accel": 1.06, "grip": 1.0,
		"desc": "Automaton voyagers racing to find their way home. Fast off the line."},
	{"name": "Wraith Speed", "home": "a haunted house of a plane", "style": "spike",
		"body": Color(0.1, 0.08, 0.13), "trim": Color(0.45, 0.12, 0.55), "glow": Color(0.8, 0.3, 1.0),
		"speed": 1.02, "accel": 1.02, "grip": 0.94,
		"desc": "Specter-haunted machines. Twitchy, slippery, terrifying in a drift."},
	{"name": "Rocket Rabble", "home": "nobody knows", "style": "rocket",
		"body": Color(0.3, 0.55, 0.15), "trim": Color(0.8, 0.15, 0.1), "glow": Color(1.0, 0.45, 0.1),
		"speed": 1.05, "accel": 0.95, "grip": 0.93,
		"desc": "Goblins strapped to rockets. Brutal on the straights, a handful in the turns."},
	{"name": "Reefjaw Haulers", "home": "the open seas", "style": "fin",
		"body": Color(0.12, 0.42, 0.62), "trim": Color(0.9, 0.95, 0.98), "glow": Color(0.3, 0.95, 1.0),
		"speed": 1.0, "accel": 1.03, "grip": 0.98,
		"desc": "Shark-folk on stripped-down aether rigs. Light and nimble."},
	{"name": "Duskwander Nomads", "home": "a plane of endless sunset", "style": "armored",
		"body": Color(0.55, 0.28, 0.14), "trim": Color(0.2, 0.18, 0.16), "glow": Color(1.0, 0.6, 0.2),
		"speed": 0.99, "accel": 0.98, "grip": 1.04,
		"desc": "Fuel-burning wasteland gangs. Armoured and stubborn."},
]

var quality := MEDIUM
var quality_chosen := false
var muted := false
var web := false
var font_title: FontVariation
var font_body: FontVariation
var font_bold: FontVariation
var mat_solid: StandardMaterial3D
var mat_glow: ShaderMaterial
var mat_paint: ShaderMaterial
var sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	web = OS.has_feature("web") or "--web" in OS.get_cmdline_user_args()
	quality = MEDIUM if web else HIGH
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		if cfg.has_section_key("video", "quality"):
			quality = clampi(int(cfg.get_value("video", "quality")), LOW, HIGH)
			quality_chosen = true
		muted = bool(cfg.get_value("audio", "muted", false))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			quality = clampi(int(a.get_slice("=", 1)), LOW, HIGH)
			quality_chosen = true
	font_title = _font("res://fonts/Orbitron.ttf", 800)
	font_bold = _font("res://fonts/Exo2.ttf", 700)
	font_body = _font("res://fonts/Exo2.ttf", 450)
	mat_solid = StandardMaterial3D.new()
	mat_solid.vertex_color_use_as_albedo = true
	mat_solid.roughness = 0.75
	mat_solid.metallic_specular = 0.35
	mat_glow = ShaderMaterial.new()
	mat_glow.shader = load("res://shaders/glow.gdshader")
	mat_paint = ShaderMaterial.new()
	mat_paint.shader = load("res://shaders/paint.gdshader")
	_setup_input()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_sounds()
	AudioServer.set_bus_mute(0, muted)


## Keyboard and gamepad controls.
func _setup_input() -> void:
	var keys := {
		"accelerate": [KEY_W, KEY_UP], "brake": [KEY_S, KEY_DOWN], "steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT], "drift": [KEY_SPACE], "boost": [KEY_SHIFT, KEY_N],
		"reset": [KEY_R], "pause": [KEY_ESCAPE, KEY_P], "camera": [KEY_C], "quality": [KEY_L], "mute": [KEY_M]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	var pad := {"accelerate": JOY_BUTTON_A, "brake": JOY_BUTTON_X, "drift": JOY_BUTTON_B, "boost": JOY_BUTTON_Y,
		"reset": JOY_BUTTON_BACK, "pause": JOY_BUTTON_START, "camera": JOY_BUTTON_RIGHT_SHOULDER}
	for action in pad:
		var e := InputEventJoypadButton.new()
		e.button_index = pad[action]
		InputMap.action_add_event(action, e)
	var axes := [["steer_left", JOY_AXIS_LEFT_X, -1.0], ["steer_right", JOY_AXIS_LEFT_X, 1.0],
		["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["brake", JOY_AXIS_TRIGGER_LEFT, 1.0]]
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[1]
		e.axis_value = a[2]
		InputMap.action_add_event(a[0], e)


func _font(path: String, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.variation_opentype = {"wght": weight}
	return f


## Points the car paint reflections at a sky (a track definition from Tracks.LIST).
func set_paint_sky(d: Dictionary) -> void:
	mat_paint.set_shader_parameter("sky_top", d.sky_top)
	mat_paint.set_shader_parameter("sky_horizon", d.sky_horizon)
	mat_paint.set_shader_parameter("sky_ground", d.sky_ground)


func set_quality(q: int, save := true) -> void:
	quality = clampi(q, LOW, HIGH)
	if save:
		quality_chosen = true
		_save()
	quality_changed.emit()


func cycle_quality() -> void:
	set_quality((quality + 1) % 3)


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	_save()


func _save() -> void:
	if "--autotest" in OS.get_cmdline_user_args() or "--bench" in OS.get_cmdline_user_args():
		return
	var cfg := ConfigFile.new()
	if quality_chosen:
		cfg.set_value("video", "quality", quality)
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)


func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = sounds[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


# --- generated sounds -------------------------------------------------------------

func make_wav(dur: float, gen: Callable, loop := false, rate := 22050) -> AudioStreamWAV:
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var p := float(i) / n
		var env := 1.0 if loop else pow(1.0 - p, 1.6) * minf(1.0, i / 80.0)
		var v: float = gen.call(float(i) / rate, p) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = n
	return s


func _noise(cut: float) -> Callable:
	var st := [0.0]
	return func(_t: float, _p: float) -> float:
		st[0] += (randf() * 2.0 - 1.0 - st[0]) * cut
		return st[0] / sqrt(cut) * 0.5


func _build_sounds() -> void:
	# Engine: a loop of whole periods so it repeats without clicks; pitch follows the revs.
	var base := 55.0
	var engine := func(t: float, _p: float) -> float:
		var ph := t * base
		var saw := fposmod(ph, 1.0) * 2.0 - 1.0
		var saw2 := fposmod(ph * 2.0, 1.0) * 2.0 - 1.0
		return (saw * 0.35 + saw2 * 0.2 + sin(TAU * ph * 0.5) * 0.35 + sin(TAU * ph * 3.0) * 0.1) * 0.8
	sounds["engine"] = make_wav(12.0 / base, engine, true)
	var hiss := _noise(0.5)
	sounds["skid"] = make_wav(0.8, func(t, p): return hiss.call(t, p) * 0.5 * (0.8 + 0.2 * sin(TAU * t * 40.0)), true)
	var rush := _noise(0.08)
	sounds["boost"] = make_wav(0.9, func(t, p): return rush.call(t, p) * 1.2 + sin(TAU * (200.0 + 500.0 * p) * t) * 0.25)
	var thud := _noise(0.05)
	sounds["hit"] = make_wav(0.25, func(t, p): return thud.call(t, p) * 1.4 + sin(TAU * 70.0 * t) * 0.5)
	sounds["beep"] = make_wav(0.25, func(t, _p): return sin(TAU * 660.0 * t) * 0.5)
	sounds["go"] = make_wav(0.6, func(t, _p): return (sin(TAU * 990.0 * t) + sin(TAU * 1320.0 * t) * 0.5) * 0.35)
	sounds["orb"] = make_wav(0.3, func(t, p): return sin(TAU * (900.0 + 900.0 * p) * t) * 0.3)
	sounds["lap"] = make_wav(0.7, func(t, p): return sin(TAU * (784.0 if p < 0.4 else 1046.0) * t) * 0.35)
	sounds["alarm"] = make_wav(0.9, func(t, p): return sin(TAU * (520.0 if fmod(p * 4.0, 2.0) < 1.0 else 700.0) * t) * 0.35)
	var blast := _noise(0.12)
	sounds["boom"] = make_wav(0.9, func(t, p): return blast.call(t, p) * 1.6 + sin(TAU * (60.0 - 30.0 * p) * t) * 0.7)
	sounds["click"] = make_wav(0.06, func(t, _p): return sin(TAU * 1200.0 * t) * 0.3)
