shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 color1 : source_color = vec4(0.146, 0.146, 0.146, 1.0);
uniform vec4 color2 : source_color = vec4(0.116, 0.116, 0.116, 1.0);
uniform float col = 20.0;
uniform float row = 20.0;

void fragment() {
	float checker = mod(floor(UV.x * col) + floor(UV.y * row), 2.0);
	vec4 color = mix(color1, color2, checker);
	ALBEDO = color.rgb;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	ALPHA = color.a;
}
