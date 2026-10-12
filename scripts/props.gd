class_name Props
extends RefCounted
## Builds the scenery: repeated props (drawn many times through MultiMesh), arches over the road
## and one-off landmarks. Everything is made from MeshKit primitives with vertex colours, styled
## after the three planes of the race: copper-and-indigo invention city, green river valley and
## desert ruins, primordial jungle.

const COPPER := Color(0.78, 0.45, 0.22)
const BRASS := Color(0.85, 0.66, 0.3)
const INDIGO := Color(0.2, 0.2, 0.55)
const AETHER := Color(0.35, 0.9, 1.0)
const SAND := Color(0.86, 0.72, 0.5)
const LIMESTONE := Color(0.9, 0.84, 0.7)
const LAPIS := Color(0.15, 0.25, 0.65)
const GOLD := Color(0.95, 0.75, 0.3)
const LEAF := Color(0.2, 0.45, 0.15)

## Props that need their own node (they move or emit particles).
const ANIMATED := ["windmill", "geyser"]
## How far from its centre a prop reaches, used to keep it off the road.
const RADIUS := {"city": 10.0, "lamp_tall": 1.0, "dome": 6.0, "curl_tree": 5.0, "windmill": 6.0,
	"palm": 4.0, "reeds": 2.0, "obelisk": 3.0, "column": 2.5, "ruin_wall": 7.0, "rock": 6.0,
	"broken_statue": 8.0, "giant_tree": 9.0, "fern": 3.0, "geyser": 6.0, "banner": 1.0}
const VARIANTS := 4


static func _rng(kind: String, v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind) + v * 7919
	return r


