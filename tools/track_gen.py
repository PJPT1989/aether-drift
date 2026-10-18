#!/usr/bin/env python3
"""Generates the long track layouts in scripts/tracks.gd: a drive of straights and bends that
loosely follows a big closed outline, with twisty features (esses, chicanes, switchbacks, city
blocks, sweepers) chosen in each track's style, several curving indoor stretches, height keys
and (for the river track) the river beside the start. Every layout keeps its parts apart (walls,
tunnel hills and scenery never overlap) and closes exactly on the start line.

    python3 tools/track_gen.py            print what each track would get
    python3 tools/track_gen.py --write    rewrite "layout", "heights", "indoor" (and "river")
                                          in scripts/tracks.gd
    python3 tools/track_gen.py --only=2   one track

Change a track's STYLES entry (or its seed) and run it again; then `python3 tools/track_check.py`
and the sim test."""
import math, os, random, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAU = math.tau

# Per track, in race order. length: metres; outline: half sizes of the loop the drive follows;
# limit: walls from the centre line (Track.limit); feats: feature weights; r: bend radius range;
# s: straight range; tunnels: indoor styles, in order; tr: bend radius range inside them;
# h: height range and how many metres between height keys.
STYLES = [
	{"seed": 11, "length": 12500, "outline": (1150, 800), "limit": 14.9, "start": 330, "close_r": 45,
		"feats": {"block": 4, "corner": 3, "hairpin": 1.2, "chicane": 1.5, "straight": 2},
		"r": (30, 60), "s": (70, 240), "snap": 90, "tunnels": ["foundry", "conduit", "foundry"], "tr": (60, 90),
		"h": (0, 10, 900)},
	{"seed": 22, "length": 13500, "outline": (1300, 900), "limit": 12.8, "start": 300, "close_r": 90,
		"feats": {"esses": 4, "sweep": 3, "hairpin": 1.2, "corner": 1.5, "straight": 1.5},
		"r": (60, 150), "s": (80, 300), "snap": 0, "tunnels": ["cave", "cave", "cave"], "tr": (70, 120),
		"h": (0, 30, 800)},
	{"seed": 33, "length": 13000, "outline": (1250, 850), "limit": 13.3, "start": 400, "close_r": 60,
		"feats": {"chicane": 3.5, "esses": 2.5, "corner": 2, "hairpin": 1.3, "straight": 1.5},
		"r": (40, 90), "s": (60, 240), "snap": 0, "tunnels": ["temple", "cave", "temple"], "tr": (65, 100),
		"h": (0, 6, 1000), "river": 80.0},
	{"seed": 44, "length": 12000, "outline": (1100, 800), "limit": 8.9, "start": 240, "close_r": 55,
		"feats": {"esses": 4, "corner": 2.5, "chicane": 2, "hairpin": 1.2, "straight": 1},
		"r": (38, 85), "s": (50, 200), "snap": 0, "tunnels": ["hollow", "hollow", "hollow", "hollow"], "tr": (55, 85),
		"h": (18, 38, 700)},
	{"seed": 55, "length": 15500, "outline": (1550, 1050), "limit": 24.3, "start": 320, "close_r": 120,
		"feats": {"sweep": 4, "esses": 2.5, "hairpin": 1, "corner": 1.5, "straight": 2.5},
		"r": (90, 200), "s": (120, 380), "snap": 0, "tunnels": ["tomb", "cave", "tomb"], "tr": (90, 150),
		"h": (2, 26, 900)},
	{"seed": 66, "length": 12000, "outline": (1100, 780), "limit": 13.8, "start": 320, "close_r": 45,
		"feats": {"hairpin": 2, "chicane": 3, "block": 2.5, "corner": 2, "esses": 1.5, "straight": 1},
		"r": (30, 60), "s": (60, 200), "snap": 45, "tunnels": ["conduit", "foundry", "conduit"], "tr": (55, 85),
		"h": (0, 12, 900)},
]

STEP = 2.0          # metres between checked points (Track.SPACING)
NEAR = 200.0        # parts of the lap closer than this along it are neighbours, not checked
MARGIN = 8.0        # extra room beyond the walls on each side of a part of the road
HILL = 32.0         # extra room round an indoor stretch (its hill, hall or trunk)
CELL = 60.0


