shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_add;

uniform vec4 color : source_color = vec4(0.78, 0.94, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.35;
uniform float overall_intensity : hint_range(0.0, 3.0) = 1.0;

varying float v_weight;

void vertex() {
	v_weight = COLOR.a;
}

void fragment() {
	float a = v_weight * intensity * overall_intensity;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = color.rgb * a;
	ALPHA = 1.0;
}
