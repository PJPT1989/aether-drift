class_name Props
extends RefCounted
## Builds the scenery: repeated props (drawn many times through MultiMesh), arches over the road
## and one-off landmarks. Everything is made from MeshKit primitives with vertex colours, styled
## after the three planes of the race: copper-and-indigo invention city, green river valley and
## desert ruins, primordial jungle. Curved parts (domes, trunks, foliage, rocks, fronds) are smooth
## shells built with `_grid`; `lite` variants (far layers and Low quality) skip the small details.

const COPPER := Color(0.78, 0.45, 0.22)
const BRASS := Color(0.85, 0.66, 0.3)
const INDIGO := Color(0.2, 0.2, 0.55)
const AETHER := Color(0.35, 0.9, 1.0)
const SAND := Color(0.86, 0.72, 0.5)
const LIMESTONE := Color(0.9, 0.84, 0.7)
const LAPIS := Color(0.15, 0.25, 0.65)
const GOLD := Color(0.95, 0.75, 0.3)
const LEAF := Color(0.2, 0.45, 0.15)
const VERDIGRIS := Color(0.32, 0.58, 0.52)
const WARM := Color(1.0, 0.74, 0.4)

## Props that need their own node (they move or emit particles).
const ANIMATED := ["windmill", "geyser"]
## How far from its centre a prop reaches, used to keep it off the road.
const RADIUS := {"city": 12.0, "lamp_tall": 2.0, "dome": 7.0, "curl_tree": 6.0, "windmill": 6.0,
	"palm": 6.0, "reeds": 2.5, "obelisk": 3.0, "column": 4.5, "ruin_wall": 8.0, "rock": 7.0,
	"broken_statue": 9.0, "giant_tree": 10.0, "fern": 4.0, "geyser": 6.5, "banner": 2.0}
const VARIANTS := 4
## The four walls of a box-shaped building, as outward normals.
const FACES := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]


static func _rng(kind: String, v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind) + v * 7919
	return r


# --- shape helpers -------------------------------------------------------------------

## Triangle with smooth normals, wound so its front faces the way the normals point.
static func tri_n(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color, glow := false) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) < 0.0:
		k.tri(a, c, b, col, glow, na, nc, nb)
	else:
		k.tri(a, b, c, col, glow, na, nb, nc)


## Quad wound so it faces `face`.
static func quad_f(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: Vector3, col: Color, glow := false) -> void:
	if (b - a).cross(c - a).dot(face) < 0.0:
		k.quad(a, d, c, b, col, glow)
	else:
		k.quad(a, b, c, d, col, glow)


## Vertical rectangle facing `nrm` (horizontal), centred at c.
static func _panel(k: MeshKit, c: Vector3, nrm: Vector3, w: float, h: float, col: Color, glow := false) -> void:
	var ax := Vector3.UP.cross(nrm).normalized() * (w * 0.5)
	var up := Vector3(0, h * 0.5, 0)
	k.quad(c - ax - up, c + ax - up, c + ax + up, c - ax + up, col, glow)


## Thin sheet seen from both sides (leaves, cloth): the side facing up gets `top`.
static func _two_sided(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, top: Color, under: Color) -> void:
	var up := (b - a).cross(c - a).y >= 0.0
	k.tri(a, b, c, top if up else under)
	k.tri(a, c, b, under if up else top)


static func _two_sided_quad(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, top: Color, under: Color) -> void:
	_two_sided(k, a, b, c, top, under)
	_two_sided(k, a, c, d, top, under)


## Smooth surface through a grid of points rows[i][j]. With rows rising and the points of each
## row going round as (cos a, sin a) in (x, z), the surface faces outwards. `col` is a Color or a
## Callable(centre: Vector3, normal: Vector3, i: int, j: int) -> Color called per quad.
static func _grid(k: MeshKit, rows: Array, col: Variant, closed := true, glow := false) -> void:
	var nr := rows.size()
	var nc: int = (rows[0] as PackedVector3Array).size()
	var nrm: Array = []
	for i in nr:
		var row: PackedVector3Array = rows[i]
		var nxt: PackedVector3Array = rows[mini(i + 1, nr - 1)]
		var prv: PackedVector3Array = rows[maxi(i - 1, 0)]
		var ns := PackedVector3Array()
		for j in nc:
			var jn := (j + 1) % nc if closed else mini(j + 1, nc - 1)
			var jp := (j - 1 + nc) % nc if closed else maxi(j - 1, 0)
			var nn := (nxt[j] - prv[j]).cross(row[jn] - row[jp])
			if nn.length_squared() < 1e-9:
				# a pole: point away from the neighbouring row's centre
				var o: PackedVector3Array = rows[1] if i == 0 else rows[nr - 2]
				var mid := Vector3.ZERO
				for p in o:
					mid += p
				nn = row[j] - mid / nc
			ns.append(nn.normalized())
		nrm.append(ns)
	var ncol := nc if closed else nc - 1
	for i in nr - 1:
		var r0: PackedVector3Array = rows[i]
		var r1: PackedVector3Array = rows[i + 1]
		var n0: PackedVector3Array = nrm[i]
		var n1: PackedVector3Array = nrm[i + 1]
		for j in ncol:
			var j1 := (j + 1) % nc
			var c: Color
			if col is Callable:
				c = col.call((r0[j] + r0[j1] + r1[j] + r1[j1]) * 0.25, (n0[j] + n0[j1] + n1[j] + n1[j1]).normalized(), i, j)
			else:
				c = col
			if (r1[j] - r0[j]).cross(r1[j1] - r0[j]).length_squared() > 1e-10:
				tri_n(k, r0[j], r1[j], r1[j1], n0[j], n1[j], n1[j1], c, glow)
			if (r1[j1] - r0[j]).cross(r0[j1] - r0[j]).length_squared() > 1e-10:
				tri_n(k, r0[j], r1[j1], r0[j1], n0[j], n1[j1], n0[j1], c, glow)


## A ring of `segs` points round centre c, square to the direction tg, starting at `side`.
static func _ring_pts(c: Vector3, tg: Vector3, side: Vector3, r: float, segs: int) -> PackedVector3Array:
	var fwd := side.cross(tg)
	var row := PackedVector3Array()
	for s in segs:
		var a := TAU * s / segs
		row.append(c + (side * cos(a) + fwd * sin(a)) * r)
	return row


static func _side_for(tg: Vector3) -> Vector3:
	return tg.cross(Vector3.FORWARD if absf(tg.y) > 0.9 else Vector3.UP).normalized()


## Smooth tube along `path`; `rad` is one radius or one per point. Ends are capped when `caps`.
static func _tube(k: MeshKit, path: Array, rad: Variant, col: Variant, segs := 8, caps := true, glow := false) -> void:
	var m := path.size()
	var rows: Array = []
	var side := _side_for((path[1] - path[0]).normalized())
	for i in m:
		var p: Vector3 = path[i]
		var tg: Vector3 = (path[mini(i + 1, m - 1)] - path[maxi(i - 1, 0)]).normalized()
		side = (side - tg * side.dot(tg)).normalized()
		var r: float = rad[i] if rad is Array else rad
		rows.append(_ring_pts(p, tg, side, r, segs))
	_grid(k, rows, col, true, glow)
	if caps:
		for e in [0, m - 1]:
			var row: PackedVector3Array = rows[e]
			var c: Vector3 = path[e]
			var out: Vector3 = (path[0] - path[1]) if e == 0 else (path[m - 1] - path[m - 2])
			out = out.normalized()
			var cc: Color = col if col is Color else BRASS
			for s in segs:
				tri_n(k, c, row[s], row[(s + 1) % segs], out, out, out, cc, glow)


## Surface of revolution round the vertical through `base`: prof is a list of Vector2(radius, y)
## going upwards.
static func _lathe(k: MeshKit, base: Vector3, prof: Array, col: Variant, segs := 16, glow := false) -> void:
	var rows: Array = []
	for p: Vector2 in prof:
		rows.append(_ring_pts(base + Vector3(0, p.y, 0), Vector3.UP, Vector3.RIGHT, maxf(p.x, 0.001), segs))
	_grid(k, rows, col, true, glow)


## Fluted shaft from a to b: `flutes` grooves cut `depth` (fraction of the radius) deep.
static func _fluted(k: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float, col: Variant, flutes := 12, depth := 0.07, rows_n := 3) -> void:
	var tg := (b - a).normalized()
	var side := _side_for(tg)
	var fwd := side.cross(tg)
	var rows: Array = []
	for i in rows_n:
		var t := float(i) / (rows_n - 1)
		var r := lerpf(ra, rb, t) * (1.0 + 0.04 * sin(t * PI))
		var row := PackedVector3Array()
		for s in flutes * 2:
			var an := TAU * s / (flutes * 2)
			var rr := r * (1.0 - depth * float(s % 2))
			row.append(a.lerp(b, t) + (side * cos(an) + fwd * sin(an)) * rr)
		rows.append(row)
	_grid(k, rows, col)
	var cc: Color = col if col is Color else LIMESTONE
	for e in [0, rows_n - 1]:
		var row: PackedVector3Array = rows[e]
		var c := a if e == 0 else b
		var out := -tg if e == 0 else tg
		for s in row.size():
			tri_n(k, c, row[s], row[(s + 1) % row.size()], out, out, out, cc)