def wrap(a):
	return (a + math.pi) % TAU - math.pi


class Drive:
	"""Turtle in (X, Y) = (x, -z): heading 0 is +x, L turns raise the heading (counter-clockwise)."""
	def __init__(self, limit):
		self.x = self.y = self.h = 0.0
		self.d = 0.0
		self.cmds = []
		self.pts = []        # (x, y, keep-out radius, distance)
		self.grid = {}
		self.limit = limit
		self.tunnels = []    # (style, from m, to m)

	def trace(self, cmds, x, y, h, d):
		"""Points every STEP metres along `cmds` from the given state, and the end state."""
		out = []
		acc = 0.0
		for c in cmds:
			if c[0] == "S":
				k = max(1, math.ceil(c[1]))
				for _ in range(k):
					x += math.cos(h) * c[1] / k
					y += math.sin(h) * c[1] / k
					acc += c[1] / k
					if acc >= STEP:
						acc -= STEP
						out.append((x, y, d))
					d += c[1] / k
			else:
				r, ang = c[1], math.radians(c[2]) * (1 if c[0] == "L" else -1)
				arc = r * abs(ang)
				k = max(1, math.ceil(arc))
				for _ in range(k):
					h += ang / k * 0.5
					x += math.cos(h) * arc / k
					y += math.sin(h) * arc / k
					h += ang / k * 0.5
					acc += arc / k
					if acc >= STEP:
						acc -= STEP
						out.append((x, y, d))
					d += arc / k
		return out, (x, y, h, d)

	def clear(self, pts, keep, total=None):
		"""True if none of `pts` comes too close to a part of the lap more than NEAR metres away along
		it (with `total`, the lap length, the start counts as just after the end)."""
		own = {}
		for (x, y, d) in pts:
			cx, cy = int(math.floor(x / CELL)), int(math.floor(y / CELL))
			for gx in range(cx - 1, cx + 2):
				for gy in range(cy - 1, cy + 2):
					for src in (self.grid.get((gx, gy), ()), own.get((gx, gy), ())):
						for (px, py, pk, pd) in src:
							if d - pd < NEAR or (total is not None and total - (d - pd) < NEAR):
								continue
							if (px - x) ** 2 + (py - y) ** 2 < (pk + keep) ** 2:
								return False
			own.setdefault((cx, cy), []).append((x, y, keep, d))
		return True

	def try_add(self, cmds, keep=None, total=None):
		keep = keep or self.limit + MARGIN
		pts, end = self.trace(cmds, self.x, self.y, self.h, self.d)
		if total is not None and abs(end[3] - total) > 0.01 * total:
			return False
		if not self.clear(pts, keep, end[3] if total is not None else None):
			return False
		for (x, y, d) in pts:
			self.grid.setdefault((int(math.floor(x / CELL)), int(math.floor(y / CELL))), []).append((x, y, keep, d))
		self.pts += [(x, y, keep, d) for (x, y, d) in pts]
		self.x, self.y, self.h, self.d = end
		self.cmds += cmds
		return True


def outline(st, rng):
	"""Closed loop through the start, counter-clockwise, as points by distance."""
	a, b = st["outline"]
	wob = [(k, rng.uniform(0.06, 0.16) * (1 if rng.random() < 0.5 else -1)) for k in (2, 3, 4)]
	pts = []
	for q in range(721):
		t = TAU * q / 720
		m = 1.0 + sum(w * math.sin(k * t) for k, w in wob)
		pts.append((a * math.sin(t) * m, b - b * math.cos(t) * m))
	cum = [0.0]
	for p, q in zip(pts, pts[1:]):
		cum.append(cum[-1] + math.dist(p, q))
	return pts, cum


def at(ol, f):
	pts, cum = ol
	want = (f % 1.0) * cum[-1]
	for i in range(1, len(cum)):
		if cum[i] >= want:
			t = (want - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-6)
			return (pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t)
	return pts[-1]


def bend(turn_deg, r):
	"""One bend turning `turn_deg` (positive left)."""
	return ["L" if turn_deg > 0 else "R", round(r), round(abs(turn_deg), 1)]


