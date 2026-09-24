shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float time = 0.0;
uniform vec2 slosh = vec2(0.0);
uniform vec2 trail = vec2(0.0);
uniform float tile_side = 109.5;
uniform sampler2D letter_mask : filter_linear, repeat_disable;

float shape(vec2 p) {
	p = abs(p);
	return max(max(p.x, p.y) - 0.5, (p.x + p.y - 0.953) * 0.707107);
}

float waves(vec2 p) {
	return sin(p.x * 13.0 + p.y * 7.0 - time * 1.5) * 0.45
		+ sin(p.y * 17.0 - p.x * 5.0 + time * 1.1) * 0.30
		+ sin(p.x * 24.0 + sin(p.y * 12.0 + time) * 1.5 + time * 0.8) * 0.15;
}

void fragment() {
	vec2 p = (UV - 0.5) * 3.0;
	vec2 q = p - slosh * smoothstep(0.15, 0.60, length(p));
	// Stretch only the trailing membrane; the central glyph stays anchored.
	float trailing = clamp(dot(q, normalize(trail + vec2(0.00001))), 0.0, 0.65);
	q -= trail * trailing * trailing * 0.6;
	float edge_wave = sin(q.x * 20.0 + time * 2.0) * sin(q.y * 17.0 - time * 1.6);
	float d = shape(q) + edge_wave * 0.009;
	float aa = 1.0 / tile_side;
	float mask = 1.0 - smoothstep(-aa, aa, d);
	vec2 flow = q - slosh * 1.8;
	float h = waves(flow);
	vec2 gradient = vec2(waves(flow + vec2(0.006, 0.0)) - h,
		waves(flow + vec2(0.0, 0.006)) - h) / 0.006;
	vec3 normal = normalize(vec3(-gradient * 0.075, 1.0));
	float reflection = pow(max(dot(normal, normalize(vec3(-0.45, -0.6, 1.0))), 0.0), 15.0);
	float depth = smoothstep(0.0, 0.14, -d);
	vec3 color = mix(vec3(0.015, 0.24, 0.43), vec3(0.025, 0.57, 0.73), depth);
	color += vec3(0.02, 0.09, 0.10) * h;
	float caustic = pow(max(1.0 - abs(sin(flow.x * 12.0 + sin(flow.y * 10.0 + time * 0.7))
		+ sin(flow.y * 13.0 - time * 0.8 + sin(flow.x * 8.0))) * 0.7, 0.0), 9.0);
	color += vec3(0.13, 0.32, 0.29) * caustic * depth * 0.36;
	float rim = exp(-abs(d + 0.021) * 130.0);
	float rim_light = 0.40 + 0.60 * smoothstep(-0.8, 0.8, sin(q.x * 9.0 + q.y * 6.0 + time));
	color = mix(color, vec3(0.54, 0.94, 0.98), rim * rim_light * 0.85);
	vec2 glyph_uv = p + 0.5 + gradient * 0.00035;
	// Three broad, faint bubbles rise inside the water, below the letter layer.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float age = fract(time * 0.21 + fi * 0.3333);
		vec2 center = vec2(sin(fi * 4.3 + 1.2) * 0.30 + sin(time * 1.3 + fi) * 0.025, mix(0.39, -0.44, age));
		float radius = 0.026 + fi * 0.007;
		float ring = 1.0 - smoothstep(0.004, 0.004 + aa, abs(length(flow - center) - radius));
		float fade = smoothstep(0.0, 0.16, age) * (1.0 - smoothstep(0.80, 1.0, age));
		color = mix(color, vec3(0.66, 0.94, 1.0), ring * fade * 0.36);
	}
	float glyph = texture(letter_mask, glyph_uv).a;
	float glyph_edge = texture(letter_mask, glyph_uv - vec2(0.0, aa)).a;
	color = mix(color, vec3(0.52, 0.88, 0.91), max(glyph_edge - glyph, 0.0) * 0.8);
	color = mix(color, vec3(0.015, 0.15, 0.24), glyph * 0.94);
	color += vec3(0.47, 0.69, 0.70) * reflection * mix(0.65, 0.12, glyph);
	COLOR = vec4(color, mask * 0.96);
}
