shader_type spatial;
render_mode unshaded, specular_disabled, shadows_disabled, cull_disabled, depth_draw_never, blend_add;

uniform vec4 color_inner : source_color = vec4(1.0, 0.97, 1.0, 1.0);
uniform vec4 color_outer : source_color = vec4(0.38, 0.08, 0.68, 1.0);
uniform float intensity = 1.0;
uniform float edge_power : hint_range(0.4, 4.0) = 1.6;
uniform int toon_steps : hint_range(2, 6) = 3;

varying float v_across;
varying float v_weight;
varying float v_along;

void vertex() {
	v_across = UV.x * 2.0 - 1.0;
	v_weight = COLOR.a;
	v_along = UV.y;
	float crawl = sin(UV.y * 26.0 + TIME * 52.0) * 0.55 + sin(UV.y * 61.0 - TIME * 79.0) * 0.32;
	VERTEX += vec3(v_across * crawl * 0.0065, crawl * 0.0028, 0.0);
}

void fragment() {
	float n = pow(max(1.0 - abs(v_across), 0.0), edge_power);
	n = clamp(n * 1.18, 0.0, 1.0);
	float steps = float(max(toon_steps, 2));
	float q = floor(n * steps + 1e-4) / steps;
	if (q < 0.001) {
		discard;
	}
	float travel = fract(v_along * 2.4 - TIME * 7.2);
	float pulse = 0.78 + 0.22 * (1.0 - abs(travel * 2.0 - 1.0));
	float buzz = 0.9 + 0.1 * sin(TIME * 88.0 + v_along * 37.0);
	float a = q * intensity * v_weight * pulse * buzz;
	vec3 col = mix(color_outer.rgb, color_inner.rgb, q);
	ALBEDO = col * a;
	ALPHA = 1.0;
}
