shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 rect_size = vec2(268.8);
uniform vec2 tile_origin = vec2(74.4);
uniform vec2 tile_size = vec2(120.0);
uniform float chamfer_px = 6.0;
uniform float time = 0.0;
uniform vec2 flow_direction = vec2(0.0, 1.0);
uniform float wind_strength = 0.0;
uniform float flame_speed : hint_range(0.0, 2.0) = 1.75;
// Lifetime is independent of travel speed: larger values soften birth/death.
uniform float lifetime_scale : hint_range(1.0, 3.0) = 1.80;
uniform float edge_flame_height : hint_range(0.0, 0.2) = 0.12;
uniform sampler2D letter_mask : filter_linear, repeat_disable;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.03 + vec2(7.1, 3.7)) * 0.25
		+ noise(p * 4.11 + vec2(2.8, 9.1)) * 0.10;
}

float tile_distance(vec2 p, float cut) {
	p = abs(p - vec2(0.5));
	return max(max(p.x, p.y) - 0.5,
		(p.x + p.y - 1.0 + cut) * 0.70710678);
}

void fragment() {
    vec2 p = (UV * rect_size - tile_origin) / tile_size;
    p.y = 1.0 - p.y;
    // Keep all roots and the underlying heat field in their original coordinates.
    vec2 axis = normalize(flow_direction);
    vec2 fire_p = p;
    float aa = 0.8 / tile_size.x;
    float clock = time * flame_speed;
    float sdf = tile_distance(p, chamfer_px / tile_size.x);
    // Final opacity is exactly zero here. Avoid all 40 sheets on the padding.
    if (sdf >= 0.16 + wind_strength * 0.20) { discard; }
    float tile_mask = 1.0 - smoothstep(-aa, aa, sdf);
    // Finite-lived flame sheets, rather than a color ramp over liquid-like noise.
    // Each sheet travels through the square and beyond it with the same shape/color.
    float fire = 0.0;
    float core = 0.0;
    float soft = 0.0;
    float surface = 0.0;
    float surface_core = 0.0;
    float surface_shade = 0.0;
    float curl = noise(fire_p * vec2(5.0, 4.0) - vec2(0.0, clock * 2.0));
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        float duration = mix(0.7, 1.25, hash21(vec2(fi, 3.1)));
        float age = clock / (duration * lifetime_scale) + hash21(vec2(fi, 9.2));
        float life = fract(age);
        // d(travel)/dt = flame_speed/duration, unchanged by lifetime_scale.
        // Center the longer path so sheets enter from deeper within the volume.
        float travel = (life - 0.5) * lifetime_scale + 0.5;
        vec2 seed = vec2(fi, floor(age));
        vec2 origin = vec2(mix(0.025, 0.975, hash21(seed + 1.7)),
            mix(-0.03, 0.87, hash21(seed + 4.3)));
        vec2 outward = normalize(origin - 0.5 + vec2(0.001));
        float lateral = smoothstep(0.25, 0.5, abs(origin.x - 0.5));
        vec2 drift = vec2(outward.x * lateral * 0.16, 0.35 + hash21(seed + 2.2) * 0.28);
        // Bottom-edge tongues expand briefly before buoyancy carries them inward/up.
        drift.y -= (1.0 - smoothstep(0.0, 0.12, origin.y)) * 0.28;
        vec2 center = origin + drift * travel;
        center.x += sin(travel * 4.5 + fi * 2.1) * 0.035 * life;
        float grow_end = mix(0.16, 0.28, hash21(seed + 11.4));
        float fade_start = mix(0.30, 0.65, hash21(seed + 12.8));
        float envelope = smoothstep(0.0, grow_end, life) * (1.0 - smoothstep(fade_start, 1.0, life));
        // Stable during each birth, resampled on the next: shape variety, not jitter.
        float shape = hash21(seed + 15.3);
        float handedness = hash21(seed + 17.8) < 0.5 ? -1.0 : 1.0;
        float bend = mix(0.12, 0.55, hash21(seed + 19.1));
        vec2 radius = vec2(mix(0.11, 0.21, hash21(seed + 6.7)),
            mix(0.20, 0.36, hash21(seed + 8.4))) * mix(0.60, 1.0, envelope);
        vec2 q = (fire_p - center) / radius;
        if (wind_strength > 0.002) {
            // Bend each sheet along its own spine, pinned at the root. The wind
            // affects the tip quadratically, unlike rotating the whole texture.
            vec2 root = center - vec2(0.0, radius.y);
            float height = radius.y * 2.0;
            float response = wind_strength * mix(0.78, 1.06, hash21(seed + 43.2));
            vec2 pull = (axis * 1.25 - vec2(0.0, 0.80)) * height * response;
            vec2 flutter = vec2(axis.y, -axis.x) * height * response * (curl - 0.5) * 0.14;
            float best = 1000.0;
            vec2 previous = root;
            for (int segment = 0; segment < 6; segment++) {
                float t0 = float(segment) / 6.0;
                float t1 = float(segment + 1) / 6.0;
                vec2 next = root + vec2(0.0, height * t1) + (pull + flutter) * t1 * t1;
                vec2 tangent = next - previous;
                float along = dot(p - previous, tangent) / max(dot(tangent, tangent), 0.000001);
                vec2 nearest = previous + tangent * clamp(along, 0.0, 1.0);
                float distance_sq = dot(p - nearest, p - nearest);
                if (distance_sq < best) {
                    best = distance_sq;
                    float extent = clamp(along, 0.0, 1.0);
                    if (segment == 0 && along < 0.0) { extent = along; }
                    if (segment == 5 && along > 1.0) { extent = along; }
                    vec2 normal = normalize(vec2(tangent.y, -tangent.x));
                    q = vec2(dot(p - nearest, normal) / radius.x, mix(t0, t1, extent) * 2.0 - 1.0);
                }
                previous = next;
            }
        }
        q.x += sin(q.y * mix(1.1, 3.4, shape) - life * mix(2.5, 6.0, hash21(seed + 21.2)) + fi) * bend;
        q.x += handedness * q.y * q.y * mix(0.04, 0.23, hash21(seed + 22.6));
        // Broad hot root narrowing into a bent, fragile tip.
        float taper = clamp(mix(0.48, 0.92, shape) - q.y * mix(0.22, 0.50, hash21(seed + 25.1)), 0.10, 1.15);
        float body = length(vec2(q.x / taper, q.y)) - 1.0;
        body += (curl - 0.5) * 0.65;
        float falloff = 1.10;
        float mask = exp(-max(body + 1.0, 0.0) * max(body + 1.0, 0.0) * falloff) * envelope;
        // A small subset forms crisp foreground sheets over the softer hot volume.
        // They share its motion and continue past the boundary instead of being stickers.
        if (i < 12) {
            // Root remains in the luminous volume; only the upper part lifts forward.
            float emergence = smoothstep(-0.50, 0.45, q.y);
            float edge = max(aa / radius.x, mix(0.38, 0.12, emergence));
            float sheet = body + mix(0.10, 0.34, hash21(seed + 26.7));
            // Mix uncut wisps, hooked sheets, forked tips and torn ribbons.
            // Unlike the former fixed right-hand bite, no one silhouette dominates.
            if (shape > 0.25 && shape < 0.72) {
                vec2 bite_center = vec2(handedness * mix(0.40, 0.77, hash21(seed + 29.2)),
                    mix(-0.10, 0.55, hash21(seed + 31.4)) + life * 0.18);
                float bite_radius = mix(0.30, 0.62, hash21(seed + 33.8));
                sheet = max(sheet, bite_radius - length(q - bite_center));
            } else if (shape >= 0.72) {
                // An open slit climbs through the tip, separating unequal branches.
                float slit_x = handedness * 0.14 + sin(q.y * 2.2 + life * 5.0) * 0.08;
                float slit_width = mix(0.07, 0.18, hash21(seed + 36.5));
                float slit = max(abs(q.x - slit_x) - slit_width, mix(0.02, 0.40, shape) - q.y);
                sheet = max(sheet, -slit);
                if (shape > 0.89) {
                    vec2 cut = q - vec2(-handedness * 0.58, -0.12 + life * 0.55);
                    sheet = max(sheet, 0.36 - length(cut));
                }
            }
            float cover = (1.0 - smoothstep(-edge, edge, sheet)) * envelope * emergence;
            // Uneven heat patches break up the repeated concentric outline look.
            float hot_patch = noise(q * 1.6 + seed * 3.1 + vec2(0.0, -life * 2.0));
            float inner = (1.0 - smoothstep(-0.32, -0.06, sheet)) * envelope;
            inner *= mix(0.35, 1.0, smoothstep(0.22, 0.78, hot_patch));
            surface = max(surface, cover);
            surface_core = max(surface_core, inner);
            surface_shade = max(surface_shade, (1.0 - smoothstep(-edge, edge, sheet - mix(0.035, 0.085, shape))) * envelope * emergence);
        }
        fire += mask * 0.65;
        core += mask * 0.65 * (1.0 - life * 0.35);
        soft += exp(-max(body, 0.0) * 3.0) * envelope * 0.12;
    }
    float heat = clamp(core, 0.0, 1.0);
    float flame = smoothstep(0.15, 0.95, fire);
    // Warm orange fill keeps the tile readable without dark red islands or cracks.
    vec3 base = mix(vec3(0.80, 0.17, 0.025), vec3(1.0, 0.36, 0.04), clamp(soft, 0.0, 1.0));
    vec3 flame_color = mix(vec3(1.0, 0.53, 0.055), vec3(1.0, 0.88, 0.36), smoothstep(0.45, 1.20, core));
    flame_color = mix(flame_color, vec3(1.0, 0.97, 0.70), smoothstep(1.25, 1.85, core));
    base = mix(base, vec3(0.98, 0.42, 0.06), 0.35);
    flame_color = mix(flame_color, vec3(1.0, 0.91, 0.47), 0.25);
    float outside_fade = 1.0 - smoothstep(0.04, 0.16 + wind_strength * 0.20, sdf);
    float vapor = smoothstep(0.18, 0.40, fire - max(sdf, 0.0) * 6.0) * outside_fade;
    float combined = tile_mask + (1.0 - tile_mask) * vapor;
    vec3 color = mix(base, flame_color, flame);
    color = mix(color, flame_color, 1.0 - tile_mask);
    // A warm edge underneath each sheet separates it from the volume without black outlines.
    float separation = max(surface_shade - surface, 0.0) * tile_mask;
    color = mix(color, vec3(0.96, 0.30, 0.025), separation * 0.24);
    vec3 sheet_color = mix(vec3(1.0, 0.62, 0.08), vec3(1.0, 0.93, 0.48), surface_core);
    float sheet_alpha = surface * mix(outside_fade, 1.0, tile_mask);
    color = mix(color, sheet_color, sheet_alpha * 0.90);
    combined = max(combined, sheet_alpha);
    // Subtle edge depth, deliberately secondary to the gas-like motion.
    float bevel = (1.0 - smoothstep(0.0, 0.028, -sdf)) * tile_mask;
    color *= 1.0 - bevel * 0.10;
    // The Waw letter mask stays stable; offset samples suggest an inset.
    vec2 uv = vec2(p.x, 1.0 - p.y);
    float glyph = texture(letter_mask, uv).a;
    float above = texture(letter_mask, uv + vec2(0.0, -1.0 / tile_size.y)).a;
    float below = texture(letter_mask, uv + vec2(0.0, 1.0 / tile_size.y)).a;
    color = mix(color, vec3(1.0, 0.76, 0.30), max(below - glyph, 0.0) * tile_mask * 0.8);
    color *= 1.0 - max(above - glyph, 0.0) * tile_mask * 0.55;
    vec3 ink = mix(vec3(0.12, 0.045, 0.02), vec3(0.32, 0.12, 0.03), heat * 0.7);
    color = mix(color, ink, glyph * tile_mask);
    COLOR = vec4(max(color, vec3(0.0)), combined);
}
