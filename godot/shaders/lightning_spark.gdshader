shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_add;

uniform float glow : hint_range(0.5, 12.0) = 8.5;
uniform int toon_steps : hint_range(2, 6) = 3;

void fragment() {
	vec2 e = vec2((UV.x - 0.5) / 0.22, (UV.y - 0.5) / 0.46);
	float n = clamp(1.0 - length(e), 0.0, 1.0);
	float steps = float(max(toon_steps, 2));
	float q = floor(n * steps + 1e-4) / steps;
	if (q < 0.001) {
		discard;
	}
	vec3 bolt = vec3(0.42, 0.08, 0.95);
	if (q >= 0.34) {
		bolt = vec3(0.95, 0.48, 1.35);
	}
	if (q >= 0.67) {
		bolt = vec3(1.7, 1.62, 1.95);
	}
	float a = COLOR.a;
	ALBEDO = bolt * COLOR.rgb * glow * a;
	ALPHA = 1.0;
}