## Lumpy smooth ellipsoid for rocks and foliage. Faces darken toward the bottom by `shade`, vary
## by `vary`, and `strata` paints horizontal bands (sandstone).
static func _blob(k: MeshKit, c: Vector3, r: Vector3, col: Color, seed: int, segs := 10, rings := 6, jit := 0.15, shade := 0.3, vary := 0.05, strata := 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var rows: Array = []
	for j in rings + 1:
		var t := PI * j / rings - PI * 0.5
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var u := Vector3(cos(t) * cos(a), sin(t), cos(t) * sin(a))
			var f := 1.0
			if j > 0 and j < rings:
				f += jit * (0.6 * sin(a * 3.0 + p1) * cos(t * 2.0 + p2) + 0.4 * rng.randf_range(-1.0, 1.0))
			row.append(c + u * r * f)
		rows.append(row)
	var ry := maxf(r.y, 0.01)
	var paint := func(m: Vector3, _n: Vector3, _i: int, _j: int) -> Color:
		var h := clampf((m.y - c.y) / ry * 0.5 + 0.5, 0.0, 1.0)
		var fc := col.darkened(shade * (0.6 - h) + rng.randf_range(-vary, vary))
		if strata > 0.0:
			fc = fc.darkened(strata * (0.5 + 0.5 * sin(m.y * 1.9 + sin(m.x * 0.3) * 0.8)))
		return fc
	_grid(k, rows, paint)


## Curved leaf (palm or fern frond) from `base` out along horizontal `dir`: it rises by `lift`
## and droops by `droop` toward the tip, with a pair of leaflets on every segment of the spine.
static func _frond(k: MeshKit, base: Vector3, dir: Vector3, length: float, width: float, lift: float, droop: float, col: Color, segs := 7) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var under := col.darkened(0.4)
	var prev := base
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var sp := base + dir * (length * t) + Vector3(0, lift * t - droop * t * t, 0)
		var w := width * sin(PI * clampf(t * 1.05 - 0.02, 0.05, 1.0))
		var mid := prev.lerp(sp, 0.35)
		var fwd := (sp - prev).normalized()
		var c := col.lightened(t * 0.08)
		for sd: float in [-1.0, 1.0]:
			var tip := mid + side * (sd * w) + fwd * (w * 0.55) + Vector3(0, -w * 0.45, 0)
			_two_sided(k, prev, sp, tip, c, under)
		prev = sp


## Grid of framed windows on one wall. `base` is the middle of the wall at y = 0.
static func _windows(k: MeshKit, base: Vector3, nrm: Vector3, span: float, y0: float, y1: float, fh: float, cols: int, night: bool, frame: Color, r: RandomNumberGenerator, lite: bool) -> void:
	var ax := Vector3.UP.cross(nrm)
	var rows := maxi(1, int((y1 - y0) / fh))
	var cw := span / cols
	var ww := cw * 0.52
	var wh := fh * 0.56
	for row in rows:
		var yc := y0 + (row + 0.5) * fh
		for c in cols:
			var p := base + ax * ((c + 0.5) * cw - span * 0.5) + Vector3(0, yc, 0)
			var pane := Color(0.07, 0.06, 0.09)
			var glow := false
			if night:
				if r.randf() < 0.55:
					var pick := r.randf()
					pane = WARM if pick < 0.7 else (Color(1.0, 0.88, 0.62) if pick < 0.88 else AETHER)
					pane = pane.darkened(r.randf() * 0.3)
					glow = true
			else:
				pane = Color(0.24, 0.3, 0.42).lightened(r.randf() * 0.15)
			if lite:
				_panel(k, p + nrm * 0.06, nrm, ww, wh, pane, glow)
				continue
			_panel(k, p + nrm * 0.05, nrm, ww + 0.5, wh + 0.45, frame)
			_panel(k, p + nrm * 0.09, nrm, ww, wh, pane, glow)
			_panel(k, p + nrm * 0.12, nrm, 0.12, wh, frame)
			# sill: front and top
			var sc := p + Vector3(0, -wh * 0.5 - 0.28, 0)
			var hx := ax * (ww * 0.5 + 0.4)
			_panel(k, sc + nrm * 0.32, nrm, ww + 0.8, 0.18, frame.lightened(0.08))
			var t0 := sc + Vector3(0, 0.09, 0) + nrm * 0.05
			var t1 := sc + Vector3(0, 0.09, 0) + nrm * 0.32
			quad_f(k, t0 - hx, t0 + hx, t1 + hx, t1 - hx, Vector3.UP, frame.lightened(0.15))


## Copper dome on a drum with ribs and a lantern on top. `base` is the bottom of the drum.
static func _ribbed_dome(k: MeshKit, base: Vector3, rd: float, col: Color, trim: Color, night: bool, lite: bool, ribs := 8) -> float:
	var segs := 10 if lite else 20
	k.cyl(base, base + Vector3(0, rd * 0.22, 0), rd * 1.05, rd * 1.05, trim, segs)
	k.cyl(base + Vector3(0, rd * 0.22, 0), base + Vector3(0, rd * 0.3, 0), rd * 1.12, rd * 1.1, trim.darkened(0.15), segs)
	var b := base + Vector3(0, rd * 0.3, 0)
	var prof: Array = []
	for i in 8:
		var f := float(i) / 7.0 * PI * 0.5
		prof.append(Vector2(rd * cos(f) * (1.0 + 0.1 * sin(f * 2.0)) + rd * 0.03, rd * 1.12 * sin(f)))
	var shade := func(m: Vector3, _n: Vector3, i: int, _j: int) -> Color:
		return col.lightened(i * 0.025)
	_lathe(k, b, prof, shade, segs)
	if not lite:
		for s in ribs:
			var a := TAU * s / ribs
			var path: Array = []
			for p: Vector2 in prof.slice(0, 7):
				path.append(b + Vector3(cos(a) * (p.x + rd * 0.02), p.y + rd * 0.01, sin(a) * (p.x + rd * 0.02)))
			_tube(k, path, rd * 0.035, BRASS, 4, false)
	var top := b + Vector3(0, rd * 1.1, 0)
	k.cyl(top, top + Vector3(0, rd * 0.28, 0), rd * 0.16, rd * 0.14, AETHER if night else BRASS, 8, night)
	k.cyl(top + Vector3(0, rd * 0.28, 0), top + Vector3(0, rd * 0.36, 0), rd * 0.22, rd * 0.2, BRASS, 8)
	k.cyl(top + Vector3(0, rd * 0.36, 0), top + Vector3(0, rd * 0.36 + 1.8, 0), rd * 0.12, 0.03, col.darkened(0.2), 8)
	return top.y + rd * 0.36 + 1.8


## Obelisk standing at the origin with a shaft `h` high.
static func _obelisk(k: MeshKit, h: float, lite: bool) -> void:
	k.box(Vector3(0, 0.35, 0), Vector3(3.8, 0.7, 3.8), LIMESTONE.darkened(0.22))
	k.box(Vector3(0, 0.95, 0), Vector3(3.0, 0.5, 3.0), LIMESTONE.darkened(0.1))
	k.box(Vector3(0, 1.25, 0), Vector3(3.08, 0.12, 3.08), GOLD)
	var y0 := 1.3
	k.taper(Vector3(0, y0, 0), Vector2(2, 2), Vector2(1.2, 1.2), h, LIMESTONE)
	k.taper(Vector3(0, y0 + h, 0), Vector2(1.2, 1.2), Vector2(0.01, 0.01), 1.4, GOLD)
	var band := y0 + h * 0.9
	k.taper(Vector3(0, band, 0), Vector2(1.34, 1.34), Vector2(1.32, 1.32), 0.3, GOLD)
	for f in 4:
		var bs := Basis(Vector3.UP, f * PI * 0.5)
		var ya := y0 + h * 0.07
		var yb := y0 + h * 0.85
		var ha := lerpf(1.0, 0.6, (ya - y0) / h) + 0.02
		var hb := lerpf(1.0, 0.6, (yb - y0) / h) + 0.02
		k.quad(bs * Vector3(-ha * 0.36, ya, ha), bs * Vector3(ha * 0.36, ya, ha), bs * Vector3(hb * 0.36, yb, hb), bs * Vector3(-hb * 0.36, yb, hb), LAPIS)
		if lite:
			continue
		for g in 9:
			var t := (g + 0.5) / 9.0
			var y := lerpf(ya, yb, t)
			var hz := lerpf(ha, hb, t) + 0.02
			var gx := hz * (0.12 if g % 2 == 0 else -0.1)
			var gs := 0.11 + 0.05 * float(g % 3)
			k.quad(bs * Vector3(gx - gs, y - gs, hz), bs * Vector3(gx + gs, y - gs, hz), bs * Vector3(gx + gs * 0.6, y + gs, hz), bs * Vector3(gx - gs * 0.6, y + gs, hz), GOLD)


## Papyrus-bundle capital (flared bell with painted bands) and its square abacus, on top of y.
static func _capital(k: MeshKit, y: float, r: float, c: Color) -> void:
	var paint := func(_m: Vector3, _n: Vector3, i: int, j: int) -> Color:
		if i == 0:
			return GOLD
		return LAPIS if j % 4 < 2 else c.lightened(0.05)
	_lathe(k, Vector3(0, y, 0), [Vector2(r * 0.95, 0), Vector2(r * 1.0, 0.3), Vector2(r * 1.25, 0.9), Vector2(r * 1.55, 1.5), Vector2(r * 1.62, 1.75)], paint, 20)
	k.box(Vector3(0, y + 2.0, 0), Vector3(r * 3.0, 0.5, r * 3.0), c)


# --- repeated props ------------------------------------------------------------------

## Mesh for one variant of a repeated prop. `night` lights windows and lamps; `lite` drops the
## small details (far layers, Low quality).
static func prop(kind: String, v: int, night: bool, lite := false) -> ArrayMesh:
	var k := MeshKit.new()
	var r := _rng(kind, v)
	match kind:
		"city":
			_city(k, r, v, night, lite)
		"lamp_tall":
			var dark := Color(0.22, 0.18, 0.2)
			var lc := AETHER if v % 2 == 0 else WARM
			k.cyl(Vector3(0, -0.2, 0), Vector3(0, 0.6, 0), 0.55, 0.45, dark, 12)
			k.cyl(Vector3(0, 0.6, 0), Vector3(0, 1.1, 0), 0.32, 0.22, COPPER, 12)
			_fluted(k, Vector3(0, 1.1, 0), Vector3(0, 7.0, 0), 0.17, 0.12, dark, 6, 0.15, 2)
			for y: float in [1.15, 3.6, 6.9]:
				k.cyl(Vector3(0, y, 0), Vector3(0, y + 0.25, 0), 0.24, 0.24, BRASS, 10)
			k.sphere(Vector3(0, 7.45, 0), Vector3(0.2, 0.2, 0.2), BRASS, 8, 4)
			k.cyl(Vector3(0, 7.6, 0), Vector3(0, 8.3, 0), 0.06, 0.01, BRASS, 6)
			for s: float in [-1.0, 1.0]:
				var arm: Array = [Vector3(0, 6.5, 0), Vector3(s * 0.55, 7.15, 0), Vector3(s * 1.15, 7.35, 0), Vector3(s * 1.6, 7.15, 0)]
				_tube(k, arm, 0.055, BRASS.darkened(0.2), 5, false)
				var lp := Vector3(s * 1.6, 6.45, 0)
				k.cyl(lp + Vector3(0, 0.4, 0), lp + Vector3(0, 0.75, 0), 0.42, 0.06, COPPER, 10)
				k.sphere(lp, Vector3(0.3, 0.42, 0.3), lc, 10, 6, true)
				for q in 4:
					var a := TAU * q / 4 + PI * 0.25
					var off := Vector3(cos(a), 0, sin(a)) * 0.33
					k.cyl(lp + off + Vector3(0, -0.4, 0), lp + off + Vector3(0, 0.42, 0), 0.03, 0.03, BRASS, 4, false, true, false)
				k.cyl(lp + Vector3(0, -0.4, 0), lp + Vector3(0, -0.7, 0), 0.22, 0.02, COPPER, 8)
		"dome":
			var rr := r.randf_range(3.5, 6.0)
			var hh := r.randf_range(3.0, 6.0)
			var wc := Color(0.85, 0.75, 0.62).lerp(Color(0.7, 0.45, 0.4), r.randf())
			var trim := wc.lerp(Color(0.95, 0.88, 0.75), 0.4)
			var roof := COPPER if r.randf() < 0.5 else VERDIGRIS
			var segs := 12 if lite else 20
			k.cyl(Vector3(0, -0.6, 0), Vector3(0, 0.4, 0), rr + 0.7, rr + 0.6, wc.darkened(0.3), segs)
			k.cyl(Vector3(0, 0.4, 0), Vector3(0, hh, 0), rr, rr, wc, segs, false, true, false)
			k.cyl(Vector3(0, hh - 0.5, 0), Vector3(0, hh, 0), rr + 0.2, rr + 0.25, COPPER.darkened(0.25), segs)
			k.cyl(Vector3(0, hh, 0), Vector3(0, hh + 0.45, 0), rr + 0.5, rr + 0.45, trim, segs)
			var bays := 8
			for i in bays:
				var a := TAU * (i + 0.5) / bays
				var nrm := Vector3(cos(a), 0, sin(a))
				if not lite:
					var pa := TAU * i / bays
					k.box(Vector3(cos(pa), 0, sin(pa)) * (rr + 0.12) + Vector3(0, hh * 0.5 + 0.2, 0), Vector3(0.5, hh - 0.4, 0.5), trim, false, -pa)
				var wy := hh * 0.55 + 0.2
				var door := i == 0
				var whh := (hh - 1.4) if door else hh * 0.42
				var wcy := (0.4 + whh * 0.5 + 0.1) if door else wy
				var lit := night and (door or r.randf() < 0.6)
				var pc := (WARM if lit else Color(0.16, 0.13, 0.13)) if door or night else Color(0.25, 0.3, 0.42)
				_panel(k, nrm * (rr + 0.04) + Vector3(0, wcy, 0), nrm, rr * 0.48, whh + 0.4, trim.darkened(0.1))
				_panel(k, nrm * (rr + 0.08) + Vector3(0, wcy - 0.1, 0), nrm, rr * 0.36, whh, pc, lit)
			_ribbed_dome(k, Vector3(0, hh + 0.45, 0), rr * 0.92, roof, trim, night, lite, 10)
		"curl_tree":
			var leaf: Color = [Color(0.25, 0.55, 0.3), Color(0.2, 0.55, 0.5), Color(0.8, 0.5, 0.2), Color(0.55, 0.65, 0.2)][v]
			var trunk := Color(0.4, 0.28, 0.2)
			var path: Array = [Vector3.ZERO + Vector3(0, -0.5, 0)]
			var rad: Array = [0.62]
			var p := Vector3.ZERO
			var dir := Vector3(r.randf_range(-0.3, 0.3), 1, r.randf_range(-0.3, 0.3)).normalized()
			for i in 5:
				p = p + dir * r.randf_range(1.6, 2.3)
				path.append(p)
				rad.append(0.5 - i * 0.07)
				dir = (dir + Vector3(r.randf_range(-0.45, 0.45), 0.25, r.randf_range(-0.45, 0.45))).normalized()
			_tube(k, path, rad, trunk, 6 if lite else 8, true)
			# the aether-sculpted curl: a branch spiralling round the crown
			var curl: Array = []
			var crad: Array = []
			var ca := r.randf() * TAU
			for i in 8:
				var t := i / 7.0
				var cr := lerpf(2.6, 0.6, t)
				curl.append(p + Vector3(cos(ca + t * 4.5) * cr, 0.6 + t * 2.2 - sin(t * PI) * 0.8, sin(ca + t * 4.5) * cr))
				crad.append(lerpf(0.26, 0.07, t))
			curl[0] = p
			_tube(k, curl, crad, trunk.lightened(0.05), 5, false)
			var blobs := 4 if lite else 7
			for i in blobs:
				var a := ca + i * 1.15
				var rad2 := 1.2 + i * 0.3
				var sz := 1.9 - i * 0.12
				var bc := leaf.lerp(leaf.lightened(0.25), float(i) / blobs).lerp(Color(0.85, 0.75, 0.3), r.randf() * 0.12)
				_blob(k, p + Vector3(cos(a) * rad2, 0.3 + i * 0.3, sin(a) * rad2), Vector3(sz * 1.15, sz * 0.9, sz * 1.15), bc, v * 31 + i, 7 if lite else 11, 5 if lite else 7, 0.2, 0.45, 0.012)
		"palm":
			var h := r.randf_range(7, 12)
			var bend := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * r.randf_range(1.5, 3.5)
			var path: Array = []
			var rad: Array = []
			var rows := 9 if lite else 17
			for i in rows:
				var t := float(i) / (rows - 1)
				path.append(bend * t * t + Vector3(0, h * t - 0.3, 0))
				rad.append(lerpf(0.45, 0.27, t) * (1.0 if i % 2 == 0 else 0.88))
			var bark := Color(0.55, 0.42, 0.3)
			var rings := func(_m: Vector3, _n: Vector3, i: int, _j: int) -> Color:
				return bark if i % 2 == 0 else bark.darkened(0.18)
			_tube(k, path, rad, rings, 6 if lite else 8, false)
			var top: Vector3 = path[rows - 1]
			k.sphere(top + Vector3(0, 0.15, 0), Vector3(0.55, 0.45, 0.55), Color(0.42, 0.4, 0.2), 8, 5)
			var fronds := 7 if lite else 11
			for i in fronds:
				var a := TAU * i / fronds + r.randf() * 0.3
				var out := Vector3(cos(a), 0, sin(a))
				var c := LEAF.lerp(Color(0.3, 0.52, 0.16), r.randf()).darkened(r.randf() * 0.15)
				var ln := r.randf_range(4.2, 5.6)
				_frond(k, top + Vector3(0, 0.3, 0), out, ln, r.randf_range(1.0, 1.3), r.randf_range(0.8, 1.8), r.randf_range(3.0, 4.6), c, 6 if lite else 12)
			if not lite:
				for i in 2:
					var a := r.randf() * TAU
					_frond(k, top, Vector3(cos(a), 0, sin(a)), 3.2, 0.7, -0.4, 2.6, Color(0.55, 0.45, 0.25), 6)
				for i in 3:
					var a := TAU * i / 3 + 0.4
					k.sphere(top + Vector3(cos(a) * 0.4, -0.25, sin(a) * 0.4), Vector3.ONE * 0.26, Color(0.4, 0.3, 0.15), 8, 5)
		"reeds":
			var stem := Color(0.45, 0.6, 0.25)
			for i in (12 if lite else 22):
				var b := Vector3(r.randf_range(-1.7, 1.7), -0.3, r.randf_range(-1.7, 1.7))
				var lean := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
				var hgt := r.randf_range(1.6, 3.0)
				var side := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * 0.07
				var m := b + lean * 0.35 + Vector3(0, hgt * 0.55, 0)
				var tip := b + lean + Vector3(0, hgt, 0)
				var c := stem.lerp(Color(0.62, 0.66, 0.3), r.randf())
				_two_sided_quad(k, b - side, b + side, m + side * 0.6, m - side * 0.6, c, c.darkened(0.2))
				_two_sided(k, m - side * 0.6, m + side * 0.6, tip, c.lightened(0.08), c.darkened(0.2))
			for i in (3 if lite else 7):
				var b := Vector3(r.randf_range(-1.4, 1.4), -0.3, r.randf_range(-1.4, 1.4))
				var top := b + Vector3(r.randf_range(-0.2, 0.2), r.randf_range(2.4, 3.2), r.randf_range(-0.2, 0.2))
				k.cyl(b, top, 0.04, 0.025, stem.darkened(0.1), 4, false, true, false)
				k.cyl(top - Vector3(0, 0.55, 0), top - Vector3(0, 0.05, 0), 0.1, 0.09, Color(0.42, 0.27, 0.15), 6)
		"obelisk":
			_obelisk(k, r.randf_range(12, 20), lite)
		"column":
			var h := r.randf_range(4, 12)
			var c := LIMESTONE.lerp(SAND, r.randf())
			var fl := 8 if lite else 12
			if v == 3:
				# fallen drums and a capital lying in the sand
				_fluted(k, Vector3(-4.2, 0.75, 0.2), Vector3(-1.4, 0.8, 0.0), 0.9, 0.9, c, fl, 0.07, 2)
				_fluted(k, Vector3(-1.0, 0.75, 0.4), Vector3(1.8, 0.75, 1.3), 0.88, 0.88, c.darkened(0.05), fl, 0.07, 2)
				_fluted(k, Vector3(2.3, 0.7, 1.0), Vector3(4.0, 0.55, 0.2), 0.85, 0.85, c.darkened(0.1), fl, 0.07, 2)
				k.box(Vector3(1.0, 0.45, -2.2), Vector3(2.6, 0.9, 2.6), c.darkened(0.08), false, 0.5)
				_blob(k, Vector3(-2.6, 0.0, -1.8), Vector3(1.4, 0.6, 1.0), c.darkened(0.15), v, 7, 4, 0.25, 0.2)
			else:
				k.box(Vector3(0, 0.3, 0), Vector3(2.9, 0.6, 2.9), c.darkened(0.15))
				k.cyl(Vector3(0, 0.6, 0), Vector3(0, 1.0, 0), 1.15, 1.0, c.darkened(0.06), 16)
				var top := h
				if v == 1:
					top = h * 0.6
				_fluted(k, Vector3(0, 1.0, 0), Vector3(0, top, 0), 0.9, 0.8, c, fl, 0.07, 3)
				if v == 1:
					# broken top: a jagged stump and a fallen piece
					_blob(k, Vector3(0, top, 0), Vector3(0.82, 0.35, 0.82), c.darkened(0.04), v, 8, 4, 0.35, 0.1)
					_fluted(k, Vector3(1.6, 0.55, -1.5), Vector3(3.4, 0.6, 1.0), 0.8, 0.8, c.darkened(0.1), fl, 0.07, 2)
				else:
					_capital(k, top, 0.82, c)
					if v == 2 and not lite:
						k.box(Vector3(1.6, top + 2.75, 0), Vector3(5.2, 1.0, 1.4), c.darkened(0.06))
		"ruin_wall":
			var c := SAND.darkened(0.05)
			var length := 13.0
			var p1 := r.randf() * TAU
			var x := -length * 0.5
			var course_h := 0.9
			var door := v % 2 == 0
			for course in 7:
				x = -length * 0.5 + (0.0 if course % 2 == 0 else -0.7)
				while x < length * 0.5:
					var bl := r.randf_range(1.3, 2.4)
					var mid := x + bl * 0.5
					var top := 2.2 + 3.6 * (0.5 + 0.5 * sin(mid * 0.45 + p1)) + r.randf_range(-0.6, 0.6)
					var y := course * course_h
					var in_door := door and absf(mid) < 1.4 and course < 4
					if y + course_h * 0.5 < top and not in_door and mid > -length * 0.5:
						var bc := c.darkened(r.randf() * 0.18).lerp(Color(0.95, 0.85, 0.65), r.randf() * 0.15)
						k.box(Vector3(mid, y + course_h * 0.5, r.randf_range(-0.08, 0.08)), Vector3(bl - 0.08, course_h - 0.06, 1.6 + r.randf_range(-0.1, 0.1)), bc, false, r.randf_range(-0.03, 0.03))
					x += bl
			if door:
				k.box(Vector3(0, 4 * course_h + 0.4, 0), Vector3(3.8, 0.8, 1.9), c.lightened(0.05))
				if not lite:
					k.box(Vector3(0, 4 * course_h + 0.05, 0.96), Vector3(3.2, 0.25, 0.04), LAPIS.lerp(c, 0.4))
			for i in (2 if lite else 5):
				k.box(Vector3(r.randf_range(-6, 6), 0.3, r.randf_range(1.6, 3.2)), Vector3(r.randf_range(1.0, 2.0), 0.8, r.randf_range(0.9, 1.5)), c.darkened(r.randf() * 0.2), false, r.randf() * PI)
		"rock":
			var rc := Color(0.72, 0.5, 0.33)
			var sz := Vector3(r.randf_range(3, 7), r.randf_range(2, 5), r.randf_range(3, 7))
			_blob(k, Vector3(0, sz.y * 0.35, 0), sz, rc, v, 9 if lite else 14, 6 if lite else 9, 0.22, 0.3, 0.06, 0.12)
			if not lite:
				for i in 2:
					var a := r.randf() * TAU
					var s2 := r.randf_range(0.8, 1.8)
					_blob(k, Vector3(cos(a) * (sz.x * 0.8 + s2), s2 * 0.2, sin(a) * (sz.z * 0.8 + s2)), Vector3(s2, s2 * 0.7, s2 * 1.1), rc.darkened(0.08), v * 7 + i, 8, 5, 0.25, 0.3, 0.06, 0.1)
		"broken_statue":
			_broken_statue(k, r, v, lite)
		"giant_tree":
			_giant_tree(k, r, v, lite)
		"fern":
			var c := Color(0.15, 0.45, 0.15).lerp(Color(0.35, 0.55, 0.15), r.randf())
			var nf := 7 if lite else 11
			for i in nf:
				var a := TAU * i / nf + r.randf() * 0.4
				var out := Vector3(cos(a), 0, sin(a))
				var fc := c.lerp(Color(0.4, 0.6, 0.18), r.randf() * 0.5)
				_frond(k, out * 0.2, out, r.randf_range(2.6, 4.0), r.randf_range(0.6, 0.8), r.randf_range(2.6, 3.6), r.randf_range(2.4, 3.4), fc, 5 if lite else 9)
			if not lite:
				for i in 3:
					var a := r.randf() * TAU
					var base := Vector3(cos(a) * 0.3, 0, sin(a) * 0.3)
					var fid: Array = [base, base + Vector3(0, 0.8, 0), base + Vector3(cos(a) * 0.25, 1.3, sin(a) * 0.25), base + Vector3(cos(a) * 0.45, 1.15, sin(a) * 0.45)]
					_tube(k, fid, [0.07, 0.06, 0.07, 0.11], c.lightened(0.12), 5, true)
		"banner":
			var dark := Color(0.3, 0.25, 0.25)
			var bc: Color = [Color(0.8, 0.15, 0.45), Color(0.2, 0.25, 0.7), Color(0.9, 0.55, 0.15), Color(0.2, 0.6, 0.55)][v]
			k.cyl(Vector3(0, -0.2, 0), Vector3(0, 0.6, 0), 0.38, 0.3, dark.darkened(0.2), 10)
			k.cyl(Vector3(0, 0.6, 0), Vector3(0, 9.2, 0), 0.13, 0.1, dark, 8)
			k.cyl(Vector3(0, 8.9, 0), Vector3(1.95, 8.9, 0), 0.06, 0.05, BRASS, 6)
			k.sphere(Vector3(0, 9.35, 0), Vector3.ONE * 0.25, BRASS, 8, 5)
			k.cyl(Vector3(0, 9.55, 0), Vector3(0, 10.2, 0), 0.08, 0.01, BRASS, 6)
			# the cloth hangs from the arm and ripples; a forked tail at the bottom
			var cols := 6
			var prev_t := Vector3.ZERO
			var prev_b := Vector3.ZERO
			for i in cols + 1:
				var x := 0.2 + 1.65 * i / cols
				var z := sin(x * 3.2 + v) * 0.16
				var tb := 4.0 - 0.7 * (1.0 - absf(float(i) / cols - 0.5) * 2.0)
				var pt := Vector3(x, 8.8, z)
				var pb := Vector3(x, tb, z)
				if i > 0:
					var sc := bc.darkened(0.1 * float(i % 2))
					_two_sided_quad(k, prev_b, pb, pt, prev_t, sc, sc)
				prev_t = pt
				prev_b = pb
			for s: float in [-1.0, 1.0]:
				# glowing emblem on both faces of the cloth
				var ec := Vector3(1.025, 6.6, sin(1.025 * 3.2 + v) * 0.16 + s * 0.05)
				var e := 0.38
				quad_f(k, ec + Vector3(0, -e, 0), ec + Vector3(e, 0, 0), ec + Vector3(0, e, 0), ec + Vector3(-e, 0, 0), Vector3(0, 0, s), AETHER, true)
		"windmill":
			_windmill(k, r, lite)
		"geyser":
			var rows: Array = []
			var prof := [Vector2(5.8, -0.8), Vector2(4.8, 0.2), Vector2(3.6, 0.9), Vector2(2.5, 1.35), Vector2(1.9, 1.1), Vector2(1.6, 0.5)]
			for pi in prof.size():
				var pr: Vector2 = prof[pi]
				var row := PackedVector3Array()
				for s in 18:
					var a := TAU * s / 18
					var jr := pr.x * (1.0 + (0.1 * sin(a * 3.0 + v) + r.randf_range(-0.05, 0.05)) * (1.0 if pi < 4 else 0.3))
					row.append(Vector3(cos(a) * jr, pr.y + r.randf_range(-0.1, 0.1), sin(a) * jr))
				rows.append(row)
			var mineral := func(_m: Vector3, _n: Vector3, i: int, j: int) -> Color:
				var cs: Array = [Color(0.42, 0.38, 0.33), Color(0.75, 0.45, 0.2), Color(0.85, 0.65, 0.3), Color(0.9, 0.86, 0.72), Color(0.4, 0.7, 0.6)]
				return (cs[mini(i, 4)] as Color).darkened(0.08 * float(j % 3))
			_grid(k, rows, mineral)
			k.cyl(Vector3(0, 0.3, 0), Vector3(0, 0.75, 0), 1.75, 1.75, Color(0.5, 1.0, 0.6), 18, true)
			for i in 4:
				var a := TAU * i / 4 + v
				_blob(k, Vector3(cos(a) * 5.4, 0.0, sin(a) * 5.4), Vector3(0.9, 0.6, 1.1), Color(0.45, 0.4, 0.35), v * 5 + i, 7, 4, 0.25, 0.3)
	return k.commit()


static func _city(k: MeshKit, r: RandomNumberGenerator, v: int, night: bool, lite: bool) -> void:
	var w := r.randf_range(10, 18)
	var d := r.randf_range(10, 18)
	var h := r.randf_range(14, 46)
	var wall := Color(0.42, 0.3, 0.3).lerp(Color(0.6, 0.45, 0.35), r.randf())
	var trim := wall.lerp(Color(0.86, 0.72, 0.52), 0.4)
	var dark := wall.darkened(0.4)
	# ground floor: shop fronts with copper awnings
	var pod := 4.5
	k.box(Vector3(0, pod * 0.5 - 0.5, 0), Vector3(w + 1.0, pod + 1.0, d + 1.0), dark)
	k.box(Vector3(0, pod + 0.2, 0), Vector3(w + 1.6, 0.4, d + 1.6), trim)
	for nrm: Vector3 in FACES:
		var span := (w if nrm.z != 0.0 else d) + 1.0
		var off := ((d if nrm.z != 0.0 else w) + 1.0) * 0.5
		var ax := Vector3.UP.cross(nrm)
		var shops := maxi(2, int(span / 5.0))
		for s in shops:
			var c := nrm * (off + 0.04) + ax * ((s + 0.5) * span / shops - span * 0.5) + Vector3(0, 2.0, 0)
			var sw := span / shops - 1.0
			var lit := night and r.randf() < 0.8
			var sc := (WARM if r.randf() < 0.7 else AETHER) if lit else Color(0.16, 0.17, 0.22)
			_panel(k, c, nrm, sw + 0.4, 3.0, trim.darkened(0.3))
			_panel(k, c + nrm * 0.04, nrm, sw, 2.6, sc.darkened(0.15) if lit else sc, lit)
			if not lite and s % 2 == 0:
				var a0 := c + nrm * 0.1 + Vector3(0, 1.7, 0)
				var a1 := c + nrm * 1.5 + Vector3(0, 1.1, 0)
				var hx := ax * (sw * 0.5 + 0.2)
				_two_sided_quad(k, a0 - hx, a0 + hx, a1 + hx, a1 - hx, COPPER, COPPER.darkened(0.45))
	# storeys in one to three tiers, each set back from the one below
	var fracs: Array = [[1.0], [0.62, 0.38], [0.5, 0.3, 0.2]][0 if h < 22.0 else (1 if h < 34.0 else 2)]
	var y := pod + 0.4
	var tw := w
	var td := d
	for ti in fracs.size():
		var th: float = (h - pod) * float(fracs[ti])
		k.box(Vector3(0, y + th * 0.5, 0), Vector3(tw, th, td), wall)
		for nrm: Vector3 in FACES:
			var span := tw if nrm.z != 0.0 else td
			var off := (td if nrm.z != 0.0 else tw) * 0.5
			var cols := clampi(int(span / 3.6), 2, 5)
			_windows(k, nrm * off, nrm, span - 1.6, y + 0.4, y + th - 0.8, 3.6, cols, night, trim, r, lite)
			if not lite and ti == 0 and v % 2 == 0 and nrm.z != 0.0:
				var floors := int((th - 1.2) / 3.6)
				for f in range(1, floors, 2):
					var by := y + 0.4 + f * 3.6 + 0.2
					k.box(nrm * (off + 0.7) + Vector3(0, by, 0), Vector3(3.6, 0.25, 1.4), trim)
					k.box(nrm * (off + 1.35) + Vector3(0, by + 0.55, 0), Vector3(3.6, 0.85, 0.08), BRASS.darkened(0.2))
					for sx: float in [-1.0, 1.0]:
						k.box(nrm * (off + 0.7) + Vector3(sx * 1.76, by + 0.55, 0), Vector3(0.08, 0.85, 1.4), BRASS.darkened(0.2))
		if not lite:
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					k.box(Vector3(cx * tw * 0.5, y + th * 0.5, cz * td * 0.5), Vector3(0.9, th, 0.9), trim.darkened(0.12))
		k.box(Vector3(0, y + th - 0.2, 0), Vector3(tw + 0.3, 0.4, td + 0.3), COPPER.darkened(0.25))
		k.box(Vector3(0, y + th + 0.25, 0), Vector3(tw + 1.0, 0.5, td + 1.0), trim)
		y += th + 0.5
		if ti < fracs.size() - 1:
			tw *= 0.78
			td *= 0.78
	var rc := COPPER if r.randf() < 0.6 else VERDIGRIS
	match v % 4:
		0:
			_ribbed_dome(k, Vector3(0, y, 0), minf(tw, td) * 0.38, rc, trim, night, lite)
		1:
			# aether crown: a needle with glowing rings and brass fins
			k.cyl(Vector3(0, y, 0), Vector3(0, y + 1.5, 0), tw * 0.3, tw * 0.26, trim, 12)
			k.cyl(Vector3(0, y + 1.5, 0), Vector3(0, y + 12.0, 0), 1.0, 0.1, rc, 12)
			k.ring(Vector3(0, y + 4.0, 0), Vector3.UP, tw * 0.38, 0.25, AETHER, 16 if lite else 32, 4, true)
			k.ring(Vector3(0, y + 6.8, 0), Vector3.UP, tw * 0.25, 0.18, AETHER, 12 if lite else 24, 4, true)
			for f in 4:
				var bs := Basis(Vector3.UP, f * PI * 0.5 + PI * 0.25)
				k.taper(Vector3(0, y + 1.5, 0) + bs * Vector3(0, 0, 1.4), Vector2(0.15, 2.4), Vector2(0.05, 0.3), 5.0, BRASS, false, f * PI * 0.5 + PI * 0.25)
		2:
			# mansard roof with dormers and chimneys
			k.taper(Vector3(0, y - 0.1, 0), Vector2(tw + 0.4, td + 0.4), Vector2(tw * 0.62, td * 0.62), 4.0, rc.darkened(0.2))
			k.box(Vector3(0, y + 4.0, 0), Vector3(tw * 0.64, 0.25, td * 0.64), BRASS.darkened(0.2))
			if not lite:
				var nd := maxi(2, int(tw / 4.5))
				for sz: float in [-1.0, 1.0]:
					for i in nd:
						var x := ((i + 0.5) / nd - 0.5) * tw * 0.6
						var z := sz * (lerpf(td * 0.5 + 0.2, td * 0.31, 0.4) - 0.3)
						k.box(Vector3(x, y + 1.6, z), Vector3(1.6, 2.0, 1.6), trim)
						k.taper(Vector3(x, y + 2.6, z), Vector2(1.9, 1.9), Vector2(0.08, 1.9), 0.9, rc)
						var lit := night and r.randf() < 0.6
						_panel(k, Vector3(x, y + 1.5, z + sz * 0.82), Vector3(0, 0, sz), 0.9, 1.2, WARM if lit else Color(0.1, 0.09, 0.12), lit)
			for i in 2:
				var cp := Vector3(r.randf_range(-0.25, 0.25) * tw, y + 3.5, r.randf_range(-0.2, 0.2) * td)
				k.box(cp, Vector3(0.9, 3.0, 0.9), dark)
				k.box(cp + Vector3(0, 1.6, 0), Vector3(1.2, 0.25, 1.2), trim)
		_:
			# two corner turrets with copper caps and a ribbed dome between them
			var segs := 8 if lite else 12
			for cx: float in [-1.0, 1.0]:
				var c := Vector3(cx * (tw * 0.5 - 0.6), y, td * 0.5 - 0.6)
				k.cyl(c, c + Vector3(0, 4.5, 0), 1.3, 1.3, trim, segs, false, true, false)
				k.cyl(c + Vector3(0, 3.6, 0), c + Vector3(0, 4.1, 0), 1.45, 1.45, COPPER.darkened(0.2), segs)
				k.sphere(c + Vector3(0, 4.5, 0), Vector3(1.45, 1.9, 1.45), rc, segs, 5)
				k.cyl(c + Vector3(0, 6.2, 0), c + Vector3(0, 7.6, 0), 0.12, 0.02, BRASS, 6)
				if not lite:
					var lit := night and r.randf() < 0.7
					_panel(k, c + Vector3(0, 2.2, 1.32), Vector3(0, 0, 1), 0.5, 1.2, WARM if lit else Color(0.1, 0.09, 0.12), lit)
			_ribbed_dome(k, Vector3(0, y, -td * 0.12), minf(tw, td) * 0.3, rc, trim, night, lite)


static func _broken_statue(k: MeshKit, r: RandomNumberGenerator, v: int, lite: bool) -> void:
	# the toppled head of a lion-headed guardian, half sunk in the sand
	var c := LIMESTONE.darkened(0.1)
	var segs := 10 if lite else 16
	var tilt := 0.35 if v % 2 == 0 else -0.3
	k.xf = Transform3D(Basis(Vector3(0, 0, 1), tilt), Vector3(0, -0.4, 0))
	_blob(k, Vector3(0, 4.0, 0), Vector3(4.0, 4.4, 4.0), c, v, segs, segs - 6, 0.04, 0.25)
	_blob(k, Vector3(0, 3.4, 3.4), Vector3(2.3, 2.1, 2.0), c.darkened(0.06), v + 1, segs - 4, 6, 0.05, 0.25)
	k.sphere(Vector3(0, 4.3, 5.2), Vector3(0.9, 0.6, 0.5), c.darkened(0.3), 8, 4)
	for s: float in [-1.0, 1.0]:
		k.sphere(Vector3(s * 1.5, 5.4, 3.5), Vector3(0.55, 0.35, 0.3), Color(0.15, 0.13, 0.12), 8, 4)
		k.taper(Vector3(s * 2.3, 7.4, -0.5), Vector2(1.8, 1.0), Vector2(0.2, 0.2), 3.2, c, false, 0.0, Vector3(s * 0.8, 0, -0.2))
	# striped headdress round the back of the head, its paint mostly worn away
	var rows: Array = []
	var prof := [Vector2(5.6, 0.0), Vector2(5.0, 2.5), Vector2(4.6, 5.0), Vector2(4.3, 7.0), Vector2(3.0, 8.4)]
	for pr: Vector2 in prof:
		var row := PackedVector3Array()
		for s in 13:
			var a := PI * 0.5 + 0.8 + (TAU - 1.6) * s / 12.0
			row.append(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x - 0.6))
		rows.append(row)
	var worn := LAPIS.lerp(c, 0.55)
	var stripes := func(_m: Vector3, _n: Vector3, _i: int, j: int) -> Color:
		return worn if j % 2 == 0 else GOLD.lerp(c, 0.45)
	_grid(k, rows, stripes, false)
	k.box(Vector3(0, 6.2, 3.2), Vector3(5.0, 0.6, 0.6), GOLD)
	k.xf = Transform3D.IDENTITY
	# a broken forearm and rubble
	_tube(k, [Vector3(6.5, 0.6, 1.5), Vector3(10, 0.9, 0.3), Vector3(13.6, 1.0, -1.0)], [1.35, 1.2, 1.1], c, segs - 4, true)
	_blob(k, Vector3(14.6, 0.6, -1.4), Vector3(1.6, 1.0, 1.8), c.darkened(0.05), v + 7, 8, 5, 0.12, 0.2)
	if not lite:
		for i in 4:
			k.box(Vector3(r.randf_range(-6, 6), 0.3, r.randf_range(4, 7)), Vector3(r.randf_range(0.8, 1.8), 0.8, r.randf_range(0.8, 1.5)), c.darkened(r.randf() * 0.2), false, r.randf() * PI)


