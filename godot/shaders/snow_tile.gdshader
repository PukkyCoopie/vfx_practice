shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float time = 0.0;
uniform vec2 wind = vec2(0.0);
uniform vec2 powder_offset = vec2(0.0);
uniform float tile_side = 109.5;
uniform sampler2D letter_mask : filter_linear, repeat_disable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float shape(vec2 p) {
	vec2 q = abs(p) - vec2(0.435);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.065;
}

void fragment() {
	vec2 p = (UV - 0.5) * 3.0;
	float aa = 1.0 / tile_side;
	float grain = noise(p * 95.0);
	float d = shape(p) + (noise(p * 31.0) - 0.5) * 0.012;
	float mask = 1.0 - smoothstep(-aa, aa, d);
	float depth = smoothstep(0.0, 0.045, -d);
	float dune = noise(p * 4.0 + vec2(3.0, 8.0));
	// Opaque powder with broad, soft shading rather than a glassy bevel or cap seam.
	vec3 color = mix(vec3(0.72, 0.79, 0.83), vec3(0.90, 0.93, 0.94), depth);
	color += (dune - 0.5) * 0.12;
	color += (noise(p * 15.0) - 0.5) * 0.035;
	color += (grain - 0.5) * 0.075;
	float glyph = texture(letter_mask, p + 0.5).a;
	float lip = texture(letter_mask, p + 0.5 - vec2(0.0, aa * 1.5)).a;
	color = mix(color, vec3(1.0), max(lip - glyph, 0.0));
	color = mix(color, vec3(0.24, 0.43, 0.55) + dune * 0.05, glyph);
	// Discrete sunlit crystals: fixed locations, independent brief glints.
	vec2 grid = p * 19.0;
	vec2 cell = floor(grid);
	float seed = hash(cell);
	vec2 center = vec2(0.22) + vec2(hash(cell + 7.0), hash(cell + 23.0)) * 0.56;
	vec2 crystal = (fract(grid) - center) / 19.0;
	float pulse = pow(max(sin(time * (1.3 + seed * 1.4) + seed * 91.0), 0.0), 18.0);
	float selected = step(0.81, seed) * pulse;
	float glint_aa = max(aa, 1.0 / 109.5);
	float core = exp(-dot(crystal, crystal) / (glint_aa * glint_aa * 0.48));
	float rays = exp(-abs(crystal.x) / (glint_aa * 0.28) - abs(crystal.y) / (glint_aa * 2.7))
		+ exp(-abs(crystal.y) / (glint_aa * 0.28) - abs(crystal.x) / (glint_aa * 2.7));
	float glint = selected * (core + rays * 0.45) * (1.0 - glyph) * depth;
	// A faint cool surround lets the white pinpoints read against white powder.
	float surround = exp(-dot(crystal, crystal) / (glint_aa * glint_aa * 9.0));
	color -= vec3(0.13, 0.10, 0.06) * selected * surround * (1.0 - glyph) * depth;
	color = mix(color, vec3(1.0, 0.995, 0.96), clamp(glint * 2.5, 0.0, 1.0));
	float powder = noise(p * 11.0 - powder_offset + vec2(time * 0.12, 0.0));
	float halo = exp(-max(d, 0.0) * 24.0) * smoothstep(-0.01, 0.025, d)
		* (0.08 + 0.14 * length(wind)) * powder;
	COLOR = vec4(mix(vec3(0.77, 0.88, 0.95), color, mask), max(mask, halo));
}
