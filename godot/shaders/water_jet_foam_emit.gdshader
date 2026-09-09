shader_type canvas_item;

uniform float body_length : hint_range(0.4, 6.0) = 2.85;
uniform float flow_time = 0.0;
uniform float flow_speed_back : hint_range(0.1, 8.0) = 1.7;
uniform float flow_speed_front : hint_range(0.4, 12.0) = 6.8;
uniform float wave_count : hint_range(0.2, 10.0) = 1.32;
uniform float flow_scroll : hint_range(0.2, 16.0) = 1.9;
uniform float noise_scale : hint_range(0.2, 3.0) = 0.88;
uniform float grow : hint_range(0.0, 1.0) = 0.0;
uniform float cut : hint_range(0.0, 1.0) = 0.0;
uniform float head_settle : hint_range(0.0, 1.0) = 0.0;
uniform float cell_count : hint_range(2.0, 16.0) = 13.0;
uniform float cell_along : hint_range(0.2, 8.0) = 4.6;
uniform float cell_warp : hint_range(0.0, 2.5) = 0.62;
uniform float wall_width : hint_range(0.04, 0.4) = 0.14;
uniform float start_half_width = 0.22;
uniform float start_half_height = 0.12;
uniform float end_half_width = 1.7;
uniform float end_half_height = 0.38;
uniform float flare_power = 1.58;
uniform float end_arc = 0.32;
uniform float superellipse_n = 2.6;
uniform float foam_tail_width : hint_range(0.04, 1.0) = 0.46;
uniform float foam_blue_retract : hint_range(0.04, 0.8) = 0.28;
uniform float foam_island_len : hint_range(0.02, 0.8) = 0.24;
uniform float foam_body_len : hint_range(0.02, 0.3) = 0.04;
uniform float foam_bite_len : hint_range(0.01, 0.5) = 0.18;
uniform float foam_scroll : hint_range(0.2, 16.0) = 9.2;

varying vec3 v_model;
varying float v_along;
varying vec2 v_uv;

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
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

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

float expand_contrast(float n, float k) {
	return clamp((n - 0.5) * k + 0.5, 0.0, 1.0);
}

float flight_u(float z) {
	float len = max(body_length, 0.001);
	float sb = max(flow_speed_back, 0.05);
	float sf = max(flow_speed_front, 0.05);
	float k = (sf - sb) / len;
	if (abs(k) < 0.0001) {
		return z / sb;
	}
	return log(max(sb + k * z, 0.001) / sb) / k;
}

float remap01(float n) {
	return clamp((n - 0.16) / 0.64, 0.0, 1.0);
}

vec2 hash22(vec2 p) {
	vec3 q = vec3(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)), dot(p, vec2(419.2, 371.9)));
	return fract(sin(q.xy) * 43758.5453);
}

float wrap_coord(float x, float w) {
	float m = mod(x, w);
	return m < 0.0 ? m + w : m;
}

vec2 voronoi_f1f2(vec2 p, float wrap_x) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = i + g;
			cell.x = wrap_coord(cell.x, wrap_x);
			vec2 o = hash22(cell);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(sqrt(f1), sqrt(f2));
}

vec2 voronoi_on_jet(float wrap_x, float along_mul, float warp_amt, float scroll, float seed) {
	float along_uv = flight_u(v_uv.y * body_length);
	float along_z = flight_u(v_model.z);
	float along = mix(along_z, along_uv, 0.42) * wave_count - scroll;
	vec2 p = vec2(v_uv.x * wrap_x, along * along_mul + seed);
	float w1 = value_noise3(vec3(p * 0.42, 3.2 + seed));
	float w2 = value_noise3(vec3(p.y * 0.42, p.x * 0.42, 9.5 + seed));
	p += (vec2(w1, w2) - 0.5) * warp_amt * 1.55;
	return voronoi_f1f2(p, wrap_x);
}

float foam_ridge() {
	vec2 ff = voronoi_on_jet(max(cell_count, 2.0), cell_along, cell_warp, flow_time * flow_scroll, 0.0);
	return ff.y - ff.x;
}

vec3 flow_p(vec3 extra) {
	float ang = v_uv.x * 6.2831853;
	float along_uv = flight_u(v_uv.y * body_length);
	float along_z = flight_u(v_model.z);
	float along = mix(along_z, along_uv, 0.42) * wave_count - flow_time * flow_scroll;
	vec3 p_uv = vec3(cos(ang) * 1.2, sin(ang) * 0.7, along);
	vec3 p_cart = vec3(v_model.x * 0.82, v_model.y * 1.85, along);
	return mix(p_cart, p_uv, 0.42) * noise_scale + extra;
}

