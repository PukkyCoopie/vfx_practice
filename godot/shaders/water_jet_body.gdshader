shader_type spatial;
render_mode unshaded, specular_disabled, shadows_disabled, cull_disabled, depth_draw_opaque;

uniform vec4 color_deep : source_color = vec4(0.07, 0.32, 0.78, 1.0);
uniform vec4 color_blue : source_color = vec4(0.14, 0.56, 1.0, 1.0);
uniform vec4 color_light : source_color = vec4(0.72, 0.93, 1.0, 1.0);
uniform vec4 color_pale : source_color = vec4(0.9, 0.97, 1.0, 1.0);

uniform float body_length : hint_range(0.4, 6.0) = 2.85;
uniform float flow_time = 0.0;
uniform float flow_speed_back : hint_range(0.1, 8.0) = 1.7;
uniform float flow_speed_front : hint_range(0.4, 12.0) = 6.8;
uniform float wave_count : hint_range(0.2, 10.0) = 1.32;
uniform float flow_scroll : hint_range(0.2, 16.0) = 1.9;
uniform float noise_scale : hint_range(0.2, 3.0) = 0.88;
uniform float warp : hint_range(0.0, 2.5) = 0.9;
uniform float grow : hint_range(0.0, 1.0) = 0.0;
uniform float cut : hint_range(0.0, 1.0) = 0.0;
uniform float head_settle : hint_range(0.0, 1.0) = 0.0;
uniform float displace_amp : hint_range(0.0, 0.5) = 0.1;
uniform float shell_offset : hint_range(0.0, 0.4) = 0.0;
uniform int layer_mode : hint_range(0, 2) = 0;
uniform float cell_count : hint_range(2.0, 16.0) = 9.0;
uniform float cell_along : hint_range(0.2, 3.0) = 1.45;
uniform float cell_warp : hint_range(0.0, 2.5) = 0.68;
uniform float wall_width : hint_range(0.04, 0.4) = 0.13;
uniform float start_half_width = 0.22;
uniform float end_half_width = 1.7;
uniform float flare_power = 1.58;
uniform float foam_tail_width : hint_range(0.04, 1.0) = 0.46;
uniform float foam_blue_retract : hint_range(0.04, 0.8) = 0.28;
uniform float foam_island_len : hint_range(0.02, 0.8) = 0.24;
uniform float foam_body_len : hint_range(0.02, 0.3) = 0.04;
uniform float foam_bite_len : hint_range(0.01, 0.5) = 0.18;
uniform float foam_scroll : hint_range(0.2, 16.0) = 9.2;
uniform bool debug_island_field = false;

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

float ridged_fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.52;
	float prev = 1.0;
	for (int i = 0; i < 4; i++) {
		float n = value_noise3(p);
		n = 1.0 - abs(n * 2.0 - 1.0);
		n *= n;
		sum += n * amp * prev;
		prev = n;
		p = p * 2.07 + vec3(1.7, 9.2, 3.4);
		amp *= 0.48;
	}
	return clamp(sum, 0.0, 1.0);
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

float fbm2(vec3 p) {
	return value_noise3(p) * 0.65 + value_noise3(p * 2.12 + vec3(1.7, 9.2, 3.4)) * 0.35;
}

