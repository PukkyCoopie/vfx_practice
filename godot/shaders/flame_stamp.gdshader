shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

uniform sampler2D sprite : filter_linear, repeat_disable;

varying vec2 v_atlas_uv;

void vertex() {
	float cell = clamp(floor(INSTANCE_CUSTOM.z * 3.999), 0.0, 3.0);
	vec2 origin = vec2(mod(cell, 2.0), floor(cell * 0.5)) * 0.5;
	vec2 inset = vec2(0.004);
	v_atlas_uv = origin + mix(inset, vec2(0.5) - inset, UV);
	float ca = cos(INSTANCE_CUSTOM.x);
	float sa = sin(INSTANCE_CUSTOM.x);
	float pscale = length(MODEL_MATRIX[0].xyz);
	mat4 mat_world = mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0) * pscale,
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(ca, -sa, 0.0, 0.0),
		vec4(sa, ca, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
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
