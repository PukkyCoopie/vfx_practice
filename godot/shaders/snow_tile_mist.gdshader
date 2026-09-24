shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float time = 0.0;
uniform vec2 motion = vec2(0.0);
uniform vec2 flow_offset = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float cloud(vec2 p) {
	return noise(p) * 0.57 + noise(p * 2.1 + 8.0) * 0.28 + noise(p * 4.2 + 17.0) * 0.15;
}

// Continuous domain-warped density, bounded to a narrow band around the tile.
float tile_distance(vec2 p) {
	vec2 q = abs(p) - vec2(0.435);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.065;
}

// Two overlapping backtraces refresh a Cartesian noise field without exposing
// a reset. Time advects 2D features; distance is used only for edge attenuation.
float advected_cloud(vec2 p, vec2 velocity, float phase, vec2 offset) {
	vec2 field = (p - velocity * phase * 2.8) * 7.0 + offset - flow_offset;
	vec2 curl = vec2(noise(field * 0.65 + 4.0), noise(field * 0.65 + 17.0)) - 0.5;
	return cloud(field + curl * 0.65);
}

void fragment() {
	vec2 p = (UV - 0.5) * 1.8;
	float original_distance = tile_distance(p);
	if (original_distance < -0.025 || original_distance > 0.29) { discard; }
	vec2 q = p - motion * smoothstep(0.25, 0.70, length(p));
	vec2 outward = normalize(q * q * q + vec2(0.00001));
	vec2 sideways = vec2(-outward.y, outward.x);
	float local_flow = noise(q * 3.5 + vec2(5.0, time * 0.08));
	vec2 velocity = outward * mix(0.065, 0.12, local_flow)
		+ sideways * (noise(q * 4.0 + 19.0) - 0.5) * 0.08;
	float phase = fract(time / 2.8);
	float second_phase = fract(phase + 0.5);
	float weight = pow(sin(phase * 3.141593), 2.0);
	float first = advected_cloud(q, velocity, phase, vec2(0.0));
	float second = advected_cloud(q, velocity, second_phase, vec2(11.7, 7.3));
	// Threshold before crossfade so unrelated patches don't merge into a band.
	float density = mix(smoothstep(0.36, 0.72, second), smoothstep(0.36, 0.72, first), weight);
	float source = smoothstep(0.28, 0.66, noise(q * 5.0 + vec2(time * 0.10, 3.0)));
	float d = max(tile_distance(q), 0.0);
	// Slowly varying dissipation breaks the uniform-width border. Most wisps
	// disappear close to the tile; occasional softer strands reach farther.
	float reach_noise = noise(q * 4.2 + vec2(time * 0.075, -time * 0.055) + 31.0);
	float reach = mix(0.065, 0.23, smoothstep(0.22, 0.78, reach_noise));
	float fade = exp(-d * mix(19.0, 10.0, reach_noise))
		* (1.0 - smoothstep(reach * 0.28, reach, d));
	// Invisible safety margin, beyond the varying visible extinction distance.
	fade *= 1.0 - smoothstep(0.24, 0.285, original_distance);
	vec3 tint = mix(vec3(0.53, 0.66, 0.74), vec3(0.81, 0.88, 0.93), density);
	COLOR = vec4(tint, density * mix(0.18, 1.0, source) * fade * 0.48);
}
