shader_type canvas_item;
render_mode unshaded, blend_add, skip_vertex_transform;

uniform float glow = 1.2;
uniform float turbulence_px = 5.0;
varying float particle_seed;
varying float particle_life;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + 1.0), u.x), u.y);
}

void vertex() {
	particle_seed = INSTANCE_CUSTOM.z * 97.3;
	particle_life = clamp(INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.001), 0.0, 1.0);
	// Per-particle eddies in canvas space, independent of the particle's spin/scale.
	// Lifetime-driven motion freezes with GPU playback and works in Compatibility.
	vec2 sample_pos = vec2(particle_life * 3.6, particle_seed);
	vec2 eddy = vec2(noise(sample_pos), noise(sample_pos + vec2(4.8, 13.1))) - 0.5;
	vec2 offset = eddy * turbulence_px * smoothstep(0.0, 0.22, particle_life);
	VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy + offset;
}

void fragment() {
    vec2 e = vec2((UV.x - 0.5) / 0.36, (UV.y - 0.5) / 0.38);
    float d = length(e);
    float mask = 1.0 - smoothstep(0.88, 1.0, d);
    float a = mask * COLOR.a;
    if (a < 0.004) { discard; }
    float heat = 1.0 - smoothstep(0.0, 0.55, d);
    vec3 ember = mix(vec3(1.0, 0.48, 0.08), vec3(1.0, 0.98, 0.86), heat);
    COLOR = vec4(ember * COLOR.rgb * glow * a, a);
}
