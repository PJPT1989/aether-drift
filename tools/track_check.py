#!/usr/bin/env python3
"""Checks the track layouts in scripts/tracks.gd without starting Godot: lap length, tightest
bend, closest approach between parts of the lap that are not neighbours (so roads, walls and
scenery never overlap), steepest slope, and the straight at the start. Draws a map of each layout.

    python3 tools/track_check.py [out_dir]      maps go to /tmp/aether-maps by default

Mirrors Track._build_line (the "layout" driven a metre at a time, closed, resampled every
SPACING metres)."""
import math, re, sys, os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPACING = 2.0


def parse():
	src = open(os.path.join(ROOT, "scripts/tracks.gd")).read()
	tracks = []
	for block in re.split(r'\n\t\{\n', src)[1:]:
		name = re.search(r'"name": "([^"]+)"', block).group(1)
		width = float(re.search(r'"width": ([\d.]+)', block).group(1))
		lay = re.search(r'"layout": \[(.*?\])\],', block, re.S).group(1)
		cmds = [(k, *map(float, re.findall(r"[-\d.]+", rest))) for k, rest in re.findall(r'\["([SLR])", ([^\]]*)\]', lay)]
		hk = [tuple(map(float, m)) for m in re.findall(r"\[([\d.]+), ([-\d.]+)\]", re.search(r'"heights": \[(.*?)\]\],', block, re.S).group(0))]
		indoor = []
		m = re.search(r'"indoor": \[(.*?)\]\],', block, re.S)
		if m:
			for a, b in re.findall(r'\["[a-z_]+", ([\d.]+), ([\d.]+)', m.group(0)):
				indoor.append((float(a), float(b)))
		river = [tuple(map(float, v)) for v in re.findall(r"Vector3\(([-\d.]+), [-\d.]+, ([-\d.]+)\)", (re.search(r'"river": \[(.*?)\]', block) or re.match("()", "")).group(1))]
		rw = float((re.search(r'"river_width": ([\d.]+)', block) or re.match("()", "")).group(1) or 0)
		tracks.append((name, width, cmds, hk, indoor, river, rw))
	return tracks


def line(cmds, hk):
	"""Mirror of Track._build_line: drive the layout one metre at a time, close the loop, add heights,
	resample every SPACING metres."""
	x = z = h = 0.0
	dense = [(x, z)]
	for c in cmds:
		if c[0] == "S":
			k = max(1, math.ceil(c[1]))
			for i in range(k):
				x += math.cos(h) * c[1] / k
				z -= math.sin(h) * c[1] / k
				dense.append((x, z))
		else:
			r, ang = c[1], math.radians(c[2]) * (1 if c[0] == "L" else -1)
			k = max(1, math.ceil(r * abs(ang)))
			for i in range(k):
				h += ang / k * 0.5
				x += math.cos(h) * r * abs(ang) / k
				z -= math.sin(h) * r * abs(ang) / k
				h += ang / k * 0.5
				dense.append((x, z))
	cum = [0.0]
	for i in range(1, len(dense)):
		cum.append(cum[-1] + math.dist(dense[i - 1], dense[i]))
	total = cum[-1]
	ex, ez = dense[-1]
	keys = sorted(hk)
	keys = [(keys[-1][0] - 1.0, keys[-1][1])] + keys + [(keys[0][0] + 1.0, keys[0][1])]
	def height(f):
		for a, b in zip(keys, keys[1:]):
			if a[0] <= f <= b[0]:
				t = (f - a[0]) / max(b[0] - a[0], 1e-6)
				return a[1] + (b[1] - a[1]) * (1 - math.cos(t * math.pi)) * 0.5
		return keys[0][1]
	pts = [(p[0] - ex * c / total, height(c / total), p[1] - ez * c / total) for p, c in zip(dense[:-1], cum[:-1])]
	segs = [math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts))]
	total = sum(segs)
	n = int(total / SPACING)
	step = total / n
	P = []
	seg, start = 0, 0.0
	for i in range(n):
		want = i * step
		while want > start + segs[seg % len(pts)]:
			start += segs[seg % len(pts)]
			seg += 1
		f = (want - start) / max(segs[seg % len(pts)], 1e-4)
		a, b = pts[seg % len(pts)], pts[(seg + 1) % len(pts)]
		P.append(tuple(a[j] + (b[j] - a[j]) * f for j in range(3)))
	return P, total, (ex, ez), math.degrees(h)


