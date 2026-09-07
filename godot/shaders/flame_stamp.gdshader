shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_mix;

uniform sampler2D sprite : source_color, filter_linear, repeat_disable;

void vertex() {
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
	vec4 s = texture(sprite, UV);
	ALBEDO = s.rgb * COLOR.rgb;
	ALPHA = s.a * COLOR.a;
}
