shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

uniform sampler2D sprite : filter_linear, repeat_disable;

varying vec2 v_atlas_uv;

void vertex() {
	float cell = clamp(floor(INSTANCE_CUSTOM.z * 3.999), 0.0, 3.0);
	vec2 origin = vec2(mod(cell, 2.0), floor(cell * 0.5)) * 0.5;
	vec2 inset = vec2(0.004);
	v_atlas_uv = origin + mix(inset, vec2(0.5) - inset, UV);

	float pscale = length(MODEL_MATRIX[0].xyz);
	float life = INSTANCE_CUSTOM.y;
	float k = smoothstep(0.0, 0.46, life);
	float stretch_along = mix(1.6, 1.0, k);
	float stretch_across = mix(0.9, 1.0, k);

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
	vec4 s = texture(sprite, v_atlas_uv);
	float a = s.a * COLOR.a;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = s.rgb * COLOR.rgb * COLOR.a;
	ALPHA = a;
}
