shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 rect_size = vec2(245.0);
uniform vec2 tile_origin = vec2(68.0);
uniform vec2 tile_size = vec2(109.5);
uniform float chamfer_px = 5.0;
uniform float time = 0.0;
uniform vec2 flow_direction = vec2(0.0, 1.0);
uniform float wind_strength = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = (UV * rect_size - tile_origin) / tile_size;
	p.y = 1.0 - p.y;
	vec2 axis = normalize(flow_direction);
	float aa = 0.8 / tile_size.x;
	// The opaque tile above completely hides this region, including under wind.
	vec2 box = abs(p - vec2(0.5));
	float sdf = max(max(box.x, box.y) - 0.5,
		(box.x + box.y - 1.0 + chamfer_px / tile_size.x) * 0.70710678);
	if (sdf <= -aa) { discard; }
	// Conservative resting bounds include width, antialiasing and all gusts.
	if (wind_strength <= 0.002 && (p.y < 0.08 || p.y > 1.50 || p.x < -0.45 || p.x > 1.45)) { discard; }
	float alpha = 0.0;
	vec3 light = vec3(0.0);
	// Each lane renews at its own rate. Two candidate births allow a random
	// delay and lifetime without snapping a visible sheet onto a new path.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float interval = mix(1.15, 1.85, hash21(vec2(fi, 9.3)));
		float age = time / interval + hash21(vec2(fi, 5.7));
		for (int previous = 0; previous < 2; previous++) {
			float generation = floor(age) - float(previous);
			vec2 seed = vec2(fi + 1.0, generation);
			float delay = hash21(seed + 1.4) * 0.32;
			float duration = mix(0.65, 1.22, hash21(seed + 3.9));
			float life = (age - generation - delay) / duration;
			if (life <= 0.0 || life >= 1.0) { continue; }
			float presence = smoothstep(0.0, 0.20, life) * (1.0 - smoothstep(0.60, 1.0, life));
			float side = hash21(seed + 7.1) < 0.5 ? -1.0 : 1.0;
			float inset = mix(0.025, 0.18, hash21(seed + 11.8));
			float root_x = side < 0.0 ? inset : 1.0 - inset;
			float root_y = mix(0.08, 0.64, hash21(seed + 13.6)) + life * 0.08;
			float end_y = mix(0.85, 1.42, hash21(seed + 17.3));
			float height = max(0.30, end_y - root_y);
            float c1 = side * mix(0.07, 0.28, hash21(seed + 21.5));
            float c2 = side * mix(-0.12, 0.25, hash21(seed + 25.7));
            float tip = mix(-0.16, 0.16, hash21(seed + 29.2));
            float t = (p.y - root_y) / height;
            float d = 0.0;
            float signed_d = 0.0;
            if (wind_strength > 0.002) {
                vec2 previous_point = vec2(root_x, root_y);
                float best = 1000.0;
                for (int segment = 0; segment < 8; segment++) {
                    float t1 = float(segment + 1) / 8.0;
                    float u1 = 1.0 - t1;
                    float bend1 = 3.0 * u1 * u1 * t1 * c1 + 3.0 * u1 * t1 * t1 * c2 + t1 * t1 * t1 * tip;
                    float wind1 = noise(vec2(t1 * 2.8 - time * 1.9, fi * 4.1 + generation * 1.3));
                    vec2 point = vec2(root_x + bend1 + (wind1 - 0.5) * 0.11 * t1, root_y + height * t1);
                    // Root stays attached; successive folds are pulled farther behind.
                    point += (axis * 1.20 - vec2(0.0, 0.85)) * height * wind_strength * t1 * t1;
                    vec2 tangent = point - previous_point;
                    float along = clamp(dot(p - previous_point, tangent) / max(dot(tangent, tangent), 0.000001), 0.0, 1.0);
                    vec2 nearest = previous_point + tangent * along;
                    float distance_sq = dot(p - nearest, p - nearest);
                    if (distance_sq < best) {
                        best = distance_sq;
                        t = (float(segment) + along) / 8.0;
                        signed_d = dot(p - nearest, normalize(vec2(tangent.y, -tangent.x)));
                    }
                    previous_point = point;
                }
                d = sqrt(best);
            } else {
                float u0 = 1.0 - t;
                float bend0 = 3.0 * u0 * u0 * t * c1 + 3.0 * u0 * t * t * c2 + t * t * t * tip;
                float wind0 = noise(vec2(t * 2.8 - time * 1.9, fi * 4.1 + generation * 1.3));
                float gust0 = noise(vec2(time * 0.75, p.y * 2.5));
                float center0 = root_x + bend0 + (wind0 - 0.5) * 0.11 * t + (gust0 - 0.5) * 0.10 * t * t;
                signed_d = p.x - center0;
                d = abs(signed_d);
            }
            // Match the exact resting sheet while the wind settles, without a switch.
            if (wind_strength > 0.002 && wind_strength < 0.12) {
                float rest_t = (p.y - root_y) / height;
                float rest_u = 1.0 - rest_t;
                float rest_bend = 3.0 * rest_u * rest_u * rest_t * c1 + 3.0 * rest_u * rest_t * rest_t * c2 + rest_t * rest_t * rest_t * tip;
                float rest_wind = noise(vec2(rest_t * 2.8 - time * 1.9, fi * 4.1 + generation * 1.3));
                float rest_gust = noise(vec2(time * 0.75, p.y * 2.5));
                float rest_center = root_x + rest_bend + (rest_wind - 0.5) * 0.11 * rest_t + (rest_gust - 0.5) * 0.10 * rest_t * rest_t;
                float blend = smoothstep(0.002, 0.12, wind_strength);
                t = mix(rest_t, t, blend);
                signed_d = mix(p.x - rest_center, signed_d, blend);
                d = mix(abs(p.x - rest_center), d, blend);
            }
            if (t <= 0.0 || t >= 1.0) { continue; }
            float u = 1.0 - t;
            float wind = noise(vec2(t * 2.8 - time * 1.9, fi * 4.1 + generation * 1.3));
			float turn = noise(vec2(t * 4.5 - time * 2.3, fi * 7.7 + generation));
			float width = mix(0.018, 0.070, turn) * pow(max(4.0 * t * u, 0.0), 0.7);
			width *= mix(0.75, 1.25, hash21(seed + 32.8));
			float ribbon = 1.0 - smoothstep(width - aa, width + aa, d);
			float ends = smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.70, 1.0, t));
			float fold_offset = (wind - 0.5) * width * 1.2;
			float fold = exp(-abs(signed_d - fold_offset) / max(aa, width * 0.20));
			float a = ribbon * ends * presence * (0.30 + fold * 0.38);
			vec3 col = mix(vec3(1.0, 0.30, 0.035), vec3(1.0, 0.80, 0.27), fold);
			light += col * a * (1.0 - alpha);
			alpha += a * (1.0 - alpha);
		}
	}
	COLOR = vec4(light / max(alpha, 0.0001), alpha);
}
