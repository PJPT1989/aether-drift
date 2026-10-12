class_name CarModels
extends RefCounted
## Low-poly racing machines, one body style per team (see Game.TEAMS). Cars point down -Z, are
## about 4.4 m long, and sit with their wheels on y = 0.

const DARK := Color(0.08, 0.08, 0.1)
const GLASS := Color(0.12, 0.2, 0.3)


## Returns {"mesh", "wheel", "wheels" (positions), "exhausts" (positions), "hover"}.
static func build(team: Dictionary) -> Dictionary:
	var k := MeshKit.new()
	var body: Color = team.body
	var trim: Color = team.trim
	var glow: Color = team.glow
	var wheels: Array[Vector3] = [Vector3(-0.9, 0.42, -1.35), Vector3(0.9, 0.42, -1.35), Vector3(-0.92, 0.45, 1.35), Vector3(0.92, 0.45, 1.35)]
	var exhausts: Array[Vector3] = [Vector3(-0.45, 0.6, 2.25), Vector3(0.45, 0.6, 2.25)]
	var hover := false
	match team.style:
		"ramjet":
			k.taper(Vector3(0, 0.25, 0), Vector2(1.7, 4.4), Vector2(1.3, 3.6), 0.45, body)
			k.taper(Vector3(0, 0.7, 0.2), Vector2(1.1, 2.0), Vector2(0.7, 1.0), 0.45, GLASS, false, 0.0, Vector3(0, 0, 0.3))
			for s in [-1, 1]:
				k.cyl(Vector3(s * 0.95, 0.7, -1.2), Vector3(s * 0.95, 0.7, 2.2), 0.28, 0.34, trim, 8)
				k.ring(Vector3(s * 0.95, 0.7, -1.22), Vector3(0, 0, 1), 0.24, 0.05, glow, 10, 3, true)
				k.taper(Vector3(s * 0.95, 0.95, 1.6), Vector2(0.08, 0.7), Vector2(0.06, 0.3), 0.5, trim)
			k.box(Vector3(0, 0.5, -2.05), Vector3(1.5, 0.12, 0.4), trim)
			k.box(Vector3(0, 0.71, -0.8), Vector3(0.12, 0.02, 1.6), glow, true)
			exhausts = [Vector3(-0.95, 0.7, 2.3), Vector3(0.95, 0.7, 2.3)]
		"wedge":
			k.taper(Vector3(0, 0.22, 0), Vector2(1.9, 4.4), Vector2(1.5, 2.2), 0.6, body, false, 0.0, Vector3(0, 0, 0.9))
			k.taper(Vector3(0, 0.82, 0.6), Vector2(1.1, 1.4), Vector2(0.8, 0.6), 0.35, GLASS, false, 0.0, Vector3(0, 0, 0.3))
			k.box(Vector3(0, 0.83, -0.4), Vector3(0.35, 0.02, 2.0), trim)
			k.box(Vector3(0, 1.35, 2.0), Vector3(2.0, 0.1, 0.55), body)
			for s in [-1, 1]:
				k.box(Vector3(s * 0.75, 1.05, 2.0), Vector3(0.08, 0.6, 0.4), trim)
			k.box(Vector3(0, 0.4, -2.2), Vector3(1.8, 0.08, 0.2), glow, true)
		"chariot":
			k.taper(Vector3(0, 0.3, 0.3), Vector2(1.6, 3.4), Vector2(1.6, 3.0), 0.55, trim)
			for s in [-1, 1]:
				k.box(Vector3(s * 0.82, 0.95, 0.5), Vector3(0.12, 0.8, 2.6), body)
				k.box(Vector3(s * 0.85, 1.1, 0.5), Vector3(0.06, 0.2, 2.4), trim)
			k.cyl(Vector3(0, 0.5, -1.4), Vector3(0, 1.8, -2.3), 0.35, 0.12, body, 8)
			k.sphere(Vector3(0, 1.9, -2.35), Vector3(0.35, 0.35, 0.2), glow, 8, 4, true)
			k.box(Vector3(0, 1.3, 1.5), Vector3(1.4, 0.8, 0.12), body)
			k.ring(Vector3(0, 1.45, 1.6), Vector3(0, 0, 1), 0.45, 0.06, glow, 14, 3, true)
			k.sphere(Vector3(0, 1.1, 0.6), Vector3(0.35, 0.4, 0.35), DARK, 6, 4)
			wheels = [Vector3(-0.9, 0.42, -1.2), Vector3(0.9, 0.42, -1.2), Vector3(-1.0, 0.6, 1.3), Vector3(1.0, 0.6, 1.3)]
			exhausts = [Vector3(0, 0.8, 1.9)]
		"pod":
			k.sphere(Vector3(0, 0.75, 0), Vector3(0.95, 0.55, 2.1), body, 12, 6)
			k.sphere(Vector3(0, 1.1, -0.3), Vector3(0.55, 0.38, 0.9), trim, 10, 5)
			k.sphere(Vector3(0, 1.15, -0.55), Vector3(0.28, 0.2, 0.3), glow, 8, 4, true)
			k.ring(Vector3(0, 0.75, 0.2), Vector3.UP, 1.0, 0.07, Props.BRASS, 18, 3)
			hover = true
			wheels = [Vector3(-0.85, 0.32, -1.2), Vector3(0.85, 0.32, -1.2), Vector3(-0.85, 0.32, 1.2), Vector3(0.85, 0.32, 1.2)]
			exhausts = [Vector3(0, 0.75, 2.15)]
		"spike":
			k.taper(Vector3(0, 0.25, 0.2), Vector2(1.8, 4.0), Vector2(0.9, 2.6), 0.6, body, false, 0.0, Vector3(0, 0, 0.4))
			k.taper(Vector3(0, 0.85, 0.5), Vector2(0.8, 1.4), Vector2(0.1, 0.4), 0.45, GLASS, false, 0.0, Vector3(0, 0, 0.4))
			k.taper(Vector3(0, 0.3, -1.8), Vector2(1.2, 0.8), Vector2(0.1, 0.1), 0.2, body, false, 0.0, Vector3(0, 0, -1.0))
			for i in 4:
				var z := -0.8 + i * 0.8
				for s in [-1, 1]:
					k.taper(Vector3(s * 0.8, 0.65, z), Vector2(0.18, 0.3), Vector2(0.02, 0.02), 0.6, trim, false, 0.0, Vector3(s * 0.4, 0, 0.3))
			k.box(Vector3(0, 0.3, 0), Vector3(1.95, 0.06, 3.6), glow, true)
		"rocket":
			k.box(Vector3(0, 0.45, 0), Vector3(1.5, 0.4, 3.6), body)
			k.cyl(Vector3(0, 1.15, 2.3), Vector3(0, 1.15, -1.2), 0.55, 0.55, trim.darkened(0.1), 10)
			k.cyl(Vector3(0, 1.15, -1.2), Vector3(0, 1.15, -2.2), 0.55, 0.02, trim, 10, false, true, false)
			for i in 3:
				var a := TAU * i / 3.0
				k.taper(Vector3(cos(a) * 0.45, 1.15 + sin(a) * 0.45, 1.6), Vector2(0.06, 0.6), Vector2(0.04, 0.3), 0.4, body, false, a)
			k.sphere(Vector3(0, 0.95, 0.1), Vector3(0.3, 0.35, 0.3), Color(0.35, 0.55, 0.2), 6, 4)
			k.ring(Vector3(0, 1.15, 2.32), Vector3(0, 0, 1), 0.42, 0.08, glow, 12, 3, true)
			exhausts = [Vector3(0, 1.15, 2.45)]
		"fin":
			k.taper(Vector3(0, 0.25, 0.1), Vector2(1.6, 4.2), Vector2(0.9, 3.0), 0.55, body, false, 0.0, Vector3(0, 0, 0.3))
			k.taper(Vector3(0, 0.25, -2.0), Vector2(1.1, 0.6), Vector2(0.2, 0.1), 0.45, trim, false, 0.0, Vector3(0, 0, -0.4))
			k.taper(Vector3(0, 0.78, 0.6), Vector2(0.15, 1.6), Vector2(0.05, 0.3), 1.0, body, false, 0.0, Vector3(0, 0, 0.6))
			k.box(Vector3(0, 0.55, -1.3), Vector3(1.2, 0.25, 0.4), trim)
			for s in [-1, 1]:
				k.box(Vector3(s * 0.45, 0.62, -1.75), Vector3(0.2, 0.08, 0.02), glow, true)
				k.taper(Vector3(s * 0.85, 0.3, 0.6), Vector2(0.1, 0.8), Vector2(0.05, 0.3), 0.35, trim, false, 0.0, Vector3(s * 0.3, 0, 0.2))
		"armored":
			k.box(Vector3(0, 0.65, 0.1), Vector3(1.9, 0.8, 4.0), body)
			k.taper(Vector3(0, 1.05, 0.3), Vector2(1.6, 2.2), Vector2(1.3, 1.6), 0.5, trim)
			k.box(Vector3(0, 1.3, -0.45), Vector3(1.2, 0.18, 0.05), glow, true)
			k.box(Vector3(0, 0.45, -2.2), Vector3(2.0, 0.35, 0.3), trim)
			for i in 4:
				k.taper(Vector3(-0.75 + i * 0.5, 0.45, -2.35), Vector2(0.2, 0.2), Vector2(0.02, 0.02), 0.45, Props.BRASS, false, 0.0, Vector3(0, -0.2, -0.3))
			for s in [-1, 1]:
				k.cyl(Vector3(s * 0.7, 1.0, 1.9), Vector3(s * 0.7, 1.9, 2.1), 0.12, 0.12, Props.BRASS.darkened(0.3), 6)
				k.ring(Vector3(s * 0.7, 1.92, 2.1), Vector3(0, 1, 0.2), 0.12, 0.04, glow, 8, 3, true)
			exhausts = [Vector3(-0.7, 1.95, 2.1), Vector3(0.7, 1.95, 2.1)]
	# undertray glow every car shares: a strip of the team's aether colour
	k.box(Vector3(0, 0.16, 0), Vector3(1.2, 0.04, 3.0), glow, true)
	var wk := MeshKit.new()
	if hover:
		wk.cyl(Vector3(-0.2, 0, 0), Vector3(0.2, 0, 0), 0.4, 0.4, Props.BRASS, 10)
		wk.cyl(Vector3(0, -0.1, 0), Vector3(0, -0.14, 0), 0.38, 0.38, glow, 10, true)
	else:
		wk.cyl(Vector3(-0.18, 0, 0), Vector3(0.18, 0, 0), 0.42, 0.42, DARK, 10)
		wk.cyl(Vector3(-0.19, 0, 0), Vector3(0.19, 0, 0), 0.2, 0.2, trim, 6)
		wk.box(Vector3(0, 0.3, 0), Vector3(0.38, 0.12, 0.12), Color(0.2, 0.2, 0.22))
	return {"mesh": k.commit(), "wheel": wk.commit(), "wheels": wheels, "exhausts": exhausts, "hover": hover}
