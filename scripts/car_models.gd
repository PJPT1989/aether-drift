class_name CarModels
extends RefCounted
## Racing machines, one body style per team (see Game.TEAMS). Bodies are smooth lofted shells
## (cross-sections along the car) in glossy paint with glass cabins, painted wheel arches, lights,
## and the team's own parts on top. Cars point down -Z, are about 4.5 m long, and sit with their
## wheels on y = 0.

const DARK := Color(0.07, 0.07, 0.08)
const ARCH := Color(0.03, 0.03, 0.035)
const GLASS := Color(0.06, 0.09, 0.14)
const CHROME := Color(0.75, 0.76, 0.8)
const HEAD := Color(1.0, 0.95, 0.8)
const TAIL := Color(1.0, 0.12, 0.08)
const WHEEL_R := 0.42
const SEGS := 22


## Returns {"mesh", "wheel", "wheels" (positions), "exhausts" (positions), "hover"}.
static func build(team: Dictionary) -> Dictionary:
	var k := MeshKit.new()
	var body: Color = team.body
	var trim: Color = team.trim
	var glow: Color = team.glow
	var wheels: Array[Vector3] = [Vector3(-0.92, WHEEL_R, -1.4), Vector3(0.92, WHEEL_R, -1.4), Vector3(-0.94, WHEEL_R, 1.4), Vector3(0.94, WHEEL_R, 1.4)]
	var exhausts: Array[Vector3] = [Vector3(-0.42, 0.42, 2.3), Vector3(0.42, 0.42, 2.3)]
	var hover := false
	match team.style:
		"ramjet":
			# long, low streamliner with a bubble canopy and twin aether ramjets on outriggers
			_shell(k, [[-2.35, 0.35, 0.34, 0.5, 0.8, 2.6], [-2.0, 0.72, 0.26, 0.6, 0.85, 3.0], [-1.4, 0.86, 0.22, 0.72, 0.8, 3.2],
				[-0.4, 0.86, 0.2, 0.74, 0.8, 3.2], [0.8, 0.88, 0.2, 0.76, 0.8, 3.2], [1.6, 0.86, 0.24, 0.74, 0.85, 3.0],
				[2.3, 0.7, 0.32, 0.66, 0.85, 3.0]], _livery(body, trim, wheels, 0.14))
			_cabin(k, [[-0.95, 0.5, 0.66, 0.7, 0.7, 2.2], [-0.5, 0.58, 0.68, 1.08, 0.55, 2.2], [0.3, 0.6, 0.7, 1.16, 0.55, 2.2],
				[1.0, 0.52, 0.7, 0.98, 0.6, 2.2], [1.5, 0.4, 0.7, 0.76, 0.7, 2.2]], body, 0.95)
			for s: float in [-1.0, 1.0]:
				k.paint = true
				_shell(k, [[-1.5, 0.2, 0.52, 0.86, 1.0, 2.0], [-1.3, 0.3, 0.42, 0.96, 1.0, 2.0], [1.6, 0.3, 0.42, 0.96, 1.0, 2.0],
					[2.3, 0.24, 0.48, 0.9, 1.0, 2.0]], trim, Vector3(s * 1.12, 0, 0))
				k.paint = false
				k.ring(Vector3(s * 1.12, 0.69, -1.52), Vector3(0, 0, 1), 0.2, 0.045, glow, 16, 4, true)
				k.cyl(Vector3(s * 1.12, 0.69, -1.5), Vector3(s * 1.12, 0.69, -1.3), 0.18, 0.18, DARK, 14)
				k.cyl(Vector3(s * 1.12, 0.69, 2.28), Vector3(s * 1.12, 0.69, 2.36), 0.22, 0.18, glow, 14, true)
				k.box(Vector3(s * 1.0, 0.62, 0.2), Vector3(0.3, 0.08, 0.5), trim)
				k.paint = true
				k.taper(Vector3(s * 1.12, 0.9, 1.7), Vector2(0.07, 0.7), Vector2(0.05, 0.35), 0.45, body)
			k.paint = true
			k.box(Vector3(0, 0.34, -2.28), Vector3(1.5, 0.04, 0.3), body)
			k.paint = false
			k.box(Vector3(0, 0.753, -0.2), Vector3(0.1, 0.02, 3.4), glow, true)
			_lights(k, 0.62, -2.08, 0.5, 2.27, 0.56)
			exhausts = [Vector3(-1.12, 0.69, 2.4), Vector3(1.12, 0.69, 2.4)]
		"wedge":
			# mid-engined supercar wedge with a tall rear wing
			_shell(k, [[-2.3, 0.62, 0.3, 0.42, 0.9, 3.2], [-2.0, 0.92, 0.25, 0.55, 0.9, 3.6], [-1.4, 1.0, 0.22, 0.7, 0.85, 3.6],
				[-0.6, 0.98, 0.2, 0.76, 0.85, 3.6], [0.5, 0.98, 0.2, 0.82, 0.85, 3.6], [1.4, 1.05, 0.22, 0.9, 0.85, 3.6],
				[2.05, 1.0, 0.28, 0.88, 0.85, 3.6], [2.3, 0.9, 0.34, 0.82, 0.85, 3.4]], _livery(body, trim, wheels, 0.2))
			_cabin(k, [[-0.85, 0.78, 0.72, 0.76, 0.7, 3.0], [-0.35, 0.8, 0.74, 1.16, 0.62, 3.0], [0.5, 0.8, 0.78, 1.2, 0.62, 3.0],
				[1.15, 0.76, 0.8, 0.98, 0.66, 3.0], [1.5, 0.7, 0.84, 0.86, 0.7, 3.0]], body, 1.0)
			k.paint = true
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(s * 0.62, 1.12, 2.05), Vector3(0.07, 0.48, 0.3), trim)
				k.box(Vector3(s * 0.96, 0.98, -0.45), Vector3(0.14, 0.04, 0.06), body)
				k.box(Vector3(s * 1.03, 0.99, -0.46), Vector3(0.05, 0.1, 0.16), body)
			_wing(k, Vector3(0, 1.38, 2.12), 2.05, 0.5, body, trim)
			k.paint = false
			for s: float in [-1.0, 1.0]:
				_vent(k, Vector3(s * 1.01, 0.62, 0.95), s, 0.5, 0.22)
			k.box(Vector3(0, 0.25, -2.3), Vector3(1.6, 0.04, 0.22), DARK)
			k.box(Vector3(0, 0.275, -2.4), Vector3(1.5, 0.015, 0.03), glow, true)
			_lights(k, 0.6, -2.12, 0.62, 2.31, 0.66)
		"chariot":
			# desert chariot: an open gilded tub with tall flared flanks, a sun-disc prow and a rider
			_shell(k, [[-2.25, 0.4, 0.4, 0.58, 0.9, 2.6], [-1.8, 0.82, 0.3, 0.7, 0.95, 3.0], [-0.8, 0.92, 0.26, 0.8, 1.0, 3.6],
				[1.0, 0.94, 0.26, 0.82, 1.0, 3.6], [1.9, 0.9, 0.32, 0.86, 1.0, 3.4], [2.25, 0.8, 0.4, 0.84, 1.0, 3.0]], _livery(trim, body, wheels, 0.0))
			k.paint = true
			for s: float in [-1.0, 1.0]:
				_shell(k, [[-1.6, 0.06, 0.55, 0.9, 1.0, 4.0], [-1.0, 0.07, 0.7, 1.35, 1.0, 4.0], [1.0, 0.07, 0.72, 1.4, 1.0, 4.0],
					[1.9, 0.06, 0.62, 1.2, 1.0, 4.0]], body, Vector3(s * 0.9, 0, 0))
				k.box(Vector3(s * 0.92, 1.36, 0.0), Vector3(0.1, 0.07, 2.0), Props.GOLD)
				for i in 3:
					k.box(Vector3(s * 0.97, 0.9 + i * 0.12, 0.0), Vector3(0.02, 0.04, 1.8 - i * 0.3), trim)
			# prow neck rising to the sun disc
			k.cyl(Vector3(0, 0.6, -1.9), Vector3(0, 1.45, -2.3), 0.22, 0.1, body, 12)
			k.ring(Vector3(0, 1.75, -2.32), Vector3(0, 0.15, 1), 0.36, 0.06, Props.GOLD, 20, 5)
			k.paint = false
			k.cyl(Vector3(0, 1.75, -2.34), Vector3(0, 1.75, -2.3), 0.3, 0.3, glow, 18, true)
			for i in 10:
				var a := TAU * i / 10.0
				k.taper(Vector3(cos(a) * 0.44, 1.75 + sin(a) * 0.44, -2.32), Vector2(0.08, 0.04), Vector2(0.01, 0.01), 0.18, Props.GOLD, false, 0.0, Vector3(cos(a) * 0.12, 0.0, 0))
			# rider in a lapis headdress
			k.cyl(Vector3(0, 0.75, 0.45), Vector3(0, 1.35, 0.4), 0.32, 0.24, Color(0.85, 0.8, 0.7), 12)
			k.sphere(Vector3(0, 1.55, 0.38), Vector3(0.2, 0.24, 0.22), Color(0.55, 0.38, 0.25), 12, 8)
			k.paint = true
			k.taper(Vector3(0, 1.58, 0.42), Vector2(0.5, 0.42), Vector2(0.34, 0.3), 0.25, Props.LAPIS)
			k.paint = false
			k.box(Vector3(0, 1.45, 0.62), Vector3(0.46, 0.4, 0.08), Props.LAPIS)
			# rear shield with the team's sun
			k.paint = true
			k.box(Vector3(0, 1.15, 1.75), Vector3(1.5, 0.7, 0.1), body)
			k.paint = false
			k.ring(Vector3(0, 1.2, 1.81), Vector3(0, 0, 1), 0.26, 0.05, glow, 18, 4, true)
			k.cyl(Vector3(0, 1.2, 1.8), Vector3(0, 1.2, 1.82), 0.14, 0.14, glow, 14, true)
			_lights(k, 0.5, -2.1, 0.62, 2.25, 0.52)
			wheels = [Vector3(-0.98, WHEEL_R, -1.3), Vector3(0.98, WHEEL_R, -1.3), Vector3(-1.02, 0.55, 1.3), Vector3(1.02, 0.55, 1.3)]
			exhausts = [Vector3(0, 0.6, 2.3)]
		"pod":
			# automaton pilgrims' teardrop hover-pod, brass-banded, with a glass dome
			_shell(k, _ring_stations(-2.25, 2.25, 0.98, 0.24, 1.3, 9, 2.4, 0.45), _livery(body, trim, [], 0.0))
			_cabin(k, [[-1.25, 0.3, 1.0, 1.04, 1.0, 2.0], [-0.95, 0.56, 1.02, 1.4, 1.0, 2.0], [-0.2, 0.62, 1.06, 1.58, 1.0, 2.0],
				[0.5, 0.52, 1.08, 1.48, 1.0, 2.0], [0.9, 0.3, 1.1, 1.18, 1.0, 2.0]], body, 2.0)
			k.paint = true
			k.ring(Vector3(0, 0.78, 0.0), Vector3.UP, 1.02, 0.07, Props.BRASS, 40, 6)
			k.ring(Vector3(0, 1.16, 0.2), Vector3.UP, 0.78, 0.04, Props.BRASS, 32, 4)
			k.paint = false
			k.sphere(Vector3(0, 1.62, -0.25), Vector3(0.1, 0.1, 0.1), glow, 10, 6, true)
			k.cyl(Vector3(0, 1.48, -0.25), Vector3(0, 1.6, -0.25), 0.02, 0.02, Props.BRASS, 6)
			for s: float in [-1.0, 1.0]:
				k.ring(Vector3(s * 0.9, 0.85, -0.9), Vector3(1, 0, 0), 0.14, 0.03, glow, 14, 3, true)
			_lights(k, 0.36, -2.13, 0.78, 2.17, 0.82)
			hover = true
			wheels = [Vector3(-0.82, 0.32, -1.3), Vector3(0.82, 0.32, -1.3), Vector3(-0.82, 0.32, 1.3), Vector3(0.82, 0.32, 1.3)]
			exhausts = [Vector3(0, 0.82, 2.3)]
		"spike":
			# haunted hypercar: knife-edged, very low, ribbed with bone-like spines
			_shell(k, [[-2.45, 0.2, 0.3, 0.36, 0.6, 5.0], [-2.0, 0.78, 0.24, 0.5, 0.75, 5.0], [-1.4, 1.0, 0.2, 0.66, 0.7, 5.0],
				[-0.3, 0.92, 0.2, 0.7, 0.65, 5.0], [0.8, 0.96, 0.2, 0.76, 0.65, 5.0], [1.45, 1.06, 0.22, 0.82, 0.7, 5.0],
				[2.3, 0.88, 0.3, 0.74, 0.75, 5.0]], _livery(body, trim, wheels, 0.08))
			_cabin(k, [[-0.95, 0.5, 0.64, 0.68, 0.5, 4.0], [-0.4, 0.6, 0.66, 1.04, 0.38, 4.0], [0.45, 0.6, 0.7, 1.08, 0.38, 4.0],
				[1.3, 0.5, 0.74, 0.8, 0.5, 4.0]], body, 0.92)
			k.paint = true
			for i in 5:
				var z := -1.1 + i * 0.6
				for s: float in [-1.0, 1.0]:
					k.taper(Vector3(s * 0.86, 0.66, z), Vector2(0.14, 0.26), Vector2(0.01, 0.01), 0.55 - absf(i - 2) * 0.08, trim, false, 0.0, Vector3(s * 0.45, 0, 0.32))
			k.taper(Vector3(0, 0.82, 1.6), Vector2(0.08, 1.0), Vector2(0.02, 0.2), 0.6, trim, false, 0.0, Vector3(0, 0, 0.45))
			_wing(k, Vector3(0, 0.98, 2.15), 1.9, 0.36, body, trim)
			k.paint = false
			k.box(Vector3(0, 0.2, 0), Vector3(2.0, 0.04, 3.8), glow, true)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(s * 0.5, 0.4, -2.08), Vector3(0.42, 0.04, 0.12), glow, true, s * -0.12)
				_vent(k, Vector3(s * 1.0, 0.52, 0.95), s, 0.55, 0.16)
			_lights(k, 0.62, 99.0, 0.5, 2.3, 0.52)
		"rocket":
			# goblin rocket strapped to a buggy frame
			_shell(k, [[-2.1, 0.5, 0.3, 0.5, 0.9, 3.0], [-1.7, 0.86, 0.26, 0.62, 0.95, 4.0], [1.6, 0.86, 0.26, 0.66, 0.95, 4.0],
				[2.1, 0.7, 0.3, 0.62, 0.95, 3.4]], _livery(body, trim, wheels, 0.0))
			var rk := trim.darkened(0.05)
			k.paint = true
			_shell(k, [[-2.5, 0.02, 1.24, 1.26, 1.0, 2.0], [-2.2, 0.32, 0.92, 1.56, 1.0, 2.0], [-1.7, 0.52, 0.72, 1.76, 1.0, 2.0],
				[-1.0, 0.56, 0.68, 1.8, 1.0, 2.0], [2.0, 0.56, 0.68, 1.8, 1.0, 2.0], [2.3, 0.5, 0.74, 1.74, 1.0, 2.0]],
				func(t: float, _a: float, p: Vector3, _n: Vector3) -> Color:
					if t < 0.12:
						return Color(0.9, 0.88, 0.8)
					return Color(0.92, 0.9, 0.85) if absf(fposmod(p.z + 0.2, 1.2) - 0.6) < 0.08 else rk)
			for i in 4:
				var a := TAU * i / 4.0 + PI * 0.25
				var dir := Vector3(cos(a), sin(a), 0)
				k.quad(Vector3(0, 1.24, 1.2) + dir * 0.5, Vector3(0, 1.24, 2.2) + dir * 0.5, Vector3(0, 1.24, 2.4) + dir * 1.0, Vector3(0, 1.24, 1.9) + dir * 1.0, body)
				k.quad(Vector3(0, 1.24, 1.2) + dir * 0.5, Vector3(0, 1.24, 1.9) + dir * 1.0, Vector3(0, 1.24, 2.4) + dir * 1.0, Vector3(0, 1.24, 2.2) + dir * 0.5, body)
			k.paint = false
			for i in 3:
				k.ring(Vector3(0, 1.24, -0.6 + i * 0.9), Vector3(0, 0, 1), 0.57, 0.035, Props.BRASS, 22, 3)
			k.cyl(Vector3(0, 1.24, 2.3), Vector3(0, 1.24, 2.55), 0.42, 0.5, DARK, 18)
			k.cyl(Vector3(0, 1.24, 2.5), Vector3(0, 1.24, 2.56), 0.38, 0.38, glow, 18, true)
			# goblin rider with goggles, holding on for dear life
			k.sphere(Vector3(0, 1.98, -0.4), Vector3(0.22, 0.2, 0.22), Color(0.35, 0.55, 0.2), 12, 8)
			for s: float in [-1.0, 1.0]:
				k.taper(Vector3(s * 0.2, 2.02, -0.4), Vector2(0.12, 0.08), Vector2(0.01, 0.01), 0.3, Color(0.35, 0.55, 0.2), false, 0.0, Vector3(s * 0.25, 0.05, 0.05))
				k.ring(Vector3(s * 0.08, 2.02, -0.6), Vector3(0, 0, 1), 0.06, 0.02, Props.BRASS, 10, 3)
			k.box(Vector3(0, 2.02, -0.6), Vector3(0.26, 0.08, 0.04), Color(0.6, 0.9, 1.0), true)
			k.cyl(Vector3(0, 1.8, -0.35), Vector3(0, 1.8, -0.35) + Vector3(0, -0.2, 0.3), 0.2, 0.18, Color(0.4, 0.25, 0.15), 10)
			_lights(k, 0.45, -2.07, 0.6, 2.08, 0.5)
			exhausts = [Vector3(0, 1.24, 2.6)]
		"fin":
			# shark-folk hauler: a shark's body, gill slits, a dorsal fin and a toothy grille
			_shell(k, [[-2.35, 0.45, 0.3, 0.52, 0.8, 2.4], [-2.0, 0.84, 0.24, 0.66, 0.8, 2.6], [-1.2, 0.98, 0.22, 0.8, 0.75, 2.8],
				[0.0, 0.98, 0.22, 0.84, 0.72, 2.8], [1.2, 0.94, 0.24, 0.8, 0.75, 2.8], [1.9, 0.78, 0.3, 0.72, 0.8, 2.6],
				[2.4, 0.5, 0.4, 0.62, 0.85, 2.4]], _shark(body, trim, wheels))
			_cabin(k, [[-0.75, 0.6, 0.76, 0.8, 0.6, 2.4], [-0.3, 0.66, 0.78, 1.12, 0.5, 2.4], [0.5, 0.64, 0.8, 1.12, 0.5, 2.4],
				[1.05, 0.56, 0.8, 0.88, 0.6, 2.4]], body, 0.9)
			k.paint = true
			# dorsal fin and tail flukes
			var fin_pts := [Vector3(0, 1.1, 0.7), Vector3(0, 1.85, 1.45), Vector3(0, 1.9, 1.62), Vector3(0, 0.82, 1.8)]
			for s: float in [-1.0, 1.0]:
				var o := Vector3(s * 0.05, 0, 0)
				if s > 0:
					k.quad(fin_pts[0] + o, fin_pts[3] + o, fin_pts[2] + o, fin_pts[1] + o, body)
				else:
					k.quad(fin_pts[0] + o, fin_pts[1] + o, fin_pts[2] + o, fin_pts[3] + o, body)
			k.quad(fin_pts[1] + Vector3(-0.05, 0, 0), fin_pts[1] + Vector3(0.05, 0, 0), fin_pts[2] + Vector3(0.05, 0, 0), fin_pts[2] + Vector3(-0.05, 0, 0), body)
			for s: float in [-1.0, 1.0]:
				k.taper(Vector3(s * 0.25, 0.55, 2.3), Vector2(0.3, 0.3), Vector2(0.06, 0.12), 0.75, body, false, 0.0, Vector3(s * 0.55, 0.15, 0.4))
				k.taper(Vector3(s * 0.9, 0.32, -0.2), Vector2(0.12, 0.7), Vector2(0.04, 0.2), 0.3, body, false, 0.0, Vector3(s * 0.35, -0.05, 0.3))
			k.paint = false
			# toothy grille
			k.box(Vector3(0, 0.38, -2.18), Vector3(1.1, 0.16, 0.22), ARCH)
			for i in 7:
				var x := -0.45 + i * 0.15
				k.taper(Vector3(x, 0.46, -2.22), Vector2(0.08, 0.05), Vector2(0.01, 0.01), -0.12, Color(0.95, 0.95, 0.9))
				k.taper(Vector3(x + 0.07, 0.3, -2.22), Vector2(0.08, 0.05), Vector2(0.01, 0.01), 0.1, Color(0.95, 0.95, 0.9))
			_lights(k, 0.62, -2.1, 0.66, 2.3, 0.6)
		"armored":
			# wasteland war-rig: a boxy armoured shell, roof cage, ram plough and exhaust stacks
			_shell(k, [[-2.35, 0.9, 0.3, 0.8, 0.95, 6.0], [-2.0, 1.0, 0.26, 0.98, 0.95, 6.0], [-1.0, 1.02, 0.24, 1.02, 0.95, 6.0],
				[1.2, 1.02, 0.24, 1.04, 0.95, 6.0], [2.3, 0.98, 0.28, 1.0, 0.95, 6.0]], _armour(body, trim, wheels))
			_cabin(k, [[-0.9, 0.86, 0.98, 1.0, 0.85, 5.0], [-0.55, 0.88, 0.98, 1.55, 0.82, 5.0], [0.9, 0.88, 0.98, 1.58, 0.82, 5.0],
				[1.2, 0.86, 0.98, 1.0, 0.85, 5.0]], body, 1.3)
			k.paint = false
			# roof cage
			for x: float in [-0.7, 0.7]:
				k.cyl(Vector3(x, 1.65, -0.5), Vector3(x, 1.65, 0.9), 0.04, 0.04, Props.BRASS.darkened(0.4), 8)
			for z: float in [-0.5, 0.2, 0.9]:
				k.cyl(Vector3(-0.7, 1.65, z), Vector3(0.7, 1.65, z), 0.04, 0.04, Props.BRASS.darkened(0.4), 8)
			k.box(Vector3(0, 1.7, 0.2), Vector3(0.9, 0.18, 0.6), Color(0.35, 0.3, 0.22))
			k.box(Vector3(0, 1.62, -0.42), Vector3(1.0, 0.07, 0.12), glow, true)
			# ram plough with spikes
			k.paint = true
			k.box(Vector3(0, 0.45, -2.42), Vector3(2.1, 0.4, 0.14), trim)
			for i in 5:
				k.taper(Vector3(-0.8 + i * 0.4, 0.45, -2.48), Vector2(0.18, 0.18), Vector2(0.01, 0.01), 0.36, Props.BRASS, false, 0.0, Vector3(0, 0, -0.1))
			k.paint = false
			for s: float in [-1.0, 1.0]:
				k.cyl(Vector3(s * 0.8, 0.9, 1.95), Vector3(s * 0.8, 2.05, 2.15), 0.11, 0.11, Props.BRASS.darkened(0.25), 12)
				k.ring(Vector3(s * 0.8, 2.06, 2.15), Vector3(0, 1, 0.17), 0.11, 0.035, glow, 12, 3, true)
				for i in 4:
					k.box(Vector3(s * 1.04, 0.5 + i * 0.13, -0.2), Vector3(0.04, 0.05, 2.6), Props.BRASS.darkened(0.3))
			_lights(k, 0.74, -2.37, 0.8, 2.31, 0.84)
			exhausts = [Vector3(-0.8, 2.1, 2.15), Vector3(0.8, 2.1, 2.15)]
	k.paint = false
	# undertray glow every car shares: a strip of the team's aether colour
	k.box(Vector3(0, 0.14, 0), Vector3(1.2, 0.04, 3.0), glow, true)
	return {"mesh": k.commit(), "wheel": _wheel(trim, glow, hover), "wheels": wheels, "exhausts": exhausts, "hover": hover}


