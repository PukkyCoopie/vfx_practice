shader_type particles;
render_mode disable_force, disable_velocity;

uniform float tile_side = 109.5;
uniform vec2 wind = vec2(0.0);
uniform vec2 gust = vec2(0.0);
uniform vec2 center = vec2(0.0);

float random(float seed) {
	return fract(sin(seed * 127.1 + 311.7) * 43758.5453);
}

void start() {
	float seed = float(NUMBER) + float(RANDOM_SEED % uint(10000));
	CUSTOM = vec4(0.0, random(seed + 1.0), random(seed + 2.0), random(seed + 3.0));
	float angle = CUSTOM.y * 6.283185;
	vec2 outward = vec2(cos(angle), sin(angle));
	vec2 origin = vec2(random(seed + 4.0) - 0.5, random(seed + 5.0) - 0.5) * vec2(1.5, 1.35);
	TRANSFORM = EMISSION_TRANSFORM;
	TRANSFORM[3].xy += origin * tile_side;
	VELOCITY = vec3(outward * tile_side * (0.10 + CUSTOM.z * 0.10), 0.0);
}

void process() {
	CUSTOM.x += DELTA;
	float life = CUSTOM.x / LIFETIME;
	float phase = CUSTOM.y * 6.283185;
	float age = CUSTOM.x;
	vec2 swirl = vec2(sin(age * 2.7 + phase) + 0.45 * sin(age * 5.1 + CUSTOM.z * 19.0),
		cos(age * 2.1 + phase * 1.7) + 0.35 * sin(age * 4.3 + CUSTOM.z * 13.0));
	// Differing phases and frequencies give each flake its own curling path.
	float nearby = 1.0 - smoothstep(0.65, 2.0, length(TRANSFORM[3].xy - center) / tile_side);
	vec2 target = vec2(0.0, 0.10) + swirl * 0.22 + nearby * (wind * 0.85 + gust * 1.35);
	float size = tile_side / 109.5 * mix(0.28, 0.62, CUSTOM.z);
	VELOCITY.xy = mix(VELOCITY.xy, target * tile_side, 1.0 - exp(-DELTA * 3.0));
	TRANSFORM[3].xy += VELOCITY.xy * DELTA;
	float angle = phase + age * (CUSTOM.z - 0.5) * 0.6;
	TRANSFORM[0] = vec4(cos(angle) * size, sin(angle) * size, 0.0, 0.0);
	TRANSFORM[1] = vec4(-sin(angle) * size, cos(angle) * size, 0.0, 0.0);
	COLOR = vec4(1.0, 1.0, 1.0, smoothstep(0.0, 0.16, life) * (1.0 - smoothstep(0.50, 1.0, life)));
	if (life >= 1.0) { ACTIVE = false; }
}