## Mesh for one variant of a repeated prop. `night` lights windows and lamps.
static func prop(kind: String, v: int, night: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var r := _rng(kind, v)
	match kind:
		"city":
			var w := r.randf_range(10, 18)
			var d := r.randf_range(10, 18)
			var h := r.randf_range(14, 46)
			var wall := Color(0.42, 0.3, 0.3).lerp(Color(0.6, 0.45, 0.35), r.randf())
			k.box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
			k.box(Vector3(0, h + 1.0, 0), Vector3(w * 0.75, 2.0, d * 0.75), COPPER)
			var win := Color(1.0, 0.75, 0.4) if night else Color(0.25, 0.3, 0.45)
			for row in int(h / 4.0) - 1:
				for side in 2:
					for c in 3:
						var x := (c - 1) * w * 0.28
						var y := 3.0 + row * 4.0
						if r.randf() < (0.55 if night else 1.0):
							var sg := 1.0 if side == 0 else -1.0
							k.box(Vector3(x, y, (d * 0.5 + 0.05) * sg), Vector3(w * 0.16, 1.6, 0.1), win, night)
							k.box(Vector3((w * 0.5 + 0.05) * sg, y, (c - 1) * d * 0.28), Vector3(0.1, 1.6, d * 0.16), win, night)
			if r.randf() < 0.6:
				k.sphere(Vector3(0, h + 2.0, 0), Vector3(w * 0.33, w * 0.4, w * 0.33), COPPER, 10, 5)
				k.cyl(Vector3(0, h + 2.0 + w * 0.38, 0), Vector3(0, h + 6.0 + w * 0.4, 0), 0.4, 0.05, BRASS, 6)
			else:
				k.ring(Vector3(0, h + 3.0, 0), Vector3.UP, w * 0.45, 0.3, AETHER, 16, 4, true)
				k.cyl(Vector3(0, h + 2.0, 0), Vector3(0, h + 9.0, 0), 1.2, 0.3, COPPER, 8)
			k.box(Vector3(0, 1.5, 0), Vector3(w + 0.6, 3.0, d + 0.6), Color(0.3, 0.22, 0.2))
		"lamp_tall":
			k.cyl(Vector3.ZERO, Vector3(0, 7, 0), 0.18, 0.12, Color(0.25, 0.2, 0.2), 6)
			k.ring(Vector3(0, 7.2, 0), Vector3.UP, 0.6, 0.08, COPPER, 10, 3)
			k.sphere(Vector3(0, 7.5, 0), Vector3(0.45, 0.6, 0.45), AETHER if v % 2 == 0 else Color(1.0, 0.7, 0.35), 8, 4, true)
		"dome":
			var rr := r.randf_range(3.5, 6.0)
			var hh := r.randf_range(3.0, 6.0)
			var wc := Color(0.85, 0.75, 0.62).lerp(Color(0.7, 0.45, 0.4), r.randf())
			k.cyl(Vector3.ZERO, Vector3(0, hh, 0), rr, rr, wc, 10, false, false)
			k.sphere(Vector3(0, hh, 0), Vector3(rr, rr * 0.9, rr), COPPER if r.randf() < 0.5 else Color(0.3, 0.55, 0.55), 10, 5)
			k.cyl(Vector3(0, hh + rr * 0.85, 0), Vector3(0, hh + rr * 0.85 + 2.0, 0), 0.25, 0.02, BRASS, 5)
			k.box(Vector3(0, 1.3, rr - 0.1), Vector3(1.2, 2.4, 0.4), Color(1, 0.75, 0.4) if night else Color(0.2, 0.15, 0.15), night)
		"curl_tree":
			var p := Vector3.ZERO
			var dir := Vector3(r.randf_range(-0.3, 0.3), 1, r.randf_range(-0.3, 0.3)).normalized()
			var trunk := Color(0.4, 0.28, 0.2)
			for i in 4:
				var q := p + dir * r.randf_range(2.0, 3.0)
				k.cyl(p, q, 0.5 - i * 0.08, 0.42 - i * 0.08, trunk, 6)
				dir = (dir + Vector3(r.randf_range(-0.5, 0.5), 0.2, r.randf_range(-0.5, 0.5))).normalized()
				p = q
			var leaf: Color = [Color(0.25, 0.55, 0.3), Color(0.2, 0.55, 0.5), Color(0.8, 0.5, 0.2), Color(0.55, 0.65, 0.2)][v]
			for i in 9:
				var a := i * 0.9
				var rad := 1.0 + i * 0.35
				k.sphere(p + Vector3(cos(a) * rad, 0.4 + i * 0.25, sin(a) * rad), Vector3.ONE * (1.6 - i * 0.08), leaf.lightened(i * 0.03), 6, 4)
		"palm":
			var p := Vector3.ZERO
			var lean := Vector3(r.randf_range(-0.35, 0.35), 1, r.randf_range(-0.35, 0.35)).normalized()
			var h := r.randf_range(7, 12)
			for i in 5:
				var q := p + lean * (h / 5.0) + Vector3(0, 0, 0)
				k.cyl(p, q, 0.38 - i * 0.04, 0.34 - i * 0.04, Color(0.55, 0.42, 0.3).darkened(i % 2 * 0.1), 6, false, true, false)
				lean = (lean + Vector3(0, 0.12, 0)).normalized()
				p = q
			for i in 8:
				var a := TAU * i / 8 + r.randf() * 0.3
				var out := Vector3(cos(a), 0, sin(a))
				var tip := p + out * 4.5 + Vector3(0, -1.8, 0)
				var mid := p + out * 2.4 + Vector3(0, 0.6, 0)
				var sd := out.cross(Vector3.UP) * 0.7
				var c := LEAF.lerp(Color(0.4, 0.6, 0.2), r.randf())
				k.tri(p, mid + sd, mid - sd, c)
				k.tri(p, mid - sd, mid + sd, c)
				k.tri(mid + sd, tip, mid - sd, c)
				k.tri(mid - sd, tip, mid + sd, c)
		"reeds":
			for i in 14:
				var b := Vector3(r.randf_range(-1.6, 1.6), -0.3, r.randf_range(-1.6, 1.6))
				k.cyl(b, b + Vector3(r.randf_range(-0.3, 0.3), r.randf_range(1.6, 2.8), r.randf_range(-0.3, 0.3)), 0.07, 0.02, Color(0.45, 0.6, 0.25), 4, false, false, false)
		"obelisk":
			var h := r.randf_range(12, 20)
			k.box(Vector3(0, 0.5, 0), Vector3(3.2, 1.0, 3.2), LIMESTONE.darkened(0.15))
			k.taper(Vector3(0, 1, 0), Vector2(2, 2), Vector2(1.2, 1.2), h, LIMESTONE)
			k.taper(Vector3(0, 1 + h, 0), Vector2(1.2, 1.2), Vector2(0.01, 0.01), 1.4, GOLD)
			for i in 4:
				k.box(Vector3(0, 3 + i * h * 0.2, 0.0), Vector3(1.72 - i * 0.12, 0.25, 1.72 - i * 0.12), LAPIS)
		"column":
			var h := r.randf_range(3, 12)
			var c := LIMESTONE.lerp(SAND, r.randf())
			if v == 3:
				k.cyl(Vector3(-4, 0.9, 0), Vector3(4, 0.9, 0.5), 0.9, 0.9, c, 8)
			else:
				k.box(Vector3(0, 0.4, 0), Vector3(2.6, 0.8, 2.6), c.darkened(0.1))
				k.cyl(Vector3(0, 0.8, 0), Vector3(0, h, 0), 0.9, 0.82, c, 8)
				if v == 0:
					k.box(Vector3(0, h + 0.4, 0), Vector3(2.6, 0.8, 2.6), c)
					k.box(Vector3(0, h - 0.6, 0), Vector3(1.9, 0.4, 1.9), LAPIS)
		"ruin_wall":
			var c := SAND.darkened(0.05)
			for i in 6:
				var hh := r.randf_range(1.5, 6.0)
				k.box(Vector3((i - 2.5) * 2.2, hh * 0.5, r.randf_range(-0.3, 0.3)), Vector3(2.1, hh, 1.6), c.darkened(r.randf() * 0.15))
		"rock":
			k.rock(Vector3(0, 1.0, 0), Vector3(r.randf_range(3, 7), r.randf_range(2, 5), r.randf_range(3, 7)), Color(0.72, 0.5, 0.33), v)
		"broken_statue":
			var c := LIMESTONE.darkened(0.1)
			k.sphere(Vector3(0, 3.5, 0), Vector3(4, 4.5, 4), c, 8, 5)
			k.box(Vector3(0, 4.5, 3.6), Vector3(2.2, 3, 1.4), c.darkened(0.1))
			k.taper(Vector3(-2.5, 6.5, 0), Vector2(1.8, 1.0), Vector2(0.2, 0.2), 4.0, c, false, 0.0, Vector3(-1, 0, 0))
			k.taper(Vector3(2.5, 6.5, 0), Vector2(1.8, 1.0), Vector2(0.2, 0.2), 4.0, c, false, 0.0, Vector3(1, 0, 0))
			k.box(Vector3(0, 4.0, 4.0), Vector3(5, 0.6, 0.3), GOLD)
			k.cyl(Vector3(7, 0.8, 1), Vector3(14, 1.2, -1), 1.3, 1.1, c, 7)
		"giant_tree":
			var h := r.randf_range(38, 60)
			var bark := Color(0.32, 0.24, 0.16)
			k.cyl(Vector3.ZERO, Vector3(0, h, 0), 2.6, 1.4, bark, 8)
			for i in 5:
				var a := TAU * i / 5 + r.randf()
				k.cyl(Vector3(cos(a) * 1.5, 3, sin(a) * 1.5), Vector3(cos(a) * 5, -0.5, sin(a) * 5), 0.9, 0.4, bark, 5)
			var g := Color(0.12, 0.35, 0.12).lerp(Color(0.25, 0.42, 0.1), r.randf())
			for i in 4:
				var y := h * (0.6 + i * 0.13)
				var a := r.randf() * TAU
				k.sphere(Vector3(cos(a) * 3, y, sin(a) * 3), Vector3(10 - i * 1.5, 3.2, 10 - i * 1.5), g.lightened(i * 0.05), 9, 4)
			for i in 6:
				var a := r.randf() * TAU
				var top := Vector3(cos(a) * 7, h * 0.62, sin(a) * 7)
				k.cyl(top, top + Vector3(0, -r.randf_range(8, 16), 0), 0.12, 0.08, Color(0.2, 0.4, 0.15), 4, false, false, false)
		"fern":
			var c := Color(0.15, 0.45, 0.15).lerp(Color(0.35, 0.55, 0.15), r.randf())
			for i in 7:
				var a := TAU * i / 7 + r.randf() * 0.4
				var out := Vector3(cos(a), 0, sin(a))
				var tip := out * r.randf_range(2.5, 4.0) + Vector3(0, r.randf_range(0.5, 1.5), 0)
				var mid := out * 1.5 + Vector3(0, 2.0, 0)
				var sd := out.cross(Vector3.UP) * 0.5
				k.tri(Vector3.ZERO, mid + sd, mid - sd, c)
				k.tri(Vector3.ZERO, mid - sd, mid + sd, c)
				k.tri(mid + sd, tip, mid - sd, c.lightened(0.1))
				k.tri(mid - sd, tip, mid + sd, c.lightened(0.1))
		"banner":
			k.cyl(Vector3.ZERO, Vector3(0, 9, 0), 0.12, 0.1, Color(0.3, 0.25, 0.25), 5)
			var bc: Color = [Color(0.8, 0.15, 0.45), Color(0.2, 0.25, 0.7), Color(0.9, 0.55, 0.15), Color(0.2, 0.6, 0.55)][v]
			k.box(Vector3(0.9, 6.5, 0), Vector3(1.6, 4.5, 0.06), bc)
			k.box(Vector3(0.9, 6.5, 0.04), Vector3(0.5, 0.5, 0.04), AETHER, true)
			k.sphere(Vector3(0, 9.2, 0), Vector3.ONE * 0.25, BRASS, 6, 3)
		"windmill":
			k.taper(Vector3.ZERO, Vector2(3, 3), Vector2(1, 1), 16, BRASS.darkened(0.2))
			for i in 4:
				k.ring(Vector3(0, 3 + i * 3.5, 0), Vector3.UP, 1.4 - i * 0.12, 0.12, COPPER, 10, 3)
			k.sphere(Vector3(0, 16.5, 0), Vector3(1.2, 1.2, 1.6), COPPER, 8, 4)
		"geyser":
			k.rock(Vector3(0, -0.5, 0), Vector3(5, 2, 5), Color(0.45, 0.4, 0.35), v)
			k.cyl(Vector3(0, 0.6, 0), Vector3(0, 1.6, 0), 1.6, 1.2, Color(0.5, 1.0, 0.6), 8, true)
	return k.commit()


## Rotor of a windmill (the blades), spun by the track.
static func windmill_rotor() -> ArrayMesh:
	var k := MeshKit.new()
	for i in 6:
		var a := TAU * i / 6
		var dir := Vector3(cos(a), sin(a), 0)
		var sd := Vector3(-dir.y, dir.x, 0)
		k.quad(dir * 0.8 - sd * 0.3, dir * 7.0 - sd * 0.8, dir * 7.0 + sd * 0.8, dir * 0.8 + sd * 0.3, Color(0.92, 0.85, 0.7))
		k.quad(dir * 0.8 + sd * 0.3, dir * 7.0 + sd * 0.8, dir * 7.0 - sd * 0.8, dir * 0.8 - sd * 0.3, Color(0.92, 0.85, 0.7))
	k.ring(Vector3.ZERO, Vector3(0, 0, 1), 5.5, 0.1, BRASS, 18, 3)
	return k.commit()


## An arch over the road, built across a road of width w. Local x crosses the road, z runs along it.
static func arch(kind: String, w: float, night: bool) -> ArrayMesh:
	var k := MeshKit.new()
	var hw := w * 0.5 + 2.5
	match kind:
		"pipe":
			for s in [-1, 1]:
				k.cyl(Vector3(s * hw, 0, 0), Vector3(s * hw, 9, 0), 0.9, 0.7, COPPER.darkened(0.2), 8)
				k.ring(Vector3(s * hw, 3, 0), Vector3.UP, 1.1, 0.18, BRASS, 10, 3)
			k.ring(Vector3(0, 9, 0), Vector3(0, 0, 1), hw, 0.8, COPPER, 20, 6, false, PI)
			k.ring(Vector3(0, 9, 0), Vector3(0, 0, 1), hw, 0.35, AETHER, 20, 4, true, PI)
			k.ring(Vector3(0, 9, 0.9), Vector3(0, 0, 1), hw - 0.6, 0.15, AETHER, 20, 3, true, PI)
		"gate":
			for s in [-1, 1]:
				k.taper(Vector3(s * (hw + 2), 0, 0), Vector2(6, 5), Vector2(4, 3.6), 14, LIMESTONE)
				k.box(Vector3(s * (hw + 2), 10, 2.0), Vector3(3.4, 6, 0.3), LAPIS)
				k.box(Vector3(s * (hw + 2), 10, -2.0), Vector3(3.4, 6, 0.3), LAPIS)
			k.box(Vector3(0, 15, 0), Vector3(hw * 2 + 10, 2.4, 4.4), LIMESTONE)
			k.box(Vector3(0, 13.6, 0), Vector3(hw * 2 + 8, 0.6, 4.6), GOLD)
			k.sphere(Vector3(0, 15, 2.3), Vector3(2.4, 1.4, 0.4), GOLD, 10, 4)
		"vine":
			for s in [-1, 1]:
				k.cyl(Vector3(s * (hw + 3), -30, 0), Vector3(s * (hw + 2), 22, 0), 3.0, 1.8, Color(0.32, 0.24, 0.16), 8)
				k.sphere(Vector3(s * (hw + 2), 24, 0), Vector3(9, 4, 9), Color(0.15, 0.38, 0.12), 9, 4)
			k.ring(Vector3(0, 10, 0), Vector3(0, 0, 1), hw + 2.5, 0.35, Color(0.25, 0.42, 0.15), 20, 4, false, PI)
			for i in 7:
				var x := (i - 3) * hw * 0.28
				k.cyl(Vector3(x, 10 + sqrt(maxf(0.0, (hw + 2.5) * (hw + 2.5) - x * x)) - 10, 0), Vector3(x, 8, 0), 0.1, 0.06, Color(0.3, 0.5, 0.2), 4, false, false, false)
				k.sphere(Vector3(x, 8, 0), Vector3.ONE * 0.35, Color(0.6, 1.0, 0.5), 6, 3, true)
		"ruin_gate":
			for s in [-1, 1]:
				k.cyl(Vector3(s * (hw + 1), 0, 0), Vector3(s * (hw + 1), 13 if s < 0 else 9, 0), 1.6, 1.5, SAND, 10)
			k.box(Vector3(-hw * 0.3, 13.8, 0), Vector3(hw * 1.6, 1.8, 3.4), SAND.darkened(0.08), false)
			k.box(Vector3(hw * 0.75, 3.0, 4.0), Vector3(6, 1.8, 3.0), SAND.darkened(0.15), false, 0.4)
		"omen":
			var rr := hw + 2.0
			k.ring(Vector3(0, rr * 0.55, 0), Vector3(0, 0, 1), rr, 0.9, Color(0.25, 0.22, 0.3), 32, 6)
			k.ring(Vector3(0, rr * 0.55, 0), Vector3(0, 0, 1), rr - 1.0, 0.35, AETHER, 32, 4, true)
			k.ring(Vector3(0, rr * 0.55, 0), Vector3(0, 0, 1), rr + 1.0, 0.25, Color(1.0, 0.6, 0.95), 32, 4, true)
			for i in 8:
				var a := TAU * i / 8
				var p := Vector3(cos(a) * (rr + 0.4), rr * 0.55 + sin(a) * (rr + 0.4), 0)
				k.taper(p - Vector3(0, 0, 0.8), Vector2(1.6, 1.6), Vector2(0.5, 0.5), 1.6, BRASS)
	return k.commit()


## Landmark nodes. `sc` scales the whole thing.
static func landmark(kind: String, sc: float, night: bool) -> Node3D:
	var n := Node3D.new()
	n.scale = Vector3.ONE * sc
	var k := MeshKit.new()
	match kind:
		"spire":
			k.taper(Vector3.ZERO, Vector2(30, 30), Vector2(14, 14), 30, Color(0.4, 0.28, 0.26))
			k.taper(Vector3(0, 30, 0), Vector2(14, 14), Vector2(6, 6), 70, Color(0.5, 0.33, 0.28))
			k.cyl(Vector3(0, 100, 0), Vector3(0, 150, 0), 3, 0.3, COPPER, 10)
			k.sphere(Vector3(0, 102, 0), Vector3(9, 10, 9), COPPER, 12, 6)
			for i in 12:
				var y := 8.0 + i * 7.5
				for side in 4:
					var a := side * PI * 0.5
					var off := Vector3(sin(a), 0, cos(a)) * (14.0 - i * 0.6)
					k.box(off + Vector3(0, y, 0), Vector3(3 if side % 2 == 0 else 0.3, 2.5, 0.3 if side % 2 == 0 else 3), Color(1, 0.75, 0.4) if night else Color(0.25, 0.3, 0.4), night)
			var rings := Node3D.new()
			rings.name = "Spin"
			rings.position = Vector3(0, 102, 0)
			var rk := MeshKit.new()
			rk.ring(Vector3.ZERO, Vector3.UP, 22, 0.8, AETHER, 32, 4, true)
			rk.ring(Vector3.ZERO, Vector3(0.3, 1, 0), 28, 0.5, Color(1.0, 0.55, 0.9), 32, 4, true)
			rk.ring(Vector3.ZERO, Vector3(-0.4, 1, 0.2), 34, 0.4, BRASS, 32, 4, false)
			var rm := MeshInstance3D.new()
			rm.mesh = rk.commit()
			rings.add_child(rm)
			n.add_child(rings)
		"pipeline":
			pass  # built along the track by track.gd
		"pyramid":
			k.taper(Vector3.ZERO, Vector2(160, 160), Vector2(4, 4), 110, SAND)
			k.taper(Vector3(0, 110, 0), Vector2(4, 4), Vector2(0.1, 0.1), 6, GOLD)
			k.taper(Vector3(0, 0, 82), Vector2(20, 6), Vector2(14, 4), 26, LIMESTONE)
		"statue":
			# a seated lion-headed guardian, original design
			var c := LIMESTONE
			k.box(Vector3(0, 4, 0), Vector3(16, 8, 20), c.darkened(0.12))
			k.box(Vector3(0, 4, 0.0), Vector3(16.4, 1.2, 20.4), LAPIS)
			k.taper(Vector3(0, 8, -2), Vector2(10, 7), Vector2(8, 5), 14, c)
			k.box(Vector3(-4.5, 11, 4), Vector3(3, 3, 12), c)
			k.box(Vector3(4.5, 11, 4), Vector3(3, 3, 12), c)
			k.sphere(Vector3(0, 26, -1), Vector3(5.2, 5.6, 5.2), GOLD, 10, 6)
			k.box(Vector3(0, 25, 3.6), Vector3(4, 3, 3), GOLD.darkened(0.15))
			k.taper(Vector3(-3.4, 29, -1), Vector2(1.6, 1.0), Vector2(0.2, 0.2), 3, GOLD)
			k.taper(Vector3(3.4, 29, -1), Vector2(1.6, 1.0), Vector2(0.2, 0.2), 3, GOLD)
			for i in 8:
				k.taper(Vector3(0, 22.5 - i * 0.1, -1), Vector2(13 - i, 0.4), Vector2(12 - i, 0.4), 0.5, LAPIS if i % 2 == 0 else GOLD, false, i * 0.4)
		"stands":
			var crowd := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.8, 0.3), Color(0.9, 0.9, 0.9), Color(0.3, 0.75, 0.5), Color(0.8, 0.4, 0.8)]
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			for row in 7:
				k.box(Vector3(0, 0.75 + row * 1.5, row * 1.6), Vector3(60, 1.5 + row * 3.0, 1.6), Color(0.35, 0.33, 0.38))
				for i in 40:
					if rng.randf() < 0.85:
						k.box(Vector3(-29 + i * 1.47, 2.0 + row * 1.5 + row * 1.5, row * 1.6 - 0.2), Vector3(0.7, 0.9, 0.5), crowd[rng.randi() % crowd.size()])
			k.box(Vector3(0, 17, 6), Vector3(62, 0.6, 14), Color(0.8, 0.35, 0.2))
			for s in [-1, 1]:
				k.cyl(Vector3(s * 30, 0, 12), Vector3(s * 30, 17, 12), 0.4, 0.4, BRASS, 6)
			k.box(Vector3(0, 15.5, -0.6), Vector3(58, 1.2, 0.2), AETHER, true)
		"volcano":
			k.taper(Vector3.ZERO, Vector2(380, 380), Vector2(70, 70), 190, Color(0.25, 0.2, 0.18))
			k.taper(Vector3(0, 189, 0), Vector2(60, 60), Vector2(40, 40), 3, Color(1.0, 0.45, 0.1), true)
			for i in 6:
				var a := TAU * i / 6 + 0.3
				k.taper(Vector3(cos(a) * 60, 0, sin(a) * 60), Vector2(10, 10), Vector2(3, 3), 150, Color(1.0, 0.35, 0.05), true, a, Vector3(-cos(a) * 25, 0, -sin(a) * 25))
			var smoke := _particles(60, 9.0, Color(0.3, 0.28, 0.28, 0.5), 30.0, 60.0)
			smoke.position = Vector3(0, 195, 0)
			smoke.direction = Vector3.UP
			smoke.gravity = Vector3(6, 2, 0)
			smoke.initial_velocity_min = 8.0
			smoke.initial_velocity_max = 14.0
			n.add_child(smoke)
		"dino":
			# a long-necked giant, made of a few chunky parts; track.gd walks it around slowly
			var hide := Color(0.35, 0.4, 0.3)
			k.sphere(Vector3(0, 12, 0), Vector3(6, 5, 11), hide, 10, 6)
			k.cyl(Vector3(0, 13, -8), Vector3(0, 30, -18), 2.4, 1.2, hide, 8)
			k.sphere(Vector3(0, 30.5, -19.5), Vector3(1.6, 1.4, 2.6), hide, 8, 4)
			k.cyl(Vector3(0, 12, 9), Vector3(0, 6, 30), 2.6, 0.3, hide, 8)
			for sx in [-3.5, 3.5]:
				for sz in [-6.0, 6.0]:
					k.cyl(Vector3(sx, 10, sz), Vector3(sx, 0, sz), 1.6, 1.3, hide.darkened(0.15), 7)
			for i in 8:
				k.taper(Vector3(0, 16.5 - i * 0.1, -6 + i * 2.2), Vector2(0.4, 1.2), Vector2(0.1, 0.2), 1.6, Color(0.7, 0.4, 0.2))
		"moonrocks":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 26:
				var p := Vector3(rng.randf_range(-700, 700), rng.randf_range(140, 380), rng.randf_range(-800, 500))
				var s := rng.randf_range(6, 30)
				k.rock(p, Vector3(s, s * 0.7, s * 0.9), Color(0.75, 0.68, 0.6), i)
		"mesa":
			k.rock(Vector3(0, 20, 0), Vector3(120, 50, 90), Color(0.72, 0.42, 0.28), 3)
			k.taper(Vector3(0, 30, 0), Vector2(150, 110), Vector2(120, 90), 30, Color(0.78, 0.5, 0.32))
		"tomb":
			var c := Color(0.75, 0.55, 0.38)
			k.taper(Vector3.ZERO, Vector2(110, 40), Vector2(90, 30), 40, c)
			for i in 5:
				var x := (i - 2) * 18.0
				k.box(Vector3(x, 8, 20.2), Vector3(6, 14, 1), Color(0.08, 0.06, 0.05))
				k.box(Vector3(x, 16, 20.5), Vector3(8, 1.5, 1.5), GOLD)
			for s in [-1, 1]:
				k.box(Vector3(s * 60, 9, 26), Vector3(10, 18, 10), c.darkened(0.08))
				k.sphere(Vector3(s * 60, 24, 26), Vector3(4, 5, 4), GOLD.darkened(0.2), 8, 5)
				k.taper(Vector3(s * 60, 18, 24), Vector2(7, 6), Vector2(5, 4), 6, c)
		"trophy":
			k.taper(Vector3.ZERO, Vector2(16, 16), Vector2(10, 10), 14, Color(0.3, 0.22, 0.25))
			k.cyl(Vector3(0, 14, 0), Vector3(0, 26, 0), 1.8, 1.2, BRASS, 10)
			k.cyl(Vector3(0, 26, 0), Vector3(0, 28, 0), 3.5, 4.5, BRASS, 12)
			var spark := Node3D.new()
			spark.name = "Spin"
			spark.position = Vector3(0, 34, 0)
			var sk := MeshKit.new()
			sk.sphere(Vector3.ZERO, Vector3.ONE * 3.2, Color(1.0, 0.85, 0.5), 12, 8, true)
			sk.ring(Vector3.ZERO, Vector3.UP, 5.5, 0.35, BRASS, 24, 4)
			sk.ring(Vector3.ZERO, Vector3(1, 0, 0.2), 6.2, 0.3, BRASS, 24, 4)
			sk.ring(Vector3.ZERO, Vector3(0.2, 0.3, 1), 6.9, 0.25, AETHER, 24, 4, true)
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