static func _giant_tree(k: MeshKit, r: RandomNumberGenerator, v: int, lite: bool) -> void:
	var h := r.randf_range(38, 60)
	var bark := Color(0.32, 0.24, 0.16)
	var segs := 10 if lite else 16
	var ph := r.randf() * TAU
	# trunk with buttress roots: the cross-section has five lobes that fade with height
	var ys := [-1.5, 0.5, 2.5, 5.0, 9.0, h * 0.3, h * 0.48, h * 0.64, h * 0.76]
	var rows: Array = []
	for y: float in ys:
		var t := clampf(y / h, 0.0, 1.0)
		var base_r := lerpf(2.7, 1.2, pow(t, 0.7))
		var lobe := 1.1 * exp(-maxf(y, 0.0) / 3.2)
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var rr := base_r * (1.0 + lobe * pow(0.5 + 0.5 * cos(5.0 * a + ph + y * 0.04), 3.0)) * (1.0 + 0.05 * sin(a * 7.0 + y))
			row.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		rows.append(row)
	var grooves := func(m: Vector3, _n: Vector3, i: int, j: int) -> Color:
		return bark.darkened(0.12 * float(j % 2) + 0.15 * (1.0 - clampf(m.y / 10.0, 0.0, 1.0))).lightened(0.03 * float(i % 2))
	_grid(k, rows, grooves)
	var g := Color(0.12, 0.35, 0.12).lerp(Color(0.25, 0.42, 0.1), r.randf())
	var top := Vector3(0, h * 0.76, 0)
	# branches out to the canopy
	var crowns: Array = []
	for i in 4:
		var a := ph + TAU * i / 4 + r.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var y0 := h * r.randf_range(0.55, 0.7)
		var end := out * r.randf_range(7, 10) + Vector3(0, y0 + r.randf_range(5, 9), 0)
		_tube(k, [Vector3(0, y0, 0), out * 3.0 + Vector3(0, y0 + 2.5, 0), end], [0.9, 0.6, 0.35], bark, 6 if lite else 7, false)
		crowns.append(end)
	crowns.append(top + Vector3(0, 4, 0))
	var lumps := 3 if lite else 6
	for i in lumps:
		var cc: Vector3 = crowns[i % crowns.size()]
		var sz := r.randf_range(7, 10) - i * 0.4
		var off := Vector3(r.randf_range(-2, 2), r.randf_range(0.5, 2.5) + float(i / crowns.size()) * 3.0, r.randf_range(-2, 2))
		_blob(k, cc + off, Vector3(sz, sz * 0.36, sz), g.lightened(i * 0.04).lerp(Color(0.3, 0.45, 0.12), r.randf() * 0.3), v * 13 + i, 9 if lite else 13, 5 if lite else 6, 0.2, 0.45, 0.015)
	if not lite:
		for i in 8:
			var a := r.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(5, 9) + Vector3(0, h * 0.68, 0)
			var ln := r.randf_range(8, 16)
			_tube(k, [p, p + Vector3(r.randf_range(-0.6, 0.6), -ln * 0.5, r.randf_range(-0.6, 0.6)), p + Vector3(r.randf_range(-1, 1), -ln, r.randf_range(-1, 1))], [0.13, 0.1, 0.07], Color(0.2, 0.4, 0.15), 4, false)