void vertex() {
	v_model = VERTEX;
	v_uv = UV;
	v_along = UV.y;
	float along = clamp(UV.y, 0.0, 1.0);
	vec3 nrm = NORMAL;
	if (length(nrm) < 0.001) {
		nrm = vec3(VERTEX.x, VERTEX.y, 0.0);
		float nl = length(nrm);
		nrm = nl > 0.001 ? nrm / nl : vec3(0.0, 1.0, 0.0);
	}
	VERTEX += nrm * shell_offset;
	float live = smoothstep(0.0, 0.12, grow);
	vec3 p_swell = vec3(v_model.x, v_model.y, v_model.z * 0.52 - flow_time * 1.35) * 0.88;
	vec3 vel = vec3(
		fbm2(p_swell),
		fbm2(p_swell + vec3(19.4, 4.2, 7.1)),
		fbm2(p_swell + vec3(6.8, 13.5, 2.4))
	) - vec3(0.5);
	float jet_t = clamp(along / max(grow, 0.12), 0.0, 1.0);
	float tail_w = pow(jet_t, 1.65);
	float amp = displace_amp * mix(0.4, 2.05, tail_w) * live;
	VERTEX += nrm * vel.x * amp * 0.88;
	VERTEX += vel * amp * 0.82;
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

float side_foam_mask() {
	float flare = pow(clamp(v_along, 0.0, 1.0), max(flare_power, 1.0));
	float half_w = mix(start_half_width, end_half_width, flare);
	float side = abs(v_model.x) / max(half_w, 0.0001);
	float n_inner = remap01(fbm3(flow_p(vec3(11.2, 0.4, 2.8)) * 0.48));
	n_inner = mix(n_inner, remap01(fbm3(flow_p(vec3(6.1, 3.4, 1.2)) * 0.92)), 0.32);
	n_inner = expand_contrast(n_inner, 1.95);
	float inner_edge = clamp(0.34 + (n_inner - 0.5) * 0.32, 0.18, 0.74);
	float t = clamp((side - inner_edge) / max(1.0 - inner_edge, 0.04), 0.0, 1.0);
	float foam = 1.0 - clamp(foam_ridge() / (wall_width * 2.4), 0.0, 1.0);
	float field = foam * mix(0.28, 1.2, pow(t, 0.8));
	float n_mid = remap01(fbm3(flow_p(vec3(2.2, 8.1, 4.4)) * 0.52));
	n_mid = mix(n_mid, remap01(fbm3(flow_p(vec3(7.8, 1.3, 9.6)) * 0.9)), 0.28);
	n_mid = expand_contrast(n_mid, 1.55);
	float mid_gate = step(0.58, n_mid) * (1.0 - smoothstep(0.0, 0.32, t));
	float mid_field = step(0.32, foam) * mid_gate;
	float n_rim = remap01(fbm3(flow_p(vec3(4.6, 2.1, 8.3)) * 0.42));
	n_rim = mix(n_rim, remap01(fbm3(flow_p(vec3(9.4, 1.6, 5.2)) * 0.85)), 0.3);
	n_rim = expand_contrast(n_rim, 1.8);
	float rim_inner = 0.9 + (n_rim - 0.5) * 0.1;
	float rim = step(rim_inner, side);
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

float tail_foam_mask(float head_front) {
	float along = clamp(v_along, 0.0, 1.0);
	float local = head_front - along;
	float width = max(foam_tail_width, 0.001);
	if (local < 0.0 || local > width) {
		return 0.0;
	}
	float island_len = clamp(foam_island_len, 0.02, width * 0.7);
	float bite_len = clamp(foam_bite_len, 0.02, width * 0.55);
	float body_len = clamp(foam_body_len, 0.02, max(width - island_len - bite_len, 0.02));
	float body_start = island_len;
	float body_end = island_len + body_len;
	if (local < body_start) {
		return tail_island_mask(local, island_len);
	}
	if (local <= body_end) {
		return 1.0;
	}
	return tail_bite_mask(local, width, max(width - body_end, 0.02));
}

void fragment() {
	float head_front;
	float tail_front;
	jet_edges(head_front, tail_front);
	float vis = edge_visibility(head_front, tail_front);
	float blue_end = head_front - foam_blue_retract;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (layer_mode == 2) {
		float local = head_front - clamp(v_along, 0.0, 1.0);
		float island_len = clamp(foam_island_len, 0.02, max(foam_tail_width, 0.001) * 0.7);
		float in_island = step(0.0, local) * step(local, island_len);
		if (debug_island_field && in_island > 0.5) {
			float field = tail_island_field(local, island_len);
			ALPHA = vis;
			ALBEDO = vec3(field);
		} else {
			float side = side_foam_mask() * (1.0 - step(blue_end, v_along));
			float tail = tail_foam_mask(head_front);
			ALPHA = vis * max(side, tail);
			ALBEDO = vec3(16.0);
		}
	} else {
		float blue_mask = 1.0 - step(blue_end, v_along);
		ALPHA = vis * blue_mask;
		vec3 col = color_blue.rgb;
		if (layer_mode == 1) {
			vec3 layer_off = vec3(8.4, 3.1, 5.6);
			float n_warp = fbm3(flow_p(vec3(5.2, 0.4, 2.1) + layer_off) * 0.72);
			vec3 p_n = flow_p(layer_off);
			p_n.x += (n_warp - 0.5) * warp * 0.85;
			p_n.y += (n_warp - 0.5) * warp * 0.45;
			p_n.z += (n_warp - 0.5) * warp * 0.3;
			float n_ridge = ridged_fbm(p_n);
			float n_flow = fbm3(p_n * 1.12 + vec3(3.7, 1.4, 0.8));
			float field = expand_contrast(mix(n_flow, n_ridge, 0.62), 1.48);
			if (field < 0.64) {
				discard;
			}
			if (field < 0.86) {
				col = color_light.rgb;
			} else {
				col = color_pale.rgb;
			}
		} else if (foam_ridge() < wall_width) {
			col = color_light.rgb;
		}
		ALBEDO = col;
	}
}
