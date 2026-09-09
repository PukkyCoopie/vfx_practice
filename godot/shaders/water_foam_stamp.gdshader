shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

uniform sampler2D sprite : filter_linear, repeat_disable;
uniform float glow : hint_range(0.5, 8.0) = 2.4;
uniform bool use_circle = false;
uniform int stamp_kind = 0;

varying vec2 v_atlas_uv;

void vertex() {
	float cell = clamp(floor(INSTANCE_CUSTOM.z * 3.999), 0.0, 3.0);
	vec2 origin = vec2(mod(cell, 2.0), floor(cell * 0.5)) * 0.5;
	vec2 inset = vec2(0.006);
	v_atlas_uv = origin + mix(inset, vec2(0.5) - inset, UV);

	float pscale = length(MODEL_MATRIX[0].xyz);
	float life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	float k = smoothstep(0.0, 0.28, life);
	float stretch_along = mix(1.28, 1.0, k);
	float stretch_across = mix(0.86, 1.0, k);
	if (stamp_kind == 1) {
		stretch_along = mix(1.06, 1.0, k);
		stretch_across = mix(1.08, 1.0, k);
	}

	vec3 vel = MODEL_MATRIX[1].xyz;
	float vlen = length(vel);
	vec3 vel_n = vlen > 0.0001 ? vel / vlen : INV_VIEW_MATRIX[1].xyz;
	vec3 vel_view = mat3(VIEW_MATRIX) * vel_n;
	vec2 dir = vec2(vel_view.x, vel_view.y);
	float dlen = length(dir);
	dir = dlen > 0.001 ? dir / dlen : vec2(0.0, 1.0);
	vec2 perp = vec2(-dir.y, dir.x);

	float ca = cos(INSTANCE_CUSTOM.x);
	float sa = sin(INSTANCE_CUSTOM.x);
	vec2 p = VERTEX.xy;
	p = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
	float along = dot(p, dir);
	float across = dot(p, perp);
	VERTEX.xy = dir * (along * stretch_along) + perp * (across * stretch_across);

	mat4 mat_world = mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0) * pscale,
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	float a;
	vec3 rgb;
	if (use_circle) {
		vec2 p = UV * 2.0 - 1.0;
		float d = length(p);
		float core = 1.0 - smoothstep(0.42, 0.78, d);
		a = (1.0 - smoothstep(0.72, 1.0, d)) * COLOR.a;
		rgb = mix(vec3(0.86, 0.94, 1.0), vec3(1.0), core);
	} else {
		vec4 s = texture(sprite, v_atlas_uv);
		a = s.a * COLOR.a;
		rgb = s.rgb * COLOR.rgb;
	}
	if (a < 0.004) {
		discard;
	}
	float g = stamp_kind == 1 ? glow * 1.35 : glow;
	vec3 col = rgb * g;
	ALBEDO = col * a;
	ALPHA = a;
}
