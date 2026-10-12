shader_type sky;
// Painted sky for each track: three-colour gradient, sun or moon, stars, aether ribbons
// (aurora-like streams of aether) and, over the primordial jungle, a shattered moon.

uniform vec3 top_color : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.85, 0.9);
uniform vec3 ground_color : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 sun_dir = vec3(0.0, 0.5, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float sun_disc = 1.0;
uniform vec3 moon_dir = vec3(0.3, 0.45, -1.0);
uniform vec3 moon_color : source_color = vec3(0.0);
uniform float stars = 0.0;
uniform vec4 aurora = vec4(0.0);
uniform float shattered = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = h > 0.0 ? mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55)) : mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	vec3 sd = normalize(sun_dir);
	float sa = max(dot(d, sd), 0.0);
	col += sun_color * (pow(sa, 8.0) * 0.35 + pow(sa, 64.0) * 0.4) * (0.4 + sun_disc * 0.6);
	col += sun_color * smoothstep(0.9992, 0.9996, sa) * sun_disc * 2.5;
	if (h > 0.0) {
		vec2 sp = d.xz / (h + 0.25);
		// stars
		if (stars > 0.0) {
			vec2 g = floor(sp * 140.0);
			float s = hash(g);
			float tw = smoothstep(0.985, 1.0, s) * smoothstep(0.0, 0.25, h);
			col += vec3(0.85, 0.9, 1.0) * tw * stars * 1.4;
		}
		// aether ribbons
		if (aurora.a > 0.0) {
			float band = noise(vec2(sp.x * 1.3, sp.y * 0.35) + vec2(3.0, 1.0));
			float wave = sin(sp.x * 3.0 + band * 6.0) * 0.5 + 0.5;
			float r = smoothstep(0.55, 0.95, wave) * smoothstep(0.05, 0.3, h) * smoothstep(0.9, 0.4, h);
			col += aurora.rgb * r * aurora.a * (0.6 + 0.4 * noise(sp * 4.0));
		}
		// clouds (soft, very light)
		float cl = noise(sp * 1.6 + vec2(7.0, 2.0)) * 0.6 + noise(sp * 4.0) * 0.4;
		col = mix(col, mix(horizon_color, vec3(1.0), 0.35), smoothstep(0.55, 0.9, cl) * 0.35 * smoothstep(0.0, 0.2, h));
	}
	// moon, possibly cracked into pieces
	if (moon_color.r + moon_color.g + moon_color.b > 0.0) {
		vec3 md = normalize(moon_dir);
		float ma = dot(d, md);
		float rad = shattered > 0.0 ? 0.9975 : 0.9985;
		float m = smoothstep(rad, rad + 0.0004, ma);
		if (shattered > 0.0) {
			vec3 side = normalize(cross(md, vec3(0, 1, 0)));
			vec3 up = cross(side, md);
			vec2 uv = vec2(dot(d, side), dot(d, up)) * 40.0;
			float crack = abs(sin(uv.x * 3.0 + uv.y * 1.5)) * abs(sin(uv.y * 2.5 - uv.x));
			m *= smoothstep(0.02, 0.12, crack);
		}
		col = mix(col, moon_color * (0.85 + 0.15 * noise(d.xy * 300.0)), m);
		col += moon_color * pow(max(ma, 0.0), 300.0) * 0.25;
	}
	COLOR = col;
}
