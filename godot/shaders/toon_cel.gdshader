shader_type spatial;
render_mode specular_disabled, shadows_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear;
uniform bool use_texture = true;
uniform int light_steps : hint_range(2, 8) = 3;
uniform float shade_floor : hint_range(0.0, 0.5) = 0.14;
uniform float light_wrap : hint_range(0.0, 0.6) = 0.14;

void fragment() {
	vec3 color = albedo_color.rgb;
	if (use_texture) {
		color *= texture(albedo_texture, UV).rgb;
	}
	ALBEDO = color;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float wrapped = clamp(ndotl * (1.0 - light_wrap) + light_wrap, 0.0, 1.0);
	float steps = float(max(light_steps, 2));
	float band = floor(wrapped * steps + 1e-4) / (steps - 1.0);
	band = clamp(band, 0.0, 1.0);
	band = mix(shade_floor, 1.0, band);
	DIFFUSE_LIGHT += LIGHT_COLOR * band * ATTENUATION;
}
