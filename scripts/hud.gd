class_name Hud
extends Control
## Race overlay: place, lap, times, standings, minimap, speedometer, aether meter, countdown
## and messages. Everything is drawn in _draw from the race's state.

const CYAN := Color(0.4, 0.92, 1.0)
const GOLD := Color(1.0, 0.78, 0.35)
const PINK := Color(1.0, 0.4, 0.7)
const AMBER := Color(1.0, 0.62, 0.15)
const PANEL := Color(0.03, 0.03, 0.08, 0.55)

var race: Race
var _map_pts := PackedVector2Array()
var _map_rect := Rect2()
var _map_scale := 1.0
var _map_origin := Vector2.ZERO
var _hint_t := 9.0


func setup(r: Race) -> void:
	race = r
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in race.track.P:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	_map_origin = (lo + hi) * 0.5
	_map_scale = 190.0 / maxf(hi.x - lo.x, hi.y - lo.y)
	for i in range(0, race.track.n, 4):
		var p := race.track.P[i]
		_map_pts.append((Vector2(p.x, p.z) - _map_origin) * _map_scale)
	_map_pts.append(_map_pts[0])


func _process(dt: float) -> void:
	_hint_t -= dt
	queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font if font else Game.font_bold
	draw_string(f, pos + Vector2(2, 2), s, align, width, size, Color(0, 0, 0, 0.6))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if race == null or race.player == null:
		return
	var sz := size
	var p := race.player
	# place and lap
	draw_rect(Rect2(16, 16, 250, 132), PANEL)
	_text(Vector2(30, 76), "%d" % p.place, 56, GOLD, Game.font_title)
	_text(Vector2(30 + 38 * str(p.place).length(), 76), "/%d" % race.cars.size(), 26, Color(1, 1, 1, 0.8), Game.font_title)
	var lap := clampi(p.laps_done + 1, 1, Game.laps)
	_text(Vector2(150, 50), "LAP", 15, Color(1, 1, 1, 0.6), Game.font_title)
	_text(Vector2(150, 80), "%d/%d" % [lap, Game.laps], 28, Color.WHITE, Game.font_title)
	_text(Vector2(30, 110), "TIME  " + Race.fmt_time(race.time), 18, Color.WHITE)
	_text(Vector2(30, 134), "BEST  " + Race.fmt_time(p.best_lap), 16, Color(1, 1, 1, 0.7))
	# standings
	var order := race.cars.duplicate()
	order.sort_custom(func(a, b): return a.place < b.place)
	var y := 172.0
	for c in order:
		var col: Color = c.team.glow
		var me: bool = c == p
		draw_rect(Rect2(16, y - 17, 230, 23), Color(1, 1, 1, 0.16) if me else Color(0, 0, 0, 0.35))
		draw_rect(Rect2(16, y - 17, 5, 23), col)
		_text(Vector2(28, y), "%d" % c.place, 16, GOLD if me else Color.WHITE, Game.font_title)
		var who: String = c.driver if c.driver != "" else c.team.name
		_text(Vector2(54, y), who + ("  (you)" if me else ""), 16, Color.WHITE if me else Color(1, 1, 1, 0.8))
		y += 26.0
	_draw_map(Vector2(sz.x - 230, 20))
	_draw_speedo(Vector2(sz.x - 150, sz.y - 130), p)
	# countdown and messages
	var mid := sz * 0.5
	if race.state == Race.COUNTDOWN:
		var c := int(ceil(race.countdown - 0.6))
		if c >= 1 and c <= 3:
			var f := fposmod(race.countdown - 0.6, 1.0)
			_text(Vector2(0, mid.y - 40), str(c), int(90 + f * 50), Color(1, 1, 1, 0.4 + f * 0.6), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if race.message_t > 0.0:
		var a := clampf(race.message_t * 2.0, 0.0, 1.0)
		_text(Vector2(0, mid.y - 120), race.message, 46, Color(CYAN, a), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	_draw_event(Vector2(mid.x, 64), p)
	if p.wrong_way > 1.5:
		_text(Vector2(0, mid.y - 60), "WRONG WAY", 44, Color(1, 0.3, 0.3, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		_text(Vector2(0, mid.y - 28), "turn round, or press R to reset", 18, Color.WHITE, null, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if p.drifting and p.drift_time > 0.3:
		var lvl := clampf(p.drift_time / 2.5, 0.0, 1.0)
		_text(Vector2(0, sz.y - 150), "AETHER DRIFT", 26, Color(PINK, 0.6 + lvl * 0.4), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		draw_rect(Rect2(mid.x - 100, sz.y - 140, 200, 6), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(mid.x - 100, sz.y - 140, 200 * lvl, 6), PINK)
	if _hint_t > 0.0 and race.state != Race.DONE:
		var a := clampf(_hint_t, 0.0, 1.0)
		draw_rect(Rect2(mid.x - 330, sz.y - 62, 660, 40), Color(0, 0, 0, 0.45 * a))
		_text(Vector2(0, sz.y - 36), "W drive · S brake · A D steer · SPACE drift · SHIFT aether boost · R reset · C camera · Esc pause", 15, Color(1, 1, 1, a), null, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_map(at: Vector2) -> void:
	draw_rect(Rect2(at, Vector2(210, 210)), PANEL)
	var c := at + Vector2(105, 105)
	var pts := PackedVector2Array()
	for q in _map_pts:
		pts.append(c + q)
	draw_polyline(pts, Color(0, 0, 0, 0.6), 7.0, true)
	draw_polyline(pts, Color(1, 1, 1, 0.75), 3.0, true)
	var s := race.track.P[0]
	draw_circle(c + (Vector2(s.x, s.z) - _map_origin) * _map_scale, 4.0, GOLD)
	for car in race.cars:
		if car == race.player:
			continue
		draw_circle(c + (Vector2(car.position.x, car.position.z) - _map_origin) * _map_scale, 4.0, car.team.glow)
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for m: Vector3 in race.hazards.markers():
		var mp := c + (Vector2(m.x, m.z) - _map_origin) * _map_scale
		draw_circle(mp, 9.0, Color(AMBER, 0.25 + 0.35 * blink))
		draw_circle(mp, 4.0, AMBER)
	var pp := race.player.position
	draw_circle(c + (Vector2(pp.x, pp.z) - _map_origin) * _map_scale, 6.5, Color.WHITE)
	draw_circle(c + (Vector2(pp.x, pp.z) - _map_origin) * _map_scale, 4.5, race.player.team.glow)


func _draw_speedo(c: Vector2, p: Car) -> void:
	draw_circle(c, 112, PANEL)
	var kmh := absf(p.speed) * 3.6
	var frac := clampf(kmh / 340.0, 0.0, 1.0)
	var a0 := deg_to_rad(140.0)
	var a1 := deg_to_rad(400.0)
	draw_arc(c, 96, a0, a1, 48, Color(1, 1, 1, 0.15), 10.0, true)
	var col := PINK if p.boosting else CYAN
	draw_arc(c, 96, a0, lerpf(a0, a1, frac), 48, col, 10.0, true)
	for i in 9:
		var a := lerpf(a0, a1, i / 8.0)
		draw_line(c + Vector2(cos(a), sin(a)) * 80, c + Vector2(cos(a), sin(a)) * 88, Color(1, 1, 1, 0.5), 2.0)
	_text(c + Vector2(-90, 12), "%d" % int(kmh), 44, Color.WHITE, Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, 180)
	_text(c + Vector2(-90, 36), "KM/H", 13, Color(1, 1, 1, 0.6), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, 180)
	# aether meter
	var bar := Rect2(c.x - 330, c.y + 62, 210, 16)
	draw_rect(bar.grow(3), PANEL)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * p.aether, bar.size.y)), PINK if p.boosting else CYAN)
	for i in range(1, 4):
		draw_line(bar.position + Vector2(bar.size.x * i / 4.0, 0), bar.position + Vector2(bar.size.x * i / 4.0, bar.size.y), Color(0, 0, 0, 0.5), 2.0)
	_text(bar.position + Vector2(0, -8), "AETHER" + ("  BOOST!" if p.boosting else ""), 15, PINK if p.boosting else CYAN, Game.font_title)


## World event banner: the event's name and what it does when it starts, then a smaller
## reminder with the distance while one waits on the road ahead.
func _draw_event(at: Vector2, p: Car) -> void:
	var h := race.hazards
	var dist := h.distance_ahead(p)
	if h.banner_t > 0.0:
		var a := clampf(h.banner_t * 2.0, 0.0, 1.0)
		var flash := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.015)
		draw_rect(Rect2(at.x - 300, at.y - 42, 600, 76), Color(0.12, 0.04, 0.0, 0.6 * a))
		draw_rect(Rect2(at.x - 300, at.y - 42, 600, 4), Color(AMBER, a))
		_text(Vector2(at.x - 300, at.y), "! " + h.banner + " !", 34, Color(AMBER, a * flash), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, 600)
		var extra := ("   -   %d m ahead" % int(dist)) if dist >= 0.0 else ""
		_text(Vector2(at.x - 300, at.y + 26), h.banner_hint + extra, 16, Color(1, 1, 1, a), null, HORIZONTAL_ALIGNMENT_CENTER, 600)
	elif dist >= 0.0 and dist < 500.0:
		_text(Vector2(at.x - 200, at.y - 18), "! hazard %d m ahead" % int(dist), 18, Color(AMBER, 0.9), Game.font_title, HORIZONTAL_ALIGNMENT_CENTER, 400)
