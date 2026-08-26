shader_type spatial;

// Draw only the outside side of the selected vehicle's screen-space mask.
// Since the mask is already the union of the whole vehicle, internal meshes
// do not create separate outlines.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.94);
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.94;
uniform float depth_bias : hint_range(0.0, 0.01) = 0.0015;


void vertex() {
	// QuadMesh vertices are already in the -1..1 range. Bypass world-space
	// placement so this quad always covers the active camera viewport. Godot
	// 4.3+ uses reverse-Z, so the clip-space near-plane value is 1.0.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float mask_at(vec2 uv) {
	return texture(mask_texture, clamp(uv, vec2(0.0), vec2(1.0))).r;
}


float visible_mask_at(vec2 uv, float scene_depth) {
	vec4 mask_sample = texture(mask_texture, clamp(uv, vec2(0.0), vec2(1.0)));
	if (mask_sample.r < 0.5) {
		return 0.0;
	}
	// Godot's reverse-Z depth buffer uses larger values for pixels closer to the
	// camera. A mask sample with a smaller depth than the main scene belongs
	// behind a wall or another occluder.
	if (mask_sample.g >= scene_depth - depth_bias) {
		return 1.0;
	}
	return 0.0;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / max(vec2(textureSize(mask_texture, 0)), vec2(1.0));
	float center_mask = mask_at(uv);
	float scene_depth = texture(depth_texture, uv).r;
	float neighbor_mask = 0.0;
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv + vec2(texel.x, 0.0), scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv - vec2(texel.x, 0.0), scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv + vec2(0.0, texel.y), scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv - vec2(0.0, texel.y), scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv + texel, scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv - texel, scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv + vec2(texel.x, -texel.y), scene_depth));
	neighbor_mask = max(neighbor_mask, visible_mask_at(uv + vec2(-texel.x, texel.y), scene_depth));

	// Only paint outside the mask. This avoids drawing an inner border around
	// holes or separate front-facing surfaces.
	float edge = neighbor_mask * (1.0 - step(0.5, center_mask));
	ALBEDO = outline_color.rgb;
	ALPHA = edge * outline_alpha * outline_color.a;
}
