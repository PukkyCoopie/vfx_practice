shader_type particles;

uniform sampler2D foam_map : hint_default_black, filter_linear, repeat_disable;
uniform float body_length = 2.85;
uniform float start_half_width = 0.22;
uniform float start_half_height = 0.12;
uniform float end_half_width = 1.7;
uniform float end_half_height = 0.38;
uniform float flare_power = 1.58;
uniform float end_arc = 0.32;
uniform float superellipse_n = 2.6;
uniform float grow = 0.0;
uniform float flow_time = 0.0;
uniform float displace_amp = 0.1;
uniform float flow_speed_back = 1.7;
uniform float flow_speed_front = 6.8;
uniform float flow_along = 0.38;
uniform float normal_speed = 0.26;
uniform float gravity = 2.6;
uniform float damping = 5.4;
uniform float spawn_lift = 0.035;
uniform float spawn_back = 0.0;
uniform int emit_group = 0;
uniform int map_channel = 0;
uniform float uv_y_min = 0.0;
uniform float uv_y_max = 1.0;
uniform float scale_min = 0.1;
uniform float scale_max = 0.2;
uniform float keep_outward = 1.0;
uniform float curl_strength = 0.55;
uniform float curl_swirl = 0.35;
uniform float side_spread = 0.1;
uniform float end_scale = 1.0;
uniform float spin_speed = 9.0;
uniform float nozzle_fade = 0.0;

