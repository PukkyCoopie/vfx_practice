shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_add;

uniform float glow : hint_range(0.5, 8.0) = 3.2;
uniform float overall_intensity : hint_range(0.0, 3.0) = 1.0;

void vertex() {
	float pscale = length(MODEL_MATRIX[0].xyz);
	float ca = cos(INSTANCE_CUSTOM.x);
	float sa = sin(INSTANCE_CUSTOM.x);
	vec2 p = VERTEX.xy;
	VERTEX.xy = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

	mat4 mat_world = mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0) * pscale,
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0) * pscale,
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	vec2 e = (UV - vec2(0.5)) / 0.42;
	float d = length(e);
	float mask = 1.0 - smoothstep(0.72, 1.0, d);
	float core = 1.0 - smoothstep(0.0, 0.45, d);
	float a = mask * COLOR.a * overall_intensity;
	if (a < 0.004) {
		discard;
	}
	vec3 ice = mix(vec3(0.55, 0.85, 1.0), vec3(1.0, 1.0, 1.0), core);
	ALBEDO = ice * COLOR.rgb * glow * a;
	ALPHA = 1.0;
}
