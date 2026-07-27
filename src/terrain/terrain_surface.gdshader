shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_mask : filter_nearest, repeat_disable;
uniform sampler2D surface_palette : filter_nearest, repeat_disable;
uniform vec2 terrain_origin = vec2(-256.0, -256.0);
uniform vec2 terrain_size = vec2(512.0, 512.0);

varying vec2 world_xz;


void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


vec4 read_surface(float encoded_id) {
	float surface_id = floor(encoded_id * 255.0 + 0.5);
	return texture(surface_palette, vec2((surface_id + 0.5) / 256.0, 0.5));
}


void fragment() {
	vec2 mask_uv = (world_xz - terrain_origin) / terrain_size;
	vec4 mask_value = texture(surface_mask, clamp(mask_uv, vec2(0.0), vec2(1.0)));
	vec4 base_surface = read_surface(mask_value.r);
	vec4 overlay_surface = read_surface(mask_value.g);
	float blend_amount = clamp(mask_value.b, 0.0, 1.0);

	ALBEDO = mix(base_surface.rgb, overlay_surface.rgb, blend_amount);
	ROUGHNESS = mix(base_surface.a, overlay_surface.a, blend_amount);
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