## Smooth body from stations [z, half width, bottom y, top y, top width factor, squareness]
## (2 = round, higher = boxier). Stations are eased into each other with extra rows between.
static func _shell(k: MeshKit, st: Array, col: Variant, off := Vector3.ZERO, steps := 3) -> void:
	var rows: Array = []
	for i in st.size() - 1:
		var p0: Array = st[maxi(i - 1, 0)]
		var p1: Array = st[i]
		var p2: Array = st[i + 1]
		var p3: Array = st[mini(i + 2, st.size() - 1)]
		for s in steps:
			var t := float(s) / steps
			var v: Array = []
			for c in 6:
				v.append(_catmull(p0[c], p1[c], p2[c], p3[c], t))
			v[0] = lerpf(p1[0], p2[0], t)
			rows.append(_section(v, off))
	rows.append(_section(st[st.size() - 1], off))
	var was := k.paint
	k.paint = k.paint or col is Callable
	k.loft(rows, col)
	k.paint = was


static func _catmull(a: float, b: float, c: float, d: float, t: float) -> float:
	return 0.5 * (2.0 * b + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (3.0 * b - a - 3.0 * c + d) * t * t * t)


## One cross-section of a body: a superellipse narrowing towards the top.
static func _section(v: Array, off: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var mid: float = (v[2] + v[3]) * 0.5
	var h: float = maxf((v[3] - v[2]) * 0.5, 0.005)
	var ex: float = 2.0 / maxf(v[5], 1.0)
	for j in SEGS:
		var a := TAU * j / SEGS
		var c := cos(a)
		var s := sin(a)
		var y := signf(s) * pow(absf(s), ex)
		var x := signf(c) * pow(absf(c), ex) * maxf(v[1], 0.005) * lerpf(1.0, v[4], clampf(y, 0.0, 1.0))
		pts.append(Vector3(x, mid + y * h, v[0]) + off)
	return pts


## Stations of a round teardrop: widest a little ahead of the middle.
static func _ring_stations(z0: float, z1: float, w: float, y0: float, y1: float, n: int, sq: float, front: float) -> Array:
	var out: Array = []
	for i in n:
		var t := float(i) / (n - 1)
		var f := sin(PI * pow(t, front * 1.6 + 0.2))
		f = sqrt(maxf(f, 0.0))
		var mid := (y0 + y1) * 0.5
		var h := (y1 - y0) * 0.5 * maxf(f, 0.08)
		out.append([lerpf(z0, z1, t), maxf(w * f, 0.03), mid - h, mid + h * 0.95, 0.85, sq])
	return out


## Glass greenhouse on top of the body: glass all round with a painted roof.
static func _cabin(k: MeshKit, st: Array, body: Color, roof_y: float) -> void:
	k.paint = true
	_shell(k, st, func(_t: float, _a: float, p: Vector3, n: Vector3) -> Color:
		return body if n.y > 0.82 and p.y > roof_y else GLASS)


## Paint scheme for the main body: base colour, a twin stripe over the top in the trim colour,
## a dark sill, and dark wheel arches cut around each wheel.
static func _livery(body: Color, trim: Color, wheels: Array, stripe: float) -> Callable:
	return func(_t: float, _a: float, p: Vector3, n: Vector3) -> Color:
		for w: Vector3 in wheels:
			if absf(n.x) > 0.35 and Vector2(p.y - w.y, p.z - w.z).length() < WHEEL_R + 0.07:
				return ARCH
		if p.y < 0.3 and n.y < -0.2:
			return DARK
		if stripe > 0.0 and n.y > 0.45 and absf(absf(p.x) - stripe) < 0.07:
			return trim
		if absf(n.x) > 0.7 and absf(p.y - 0.5) < 0.04:
			return trim
		return body


## Shark livery: dark back, pale belly, gill slits behind the front wheels.
static func _shark(body: Color, belly: Color, wheels: Array) -> Callable:
	var base := _livery(body, belly, wheels, 0.0)
	return func(t: float, a: float, p: Vector3, n: Vector3) -> Color:
		var c: Color = base.call(t, a, p, n)
		if c != body:
			return c
		if absf(n.x) > 0.6 and p.z > -0.8 and p.z < -0.2 and absf(fposmod(p.z, 0.2) - 0.1) < 0.025 and p.y > 0.4 and p.y < 0.7:
			return ARCH
		return belly if n.y < -0.05 or p.y < 0.42 else body


## Armour livery: riveted plate bands in the trim colour and dark arches.
static func _armour(body: Color, trim: Color, wheels: Array) -> Callable:
	var base := _livery(body, trim, wheels, 0.0)
	return func(t: float, a: float, p: Vector3, n: Vector3) -> Color:
		var c: Color = base.call(t, a, p, n)
		if c != body:
			return c
		if absf(fposmod(p.z + 2.4, 0.8) - 0.4) < 0.04:
			return trim
		return body.darkened(0.12) if p.y < 0.55 else body


## Rear wing: two end plates and a curved blade.
static func _wing(k: MeshKit, c: Vector3, span: float, chord: float, body: Color, trim: Color) -> void:
	k.box(c, Vector3(span, 0.06, chord), body)
	k.box(c + Vector3(0, 0.05, chord * 0.42), Vector3(span, 0.08, 0.06), trim)
	for s: float in [-1.0, 1.0]:
		k.box(c + Vector3(s * span * 0.5, -0.08, 0.02), Vector3(0.05, 0.32, chord + 0.08), trim)


## A dark side intake with slats.
static func _vent(k: MeshKit, c: Vector3, side: float, length: float, h: float) -> void:
	k.box(c, Vector3(0.04, h, length), ARCH)
	for i in 3:
		k.box(c + Vector3(side * 0.025, -h * 0.3 + i * h * 0.3, 0), Vector3(0.02, 0.025, length * 0.95), DARK)


## Headlights at the front (z = fz, height fy) and tail lights at the back.
static func _lights(k: MeshKit, fx: float, fz: float, fy: float, rz: float, ry: float) -> void:
	for s: float in [-1.0, 1.0]:
		if fz < 50.0:
			k.box(Vector3(s * fx, fy, fz), Vector3(0.34, 0.09, 0.06), HEAD, true, s * 0.12)
			k.box(Vector3(s * (fx - 0.06), fy - 0.09, fz + 0.02), Vector3(0.2, 0.04, 0.05), HEAD.darkened(0.2), true)
		k.box(Vector3(s * fx, ry, rz), Vector3(0.4, 0.07, 0.06), TAIL, true)
	k.box(Vector3(0, ry, rz + 0.01), Vector3(fx * 1.6, 0.025, 0.04), TAIL.darkened(0.3), true)


## A wheel: rounded tyre, painted rim with five spokes and a brake disc, or a hover pad.
static func _wheel(trim: Color, glow: Color, hover: bool) -> ArrayMesh:
	var k := MeshKit.new()
	if hover:
		k.paint = true
		k.cyl(Vector3(-0.16, 0, 0), Vector3(0.16, 0, 0), 0.38, 0.38, Props.BRASS, 20)
		k.paint = false
		k.ring(Vector3(0.17, 0, 0), Vector3(1, 0, 0), 0.26, 0.04, Props.COPPER, 18, 4)
		k.cyl(Vector3(0.16, 0, 0), Vector3(0.18, 0, 0), 0.2, 0.2, glow, 16, true)
		k.cyl(Vector3(0, -0.06, 0), Vector3(0, -0.12, 0), 0.34, 0.34, glow, 18, true)
		return k.commit()
	var tyre := Color(0.06, 0.06, 0.065)
	var r := WHEEL_R
	k.cyl(Vector3(-0.15, 0, 0), Vector3(0.15, 0, 0), r, r, tyre, 24, false, true, false)
	for s: float in [-1.0, 1.0]:
		k.ring(Vector3(s * 0.15, 0, 0), Vector3(1, 0, 0), r - 0.035, 0.035, tyre, 24, 4)
		k.cyl(Vector3(s * 0.07, 0, 0), Vector3(s * 0.1, 0, 0), r - 0.04, r - 0.04, Color(0.03, 0.03, 0.03), 24)
	var rim := trim.lerp(CHROME, 0.35)
	k.paint = true
	for s: float in [-1.0, 1.0]:
		k.ring(Vector3(s * 0.13, 0, 0), Vector3(1, 0, 0), 0.27, 0.025, rim, 24, 4)
		k.cyl(Vector3(s * 0.1, 0, 0), Vector3(s * 0.16, 0, 0), 0.08, 0.06, rim, 12)
		for i in 5:
			var a := TAU * i / 5.0
			var d := Vector3(0, cos(a), sin(a))
			k.cyl(Vector3(s * 0.14, 0, 0) + d * 0.06, Vector3(s * 0.12, 0, 0) + d * 0.26, 0.035, 0.025, rim, 6)
		k.paint = false
		k.cyl(Vector3(s * 0.11, 0, 0), Vector3(s * 0.115, 0, 0), 0.22, 0.22, Color(0.35, 0.35, 0.38), 18)
		k.paint = true
	k.paint = false
	return k.commit()