static func _windmill(k: MeshKit, r: RandomNumberGenerator, lite: bool) -> void:
	var body := BRASS.darkened(0.2)
	k.cyl(Vector3(0, -0.5, 0), Vector3(0, 1.0, 0), 2.6, 2.4, Color(0.55, 0.5, 0.45), 12)
	# eight-sided tower with a slight waist
	var rows: Array = []
	for i in 6:
		var t := i / 5.0
		var rr := lerpf(1.95, 0.95, t) - sin(t * PI) * 0.15
		var row := PackedVector3Array()
		for s in 8:
			var a := TAU * s / 8 + PI / 8
			row.append(Vector3(cos(a) * rr, 1.0 + t * 14.0, sin(a) * rr))
		rows.append(row)
	_grid(k, rows, body)
	for i in 4:
		var y := 3.0 + i * 3.3
		var rr := lerpf(1.95, 0.95, (y - 1.0) / 14.0) - sin((y - 1.0) / 14.0 * PI) * 0.15
		k.ring(Vector3(0, y, 0), Vector3.UP, rr + 0.05, 0.12, COPPER, 16, 4)
	if not lite:
		# filigree ribs up the corners
		for s in 8:
			var a := TAU * s / 8 + PI / 8
			var path: Array = []
			for i in 6:
				var row: PackedVector3Array = rows[i]
				path.append(row[s] + Vector3(cos(a), 0, sin(a)) * 0.06)
			_tube(k, path, 0.07, COPPER.lightened(0.1), 4, false)
	_panel(k, Vector3(0, 1.9, 1.86), Vector3(0, 0, 1), 1.3, 2.0, BRASS.darkened(0.45))
	_panel(k, Vector3(0, 1.85, 1.89), Vector3(0, 0, 1), 1.0, 1.8, Color(0.3, 0.2, 0.15))
	for i in 2:
		var y := 6.5 + i * 4.0
		var rr := lerpf(1.95, 0.95, (y - 1.0) / 14.0) - sin((y - 1.0) / 14.0 * PI) * 0.15
		_panel(k, Vector3(0, y, rr + 0.02), Vector3(0, 0, 1), 0.5, 0.9, Color(0.25, 0.32, 0.45))
	# gallery and railing under the cap
	k.cyl(Vector3(0, 14.6, 0), Vector3(0, 14.9, 0), 2.0, 2.0, COPPER.darkened(0.2), 16)
	k.ring(Vector3(0, 15.7, 0), Vector3.UP, 1.95, 0.05, BRASS, 16, 3)
	if not lite:
		for s in 8:
			var a := TAU * s / 8
			k.cyl(Vector3(cos(a) * 1.95, 14.9, sin(a) * 1.95), Vector3(cos(a) * 1.95, 15.7, sin(a) * 1.95), 0.04, 0.04, BRASS, 4, false, true, false)
	# cap and tail vane
	k.sphere(Vector3(0, 16.5, 0.1), Vector3(1.15, 1.15, 1.75), COPPER, 14, 7)
	k.cyl(Vector3(0, 16.6, -1.2), Vector3(0, 16.9, -3.4), 0.12, 0.08, BRASS, 6)
	k.box(Vector3(0, 17.0, -4.1), Vector3(0.08, 1.8, 2.0), Color(0.92, 0.85, 0.7))
	k.box(Vector3(0, 17.0, -4.1), Vector3(0.12, 1.9, 0.12), BRASS)


