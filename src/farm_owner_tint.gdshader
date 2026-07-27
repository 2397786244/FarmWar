shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 owner_color : source_color = vec4(0.0);
uniform bool use_instance_custom_data = false;
uniform float border_width : hint_range(0.01, 0.25) = 0.08;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.10;
uniform float border_alpha : hint_range(0.0, 1.0) = 0.78;

varying flat vec4 instance_owner_color;

void vertex() {
	instance_owner_color = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 tint = owner_color;
	if (use_instance_custom_data) {
		tint = instance_owner_color;
	}
	float left_edge = 1.0 - step(border_width, UV.x);
	float right_edge = step(1.0 - border_width, UV.x);
	float top_edge = 1.0 - step(border_width, UV.y);
	float bottom_edge = step(1.0 - border_width, UV.y);
	float border = clamp(
		left_edge + right_edge + top_edge + bottom_edge,
		0.0,
		1.0
	);

	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * border * 0.35;
	ALPHA = tint.a * mix(fill_alpha, border_alpha, border);
}
