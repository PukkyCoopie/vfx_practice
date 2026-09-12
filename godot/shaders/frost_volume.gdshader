shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

// Cone is only a soft containment bound. Visible shape comes from
// multi-scale advected smoke noise (billow / clump / filament) so the
// silhouette reads as spray, not a geometric solid.

uniform float smoke_time = 0.0;
uniform float cast_weight : hint_range(0.0, 1.0) = 1.0;
uniform float overall_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float density : hint_range(0.05, 3.0) = 1.25;
uniform float flow_speed : hint_range(0.2, 5.0) = 2.1;
uniform float noise_strength : hint_range(0.0, 2.5) = 1.25;
uniform float mouth_radius : hint_range(0.04, 0.4) = 0.07;
uniform float tip_radius : hint_range(0.15, 0.5) = 0.46;
uniform float flare_power : hint_range(1.2, 3.5) = 2.2;
uniform float tip_plume : hint_range(0.0, 2.5) = 1.35;
uniform float core_boost : hint_range(0.0, 2.5) = 1.2;
uniform float detail_boost : hint_range(0.0, 2.5) = 1.4;
uniform float edge_softness : hint_range(0.5, 3.0) = 1.7;
uniform int march_steps : hint_range(4, 16) = 14;
uniform int toon_steps : hint_range(2, 6) = 3;

varying vec3 v_local_pos;
varying vec3 v_cam_local;

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 hash33(vec3 p) {
	p = vec3(
			dot(p, vec3(127.1, 311.7, 74.7)),
			dot(p, vec3(269.5, 183.3, 246.1)),
			dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

mat3 rot_fbm() {
	return mat3(
			vec3(0.00, 0.80, 0.60),
			vec3(-0.80, 0.36, -0.48),
			vec3(-0.60, -0.48, 0.64)
	);
}

float fbm(vec3 p) {
	mat3 m = rot_fbm();
	float f = 0.0;
	f += 0.5000 * value_noise3(p);
	p = m * p * 2.02;
	f += 0.2500 * value_noise3(p);
	p = m * p * 2.03;
	f += 0.1250 * value_noise3(p);
	p = m * p * 2.01;
	f += 0.0625 * value_noise3(p);
	p = m * p * 2.04;
	f += 0.03125 * value_noise3(p);
	return f;
}

float ridged(vec3 p) {
	mat3 m = rot_fbm();
	float sum = 0.0;
	float a = 0.5;
	float prev = 1.0;
	for (int i = 0; i < 4; i++) {
		float n = value_noise3(p);
		n = 1.0 - abs(n * 2.0 - 1.0);
		n *= n;
		sum += n * a * prev;
		prev = n;
		p = m * p * 2.08;
		a *= 0.5;
	}
	return clamp(sum, 0.0, 1.0);
}

// Cellular puffs — classic smoke blotch look.
float worley(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 1.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash33(i + g);
				vec3 r = g + o - f;
				d = min(d, dot(r, r));
			}
		}
	}
	return sqrt(d);
}

// Cheap curl-like offset from noise gradients (smoke swirl).
vec2 curl_xy(vec3 p) {
	float e = 0.18;
	float n1 = fbm(p + vec3(e, 0.0, 0.0));
	float n2 = fbm(p - vec3(e, 0.0, 0.0));
	float n3 = fbm(p + vec3(0.0, e, 0.0));
	float n4 = fbm(p - vec3(0.0, e, 0.0));
	return vec2(n3 - n4, n2 - n1) / (2.0 * e);
}

