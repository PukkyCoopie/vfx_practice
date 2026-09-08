shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_add;

uniform float glow : hint_range(0.5, 8.0) = 4.4;

void fragment() {
	vec2 e = vec2((UV.x - 0.5) / 0.26, (UV.y - 0.5) / 0.48);
	float d = length(e);
	float mask = 1.0 - smoothstep(0.84, 1.0, d);
	float a = mask * COLOR.a;
	if (a < 0.004) {
		discard;
	}
	float heat = 1.0 - smoothstep(0.0, 0.55, d);
	vec3 ember = mix(vec3(1.0, 0.48, 0.08), vec3(1.0, 0.98, 0.86), heat);
	ALBEDO = ember * COLOR.rgb * glow * a;
	ALPHA = a;
}