## Rotor of a windmill (the blades), spun by the track.
static func windmill_rotor() -> ArrayMesh:
	var k := MeshKit.new()
	var sail := Color(0.92, 0.85, 0.7)
	k.cyl(Vector3(0, 0, -0.3), Vector3(0, 0, 0.5), 0.55, 0.5, BRASS, 12)
	k.cyl(Vector3(0, 0, 0.5), Vector3(0, 0, 1.2), 0.5, 0.05, COPPER, 12)
	for i in 6:
		var a := TAU * i / 6
		k.xf = Transform3D(Basis(Vector3(0, 0, 1), a), Vector3.ZERO)
		k.box(Vector3(3.9, 0, 0.05), Vector3(6.6, 0.16, 0.16), COPPER.darkened(0.2))
		for c in 3:
			var x := 2.2 + c * 1.9
			k.box(Vector3(x, 0.35, 0.1), Vector3(0.08, 0.9, 0.08), COPPER.darkened(0.3))
		var tw := 0.25
		_two_sided_quad(k, Vector3(0.9, 0.05, 0.0), Vector3(7.0, 0.05, -tw), Vector3(7.0, 0.85, -tw), Vector3(0.9, 0.35, 0.0), sail, sail.darkened(0.15))
	k.xf = Transform3D.IDENTITY
	k.ring(Vector3.ZERO, Vector3(0, 0, 1), 5.5, 0.1, BRASS, 36, 4)
	k.ring(Vector3.ZERO, Vector3(0, 0, 1), 3.0, 0.07, BRASS, 24, 3)
	return k.commit()


# --- arches over the road ----------------------------------------------------------

