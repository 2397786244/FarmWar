shader_type canvas_item;
render_mode unshaded;

// The world pass is rendered on a ColorRect below the gameplay HUD.  Keeping
// the screen texture linear-filtered makes the sharpening pass less harsh at
// non-native window resolutions.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

// Global color grade.
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.05;
uniform float saturation : hint_range(0.0, 2.0) = 1.08;
uniform float grade_strength : hint_range(0.0, 1.0) = 0.18;
uniform vec4 shadow_tint : source_color = vec4(0.97, 0.99, 1.02, 1.0);
uniform vec4 highlight_tint : source_color = vec4(1.02, 0.99, 0.95, 1.0);

// Subtle unsharp mask and edge darkening.
uniform float sharpen_strength : hint_range(0.0, 1.0) = 0.12;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.10;
uniform float vignette_start : hint_range(0.0, 2.5) = 1.50;
uniform float vignette_end : hint_range(0.5, 2.5) = 1.95;
uniform float chromatic_aberration_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float chromatic_aberration_strength : hint_range(0.0, 1.0) = 0.16;

// Runtime camera effects. motion_blur_amount is driven by the local player
// and stays at zero during ordinary stationary gameplay and menus.
uniform float motion_blur_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float motion_blur_strength : hint_range(0.0, 1.0) = 0.22;
uniform float motion_blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float soft_glow_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float soft_glow_strength : hint_range(0.0, 1.0) = 0.24;
uniform float soft_glow_threshold : hint_range(0.0, 1.0) = 0.72;


vec3 sample_screen(vec2 uv) {
	return texture(screen_texture, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}


vec3 bright_pass(vec2 uv) {
	vec3 sample_color = sample_screen(uv);
	float luminance = dot(sample_color, vec3(0.299, 0.587, 0.114));
	float threshold_end = max(soft_glow_threshold + 0.01, 1.0);
	float mask = smoothstep(soft_glow_threshold, threshold_end, luminance);
	return sample_color * mask;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 original = sample_screen(uv);
	vec3 source = original;

	// A compact radial camera blur. The player supplies the activity amount,
	// while the shader only handles the inexpensive center-outward sampling.
	float motion_mix = clamp(
		motion_blur_enabled * motion_blur_strength * motion_blur_amount,
		0.0,
		1.0
	);
	if (motion_mix > 0.001) {
		vec2 radial_step = (uv - vec2(0.5)) * 0.06 * motion_mix;
		vec3 radial_blur = original;
		for (int sample_index = 1; sample_index <= 4; sample_index++) {
			float sample_position = float(sample_index) / 4.0;
			radial_blur += sample_screen(uv + radial_step * sample_position);
			radial_blur += sample_screen(uv - radial_step * sample_position);
		}
		source = radial_blur / 9.0;
	}

	// Four-neighbour unsharp mask.  This adds definition without the halos of
	// a strong edge-detection outline.
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec3 blur = (
		sample_screen(uv + vec2(texel.x, 0.0)) +
		sample_screen(uv - vec2(texel.x, 0.0)) +
		sample_screen(uv + vec2(0.0, texel.y)) +
		sample_screen(uv - vec2(0.0, texel.y))
	) * 0.25;
	vec3 color = source + (source - blur) * sharpen_strength;

	// Contrast, exposure-like brightness, and saturation adjustment.
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);

	// Slightly cool shadows and slightly warm highlights suit the farm/daylight
	// palette while leaving the team colors readable.
	float shadow_mask = 1.0 - smoothstep(0.05, 0.55, luminance);
	float highlight_mask = smoothstep(0.45, 0.95, luminance);
	color *= mix(vec3(1.0), shadow_tint.rgb, shadow_mask * grade_strength);
	color *= mix(vec3(1.0), highlight_tint.rgb, highlight_mask * grade_strength);

	// Bright-pass soft glow. It is intentionally subtle and stays below the
	// HUD because this ColorRect is rendered on the world effect layer.
	if (soft_glow_enabled > 0.001 && soft_glow_strength > 0.001) {
		vec2 glow_radius = texel * 5.0;
		vec3 glow = bright_pass(uv) * 0.28;
		glow += bright_pass(uv + vec2(glow_radius.x, 0.0)) * 0.18;
		glow += bright_pass(uv - vec2(glow_radius.x, 0.0)) * 0.18;
		glow += bright_pass(uv + vec2(0.0, glow_radius.y)) * 0.18;
		glow += bright_pass(uv - vec2(0.0, glow_radius.y)) * 0.18;
		color += glow * soft_glow_strength * 0.75;
	}

	// A restrained RGB split gives the whole image a cinematic/sci-fi lens
	// character. The offset grows toward the corners, where the effect is least
	// distracting, and the green channel remains centered for a stable image.
	if (chromatic_aberration_enabled > 0.001 && chromatic_aberration_strength > 0.001) {
		vec2 chromatic_centered = uv * 2.0 - 1.0;
		chromatic_centered.x *= SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
		float chromatic_radius = length(chromatic_centered);
		vec2 chromatic_direction = chromatic_centered / max(chromatic_radius, 0.000001);
		float chromatic_offset = chromatic_aberration_strength * 0.012;
		float chromatic_mix = chromatic_aberration_enabled * smoothstep(0.12, 1.8, chromatic_radius);
		vec3 split_color = color;
		split_color.r = sample_screen(uv + chromatic_direction * chromatic_offset).r;
		split_color.b = sample_screen(uv - chromatic_direction * chromatic_offset).b;
		color = mix(color, split_color, chromatic_mix);
	}

	// Aspect-correct vignette so it remains circular on widescreen displays.
	vec2 centered = uv * 2.0 - 1.0;
	// SCREEN_PIXEL_SIZE stores the inverse viewport dimensions, so its Y/X
	// ratio gives the viewport aspect ratio without relying on a viewport-size
	// built-in that is unavailable in Godot 4 CanvasItem shaders.
	centered.x *= SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	float vignette = smoothstep(
		vignette_start,
		vignette_end,
		length(centered)
	);
	color *= 1.0 - vignette * vignette_strength;
	color = clamp(color, vec3(0.0), vec3(1.0));

	COLOR = vec4(mix(original, color, effect_strength), 1.0);
}
