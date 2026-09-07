shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_mix;

const int BITE_COUNT = 48;
const float ANG_NOISE = 0.42;
const float SPAWN_MID = 0.36;
const float SPAWN_SPAN = 0.22;
const float RAD_MIN = 0.20;
const float RAD_MAX = 0.34;
const float DISC_RAD = 0.48;
const float EDGE = 0.006;
const float SPRITE_SEED = 0.19;

uniform float bite_time = 0.0;
uniform float bite_speed : hint_range(0.2, 2.5) = 0.55;
uniform float bite_grow : hint_range(0.5, 2.5) = 1.12;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float seed = SPRITE_SEED;
	vec2 p = uv - vec2(0.5, 0.5);
	float body = length(p) - DISC_RAD;
	float clock = bite_time;
	float pix_ang = atan(p.y, p.x);
	float r_max = RAD_MAX * bite_grow;
	float d_spawn_min = (SPAWN_MID - 0.5 * SPAWN_SPAN) * DISC_RAD;
	float ang_reach = ANG_NOISE * 0.5 + atan(r_max, max(d_spawn_min, 0.08)) + 0.06;

	if (body < EDGE + 0.08) {
		for (int i = 0; i < BITE_COUNT; i++) {
			float fi = float(i);
			float slot = fi / float(BITE_COUNT);
			float slot_ang = slot * 6.2831853;
			float dang = abs(atan(sin(pix_ang - slot_ang), cos(pix_ang - slot_ang)));
			if (dang <= ang_reach) {
				float h_size = hash21(vec2(seed + fi * 0.37, seed * 1.9 + fi));
				float h_spd = hash21(vec2(fi * 2.17, seed * 4.3));
				float h_grow = hash21(vec2(seed * 6.2 + fi, fi * 0.91));
				float h_ease = hash21(vec2(seed * 7.7, fi * 3.3));
				float h_phase = hash21(vec2(fi * 9.1, seed * 1.4));

				float duration = mix(0.72, 1.42, h_spd) / max(bite_speed / 0.55, 0.2);
				float timed = clock / duration + slot + (h_phase - 0.5) * 0.55;
				float cycle = mod(floor(timed), 1024.0);
				float life = fract(timed);
				float h_pos = hash21(vec2(cycle * 1.73 + fi, seed + cycle * 0.31));
				float h_dir = hash21(vec2(cycle * 2.91, fi * 5.17 + seed));
				float h_rad = hash21(vec2(h_pos * 4.2, h_size + cycle));

				float spawn = (SPAWN_MID + (h_pos - 0.5) * SPAWN_SPAN) * DISC_RAD;
				float rad_final = mix(RAD_MIN, RAD_MAX, 0.5 + (h_rad - 0.5) * 0.7) * bite_grow;
				float fade_w = mix(0.02, 0.05, h_ease);
				float dist_end = DISC_RAD + rad_final + fade_w + 0.04;
				float travel = 1.0 - pow(1.0 - life, mix(2.1, 2.9, h_ease));
				float dist = mix(spawn, dist_end, travel);
				float grow_span = mix(0.18, 0.38, h_grow);
				float scale_up = clamp(life / grow_span, 0.0, 1.0);
				scale_up = 1.0 - pow(1.0 - scale_up, mix(1.05, 1.7, h_ease));
				float rad = rad_final * scale_up;
				float inner = dist - rad;
				float fade_out = 1.0 - smoothstep(DISC_RAD, DISC_RAD + fade_w, inner);
				float rad_draw = rad * fade_out;

				if (rad_draw > 0.002) {
					float ang = slot_ang + (h_dir - 0.5) * ANG_NOISE;
					vec2 dir = vec2(cos(ang), sin(ang));
					vec2 center = vec2(0.5, 0.5) + dir * dist;
					float disc = length(uv - center) - rad_draw;
					body = max(body, -disc);
				}
			}
		}
	}

	float mask = 1.0 - smoothstep(-EDGE, EDGE, body);
	float heat = 0.97;
	if (length(p) < 0.18) {
		heat = 1.0;
	}
	ALBEDO = vec3(heat);
	ALPHA = mask;
}