def feature(kind, st, rng, err):
	"""Commands for one feature; `err` (degrees, positive left) is how far the drive should turn
	to get back on course, worked into the feature's net turn."""
	r0, r1 = st["r"]
	s0, s1 = st["s"]
	R = lambda: rng.uniform(r0, r1)
	S = lambda: ["S", round(rng.uniform(s0, s1))]
	side = 1 if rng.random() < 0.5 else -1
	snap = st["snap"]
	if kind == "straight":
		return [["S", round(rng.uniform(s0, s1) * 1.3)]]
	if kind == "corner":
		a = err + rng.uniform(-30, 30)
		if snap:
			a = snap * round(a / snap) or snap * side
		a = max(-120, min(120, a)) or 45
		return [S(), bend(a, R())]
	if kind == "block":
		# a city block: turn, short street, turn back (a jog sideways)
		r = rng.uniform(r0, r0 + 15)
		a = 90 * side
		return [S(), bend(a, r), ["S", round(rng.uniform(40, 120))], bend(-a + (90 * round(err / 90) if abs(err) > 60 else 0), r)]
	if kind == "esses":
		a = rng.uniform(35, 75)
		r = R()
		return [S(), bend(side * a + err * 0.5, r), bend(-side * a * 2, r), bend(side * a + err * 0.5, r)]
	if kind == "chicane":
		a = rng.uniform(30, 50)
		r = rng.uniform(r0, (r0 + r1) / 2)
		return [S(), bend(side * a + err * 0.4, r), ["S", round(rng.uniform(15, 40))], bend(-side * a * 2, r), ["S", round(rng.uniform(15, 40))], bend(side * a + err * 0.4, r)]
	if kind == "hairpin":
		# a switchback: out, round a hairpin, back past, round the other way
		r = max(r0, rng.uniform(r0, r0 + 20), st["limit"] + MARGIN + 2)
		leg = rng.uniform(s0 * 1.2, s1)
		a = rng.uniform(150, 180)
		return [S(), bend(side * 90, R()), ["S", round(leg * 0.6)], bend(-side * a, r), ["S", round(leg)], bend(side * (a - 90) + err, r)]
	if kind == "sweep":
		a = rng.uniform(30, 70)
		r = rng.uniform(r1, r1 * 1.6)
		return [S(), bend(side * a + err * 0.6, r), ["S", round(rng.uniform(30, 120))], bend(-side * a * 0.7 + err * 0.4, r)]
	raise ValueError(kind)


def tunnel(st, rng, err):
	"""A curving indoor stretch: straight mouth, two to four bends, straight mouth."""
	t0, t1 = st["tr"]
	cmds = [["S", 60]]
	side = 1 if rng.random() < 0.5 else -1
	nb = rng.choice([3, 4, 4, 5])
	for q in range(nb):
		a = rng.uniform(35, 80)
		cmds.append(bend(side * a + err / nb, rng.uniform(t0, t1)))
		if rng.random() < 0.7:
			cmds.append(["S", round(rng.uniform(30, 120))])
		if rng.random() < 0.75:
			side = -side
	cmds.append(["S", 60])
	return cmds


def dubins(x0, y0, h0, x1, y1, h1, r):
	"""Bend, straight, bend from one pose to another (all four words): [(turn1, straight, turn2)]
	with turns in radians, positive left."""
	out = []
	for w in ("LSL", "RSR", "LSR", "RSL"):
		s0 = 1 if w[0] == "L" else -1
		s1 = 1 if w[2] == "L" else -1
		c0 = (x0 - s0 * r * math.sin(h0), y0 + s0 * r * math.cos(h0))
		c1 = (x1 - s1 * r * math.sin(h1), y1 + s1 * r * math.cos(h1))
		dx, dy = c1[0] - c0[0], c1[1] - c0[1]
		D = math.hypot(dx, dy)
		al = math.atan2(dy, dx)
		if s0 == s1:
			phi, L = al, D
		else:
			if D < 2 * r:
				continue
			phi = al + math.asin(2 * r / D) * s0
			L = math.sqrt(D * D - 4 * r * r)
		t1 = ((phi - h0) % TAU) if s0 > 0 else -((h0 - phi) % TAU)
		t2 = ((h1 - phi) % TAU) if s1 > 0 else -((phi - h1) % TAU)
		out.append((t1, L, t2))
	return out