## An arch over the road, built across a road of width w. Local x crosses the road, z runs along it.
static func arch(kind: String, w: float, night: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var hw := w * 0.5 + 2.5
	match kind:
		"pipe":
			var stone := Color(0.3, 0.24, 0.24)
			for s: float in [-1.0, 1.0]:
				var x := s * hw
				k.box(Vector3(x, 0.5, 0), Vector3(2.8, 1.4, 2.8), stone)
				k.box(Vector3(x, 1.3, 0), Vector3(2.4, 0.3, 2.4), BRASS.darkened(0.2))
				_fluted(k, Vector3(x, 1.4, 0), Vector3(x, 8.2, 0), 0.85, 0.72, COPPER.darkened(0.2), 12, 0.08, 3)
				for y: float in [2.6, 6.0]:
					k.cyl(Vector3(x, y, 0), Vector3(x, y + 0.4, 0), 1.02, 1.02, BRASS, 16)
				k.cyl(Vector3(x, 8.2, 0), Vector3(x, 9.0, 0), 0.9, 1.1, BRASS, 16)
				for z: float in [-1.0, 1.0]:
					k.cyl(Vector3(x, 4.4, z * 0.78), Vector3(x, 4.4, z * 0.95), 0.32, 0.32, BRASS, 10)
					k.cyl(Vector3(x, 4.4, z * 0.95), Vector3(x, 4.4, z * 0.99), 0.24, 0.24, AETHER, 10, true)
			k.ring(Vector3(0, 9, 0), Vector3(0, 0, 1), hw, 0.8, COPPER, 48, 10, false, PI)
			for f in 9:
				var a := PI * (f + 0.5) / 9.0
				var p := Vector3(-cos(a) * hw, 9.0 + sin(a) * hw, 0)
				var tg := Vector3(sin(a), cos(a), 0)
				k.cyl(p - tg * 0.22, p + tg * 0.22, 1.02, 1.02, BRASS, 16)
				if f < 8:
					# glass windows showing the aether flowing inside
					var a2 := PI * (f + 1.0) / 9.0
					var path: Array = []
					for q in 4:
						var aa := lerpf(a + 0.07, a2 - 0.07, q / 3.0)
						path.append(Vector3(-cos(aa) * hw, 9.0 + sin(aa) * hw, 0))
					_tube(k, path, 0.83, AETHER, 10, false, true)
			for z: float in [-0.9, 0.9]:
				k.ring(Vector3(0, 9, z), Vector3(0, 0, 1), hw - 0.6, 0.12, AETHER, 40, 4, true, PI)
			# hanging sign at the top
			var sy := 9.0 + hw - 2.6
			for sx: float in [-2.2, 2.2]:
				k.cyl(Vector3(sx, sy + 0.6, 0), Vector3(sx, 9.0 + hw - 0.7, 0), 0.05, 0.05, BRASS, 4)
			k.box(Vector3(0, sy, 0), Vector3(6.0, 1.3, 0.3), BRASS.darkened(0.25))
			for z: float in [-1.0, 1.0]:
				_panel(k, Vector3(0, sy, z * 0.16), Vector3(0, 0, z), 5.2, 0.6, AETHER, true)
		"gate":
			for s: float in [-1.0, 1.0]:
				var x := s * (hw + 2)
				k.box(Vector3(x, 0.3, 0), Vector3(7.0, 1.0, 6.0), LIMESTONE.darkened(0.2))
				k.taper(Vector3(x, 0.8, 0), Vector2(6, 5), Vector2(4.4, 3.8), 13.2, LIMESTONE)
				for cx: float in [-1.0, 1.0]:
					for cz: float in [-1.0, 1.0]:
						_tube(k, [Vector3(x + cx * 3.0, 0.8, cz * 2.5), Vector3(x + cx * 2.2, 14.0, cz * 1.9)], 0.24, LIMESTONE.lightened(0.05), 8, true)
				k.taper(Vector3(x, 14.0, 0), Vector2(4.4, 3.8), Vector2(5.8, 5.2), 1.5, LIMESTONE.lightened(0.04))
				k.box(Vector3(x, 15.7, 0), Vector3(5.9, 0.4, 5.3), GOLD.darkened(0.1))
				for z: float in [-1.0, 1.0]:
					var face := Vector3(0, 0, z)
					k.box(Vector3(x, 9, z * 2.05), Vector3(3.4, 7, 0.3), LAPIS)
					for gy in 5:
						for gx in 3:
							var gc := Vector3(x + (gx - 1) * 0.95, 6.3 + gy * 1.35, z * 2.22)
							_panel(k, gc, face, 0.45 if (gx + gy) % 2 == 0 else 0.3, 0.55, GOLD)
					# flagpole with a lapis and gold pennant
					var fp := Vector3(x + s * 0.0, 0, z * 3.4)
					k.cyl(fp, fp + Vector3(0, 21, 0), 0.16, 0.1, BRASS.darkened(0.3), 6)
					k.sphere(fp + Vector3(0, 21.1, 0), Vector3.ONE * 0.25, GOLD, 6, 4)
					_two_sided(k, fp + Vector3(0, 20.6, 0), fp + Vector3(0, 18.6, 0), fp + Vector3(-s * 4.0, 19.8, z * 0.3), LAPIS, LAPIS.darkened(0.2))
					_two_sided(k, fp + Vector3(0, 18.6, 0), fp + Vector3(0, 17.6, 0), fp + Vector3(-s * 2.5, 18.4, z * 0.3), GOLD, GOLD.darkened(0.2))
			var lw := hw * 2 + 10
			k.box(Vector3(0, 15, 0), Vector3(lw, 2.4, 4.4), LIMESTONE)
			k.taper(Vector3(0, 16.2, 0), Vector2(lw, 4.4), Vector2(lw + 1.2, 5.4), 1.0, LIMESTONE.lightened(0.05))
			k.box(Vector3(0, 13.6, 0), Vector3(lw - 2, 0.6, 4.6), GOLD)
			# winged sun disc on both faces
			for z: float in [-1.0, 1.0]:
				var face := Vector3(0, 0, z)
				k.cyl(Vector3(0, 15, z * 2.2), Vector3(0, 15, z * 2.55), 1.3, 1.3, GOLD, 20)
				for wsd: float in [-1.0, 1.0]:
					for f in 3:
						var y0 := 15.6 - f * 0.55
						var x0 := wsd * 1.3
						var x1 := wsd * (8.5 - f * 1.6)
						var zz := z * (2.24 + f * 0.01)
						var col := GOLD if f != 1 else LAPIS
						quad_f(k, Vector3(x0, y0 - 0.5, zz), Vector3(x1, y0 - 0.25, zz), Vector3(x1 + wsd * 0.3, y0 + 0.15, zz), Vector3(x0, y0 + 0.1, zz), face, col)
		"vine":
			var bark := Color(0.32, 0.24, 0.16)
			for s: float in [-1.0, 1.0]:
				var x0 := s * (hw + 3)
				var rows: Array = []
				for y: float in [-30.0, -10.0, 4.0, 14.0, 22.0]:
					var row := PackedVector3Array()
					var cx := lerpf(x0, s * (hw + 2), (y + 30.0) / 52.0)
					var rr := lerpf(3.0, 1.8, (y + 30.0) / 52.0)
					for q in 14:
						var a := TAU * q / 14
						var lob := 1.0 + 0.18 * pow(0.5 + 0.5 * cos(4.0 * a + y * 0.08), 2.0)
						row.append(Vector3(cx + cos(a) * rr * lob, y, sin(a) * rr * lob))
					rows.append(row)
				var groove := func(_m: Vector3, _n: Vector3, i: int, j: int) -> Color:
					return bark.darkened(0.12 * float(j % 2)).lightened(0.03 * float(i % 2))
				_grid(k, rows, groove)
				_blob(k, Vector3(s * (hw + 2), 24, 0), Vector3(9, 3.6, 9), Color(0.15, 0.38, 0.12), 11 + int(s), 14, 6, 0.2, 0.45, 0.015)
				_blob(k, Vector3(s * (hw + 6), 21, 4), Vector3(6, 2.8, 6), Color(0.2, 0.42, 0.13), 21 + int(s), 12, 6, 0.2, 0.45, 0.015)
			var big := hw + 2.5
			var vine: Array = []
			var helix: Array = []
			for q in 33:
				var a := PI * q / 32.0
				var p := Vector3(-cos(a) * big, 10.0 + sin(a) * big, 0)
				vine.append(p)
				var rad := Vector3(-cos(a), sin(a), 0)
				helix.append(p + rad * cos(q * 1.3) * 0.5 + Vector3(0, 0, sin(q * 1.3) * 0.5))
			_tube(k, vine, 0.4, Color(0.25, 0.42, 0.15), 8, false)
			_tube(k, helix, 0.16, Color(0.3, 0.48, 0.18), 5, false)
			for q in range(2, 31, 3):
				var p: Vector3 = vine[q]
				var lc := Color(0.25, 0.55, 0.2).lightened(0.05 * float(q % 3))
				for f: float in [-1.0, 1.0]:
					_two_sided(k, p, p + Vector3(0.8, 0.3, f * 1.3), p + Vector3(-0.6, -0.4, f * 1.1), lc, lc.darkened(0.3))
			for i in 7:
				var x := (i - 3) * hw * 0.28
				var y_top := 10.0 + sqrt(maxf(0.0, big * big - x * x)) - 0.3
				var hang := y_top - 8.0 - absf(i - 3) * 0.3
				_tube(k, [Vector3(x, y_top, 0), Vector3(x + 0.2, y_top - hang * 0.5, 0.1), Vector3(x, y_top - hang, 0)], 0.08, Color(0.3, 0.5, 0.2), 4, false)
				k.sphere(Vector3(x, y_top - hang - 0.2, 0), Vector3(0.38, 0.5, 0.38), Color(0.6, 1.0, 0.5), 8, 5, true)
		"ruin_gate":
			for s: float in [-1.0, 1.0]:
				var x := s * (hw + 1)
				var top := 13.0 if s < 0 else 9.0
				k.box(Vector3(x, 0.4, 0), Vector3(4.2, 1.2, 4.2), SAND.darkened(0.15))
				_fluted(k, Vector3(x, 1.0, 0), Vector3(x, top, 0), 1.6, 1.45, SAND, 14, 0.07, 3)
				if s < 0:
					k.xf = Transform3D(Basis(), Vector3(x, 0, 0))
					_capital(k, top - 0.3, 1.45, SAND.darkened(0.04))
					k.xf = Transform3D.IDENTITY
				else:
					_blob(k, Vector3(x, top, 0), Vector3(1.5, 0.6, 1.5), SAND.darkened(0.05), 3, 10, 4, 0.35, 0.15)
			k.box(Vector3(-hw * 0.3, 15.7, 0), Vector3(hw * 1.6, 1.8, 3.4), SAND.darkened(0.08), false)
			k.box(Vector3(-hw * 0.3, 14.65, 0), Vector3(hw * 1.6 - 0.4, 0.3, 3.0), LAPIS.lerp(SAND, 0.5), false)
			k.box(Vector3(hw * 0.75, 3.0, 4.0), Vector3(6, 1.8, 3.0), SAND.darkened(0.15), false, 0.4)
			for i in 4:
				_blob(k, Vector3(hw * 0.5 + i * 1.6, 0.3, 6.0 + (i % 2) * 1.5), Vector3(0.9, 0.6, 0.8), SAND.darkened(0.12), 30 + i, 7, 4, 0.25, 0.2)
		"omen":
			var rr := hw + 2.0
			var c := Vector3(0, rr * 0.55, 0)
			k.ring(c, Vector3(0, 0, 1), rr, 0.9, Color(0.25, 0.22, 0.3), 64, 8)
			k.ring(c + Vector3(0, 0, 0.0), Vector3(0, 0, 1), rr - 1.0, 0.35, AETHER, 64, 6, true)
			k.ring(c, Vector3(0, 0, 1), rr + 1.0, 0.25, Color(1.0, 0.6, 0.95), 64, 6, true)
			for z: float in [-0.95, 0.95]:
				k.ring(c + Vector3(0, 0, z), Vector3(0, 0, 1), rr, 0.18, BRASS, 64, 4)
			for i in 12:
				var a := TAU * i / 12
				var dir := Vector3(cos(a), sin(a), 0)
				var p := c + dir * (rr + 0.4)
				k.xf = Transform3D(Basis(Vector3(0, 0, 1), a - PI * 0.5), p)
				k.taper(Vector3(0, 0, -0.9), Vector2(1.6, 1.8), Vector2(0.3, 0.6), 2.2, BRASS)
				k.box(Vector3(0, 0.4, 0), Vector3(0.5, 0.5, 2.0), AETHER, true)
				k.xf = Transform3D.IDENTITY
	return k.commit()


# --- landmarks ---------------------------------------------------------------------

## Landmark nodes. `sc` scales the whole thing.
static func landmark(kind: String, sc: float, night: bool) -> Node3D:
	var n := Node3D.new()
	n.scale = Vector3.ONE * sc
	var k := MeshKit.new()
	match kind:
		"spire":
			var stone := Color(0.4, 0.28, 0.26)
			var upper := Color(0.5, 0.33, 0.28)
			var trim := Color(0.72, 0.56, 0.42)
			k.box(Vector3(0, 0.5, 0), Vector3(34, 2.0, 34), stone.darkened(0.3))
			k.taper(Vector3(0, 1.5, 0), Vector2(30, 30), Vector2(14, 14), 28.5, stone)
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					_tube(k, [Vector3(cx * 16.5, 0, cz * 16.5), Vector3(cx * 12, 14, cz * 12), Vector3(cx * 7.4, 30, cz * 7.4)], [2.2, 1.5, 0.9], trim.darkened(0.2), 10, true)
					_tube(k, [Vector3(cx * 7.3, 30, cz * 7.3), Vector3(cx * 3.4, 100, cz * 3.4)], [0.7, 0.4], COPPER, 8, false)
			k.box(Vector3(0, 30.5, 0), Vector3(18, 1.2, 18), trim)
			k.box(Vector3(0, 31.6, 9.2), Vector3(18, 1.0, 0.2), BRASS)
			k.taper(Vector3(0, 30, 0), Vector2(14, 14), Vector2(6, 6), 70, upper)
			for i in 9:
				var y := 37.5 + i * 7.5
				var wd := lerpf(14.0, 6.0, (y - 30.0) / 70.0) + 0.5
				k.box(Vector3(0, y, 0), Vector3(wd, 0.5, wd), trim)
			for i in 12:
				var y := 8.0 + i * 7.5
				for side in 4:
					var a := side * PI * 0.5
					var nrm := Vector3(sin(a), 0, cos(a))
					var hz: float
					if y < 30.0:
						hz = lerpf(15.0, 7.0, (y - 1.5) / 28.5)
					else:
						hz = lerpf(7.0, 3.0, (y - 30.0) / 70.0)
					var wcount := 3 if y < 30.0 else 1
					for q in wcount:
						var off := Vector3.UP.cross(nrm) * (q - (wcount - 1) * 0.5) * 4.5
						var lit := night and (i + side + q) % 3 != 0
						var p := nrm * (hz + 0.25) + off + Vector3(0, y, 0)
						_panel(k, p, nrm, 3.2, 3.2, trim.darkened(0.15))
						_panel(k, p + nrm * 0.05, nrm, 2.4, 2.5, WARM if lit else Color(0.2, 0.24, 0.34), lit)
			var tip := _ribbed_dome(k, Vector3(0, 99.5, 0), 8.5, COPPER, trim, night, false, 12)
			k.cyl(Vector3(0, tip - 1.0, 0), Vector3(0, 150, 0), 2.6, 0.25, COPPER, 14)
			k.sphere(Vector3(0, 128, 0), Vector3(1.6, 1.6, 1.6), AETHER, 12, 6, true)
			var rings := Node3D.new()
			rings.name = "Spin"
			rings.position = Vector3(0, 104, 0)
			var rk := MeshKit.new()
			rk.ring(Vector3.ZERO, Vector3.UP, 22, 0.8, AETHER, 64, 6, true)
			rk.ring(Vector3.ZERO, Vector3(0.3, 1, 0), 28, 0.5, Color(1.0, 0.55, 0.9), 64, 6, true)
			rk.ring(Vector3.ZERO, Vector3(-0.4, 1, 0.2), 34, 0.4, BRASS, 64, 6, false)
			for i in 6:
				var a := TAU * i / 6
				rk.sphere(Vector3(cos(a) * 22, 0, sin(a) * 22), Vector3.ONE * 1.4, BRASS, 10, 6)
			var rm := MeshInstance3D.new()
			rm.mesh = rk.commit()
			rings.add_child(rm)
			n.add_child(rings)
		"pipeline":
			pass  # built along the track by track.gd
		"pyramid":
			k.box(Vector3(0, -0.5, 0), Vector3(176, 3, 176), SAND.darkened(0.15))
			k.taper(Vector3.ZERO, Vector2(160, 160), Vector2(4, 4), 110, SAND)
			k.taper(Vector3.ZERO, Vector2(162.5, 162.5), Vector2(158.6, 158.6), 3.0, LIMESTONE.darkened(0.05))
			k.taper(Vector3(0, 109, 0), Vector2(5.8, 5.8), Vector2(0.1, 0.1), 8, GOLD)
			k.taper(Vector3(0, 103.5, 0), Vector2(14.4, 14.4), Vector2(5.8, 5.8), 5.6, GOLD.darkened(0.12))
			# entrance pylon with two obelisks before it
			k.taper(Vector3(0, 0, 82), Vector2(20, 6), Vector2(14, 4), 26, LIMESTONE)
			k.taper(Vector3(0, 26, 82), Vector2(14, 4), Vector2(16, 5.2), 2.0, LIMESTONE.lightened(0.05))
			k.box(Vector3(0, 7, 85.05), Vector3(5, 14, 0.3), Color(0.1, 0.08, 0.06))
			k.box(Vector3(0, 14.6, 85.1), Vector3(7, 1.2, 0.4), GOLD)
			k.box(Vector3(0, 21, 84.5), Vector3(12, 1.0, 0.4), LAPIS)
			for s: float in [-1.0, 1.0]:
				k.xf = Transform3D(Basis().scaled(Vector3.ONE * 1.3), Vector3(s * 16, 0, 94))
				_obelisk(k, 18.0, false)
				k.xf = Transform3D.IDENTITY
		"statue":
			_statue(k, night)
		"stands":
			var crowd := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.8, 0.3), Color(0.9, 0.9, 0.9), Color(0.3, 0.75, 0.5), Color(0.8, 0.4, 0.8)]
			var skin := [Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2), Color(0.95, 0.8, 0.65)]
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			for row in 7:
				var seat := Color(0.35, 0.33, 0.38) if row % 2 == 0 else Color(0.4, 0.36, 0.42)
				k.box(Vector3(0, 0.75 + row * 1.5, row * 1.6), Vector3(60, 1.5 + row * 3.0, 1.6), seat)
				k.box(Vector3(0, 1.55 + row * 3.0, row * 1.6 - 0.75), Vector3(60, 0.1, 0.12), BRASS.darkened(0.3))
				for i in 40:
					if rng.randf() < 0.85:
						var px := -29 + i * 1.47 + rng.randf_range(-0.15, 0.15)
						var py := 2.0 + row * 3.0
						var pz := row * 1.6 - 0.2
						k.box(Vector3(px, py, pz), Vector3(0.7, 0.9, 0.5), crowd[rng.randi() % crowd.size()])
						k.box(Vector3(px, py + 0.68, pz), Vector3(0.38, 0.42, 0.38), skin[rng.randi() % skin.size()])
						if rng.randf() < 0.2:
							k.box(Vector3(px + 0.3, py + 0.9, pz - 0.1), Vector3(0.14, 0.8, 0.14), crowd[rng.randi() % crowd.size()])
			# front wall with glowing team panels, side walls
			k.box(Vector3(0, 0.6, -1.0), Vector3(61, 1.2, 0.3), Color(0.2, 0.18, 0.24))
			for i in 8:
				_panel(k, Vector3(-26.25 + i * 7.5, 0.65, -1.17), Vector3(0, 0, -1), 6.6, 0.8, crowd[i % crowd.size()].lightened(0.1), true)
			for s: float in [-1.0, 1.0]:
				k.taper(Vector3(s * 30.6, 0, 4.8), Vector2(1.2, 11.2), Vector2(1.2, 11.2), 12.0, Color(0.3, 0.28, 0.34), false, 0.0, Vector3(0, 0, 0))
			# roof on trusses
			k.box(Vector3(0, 17, 6), Vector3(62, 0.6, 14), Color(0.8, 0.35, 0.2))
			k.box(Vector3(0, 16.5, -0.9), Vector3(62.4, 0.8, 0.4), BRASS)
			for i in 7:
				var x := -30.0 + i * 10.0
				k.cyl(Vector3(x, 0, 12.5), Vector3(x, 16.8, 12.5), 0.4, 0.35, BRASS, 8)
				_tube(k, [Vector3(x, 12.0, 12.5), Vector3(x, 15.6, 6.0), Vector3(x, 16.6, -0.6)], 0.18, BRASS.darkened(0.2), 6, false)
				var fc: Color = crowd[i % crowd.size()]
				k.cyl(Vector3(x, 17.3, 2.0), Vector3(x, 21.5, 2.0), 0.07, 0.07, BRASS, 4)
				_two_sided_quad(k, Vector3(x, 21.4, 2.0), Vector3(x + 2.0, 21.2, 2.3), Vector3(x + 2.0, 20.0, 2.3), Vector3(x, 20.2, 2.0), fc, fc.darkened(0.2))
			k.box(Vector3(0, 15.5, -0.6), Vector3(58, 0.5, 0.2), AETHER, true)
		"volcano":
			_volcano(k)
			var smoke := _particles(60, 9.0, Color(0.3, 0.28, 0.28, 0.5), 30.0, 60.0)
			smoke.position = Vector3(0, 195, 0)
			smoke.direction = Vector3.UP
			smoke.gravity = Vector3(6, 2, 0)
			smoke.initial_velocity_min = 8.0
			smoke.initial_velocity_max = 14.0
			n.add_child(smoke)
		"dino":
			# a long-necked giant; track.gd walks it around slowly
			var hide := Color(0.35, 0.4, 0.3)
			_blob(k, Vector3(0, 12, 0), Vector3(6, 5, 11), hide, 4, 18, 10, 0.03, 0.4, 0.02)
			_tube(k, [Vector3(0, 13.5, -7), Vector3(0, 19, -11.5), Vector3(0, 25, -15.5), Vector3(0, 29.5, -18), Vector3(0, 30.5, -19)], [3.2, 2.2, 1.7, 1.35, 1.25], hide, 12, false)
			_blob(k, Vector3(0, 30.8, -20.0), Vector3(1.5, 1.35, 2.6), hide, 5, 12, 7, 0.04, 0.3)
			for s: float in [-1.0, 1.0]:
				k.sphere(Vector3(s * 1.1, 31.4, -21.0), Vector3(0.25, 0.25, 0.25), Color(0.1, 0.08, 0.05), 6, 4)
			_tube(k, [Vector3(0, 12.5, 9), Vector3(0, 11, 16), Vector3(0.6, 8, 23), Vector3(1.8, 6, 30), Vector3(3.2, 5.2, 34)], [3.4, 2.2, 1.3, 0.6, 0.15], hide, 12, true)
			for sx: float in [-3.6, 3.6]:
				for sz: float in [-6.0, 6.0]:
					var lc := hide.darkened(0.15)
					_tube(k, [Vector3(sx, 12.5, sz), Vector3(sx * 1.05, 6.0, sz + 0.8), Vector3(sx, 0.6, sz + 0.2)], [2.1, 1.5, 1.45], lc, 10, false)
					_blob(k, Vector3(sx, 0.6, sz + 0.5), Vector3(1.8, 0.8, 2.1), lc.darkened(0.1), int(sx + sz), 10, 5, 0.04, 0.2)
			for i in 10:
				var z := -8.0 + i * 2.2
				var y := 16.4 - absf(z) * 0.06 if z < 7.0 else 16.0 - (z - 7.0) * 0.4
				k.taper(Vector3(0, y - 0.6, z), Vector2(0.45, 1.4), Vector2(0.1, 0.2), 2.0 - absf(i - 4) * 0.15, Color(0.7, 0.4, 0.2))
		"moonrocks":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 26:
				var p := Vector3(rng.randf_range(-700, 700), rng.randf_range(140, 380), rng.randf_range(-800, 500))
				var s := rng.randf_range(6, 30)
				_blob(k, p, Vector3(s, s * 0.7, s * 0.9), Color(0.75, 0.68, 0.6), i, 11, 7, 0.28, 0.35, 0.08)
		"mesa":
			_mesa(k)
		"tomb":
			_tomb(k)
		"trophy":
			k.box(Vector3(0, 0.5, 0), Vector3(18, 1.0, 18), Color(0.22, 0.17, 0.2))
			k.taper(Vector3(0, 1.0, 0), Vector2(16, 16), Vector2(10, 10), 13, Color(0.3, 0.22, 0.25))
			k.taper(Vector3(0, 13.6, 0), Vector2(10.6, 10.6), Vector2(10.6, 10.6), 0.6, BRASS)
			for f in 4:
				var bs := Basis(Vector3.UP, f * PI * 0.5)
				var na := bs * Vector3(0, 0, 1)
				_panel(k, bs * Vector3(0, 7.5, 6.6), na, 6.0, 1.0, AETHER, true)
			_lathe(k, Vector3(0, 14, 0), [Vector2(2.2, 0), Vector2(1.6, 1.2), Vector2(1.1, 4.0), Vector2(1.6, 6.0), Vector2(1.0, 8.5), Vector2(1.3, 11.0),
				Vector2(2.6, 12.0), Vector2(3.6, 13.0), Vector2(4.6, 14.6), Vector2(4.9, 15.0)], BRASS, 24)
			k.cyl(Vector3(0, 28.9, 0), Vector3(0, 29.2, 0), 4.9, 4.9, BRASS.lightened(0.1), 24)
			for s: float in [-1.0, 1.0]:
				k.ring(Vector3(s * 4.6, 25.5, 0), Vector3(0, 0, 1), 2.2, 0.3, BRASS, 16, 6)
			var spark := Node3D.new()
			spark.name = "Spin"
			spark.position = Vector3(0, 34, 0)
			var sk := MeshKit.new()
			sk.sphere(Vector3.ZERO, Vector3.ONE * 3.2, Color(1.0, 0.85, 0.5), 20, 12, true)
			sk.ring(Vector3.ZERO, Vector3.UP, 5.5, 0.35, BRASS, 48, 6)
			sk.ring(Vector3.ZERO, Vector3(1, 0, 0.2), 6.2, 0.3, BRASS, 48, 6)
			sk.ring(Vector3.ZERO, Vector3(0.2, 0.3, 1), 6.9, 0.25, AETHER, 48, 6, true)
			var sm := MeshInstance3D.new()
			sm.mesh = sk.commit()
			spark.add_child(sm)
			n.add_child(spark)
			var light := OmniLight3D.new()
			light.position = Vector3(0, 34, 0)
			light.light_color = Color(1.0, 0.8, 0.5)
			light.omni_range = 60.0
			light.light_energy = 3.0
			n.add_child(light)
	if kind != "pipeline":
		var mi := MeshInstance3D.new()
		mi.mesh = k.commit()
		n.add_child(mi)
	return n


