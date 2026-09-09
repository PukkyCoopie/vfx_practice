shader_type canvas_item;

uniform float body_length : hint_range(0.4, 6.0) = 2.85;
uniform float flow_time = 0.0;
uniform float flow_speed_back : hint_range(0.1, 8.0) = 1.7;
uniform float flow_speed_front : hint_range(0.4, 12.0) = 6.8;
uniform float wave_count : hint_range(0.2, 10.0) = 1.32;
uniform float flow_scroll : hint_range(0.2, 16.0) = 1.9;
uniform float cell_count : hint_range(2.0, 16.0) = 13.0;
uniform float cell_along : hint_range(0.2, 8.0) = 4.6;
uniform float cell_warp : hint_range(0.0, 2.5) = 0.62;
uniform float wall_width : hint_range(0.04, 0.4) = 0.14;

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

float foam_ridge(vec2 uv) {
	float wrap_x = max(cell_count, 2.0);
	float z = uv.y * body_length;
	float along_uv = flight_u(uv.y * body_length);
	float along_z = flight_u(z);
	float along = mix(along_z, along_uv, 0.42) * wave_count - flow_time * flow_scroll;
	vec2 p = vec2(uv.x * wrap_x, along * cell_along);
	float w1 = value_noise3(vec3(p * 0.42, 3.2));
	float w2 = value_noise3(vec3(p.y * 0.42, p.x * 0.42, 9.5));
	p += (vec2(w1, w2) - 0.5) * cell_warp * 1.55;
	vec2 ff = voronoi_f1f2(p, wrap_x);
	return ff.y - ff.x;
}

void fragment() {
	float ridge = foam_ridge(UV);
	float foam = 1.0 - clamp(ridge / (wall_width * 2.4), 0.0, 1.0);
	COLOR = vec4(vec3(foam), 1.0);
}