def generate(st, attempt):
	rng = random.Random(st["seed"] * 1000 + attempt)
	ol = outline(st, rng)
	L = st["length"]
	dr = Drive(st["limit"])
	if not dr.try_add([["S", st["start"]]]):
		return None
	plan = [(f, k) for f, k in zip([(q + 0.6) / len(st["tunnels"]) * 0.92 + 0.02 for q in range(len(st["tunnels"]))], st["tunnels"])]
	feats = list(st["feats"].items())
	fails = 0
	prog = 0.0
	per = ol[1][-1]
	while True:
		f = dr.d / L
		prog = project(ol, dr.x, dr.y, prog)
		if f > 1.1 or (prog > 0.9 and plan):
			return None
		if prog > 0.9:
			# try to close: bend, straight, bend onto the main straight behind the start line
			for back in (st["start"] * 0.4, st["start"] * 0.6, 120.0, 200.0):
				for rr in (st["close_r"], st["close_r"] * 1.5, st["close_r"] * 2.2):
					for t1, s, t2 in sorted(dubins(dr.x, dr.y, dr.h, -back, 0.0, 0.0, rr), key=lambda c: abs(c[0]) + abs(c[2])):
						if abs(dr.h + t1 + t2 - TAU) > 1e-3 or s < 30 or s > 650:
							continue
						cmds = [bend(math.degrees(t1), rr), ["S", round(s, 1)], bend(math.degrees(t2), rr), ["S", round(back, 1)]]
						cmds = [c for c in cmds if c[0] == "S" and c[1] > 0.5 or c[0] != "S" and c[2] > 0.05]
						_, end = dr.trace(cmds, dr.x, dr.y, dr.h, dr.d)
						if abs(end[3] - L) < L * 0.06 and dr.try_add(cmds, total=end[3]):
							return dr, ol
		# steer for a point on the outline a little ahead of where we are along it
		tx, ty = at(ol, prog + 250.0 / per)
		gx, gy = at(ol, prog)
		off = math.hypot(gx - dr.x, gy - dr.y)
		err = math.degrees(wrap(math.atan2(ty - dr.y, tx - dr.x) - dr.h))
		lag = f - prog   # > 0: used up more of the lap's length than the outline allows for
		if plan and prog >= plan[0][0] and abs(err) < 70:
			start = dr.d
			cmds = tunnel(st, rng, err)
			if dr.try_add(cmds, keep=st["limit"] + MARGIN + HILL):
				dr.tunnels.append((plan[0][1], start + 25, dr.d - 25))
				plan.pop(0)
				fails = 0
				continue
			fails += 1
			if fails % 5:
				continue
		if off > 300 or lag > 0.04 or abs(err) > 100:
			# off course or running out of lap: head on along the outline
			if abs(err) > 25:
				cmds = [bend(max(-150, min(150, err)), rng.uniform(*st["r"]))]
			else:
				cmds = [bend(err, st["r"][1]), ["S", round(rng.uniform(80, 200))]]
		else:
			tot = sum(w for _, w in feats)
			pick = rng.uniform(0, tot)
			for kind, w in feats:
				pick -= w
				if pick <= 0:
					break
			cmds = feature(kind, st, rng, err)
		if dr.try_add(cmds):
			fails = 0
		else:
			fails += 1
			if fails > 80:
				return None


