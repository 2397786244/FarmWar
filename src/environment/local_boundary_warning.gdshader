shader_type spatial;

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 boundary_color : source_color = vec4(1.0, 0.12, 0.16, 0.42);
uniform float visibility_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 2.6;


void fragment() {
	float vertical_fade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.86, 1.0, UV.y));
	float slow_wave = 0.72 + 0.28 * sin(UV.y * 44.0 - TIME * 1.8);
	float broad_pulse = 0.82 + 0.18 * sin(TIME * 2.2);
	float strength = vertical_fade * slow_wave * broad_pulse;
	ALBEDO = boundary_color.rgb;
	EMISSION = boundary_color.rgb * emission_strength * strength;
	ALPHA = boundary_color.a * visibility_alpha * (0.45 + 0.55 * strength);
}
