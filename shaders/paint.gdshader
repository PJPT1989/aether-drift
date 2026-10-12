shader_type spatial;
// Glossy car paint and glass: vertex colour, a sharp sun highlight and a cheap reflection of
// the track's sky (its three gradient colours, set per track), stronger at grazing angles.

uniform vec3 sky_top : source_color = vec3(0.2, 0.3, 0.6);
uniform vec3 sky_horizon : source_color = vec3(0.7, 0.75, 0.85);
uniform vec3 sky_ground : source_color = vec3(0.2, 0.2, 0.2);
uniform float reflect_strength = 0.55;

void fragment() {
	ALBEDO = COLOR.rgb;
	// dark colours (glass, black trim) read as glossier
	float dark = 1.0 - clamp(dot(COLOR.rgb, vec3(0.33)) * 2.0, 0.0, 1.0);
	ROUGHNESS = mix(0.32, 0.12, dark);
	METALLIC = 0.25;
	SPECULAR = 0.75;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 env = r.y > 0.0 ? mix(sky_horizon, sky_top, sqrt(r.y)) : mix(sky_horizon, sky_ground, sqrt(-r.y) * 1.5);
	float fres = 0.12 + 0.88 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
	EMISSION = env * fres * reflect_strength * mix(0.6, 1.2, dark);
}
