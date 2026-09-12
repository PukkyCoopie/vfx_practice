shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

uniform vec4 color_center : source_color = vec4(0.72, 0.92, 1.0, 1.0);
uniform vec4 color_edge : source_color = vec4(0.28, 0.62, 0.95, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 0.85;
uniform float overall_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float noise_amount : hint_range(0.0, 1.5) = 0.55;
uniform float distort_speed : hint_range(0.0, 2.0) = 0.35;
uniform float oval_x : hint_range(0.5, 2.0) = 0.85;
uniform float oval_z : hint_range(0.5, 2.5) = 1.35;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise21(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	vec2 distort = vec2(
		fbm(uv * 3.5 + TIME * distort_speed),
		fbm(uv * 3.5 + vec2(2.7, 1.1) - TIME * distort_speed * 0.8)
	);
	uv += (distort - 0.5) * noise_amount * 0.22;

	float r = length(vec2(uv.x / oval_x, uv.y / oval_z));
	float edge_noise = fbm(uv * 5.5 + TIME * 0.12) * 0.18;
	float radial = 1.0 - smoothstep(0.18, 0.92 + edge_noise, r);
	radial = pow(clamp(radial, 0.0, 1.0), 1.55);

	float a = radial * intensity * overall_intensity * COLOR.a;
	if (a < 0.003) {
		discard;
	}
	vec3 col = mix(color_edge.rgb, color_center.rgb, radial);
	ALBEDO = col * a;
	ALPHA = a;
}
