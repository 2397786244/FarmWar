shader_type spatial;

// The mask is the union of every MeshInstance3D belonging to a scanned target.
// Drawing only outside that union produces one model silhouette instead of an
// outline around each imported child mesh. Deliberately omit the main depth
// texture so detected targets remain visible through terrain and buildings.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(0.92, 0.08, 0.08, 0.96);
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.96;
uniform float thickness_pixels : hint_range(1.0, 6.0) = 4.0;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float mask_at(vec2 uv) {
	return texture(mask_texture, clamp(uv, vec2(0.0), vec2(1.0))).r;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / max(vec2(textureSize(mask_texture, 0)), vec2(1.0));
	float center = mask_at(uv);
	float outside_mask = 0.0;
	for (int step_index = 1; step_index <= 4; step_index++) {
		float radius = min(float(step_index), thickness_pixels);
		vec2 offset = texel * radius;
		outside_mask = max(outside_mask, mask_at(uv + vec2(offset.x, 0.0)));
		outside_mask = max(outside_mask, mask_at(uv - vec2(offset.x, 0.0)));
		outside_mask = max(outside_mask, mask_at(uv + vec2(0.0, offset.y)));
		outside_mask = max(outside_mask, mask_at(uv - vec2(0.0, offset.y)));
		outside_mask = max(outside_mask, mask_at(uv + offset));
		outside_mask = max(outside_mask, mask_at(uv - offset));
		outside_mask = max(outside_mask, mask_at(uv + vec2(offset.x, -offset.y)));
		outside_mask = max(outside_mask, mask_at(uv + vec2(-offset.x, offset.y)));
	}
	float edge = outside_mask * (1.0 - step(0.5, center));
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.35;
	ALPHA = edge * outline_alpha * outline_color.a;
}