bool intersect_unit_box(vec3 ro, vec3 rd, out float t_enter, out float t_exit) {
	vec3 safe_rd = rd;
	if (abs(safe_rd.x) < 1e-5) {
		safe_rd.x = 1e-5;
	}
	if (abs(safe_rd.y) < 1e-5) {
		safe_rd.y = 1e-5;
	}
	if (abs(safe_rd.z) < 1e-5) {
		safe_rd.z = 1e-5;
	}
	vec3 inv = 1.0 / safe_rd;
	vec3 t0 = (-0.5 - ro) * inv;
	vec3 t1 = (0.5 - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	t_enter = max(max(tmin.x, tmin.y), tmin.z);
	t_exit = min(min(tmax.x, tmax.y), tmax.z);
	return t_exit > max(t_enter, 0.0);
}

float toon_aa(float v, float steps, float soft_mul) {
	float x = clamp(v, 0.0, 0.9999) * steps;
	float fw = clamp(fwidth(x) * soft_mul, 0.1, 0.55);
	float base = floor(x);
	float f = fract(x);
	float rise = smoothstep(1.0 - fw, 1.0, f);
	return (base + rise) / steps;
}

float spray_density(vec3 p, float clock) {
	float along = clamp(p.z + 0.5, 0.0, 1.0);
	float ns = noise_strength;
	float db = detail_boost;

	// Different advection speeds per scale → spray velocity feel.
	float t_slow = clock * 1.15;
	float t_mid = clock * 2.35;
	float t_fast = clock * 4.1;

	// Anisotropic coords: denser in XY, stretched along Z (spray axis).
	// Low Z frequency → elongated streaks instead of flat pancakes.
	vec3 base_uv = vec3(p.xy * 2.8, along * 1.15);
	vec2 curl = curl_xy(base_uv + vec3(0.0, 0.0, -t_slow * 0.35));
	vec3 wpos = p;
	// Prefer axial / streamwise warp over radial bloat.
	wpos.xy += curl * (0.04 + ns * 0.06);
	wpos.xy += vec2(
			fbm(base_uv + vec3(1.2, 0.4, -t_mid * 0.2)) - 0.5,
			fbm(base_uv + vec3(0.3, 2.0, -t_mid * 0.18)) - 0.5
	) * (0.05 + ns * 0.08);
	wpos.z += (fbm(base_uv * 0.7 + vec3(0.0, 0.0, -t_slow * 0.15)) - 0.5) * 0.06;

	float along_w = clamp(wpos.z + 0.5, 0.0, 1.0);

	float ease_in = pow(along_w, flare_power);
	float tip_zone = smoothstep(0.42, 0.78, along_w);
	float tip_deep = smoothstep(0.62, 0.95, along_w);

	float radius = mix(mouth_radius, tip_radius, ease_in);
	float edge_break = fbm(vec3(wpos.xy * 3.8, along_w * 1.1 - t_mid * 0.5));
	float puff_edge = 1.0 - worley(vec3(wpos.xy * 3.2, along_w * 1.2 - t_mid * 0.4));
	radius *= mix(0.92, 1.06, edge_break);
	radius *= mix(0.94, 1.05, puff_edge);

	// Tip flame tongues: angular lobes like exhaust plume.
	float ang = atan(wpos.y, wpos.x);
	float tongue_n = fbm(vec3(ang * 0.55, along_w * 1.4 - t_fast * 0.35, t_mid * 0.2));
	float tongues = 0.55 + 0.45 * sin(ang * 5.0 + tongue_n * 6.28318 + t_fast * 0.8);
	tongues *= 0.55 + 0.45 * sin(ang * 3.0 - tongue_n * 4.0 + t_mid * 0.5);
	radius *= mix(1.0, mix(0.72, 1.28, tongues), tip_zone * tip_plume * 0.85);

	float nrm = length(wpos.xy) / max(radius, 1e-4);
	float bound = 1.0 - smoothstep(0.5, 1.05, nrm);
	float sil_noise = fbm(vec3(wpos.xy * 2.2, along_w * 0.9 - t_slow * 0.55));
	float sil_gate = mix(0.35, 1.0, smoothstep(0.15, 0.7, sil_noise * 0.55 + puff_edge * 0.45));
	bound *= mix(sil_gate, mix(sil_gate, 1.0, tongues), tip_zone);
	if (bound < 0.02) {
		return 0.0;
	}

	float z_stretch = mix(0.85, 0.35, tip_zone);
	vec3 uv_l = vec3(wpos.xy * 1.55, along_w * z_stretch - t_slow);
	vec3 uv_m = vec3(wpos.xy * 3.4, along_w * (z_stretch * 1.8) - t_mid);
	vec3 uv_f = vec3(wpos.xy * 6.4, along_w * (z_stretch * 3.0) - t_fast);

	float billow = fbm(uv_l);
	billow = 0.5 + 0.5 * billow;

	float cells = 1.0 - worley(uv_m * 0.85 + vec3(2.1, -0.7, 0.0));
	cells = smoothstep(0.15, 0.75, cells);
	float clump = fbm(uv_m + vec3(1.4, 0.2, 0.0));
	clump = 0.5 + 0.5 * clump;
	clump = mix(clump, cells, 0.55);

	float filament = ridged(uv_f * 0.85 + vec3(0.5, 1.7, 0.0));
	float grit = fbm(uv_f * 1.35 + vec3(-1.2, 0.8, 0.0));
	grit = 0.5 + 0.5 * grit;

	float streak = ridged(vec3(wpos.xy * 4.5, along_w * 0.45 - t_fast * 1.1));
	streak = smoothstep(0.25, 0.8, streak);

	float smoke = billow * 0.55 + clump * 0.5;
	smoke *= mix(0.45, 1.15, clump);
	smoke = mix(smoke, smoke * (0.5 + 0.75 * filament), 0.5 * db);
	smoke *= mix(0.55, 1.2, smoothstep(0.3, 0.7, grit));
	smoke += (filament - 0.4) * 0.2 * db;
	smoke += (grit - 0.5) * 0.12 * db;
	smoke = mix(smoke, smoke * (0.65 + 0.7 * streak) + streak * 0.25, tip_zone * tip_plume);
	smoke = clamp(smoke, 0.0, 1.55);
	smoke = smoothstep(0.16, 0.82, smoke);
	smoke = pow(smoke, mix(0.72, 0.62, tip_zone));

	float dens = bound * smoke;
	float axis = exp(-nrm * nrm * mix(3.4, 2.2, tip_zone));
	dens += axis * smoke * (0.2 + tip_deep * 0.45 * tip_plume) * core_boost * bound;
	float tip_feather = 1.0 - smoothstep(0.9, 1.0, along_w);
	tip_feather = mix(tip_feather, tip_feather * mix(0.35, 1.15, streak * tongues), tip_deep);
	dens *= smoothstep(0.0, 0.04, along) * tip_feather;
	float flicker = 0.88 + 0.12 * sin(t_fast * 1.7 + along_w * 8.0 + tongue_n * 5.0);
	dens *= mix(1.0, flicker, tip_zone * 0.85);
	return dens;
}

void vertex() {
	v_local_pos = VERTEX;
	v_cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	if (cast_weight < 0.001) {
		discard;
	}

	vec3 ro = v_cam_local;
	vec3 rd = v_local_pos - ro;
	float rd_len = length(rd);
	if (rd_len < 1e-5) {
		discard;
	}
	rd /= rd_len;

	float t_enter;
	float t_exit;
	if (!intersect_unit_box(ro, rd, t_enter, t_exit)) {
		discard;
	}
	t_enter = max(t_enter, 0.0);
	float span = t_exit - t_enter;
	if (span < 1e-4) {
		discard;
	}

	int steps = clamp(march_steps, 4, 16);
	float step_len = span / float(steps);
	// Faster overall advection for spray velocity.
	float clock = smoke_time * flow_speed * 1.85;
	float optical = 0.0;
	float heat_acc = 0.0;

	for (int i = 0; i < 16; i++) {
		if (i >= steps) {
			break;
		}
		float t = t_enter + (float(i) + 0.5) * step_len;
		vec3 p = ro + rd * t;
		float d = spray_density(p, clock);
		optical += d * step_len * density * 3.2;
		float along_h = clamp(p.z + 0.5, 0.0, 1.0);
		float tip_h = smoothstep(0.5, 0.9, along_h);
		heat_acc += d * d * step_len * (1.1 - length(p.xy) * 1.1) * (1.0 + tip_h * 1.4);
		if (optical > 2.8) {
			break;
		}
	}

	float cover = 1.0 - exp(-optical);
	cover *= cast_weight * overall_intensity;
	float edge_w = max(fwidth(cover) * edge_softness, 0.012);
	cover = smoothstep(0.0, edge_w * 1.8, cover) * cover;
	if (cover < 0.012) {
		discard;
	}

	float steps_f = float(max(toon_steps, 2));
	float q = toon_aa(cover, steps_f, edge_softness);
	if (q < 0.001) {
		discard;
	}

	float heat = clamp(heat_acc * 2.4, 0.0, 1.0);
	float heat_q = toon_aa(heat, steps_f, edge_softness * 0.85);
	vec3 cold = vec3(0.34, 0.7, 1.0);
	vec3 mid = vec3(0.68, 0.9, 1.0);
	vec3 hot = vec3(0.96, 0.99, 1.0);
	vec3 col = mix(cold, mid, clamp(q * 1.25, 0.0, 1.0));
	col = mix(col, hot, heat_q * 0.75 * core_boost);

	ALBEDO = col * q;
	ALPHA = q;
}
