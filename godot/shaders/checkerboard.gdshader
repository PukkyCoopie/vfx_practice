shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 color1 : source_color = vec4(0.146, 0.146, 0.146, 1.0);
uniform vec4 color2 : source_color = vec4(0.116, 0.116, 0.116, 1.0);
uniform float tile_size = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float size = max(tile_size, 0.001);
	float checker = mod(floor(world_pos.x / size) + floor(world_pos.z / size), 2.0);
	vec4 color = mix(color1, color2, checker);
	ALBEDO = color.rgb;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	ALPHA = color.a;
}