vec3 jet_model(vec2 uv) {
	float t = clamp(uv.y, 0.0, 1.0);
	float flare = pow(t, max(flare_power, 1.0));
	float half_w = mix(start_half_width, end_half_width, flare);
	float half_h = mix(start_half_height, end_half_height, flare);
	float n = max(superellipse_n, 1.2);
	float expn = 2.0 / n;
	float theta = uv.x * 6.2831853;
	float c = cos(theta);
	float s = sin(theta);
	float x = half_w * sign(c) * pow(abs(c), expn);
	float y = half_h * sign(s) * pow(abs(s), expn);
	float nx = x / max(half_w, 0.0001);
	float ny = y / max(half_h, 0.0001);
	float rim = clamp(pow(nx * nx + ny * ny * 0.22, 0.68), 0.0, 1.0);
	float z = t * body_length - body_length * end_arc * flare * rim;
	return vec3(x, y, z);
}

void vertex() {
	v_uv = UV;
	v_model = jet_model(UV);
	v_along = UV.y;
}

float bite_noise(float seed, float scale) {
	float ang = v_uv.x * 6.2831853;
	vec3 p = vec3(cos(ang) * scale, sin(ang) * scale * 0.62, flow_time * 0.32 + seed);
	float n = remap01(fbm3(p));
	n = mix(n, remap01(fbm3(p * 1.35 + vec3(4.1, 0.7, 2.2))), 0.16);
	return expand_contrast(n, 1.55);
}

void jet_edges(out float head_front, out float tail_front) {
	float move_len = 0.62;
	float entering = smoothstep(0.015, 0.07, grow) * (1.0 - head_settle);
	float exiting = smoothstep(0.015, 0.07, cut) * (1.0 - smoothstep(0.97, 1.0, cut));
	float head_len = min(move_len * entering, grow * 0.92);
	float tail_len = min(move_len * exiting, (1.0 - cut) * 0.92);
	float n_head = bite_noise(2.4, 1.15);
	float n_tail = bite_noise(8.7, 1.5);
	head_front = clamp(grow - n_head * head_len + 0.5 * head_len, 0.0, 1.0);
	tail_front = clamp(cut + n_tail * tail_len - 0.5 * tail_len, 0.0, 1.0);
	float n_mouth = bite_noise(4.2, 1.75);
	n_mouth = mix(n_mouth, bite_noise(11.6, 2.55), 0.32);
	float mouth = mix(0.01, 0.08, n_mouth);
	float mouth_live = smoothstep(0.02, 0.12, grow) * (1.0 - smoothstep(0.88, 1.0, cut));
	tail_front = max(tail_front, mouth * mouth_live);
}

float edge_visibility(float head_front, float tail_front) {
	float along = clamp(v_along, 0.0, 1.0);
	float head_mask = 1.0 - smoothstep(head_front, head_front + 0.012, along);
	float tail_mask = smoothstep(tail_front - 0.012, tail_front, along);
	return tail_mask * head_mask * smoothstep(0.0, 0.02, grow);
}

float side_foam_parts(out float field, out float mid_field, out float rim) {
	float flare = pow(clamp(v_along, 0.0, 1.0), max(flare_power, 1.0));
	float half_w = mix(start_half_width, end_half_width, flare);
	float side = abs(v_model.x) / max(half_w, 0.0001);
	float n_inner = remap01(fbm3(flow_p(vec3(11.2, 0.4, 2.8)) * 0.48));
	n_inner = mix(n_inner, remap01(fbm3(flow_p(vec3(6.1, 3.4, 1.2)) * 0.92)), 0.32);
	n_inner = expand_contrast(n_inner, 1.95);
	float inner_edge = clamp(0.34 + (n_inner - 0.5) * 0.32, 0.18, 0.74);
	float t = clamp((side - inner_edge) / max(1.0 - inner_edge, 0.04), 0.0, 1.0);
	float foam = 1.0 - clamp(foam_ridge() / (wall_width * 2.4), 0.0, 1.0);
	field = foam * mix(0.28, 1.2, pow(t, 0.8));
	float n_mid = remap01(fbm3(flow_p(vec3(2.2, 8.1, 4.4)) * 0.52));
	n_mid = mix(n_mid, remap01(fbm3(flow_p(vec3(7.8, 1.3, 9.6)) * 0.9)), 0.28);
	n_mid = expand_contrast(n_mid, 1.55);
	float mid_gate = step(0.58, n_mid) * (1.0 - smoothstep(0.0, 0.32, t));
	mid_field = step(0.32, foam) * mid_gate;
	float n_rim = remap01(fbm3(flow_p(vec3(4.6, 2.1, 8.3)) * 0.42));
	n_rim = mix(n_rim, remap01(fbm3(flow_p(vec3(9.4, 1.6, 5.2)) * 0.85)), 0.3);
	n_rim = expand_contrast(n_rim, 1.8);
	float rim_inner = 0.9 + (n_rim - 0.5) * 0.1;
	rim = step(rim_inner, side);
	return max(max(step(0.5, field), rim), step(0.5, mid_field));
}