def check(name, width, cmds, hk, indoor, river, rw, out):
	P, total, miss, net_turn = line(cmds, hk)
	n = len(P)
	# heading per sample, bend radius over 12 m
	hd = [math.atan2(P[(i + 1) % n][2] - P[i - 1][2], P[(i + 1) % n][0] - P[i - 1][0]) for i in range(n)]
	def turn(a, b):
		d = (hd[b % n] - hd[a % n] + math.pi) % (2 * math.pi) - math.pi
		return d
	radius = []
	for i in range(n):
		t = abs(turn(i - 3, i + 3))
		radius.append(12.0 / t if t > 1e-6 else 1e9)
	rmin = min(radius)
	rat = radius.index(rmin) * SPACING
	# closest approach between parts of the lap at least 200 m apart along it (hairpin legs,
	# neighbouring straights, crossings)
	gap = int(200 / SPACING)
	xz = np.array([(p[0], p[2]) for p in P])
	idx = np.arange(n)
	sep, where = 1e9, (0, 0)
	for i in range(0, n, 2):
		far = np.abs(idx - i)
		far = np.minimum(far, n - far) >= gap
		if not far.any():
			continue
		d = np.hypot(*(xz[far] - xz[i]).T)
		k = int(np.argmin(d))
		if d[k] < sep:
			sep, where = float(d[k]), (i, int(idx[far][k]))
	slope = max(abs(P[(i + 1) % n][1] - P[i][1]) / SPACING for i in range(n))
	climb = sum(max(0.0, P[(i + 1) % n][1] - P[i][1]) for i in range(n))
	ys = [p[1] for p in P]
	straight = 0
	while straight < n // 4 and abs(turn(-straight - 1, straight + 1)) < 0.06:
		straight += 1
	turns = sum(1 for i in range(0, n, 5) if radius[i] < 90 and radius[i - 5] >= 90)
	river_gap = 1e9
	for i in range(0, n, 3):
		for a, b in zip(river, river[1:]):
			ax, az, bx, bz = a[0], a[1], b[0], b[1]
			dx, dz = bx - ax, bz - az
			t = max(0.0, min(1.0, ((P[i][0] - ax) * dx + (P[i][2] - az) * dz) / (dx * dx + dz * dz)))
			river_gap = min(river_gap, math.hypot(P[i][0] - ax - dx * t, P[i][2] - az - dz * t) - rw * 0.5)
	print("%-28s %5.0f m  bends<90m %2d  tightest r %4.0f m (at %4.0f m)  closest other part %4.0f m (at %4.0f/%4.0f m)  slope %3.0f%%  heights %3.0f-%3.0f m, %4.0f m climbing  start straight +-%3.0f m  loop gap %3.0f m, turn %4.0f deg%s"
		% (name, total, turns, rmin, rat, sep, where[0] * SPACING, where[1] * SPACING, slope * 100, min(ys), max(ys), climb, straight * SPACING,
		math.hypot(*miss), net_turn, "  river %3.0f m away" % river_gap if river else ""))
	# map
	xs = [p[0] for p in P]
	zs = [p[2] for p in P]
	lo_x, hi_x, lo_z, hi_z = min(xs) - 60, max(xs) + 60, min(zs) - 60, max(zs) + 60
	sc = 900 / max(hi_x - lo_x, hi_z - lo_z)
	img = Image.new("RGB", (int((hi_x - lo_x) * sc) + 1, int((hi_z - lo_z) * sc) + 1), (20, 20, 30))
	dr = ImageDraw.Draw(img)
	xy = lambda p: ((p[0] - lo_x) * sc, (p[2] - lo_z) * sc)
	for a, b in zip(river, river[1:]):
		dr.line([xy((a[0], 0, a[1])), xy((b[0], 0, b[1]))], fill=(30, 70, 140), width=max(2, int(rw * sc)))
	ys = [p[1] for p in P]
	for i in range(n):
		f = i / n
		inside = any(a <= f <= b for a, b in indoor)
		h = (P[i][1] - min(ys)) / max(max(ys) - min(ys), 1)
		col = (90, 90, 110) if inside else (int(80 + 175 * h), int(200 - 60 * h), 255 - int(155 * h))
		dr.line([xy(P[i]), xy(P[(i + 1) % n])], fill=col, width=max(2, int(width * sc)))
	for i in range(0, n, int(250 / SPACING)):
		dr.text(xy(P[i]), "%d" % (i * SPACING), fill=(255, 255, 255))
	dr.ellipse([xy(P[0])[0] - 6, xy(P[0])[1] - 6, xy(P[0])[0] + 6, xy(P[0])[1] + 6], fill=(255, 60, 60))
	dr.line([xy(P[0]), xy(P[6])], fill=(255, 60, 60), width=3)
	img.save(os.path.join(out, re.sub(r"\W+", "_", name.lower()) + ".png"))


if __name__ == "__main__":
	out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/aether-maps"
	os.makedirs(out, exist_ok=True)
	for t in parse():
		check(*t, out)
	print("maps in", out)