def project(ol, x, y, f0):
	"""How far round the outline (0..1) the point nearest to (x, y) is, searching forward from f0."""
	pts, cum = ol
	m = len(pts) - 1
	i0 = int(f0 * m)
	best, bi = 1e18, i0
	for i in range(max(0, i0 - 10), min(m, i0 + 110)):
		d = (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2
		if d < best:
			best, bi = d, i
	return max(f0, cum[bi] / cum[-1])


def heights(st, rng, total, tunnels):
	lo, hi, every = st["h"]
	keys = [(0.0, round(lo + (hi - lo) * 0.2, 1))]
	d = every
	while d < total - every * 0.8:
		y = rng.uniform(lo, hi) if len(keys) % 2 else rng.uniform(lo, (lo + hi) * 0.5)
		keys.append((round(d / total, 3), round(y, 1)))
		d += every * rng.uniform(0.8, 1.2)
	return keys


def river(st, dr):
	"""A river along the outside of the main straight: x from far left to far right, kept clear of
	every part of the road."""
	w = st["river"]
	xs = [p[0] for p in dr.pts]
	pts = []
	for x in range(int(min(xs)) - 900, int(max(xs)) + 901, 150):
		# lowest Y (largest z) of the road near this x, the river runs beyond it
		near = [p[1] for p in dr.pts if abs(p[0] - x) < 260]
		y = min(near) if near else 0.0
		pts.append([x, y - st["limit"] - w * 0.5 - 45.0])
	# smooth, and never closer than before smoothing
	for _ in range(3):
		pts = [pts[0]] + [[p[0], min(p[1], (a[1] + p[1] * 2 + b[1]) / 4)] for a, p, b in zip(pts, pts[1:], pts[2:])] + [pts[-1]]
	return [(x, round(-y)) for x, y in pts]


def fmt_layout(cmds):
	merged = []
	for c in cmds:
		if c[0] == "S" and merged and merged[-1][0] == "S":
			merged[-1] = ["S", merged[-1][1] + c[1]]
		else:
			merged.append(c)
	parts = []
	for c in merged:
		if c[0] == "S":
			parts.append('["S", %g]' % round(c[1], 1))
		else:
			parts.append('["%s", %g, %g]' % (c[0], round(c[1]), round(c[2], 2)))
	lines = []
	for q in range(0, len(parts), 8):
		lines.append(", ".join(parts[q:q + 8]))
	return "[" + ",\n\t\t\t".join(lines) + "]"


def score(dr):
	"""Higher is better: many bends, no long straights away from the start."""
	longest = 0.0
	run = 0.0
	for c in dr.cmds[1:-2]:
		run = run + c[1] if c[0] == "S" else 0.0
		longest = max(longest, run)
	bends = sum(1 for c in dr.cmds if c[0] != "S" and c[2] > 15)
	return bends / dr.d * 1000.0 - max(0.0, longest - 300.0) / 100.0


def build(ti, st):
	found = []
	for attempt in range(3000):
		res = generate(st, attempt)
		if res:
			found.append((score(res[0]), attempt, res))
			if len(found) == 8:
				break
	if not found:
		raise SystemExit("track %d: no layout found" % ti)
	sc, attempt, (dr, ol) = max(found, key=lambda t: t[0])
	rng = random.Random(st["seed"] + 7)
	total = dr.d
	out = {
		"layout": fmt_layout(dr.cmds),
		"heights": "[" + ", ".join("[%g, %g]" % k for k in heights(st, rng, total, dr.tunnels)) + "]",
		"indoor": "[" + ", ".join('["%s", %.3f, %.3f]' % (k, a / total, b / total) for k, a, b in dr.tunnels) + "]",
	}
	if "river" in st:
		out["river"] = "[" + ", ".join("Vector3(%d, 0, %d)" % p for p in river(st, dr)) + "]"
	print("track %d: %.0f m, %d commands, attempt %d, score %.1f, tunnels %s" % (ti, total, len(dr.cmds), attempt, sc,
		", ".join("%s %.0f-%.0f m" % t for t in dr.tunnels)))
	return out


def write(results):
	path = os.path.join(ROOT, "scripts/tracks.gd")
	src = open(path).read()
	blocks = re.split(r'(\n\t\{\n)', src)
	# blocks: [head, sep, track 0, sep, track 1, ...]
	for ti, out in results.items():
		b = blocks[2 + ti * 2]
		for key, val in out.items():
			pat = r'"river": \[.*?\],' if key == "river" else r'"%s": \[.*?\]\],' % key
			b, k = re.subn(pat, lambda m: '"%s": %s,' % (key, val), b, count=1, flags=re.S)
			if not k:
				raise SystemExit("track %d: no %s entry" % (ti, key))
		blocks[2 + ti * 2] = b
	open(path, "w").write("".join(blocks))
	print("wrote", path)


if __name__ == "__main__":
	only = [int(a.split("=")[1]) for a in sys.argv[1:] if a.startswith("--only=")]
	results = {}
	for ti, st in enumerate(STYLES):
		if only and ti not in only:
			continue
		results[ti] = build(ti, st)
	if "--write" in sys.argv:
		write(results)
	else:
		for ti, out in results.items():
			print(ti, out)
