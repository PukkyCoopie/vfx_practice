shader_type canvas_item;

uniform float outer_radius : hint_range(0.0, 5.0) = 1.15;
uniform float alpha : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = abs(UV.y - 0.5) * 2.0;
	float v = sqrt((x * x) + (y * y)) / outer_radius;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v * alpha, 0.0, 1.0));
}
