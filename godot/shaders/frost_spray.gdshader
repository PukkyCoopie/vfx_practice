shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, specular_disabled, shadows_disabled, blend_premul_alpha;

// Stamp a random cell from the 2x2 smoke atlas (CUSTOM.z), with toon banding.
uniform sampler2D sprite : filter_linear, repeat_disable;
uniform float overall_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float smoke_alpha : hint_range(0.05, 1.0) = 0.8;
uniform float cast_weight : hint_range(0.0, 1.0) = 1.0;
uniform float density : hint_range(0.05, 2.5) = 1.0;
uniform float core_boost : hint_range(0.0, 3.0) = 1.0;
uniform int toon_steps : hint_range(2, 6) = 3;
uniform int layer_mode : hint_range(0, 1) = 0;

varying vec2 v_atlas_uv;

void vertex() {
	float cell = clamp(floor(INSTANCE_CUSTOM.z * 3.999), 0.0, 3.0);
	vec2 origin = vec2(mod(cell, 2.0), floor(cell * 0.5)) * 0.5;
	// Larger inset avoids sampling atlas tile borders / seams.
	vec2 inset = vec2(0.03);
	v_atlas_uv = origin + mix(inset, vec2(0.5) - inset, UV);

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
	if (cast_weight < 0.001) {
		discard;
	}
	vec4 s = texture(sprite, v_atlas_uv);
	float raw = s.a * COLOR.a;
	if (raw < 0.003) {
		discard;
	}

	float steps = float(max(toon_steps, 2));
	float q = floor(clamp(raw, 0.0, 1.0) * steps + 1e-4) / steps;
	if (q < 0.001) {
		discard;
	}

	float a = q * density * overall_intensity * smoke_alpha * cast_weight;
	if (layer_mode == 1) {
		a *= 0.7;
	}
	if (a < 0.003) {
		discard;
	}

	vec3 col = COLOR.rgb * s.rgb;
	if (layer_mode == 0) {
		col = mix(col, vec3(0.94, 0.98, 1.0), q * 0.35 * core_boost);
		col *= mix(0.95, 1.12, q * core_boost);
	}

	ALBEDO = col * a;
	ALPHA = a;
}
