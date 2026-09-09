shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = clamp(floor(UV * 2.0), vec2(0.0), vec2(1.0));
	vec2 uv = fract(UV * 2.0);
	vec2 p = uv - vec2(0.5);
	float seed = hash21(cell + vec2(0.73, 2.17));
	float ang = atan(p.y, p.x);
	float rad = 0.34
		+ 0.022 * sin(ang * 3.0 + seed * 6.2831853)
		+ 0.012 * sin(ang * 5.0 + seed * 2.4);
	float d = length(p);
	float sdf = d - rad;

	float alpha = 1.0 - smoothstep(-0.004, 0.018, sdf);
	float core = 1.0 - smoothstep(-0.08, 0.006, sdf);
	vec3 col = mix(vec3(0.92, 0.97, 1.0), vec3(1.0), core);
	float a = clamp(alpha, 0.0, 1.0);
	ALBEDO = col * a;
	ALPHA = a;
}
