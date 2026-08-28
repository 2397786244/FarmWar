shader_type spatial;

render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.16, 0.86);
uniform float glow_height = 0.24;
uniform float emission_strength = 3.2;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.12;

varying float height_ratio;


void vertex() {
	height_ratio = clamp(VERTEX.y / max(glow_height, 0.001), 0.0, 1.0);
}


void fragment() {
	float bottom_fade = smoothstep(0.0, edge_softness, height_ratio);
	float top_fade = 1.0 - smoothstep(0.72, 1.0, height_ratio);
	float strength = bottom_fade * top_fade;
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * emission_strength * strength;
	ALPHA = glow_color.a * strength;
}