static func _statue(k: MeshKit, night: bool) -> void:
	# a seated lion-headed guardian, original design; it faces +z
	var c := LIMESTONE
	k.box(Vector3(0, 0.5, 0), Vector3(18, 1.0, 22), c.darkened(0.2))
	k.box(Vector3(0, 4.5, 0), Vector3(16, 7, 20), c.darkened(0.12))
	k.box(Vector3(0, 4, 0), Vector3(16.4, 1.2, 20.4), LAPIS)
	k.box(Vector3(0, 8.3, 0), Vector3(17, 0.6, 21), c)
	for f in 2:
		var z := 10.21 if f == 0 else -10.21
		var nrm := Vector3(0, 0, 1 if f == 0 else -1)
		for g in 6:
			_panel(k, Vector3(-6.25 + g * 2.5, 6.4, z), nrm, 1.4, 2.4, GOLD.darkened(0.1))
			_panel(k, Vector3(-6.25 + g * 2.5, 6.4, z + nrm.z * 0.02), nrm, 0.9, 1.8, LAPIS.lightened(0.1))
	_blob(k, Vector3(0, 9.5, -3.5), Vector3(6.2, 3.0, 6.5), c, 1, 16, 8, 0.03, 0.25)
	_tube(k, [Vector3(0, 8.5, -3.0), Vector3(0, 14.5, -2.4), Vector3(0, 20.5, -1.5), Vector3(0, 22.5, -1.2)], [5.0, 4.6, 3.8, 3.0], c, 16, false)
	for s: float in [-1.0, 1.0]:
		_blob(k, Vector3(s * 4.6, 11.0, -4.5), Vector3(2.8, 3.2, 4.8), c.darkened(0.03), 2 + int(s), 12, 7, 0.03, 0.25)
		_tube(k, [Vector3(s * 4.0, 18.5, 0.0), Vector3(s * 4.4, 13.5, 3.2), Vector3(s * 4.4, 9.2, 5.6)], [1.9, 1.6, 1.5], c, 12, true)
		_blob(k, Vector3(s * 4.4, 9.4, 7.0), Vector3(1.9, 1.0, 2.7), c.darkened(0.05), 5 + int(s), 10, 5, 0.04, 0.2)
	# broad collar in lapis and gold
	var rows: Array = []
	var prof := [Vector2(5.8, 18.9), Vector2(5.0, 19.8), Vector2(4.2, 20.6), Vector2(3.4, 21.4)]
	for pr: Vector2 in prof:
		rows.append(_ring_pts(Vector3(0, pr.y, -1.4), Vector3.UP, Vector3.RIGHT, pr.x, 24))
	var bands := func(_m: Vector3, _n: Vector3, i: int, _j: int) -> Color:
		return LAPIS if i % 2 == 0 else GOLD
	_grid(k, rows, bands)
	# head, muzzle, ears, striped headdress
	_blob(k, Vector3(0, 26, -1), Vector3(5.0, 5.4, 5.0), GOLD, 7, 18, 11, 0.02, 0.2)
	_blob(k, Vector3(0, 24.6, 3.3), Vector3(2.5, 2.2, 2.3), GOLD.darkened(0.12), 8, 14, 7, 0.03, 0.2)
	k.sphere(Vector3(0, 25.6, 5.4), Vector3(0.8, 0.55, 0.45), GOLD.darkened(0.4), 8, 4)
	for s: float in [-1.0, 1.0]:
		k.sphere(Vector3(s * 1.7, 27.2, 3.4), Vector3(0.6, 0.4, 0.3), AETHER if night else LAPIS, 8, 4, night)
		k.taper(Vector3(s * 3.4, 29.5, -1), Vector2(1.8, 1.1), Vector2(0.2, 0.2), 3.2, GOLD, false, 0.0, Vector3(s * 0.5, 0, -0.3))
	var hrows: Array = []
	var hprof := [Vector2(6.6, 17.5), Vector2(6.0, 21.0), Vector2(5.5, 25.0), Vector2(5.4, 28.0), Vector2(4.3, 30.6), Vector2(2.2, 31.8)]
	for pr: Vector2 in hprof:
		var row := PackedVector3Array()
		for s in 15:
			var a := PI * 0.5 + 0.75 + (TAU - 1.5) * s / 14.0
			row.append(Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x - 1.4))
		hrows.append(row)
	var stripes := func(_m: Vector3, _n: Vector3, i: int, _j: int) -> Color:
		return LAPIS if i % 2 == 0 else GOLD
	_grid(k, hrows, stripes, false)
	# sun disc crown
	k.cyl(Vector3(0, 34.6, -1.6), Vector3(0, 34.6, -1.0), 2.3, 2.3, GOLD, 24)
	k.ring(Vector3(0, 34.6, -1.3), Vector3(0, 0, 1), 2.4, 0.18, AETHER, 32, 4, true)


