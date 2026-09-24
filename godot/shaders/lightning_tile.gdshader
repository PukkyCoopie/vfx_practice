shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float time = 0.0;
uniform float tile_side = 109.5;
uniform float discharge = 0.0;
uniform vec2 drift = vec2(0.0);
uniform sampler2D letter_mask : filter_linear, repeat_disable;

// Visual reference: waw/shaders/ui_electric.gdshader (lightning in smoke).
// This field uses domain-warped noise for slow clouds and thin moving filaments.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float n = 0.0;
	float gain = 0.55;
	for (int i = 0; i < 3; i++) {
		n += noise(p) * gain;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(2.7, 5.1);
		gain *= 0.42;
	}
	return n;
}

float shape(vec2 p) {
	p = abs(p);
	return max(max(p.x, p.y) - 0.5, (p.x + p.y - 0.953) * 0.707107);
}

void fragment() {
	vec2 p = (UV - 0.5) * 3.0;
	float d = shape(p);
	float aa = 0.8 / tile_side;
	float cover = 1.0 - smoothstep(-aa, aa, d);
	if (d > 0.075) { discard; }
	vec2 q = p * 1.85 + vec2(time * 0.09, -time * 0.13) + drift * 0.10;
	vec2 warp = vec2(fbm(q + vec2(time * 0.10, 0.0)), fbm(q + vec2(7.3, -time * 0.11)));
	float cloud = fbm(q + warp * 2.2);
	float inner = fbm(q * 1.35 - warp * 1.7 + vec2(0.0, time * 0.18));
	float filament = exp(-abs(cloud - 0.45) * 80.0);
	float flow_gate = smoothstep(0.32, 0.61, inner);
	float electric = filament * flow_gate;
	vec3 color = mix(vec3(0.085, 0.018, 0.18), vec3(0.40, 0.10, 0.65), smoothstep(0.18, 0.66, cloud));
	color += vec3(0.22, 0.08, 0.32) * smoothstep(0.35, 0.68, inner) * cloud;
	color += vec3(0.62, 0.30, 0.95) * electric * 1.1;
	color += vec3(0.24, 0.10, 0.38) * discharge * cloud;
	float rim = exp(-abs(d + 0.015) * 160.0);
	float rim_charge = smoothstep(0.40, 0.75, noise(p * 7.0 + time * 0.85));
	color += vec3(0.46, 0.18, 0.78) * rim * (0.25 + rim_charge * 0.9);
	float glyph = texture(letter_mask, p + 0.5).a;
	float bevel = texture(letter_mask, p + 0.5 + vec2(0.0, -1.0 / tile_side)).a;
	color = mix(color, vec3(0.72, 0.46, 1.0), max(bevel - glyph, 0.0) * (0.5 + discharge * 0.4));
	color = mix(color, vec3(0.86, 0.78, 1.0) + vec3(0.10) * discharge, glyph * 0.96);
	float halo = exp(-max(d, 0.0) * 65.0) * 0.13;
	COLOR = vec4(mix(vec3(0.38, 0.10, 0.67), color, cover), max(cover, halo));
}