float tail_voronoi_f1(float wrap_x, float along_mul, float stretch_y, float scroll, float seed) {
	float z = max(v_model.z, 0.001);
	float rad = length(vec2(v_model.x, z));
	float u = atan(v_model.x, z) / 6.2831853 + 0.5;
	vec2 p = vec2(u * wrap_x, rad * along_mul / max(body_length, 0.001) - flow_time * scroll + seed);
	float w1 = value_noise3(vec3(p * 0.2, 2.2 + seed));
	float w2 = value_noise3(vec3(p.y * 0.2, p.x * 0.2, 8.1 + seed));
	p += (vec2(w1, w2) - 0.5) * 0.55;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = i + g;
			cell.x = wrap_coord(cell.x, wrap_x);
			vec2 o = hash22(cell);
			vec2 r = g + o - f;
			r.y *= stretch_y;
			float d = dot(r, r);
			if (d < f1) {
				f1 = d;
			}
		}
	}
	return sqrt(f1);
}

float tail_island_field(float local, float island_len) {
	float scroll = max(foam_scroll, 0.2);
	float a = tail_voronoi_f1(10.0, 12.0, 0.11, scroll, 3.1);
	float b = tail_voronoi_f1(7.0, 9.0, 0.14, scroll * 0.73, 8.6);
	float f1 = min(a, b * 1.08);
	float n = clamp(1.0 - f1 / 0.38, 0.0, 1.0);
	n = expand_contrast(n, 1.7);
	float g = clamp(local / max(island_len, 0.001), 0.0, 1.0);
	float tip = smoothstep(0.0, 0.5, g);
	float fade = n * mix(0.72, 1.0, g) * tip;
	float seam = pow(g, 2.8);
	return clamp(mix(fade, 1.0, seam), 0.0, 1.0);
}

float tail_island_mask(float local, float island_len) {
	return step(0.5, tail_island_field(local, island_len));
}

float tail_bite_mask(float local, float width, float bite_len) {
	float ang = v_uv.x * 6.2831853;
	vec3 p = vec3(cos(ang) * 1.85, sin(ang) * 1.2, flow_time * 0.62 + 5.3);
	p.z += local * 0.4;
	float n = remap01(fbm3(p));
	n = mix(n, remap01(fbm3(p * 1.22 + vec3(4.1, 0.7, 2.2))), 0.22);
	n = expand_contrast(n, 1.85);
	float bite_edge = (width - bite_len) + n * bite_len;
	return step(local, bite_edge);
}

float tail_foam_amount(float head_front, out float weight) {
	float along = clamp(v_along, 0.0, 1.0);
	float local = head_front - along;
	float width = max(foam_tail_width, 0.001);
	weight = 0.0;
	if (local < 0.0 || local > width) {
		return 0.0;
	}
	float island_len = clamp(foam_island_len, 0.02, width * 0.7);
	float bite_len = clamp(foam_bite_len, 0.02, width * 0.55);
	float body_len = clamp(foam_body_len, 0.02, max(width - island_len - bite_len, 0.02));
	float body_start = island_len;
	float body_end = island_len + body_len;
	if (local < body_start) {
		weight = tail_island_field(local, island_len);
		return tail_island_mask(local, island_len);
	}
	if (local <= body_end) {
		weight = 1.0;
		return 1.0;
	}
	float bite = tail_bite_mask(local, width, max(width - body_end, 0.02));
	weight = bite;
	return bite;
}

void fragment() {
	float head_front;
	float tail_front;
	jet_edges(head_front, tail_front);
	float vis = edge_visibility(head_front, tail_front);
	float blue_end = head_front - foam_blue_retract;
	float field = 0.0;
	float mid_field = 0.0;
	float rim = 0.0;
	float side_mask = side_foam_parts(field, mid_field, rim) * (1.0 - step(blue_end, v_along));
	float tail_weight = 0.0;
	float tail_mask = tail_foam_amount(head_front, tail_weight);
	float side_weight = max(max(clamp(field, 0.0, 1.0), rim), mid_field);
	float tail_r = 0.0;
	if (tail_mask > 0.5) {
		float along = clamp(v_along, 0.0, 1.0);
		float local = head_front - along;
		float island_len = clamp(foam_island_len, 0.02, max(foam_tail_width, 0.001) * 0.7);
		float on_island = step(local, island_len);
		float edge = smoothstep(0.42, 0.7, tail_weight) * (1.0 - smoothstep(0.86, 1.0, tail_weight));
		tail_r = mix(0.22, 1.0, mix(clamp(tail_weight, 0.0, 1.0), edge, on_island));
	}
	float side_g = 0.0;
	if (side_mask > 0.5) {
		side_g = mix(0.4, 1.0, clamp(side_weight, 0.0, 1.0));
	}
	float flare = pow(clamp(v_along, 0.0, 1.0), max(flare_power, 1.0));
	float half_w = mix(start_half_width, end_half_width, flare);
	float side_t = abs(v_model.x) / max(half_w, 0.0001);
	float blue = (1.0 - step(blue_end, v_along)) * vis;
	float n_body = remap01(fbm3(flow_p(vec3(3.1, 5.2, 1.4)) * 0.42));
	float body_b = blue * (1.0 - tail_mask) * mix(1.0, 0.22, side_mask);
	body_b *= mix(1.0, 0.28, smoothstep(0.62, 1.0, side_t));
	body_b *= mix(0.12, 0.7, n_body);
	COLOR = vec4(vis * tail_r, vis * side_g, body_b, 1.0);
}