static func _volcano(k: MeshKit) -> void:
	var rock := Color(0.25, 0.2, 0.18)
	var segs := 40
	var rows: Array = []
	var ys := [-2.0, 30.0, 70.0, 110.0, 145.0, 170.0, 186.0, 190.0, 186.0, 180.0]
	var rs := [195.0, 150.0, 110.0, 78.0, 55.0, 42.0, 36.0, 33.0, 28.0, 24.0]
	for i in ys.size():
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var gully := 1.0 + 0.07 * sin(a * 9.0 + i * 0.3) + 0.04 * sin(a * 23.0) if i < 7 else 1.0 + 0.03 * sin(a * 5.0)
			row.append(Vector3(cos(a) * float(rs[i]) * gully, float(ys[i]) + (sin(a * 4.0) * 3.0 if i == 7 else 0.0), sin(a) * float(rs[i]) * gully))
		rows.append(row)
	var paint := func(m: Vector3, nrm: Vector3, i: int, j: int) -> Color:
		if i >= 7:
			return Color(0.45, 0.2, 0.1)
		return rock.lightened(0.04 * float(j % 2) + clampf(m.y / 400.0, 0.0, 0.3)).darkened(0.15 * (1.0 - nrm.y))
	_grid(k, rows, paint)
	k.cyl(Vector3(0, 181, 0), Vector3(0, 182, 0), 25, 25, Color(1.0, 0.45, 0.1), 24, true)
	# lava rivers down the gullies
	for f in 6:
		var a0 := TAU * f / 6 + 0.3
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in 4:
			var row: PackedVector3Array = rows[6 - i]
			var a := a0 + sin(i * 1.3 + f) * 0.04
			var s := int(round(a / TAU * segs)) % segs
			var p := row[s]
			var out := Vector3(p.x, 0, p.z).normalized()
			var side := out.cross(Vector3.UP) * (2.5 + i * 1.8)
			var lift := out * 1.5 + Vector3(0, 1.5, 0)
			var l := p + lift - side
			var r := p + lift + side
			if i > 0:
				quad_f(k, prev_l, prev_r, r, l, out + Vector3(0, 0.5, 0), Color(1.0, 0.35 + 0.05 * i, 0.05), true)
			prev_l = l
			prev_r = r


static func _mesa(k: MeshKit) -> void:
	var rock := Color(0.72, 0.42, 0.28)
	var segs := 40
	var ys := [-8.0, 6.0, 14.0, 20.0, 34.0, 40.0, 50.0, 58.0, 60.0]
	var rs := [1.12, 1.04, 0.98, 0.97, 0.9, 0.86, 0.83, 0.8, 0.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var outline := PackedFloat32Array()
	for s in segs:
		var a := TAU * s / segs
		outline.append(1.0 + 0.1 * sin(a * 3.0 + 1.0) + 0.06 * sin(a * 7.0) + rng.randf_range(-0.03, 0.03))
	var rows: Array = []
	for i in ys.size():
		var row := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var f: float = float(rs[i]) * outline[s] * (1.0 + (rng.randf_range(-0.03, 0.03) if i > 0 and i < 8 else 0.0))
			row.append(Vector3(cos(a) * 72.0 * f, float(ys[i]), sin(a) * 52.0 * f))
		rows.append(row)
	var strata := func(m: Vector3, nrm: Vector3, _i: int, _j: int) -> Color:
		var band := 0.5 + 0.5 * sin(m.y * 0.55)
		var c := rock.lerp(Color(0.85, 0.6, 0.4), band * 0.35)
		if nrm.y > 0.7:
			c = Color(0.78, 0.55, 0.36)
		return c.darkened(0.12 * (1.0 - clampf(m.y / 30.0, 0.0, 1.0)))
	_grid(k, rows, strata)
	for i in 6:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 80.0, 0, sin(a) * 58.0)
		var s := rng.randf_range(5, 12)
		_blob(k, p, Vector3(s, s * 0.6, s), rock.darkened(0.1), i, 10, 6, 0.25, 0.3, 0.05, 0.1)


static func _tomb(k: MeshKit) -> void:
	var c := Color(0.75, 0.55, 0.38)
	k.box(Vector3(0, -0.5, 4), Vector3(120, 3, 52), c.darkened(0.15))
	k.taper(Vector3.ZERO, Vector2(110, 40), Vector2(90, 30), 40, c)
	k.taper(Vector3(0, 40, 0), Vector2(90, 30), Vector2(96, 34), 3.5, c.lightened(0.05))
	k.box(Vector3(0, 43.8, 0), Vector3(96.5, 0.8, 34.5), GOLD.darkened(0.15))
	k.box(Vector3(0, 30, 17.6), Vector3(70, 2.5, 0.6), LAPIS)
	for i in 5:
		var x := (i - 2) * 18.0
		k.box(Vector3(x, 8, 20.2), Vector3(6, 14, 1), Color(0.08, 0.06, 0.05))
		k.box(Vector3(x, 15.8, 20.6), Vector3(8, 1.5, 1.6), GOLD)
		k.box(Vector3(x, 8, 20.45), Vector3(7.2, 14.4, 0.5), c.darkened(0.2))
		k.box(Vector3(x, 8, 20.75), Vector3(6, 14, 0.2), Color(0.08, 0.06, 0.05))
	# a colonnade in front of the doors
	for i in 6:
		var x := (i - 2.5) * 18.0
		_fluted(k, Vector3(x, 1.0, 24), Vector3(x, 22, 24), 1.6, 1.4, c.lightened(0.05), 14, 0.07, 3)
		k.xf = Transform3D(Basis(), Vector3(x, 0, 24))
		_capital(k, 22.0, 1.4, c)
		k.xf = Transform3D.IDENTITY
		k.box(Vector3(x, 0.5, 24), Vector3(4.0, 1.0, 4.0), c.darkened(0.1))
	k.box(Vector3(0, 25.3, 24), Vector3(96, 2.2, 4.4), c.lightened(0.04))
	k.box(Vector3(0, 25.3, 26.25), Vector3(94, 0.8, 0.1), LAPIS)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(s * 60, 9, 26), Vector3(10, 18, 10), c.darkened(0.08))
		k.box(Vector3(s * 60, 18.3, 26), Vector3(11, 0.6, 11), GOLD.darkened(0.2))
		k.taper(Vector3(s * 60, 18.6, 24), Vector2(7, 6), Vector2(5, 4), 6, c)
		_blob(k, Vector3(s * 60, 26.5, 25), Vector3(3.6, 4.4, 3.6), GOLD.darkened(0.2), 9 + int(s), 14, 9, 0.03, 0.25)
		_blob(k, Vector3(s * 60, 25.6, 28.2), Vector3(1.8, 1.6, 2.0), GOLD.darkened(0.3), 11 + int(s), 10, 6, 0.03, 0.2)
		for e: float in [-1.0, 1.0]:
			k.taper(Vector3(s * 60 + e * 2.2, 29.5, 25), Vector2(1.4, 0.9), Vector2(0.15, 0.15), 3.5, GOLD.darkened(0.2), false, 0.0, Vector3(e * 0.4, 0, 0))


## Soft round sprite particles used for smoke, steam, sand, spores and sparks.
static func _particles(amount: int, life: float, col: Color, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	quad.material = m
	p.mesh = quad
	p.color = col
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0, 0.15, 0.7, 1])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	p.color_ramp = g
	return p


static var _dot: ImageTexture


static func soft_dot() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
		_dot = ImageTexture.create_from_image(img)
	return _dot


static func particles(amount: int, life: float, col: Color, size_min: float, size_max: float) -> CPUParticles3D:
	return _particles(amount, life, col, size_min, size_max)