uint hashu(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float randf(inout uint seed) {
	seed = hashu(seed);
	return float(seed) * (1.0 / 4294967295.0);
}

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

float fbm2(vec3 p) {
	return value_noise3(p) * 0.65 + value_noise3(p * 2.12 + vec3(1.7, 9.2, 3.4)) * 0.35;
}

vec3 jet_pos(vec2 uv) {
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

vec3 jet_normal(vec2 uv, vec3 pos) {
	float eu = 0.012;
	float ev = 0.012;
	vec3 pu = jet_pos(vec2(fract(uv.x + eu), uv.y));
	vec3 pv = jet_pos(vec2(uv.x, clamp(uv.y + ev, 0.0, 1.0)));
	vec3 n = cross(pu - pos, pv - pos);
	float nl = length(n);
	n = nl > 0.0001 ? n / nl : vec3(pos.x, pos.y, 0.0);
	vec3 outw = vec3(pos.x, pos.y, 0.0);
	float ol = length(outw);
	outw = ol > 0.0001 ? outw / ol : vec3(0.0, 1.0, 0.0);
	if (dot(n, outw) < 0.0) {
		n = -n;
	}
	return n;
}

vec3 displaced(vec3 pos, vec3 nrm) {
	float along = clamp(pos.z / max(body_length, 0.001), 0.0, 1.0);
	float live = smoothstep(0.0, 0.12, grow);
	vec3 p_swell = vec3(pos.x, pos.y, pos.z * 0.52 - flow_time * 1.35) * 0.88;
	vec3 vel = vec3(
		fbm2(p_swell),
		fbm2(p_swell + vec3(19.4, 4.2, 7.1)),
		fbm2(p_swell + vec3(6.8, 13.5, 2.4))
	) - vec3(0.5);
	float amp = displace_amp * mix(0.55, 1.35, along) * live;
	return pos + nrm * vel.x * amp * 0.88 + vel * amp * 0.82;
}

float map_dens(vec2 uv) {
	vec4 m = texture(foam_map, uv);
	if (map_channel == 1) {
		return m.g;
	}
	if (map_channel == 2) {
		return m.b;
	}
	return m.r;
}

vec3 curl_field(vec3 p) {
	float a = fbm2(p);
	float b = fbm2(p + vec3(19.2, 4.1, 7.7));
	float c = fbm2(p + vec3(8.4, 13.6, 2.2));
	return vec3(b - c, c - a, a - b);
}

bool pick_spawn(uint seed, out vec3 pos, out vec3 vel, out vec4 col, out vec4 custom) {
	vec2 uv = vec2(0.5);
	float dens = 0.0;
	bool found = false;
	bool use_map = map_channel < 3;
	for (int i = 0; i < 24; i++) {
		uv = vec2(randf(seed), mix(uv_y_min, uv_y_max, randf(seed)));
		if (use_map) {
			dens = map_dens(uv);
			if (randf(seed) < dens) {
				found = true;
				break;
			}
		} else {
			found = true;
			dens = 1.0;
			break;
		}
	}
	pos = vec3(0.0);
	vel = vec3(0.0);
	col = vec4(0.0);
	custom = vec4(0.0, 0.0, 0.0, -1.0);
	if (!found || dens < 0.05) {
		return false;
	}

	pos = jet_pos(uv);
	vec3 nrm = jet_normal(uv, pos);
	pos = displaced(pos, nrm);
	nrm = jet_normal(uv, jet_pos(uv));
	pos += nrm * spawn_lift;
	pos.z -= spawn_back;

	vec3 ahead = jet_pos(vec2(uv.x, clamp(uv.y + 0.02, 0.0, 1.0)));
	vec3 along = ahead - jet_pos(uv);
	float al = length(along);
	along = al > 0.0001 ? along / al : vec3(0.0, 0.0, 1.0);
	vec3 around = cross(along, nrm);
	float ar = length(around);
	around = ar > 0.0001 ? around / ar : vec3(1.0, 0.0, 0.0);

	float speed_flow = mix(flow_speed_back, flow_speed_front, pow(clamp(uv.y, 0.0, 1.0), 0.82)) * flow_along;
	speed_flow *= mix(0.78, 1.48, pow(clamp(uv.y, 0.0, 1.0), 1.35));
	speed_flow *= mix(0.9, 1.04, randf(seed));
	float speed_n = normal_speed * mix(0.82, 1.08, randf(seed));
	float kick = mix(-side_spread, side_spread, randf(seed));
	float center = 1.0;
	if (emit_group == 0) {
		float flare = pow(clamp(uv.y, 0.0, 1.0), max(flare_power, 1.0));
		float half_w = mix(start_half_width, end_half_width, flare);
		float side = clamp(abs(pos.x) / max(half_w, 0.0001), 0.0, 1.0);
		center = 1.0 - smoothstep(0.12, 0.68, side);
		center *= center;
		speed_flow *= mix(0.4, 1.0, center);
		speed_n *= mix(0.45, 1.0, center);
		kick *= mix(0.4, 1.0, center);
	}
	if (emit_group == 3) {
		speed_flow = max(speed_flow, flow_speed_back * max(flow_along, 0.12) * 0.7);
	}
	vel = along * speed_flow + nrm * speed_n + around * kick;
	if (keep_outward > 0.5) {
		float inward = min(dot(vel, nrm), 0.0);
		vel -= nrm * inward;
	}

	float sc = mix(scale_min, scale_max, randf(seed));
	if (emit_group == 0) {
		float ordinary = mix(0.07, 0.11, randf(seed));
		float big = mix(scale_min, scale_max, randf(seed));
		sc = mix(ordinary, big, center);
	}
	col = vec4(mix(vec3(1.0), vec3(0.82, 0.93, 1.0), randf(seed) * 0.22), 1.0);
	custom = vec4(randf(seed) * 6.2831853, 0.0, randf(seed), sc);
	return true;
}

void start() {
	vec3 pos;
	vec3 vel;
	vec4 col;
	vec4 custom;
	if (pick_spawn(hashu(NUMBER + 19u + RANDOM_SEED), pos, vel, col, custom)) {
		float sc = custom.w;
		TRANSFORM = mat4(
			vec4(sc, 0.0, 0.0, 0.0),
			vec4(0.0, sc, 0.0, 0.0),
			vec4(0.0, 0.0, sc, 0.0),
			vec4(pos, 1.0)
		);
		VELOCITY = vel;
		COLOR = col;
		CUSTOM = custom;
		ACTIVE = true;
	} else {
		ACTIVE = false;
		VELOCITY = vec3(0.0);
		COLOR = vec4(0.0);
		CUSTOM = vec4(0.0, 0.0, 0.0, -1.0);
		TRANSFORM = mat4(1.0);
	}
}

void process() {
	if (!ACTIVE || (RESTART && CUSTOM.w <= 0.0)) {
		vec3 pos;
		vec3 vel;
		vec4 col;
		vec4 custom;
		if (pick_spawn(hashu(NUMBER + 41u + RANDOM_SEED), pos, vel, col, custom)) {
			float sc0 = custom.w;
			TRANSFORM = mat4(
				vec4(sc0, 0.0, 0.0, 0.0),
				vec4(0.0, sc0, 0.0, 0.0),
				vec4(0.0, 0.0, sc0, 0.0),
				vec4(pos, 1.0)
			);
			VELOCITY = vel;
			COLOR = col;
			CUSTOM = custom;
			ACTIVE = true;
		} else {
			ACTIVE = false;
			VELOCITY = vec3(0.0);
			COLOR = vec4(0.0);
			CUSTOM = vec4(0.0, 0.0, 0.0, -1.0);
			TRANSFORM = mat4(1.0);
		}
	}
	if (ACTIVE) {
		CUSTOM.y += DELTA / max(LIFETIME, 0.001);
		float life = clamp(CUSTOM.y, 0.0, 1.0);
		vec3 p = TRANSFORM[3].xyz * 2.35 + vec3(0.0, flow_time * 0.72, flow_time * 0.34);
		vec3 curl = curl_field(p);
		VELOCITY += curl * curl_strength * (1.0 - life * 0.22) * DELTA;
		vec3 radial = vec3(TRANSFORM[3].x, TRANSFORM[3].y, 0.0);
		float rl = length(radial);
		if (rl > 0.001) {
			vec3 swirl = vec3(-radial.y, radial.x, 0.0) / rl;
			VELOCITY += swirl * curl_swirl * (1.0 - life * 0.28) * DELTA;
		}
		if (keep_outward > 0.5 && rl > 0.001) {
			vec3 outw = radial / rl;
			float inward = min(dot(VELOCITY, outw), 0.0);
			VELOCITY -= outw * inward;
		}
		float along_t = clamp(TRANSFORM[3].z / max(body_length, 0.001), 0.0, 1.0);
		float flow_keep = mix(flow_speed_back, flow_speed_front, pow(along_t, 1.1)) * flow_along;
		float flow_push = pow(along_t, 1.35) * 0.42;
		if (emit_group == 3) {
			flow_push = 0.22;
		}
		VELOCITY.z += flow_keep * flow_push * DELTA;
		float damp = damping * mix(1.0, 0.7, pow(along_t, 1.25));
		VELOCITY *= max(1.0 - damp * DELTA, 0.18);
		TRANSFORM[3].xyz += VELOCITY * DELTA;

		float pop = mix(0.88, 1.0, smoothstep(0.0, 0.08, life));
		float fade_s = mix(1.0, max(end_scale, 0.08), smoothstep(0.12, 1.0, life));
		float sc = CUSTOM.w * pop * fade_s;
		float a = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.62, 1.0, life));
		if (emit_group == 3) {
			float appear = smoothstep(0.0, 0.18, life);
			float vanish = 1.0 - smoothstep(0.55, 1.0, life);
			float kill = 1.0 - nozzle_fade;
			sc = CUSTOM.w * appear * vanish * kill;
			a = appear * vanish * kill;
			if (kill < 0.02) {
				ACTIVE = false;
			}
		}
		TRANSFORM[0].xyz = vec3(sc, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, sc, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, sc);

		CUSTOM.x += mix(-1.0, 1.0, CUSTOM.z) * spin_speed * DELTA;
		COLOR.a = a;

		if (life >= 1.0) {
			ACTIVE = false;
		}
	}
}
