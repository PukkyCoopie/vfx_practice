shader_type canvas_item;
render_mode unshaded, blend_mix;

// x = normalized bolt age, y = simulation time (pause/speed aware).
uniform vec2 arc_clock = vec2(0.0);
uniform float tile_side = 109.5;

void vertex() {
	// Deform the existing line mesh on the GPU; no per-frame line rebuilding.
	// A shared spatial field keeps connected branches and all three glow layers
	// together. Slow travel plus a faster ripple adds twitch without random jumps.
	vec2 p = VERTEX / max(tile_side, 1.0);
	float time = arc_clock.y;
	float travel = time * 19.0;
	vec2 wave = vec2(
		sin(p.y * 14.0 + p.x * 4.0 - travel),
		sin(p.x * 16.0 - p.y * 3.0 + travel * 1.13)
	);
	vec2 twitch = vec2(
		sin(p.y * 27.0 - p.x * 9.0 + time * 43.0),
		sin(p.x * 25.0 + p.y * 7.0 - time * 39.0)
	);
	VERTEX += (wave * 0.020 + twitch * 0.006) * tile_side;
}

void fragment() {
	// Stretch UV.x follows distance along the complete polyline, not screen X.
	float age = arc_clock.x;
	float arrival = UV.x * 0.34;
	float since = age - arrival;
	float ignition = smoothstep(0.0, 0.045, since);
	float head = 1.0 - smoothstep(0.045, 0.16, since);
	float wake = 0.42 * (1.0 - smoothstep(0.12, 0.64, since));
	float restrike = smoothstep(0.0, 0.025, since - 0.30)
		* (1.0 - smoothstep(0.045, 0.15, since - 0.30)) * 0.65;
	COLOR.a *= ignition * clamp(head + wake + restrike, 0.0, 1.0);
}
