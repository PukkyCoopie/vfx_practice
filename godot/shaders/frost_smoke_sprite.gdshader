shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

// 2x2 smoke atlas. Each cell is a unique blotch animated by smoke_time + 3D noise.
uniform float smoke_time = 0.0;
uniform float smoke_speed : hint_range(0.1, 4.0) = 1.85;
uniform float noise_strength : hint_range(0.0, 2.5) = 1.0;
uniform float threshold : hint_range(0.05, 0.7) = 0.36;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
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

float noise31(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) {
		v += a * noise21(p);
		p = m * p;
		a *= 0.5;
	}
	return v;
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise31(p);
		p = p * 2.05 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float ridged2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(noise21(p) * 2.0 - 1.0);
		v += a * n * n;
		p = m * p;
		a *= 0.5;
	}
	return v;
}

float worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			vec2 r = g + o - f;
			d = min(d, dot(r, r));
		}
	}
	return sqrt(d);
}

void fragment() {
	vec2 cell = clamp(floor(UV * 2.0), vec2(0.0), vec2(1.0));
	vec2 uv = fract(UV * 2.0);
	vec2 p = uv - vec2(0.5);
	float seed = hash21(cell + vec2(0.37, 2.91));
	float cell_id = cell.x + cell.y * 2.0;

	float clock = smoke_time * smoke_speed + seed * 2.4 + cell_id * 0.85;
	vec3 p3 = vec3(p * 2.8, clock * 1.15);

	float w0 = fbm3(p3 + vec3(seed * 3.0, 1.2, clock * 0.2));
	float w1 = fbm3(p3 + vec3(2.1, seed * 2.5, clock * 0.25 + 1.7));
	vec2 q = p * 2.6 + vec2(w0, w1) * (0.22 + noise_strength * 0.22);
	q += vec2(seed * 2.0, cell_id * 1.3);

	float smoke = fbm2(q + vec2(clock * 0.55, clock * 0.18));
	smoke = mix(smoke, ridged2(q * 1.2 + seed * 0.5 + clock * 0.2), 0.32);
	smoke = mix(smoke, fbm3(vec3(q * 1.05, clock * 0.9)), 0.4);
	float cells = worley(q * 1.25 + seed + clock * 0.22);
	smoke *= mix(0.72, 1.08, smoothstep(0.1, 0.48, cells));

	// Stabilize coverage across the 4 atlas cells.
	smoke = clamp(0.5 + (smoke - 0.5) * 0.55, 0.0, 1.0);
	smoke = clamp(smoke * 0.78 + 0.22, 0.0, 1.0);

	float thr = threshold;
	float mask = smoothstep(thr, thr + 0.28, smoke);

	// Irregular soft silhouette (NOT circle, NOT square):
	// noise-warped radius so the outline reads as ragged smoke, and always
	// dies before the atlas tile corners.
	float ang = atan(p.y, p.x);
	float r = length(p);
	float lobe = 0.04 * sin(ang * 3.0 + seed * 6.28 + clock * 0.7)
			+ 0.028 * sin(ang * 5.0 - seed * 4.1 + clock * 0.9)
			+ 0.035 * (fbm2(vec2(ang * 0.55 + seed, clock * 0.35)) - 0.5)
			+ 0.03 * (fbm3(vec3(p * 3.2, clock * 0.5 + seed)) - 0.5);
	float r_lim = 0.34 + lobe;
	r_lim = clamp(r_lim, 0.26, 0.42);
	float sil = 1.0 - smoothstep(r_lim - 0.1, r_lim, r);
	// Extra ragged bites on the silhouette edge.
	float bite = smoothstep(0.35, 0.7, fbm2(p * 5.5 + vec2(clock * 0.4, seed * 3.0)));
	sil *= mix(0.55, 1.0, bite);
	mask *= sil;

	float a = clamp(mask, 0.0, 1.0);
	if (a < 0.004) {
		discard;
	}
	float heat = smoothstep(thr + 0.05, 0.9, smoke);
	vec3 col = mix(vec3(0.55, 0.85, 1.0), vec3(0.95, 0.99, 1.0), heat);
	ALBEDO = col * a;
	ALPHA = a;
}
