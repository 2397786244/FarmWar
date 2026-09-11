shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_render : filter_linear, repeat_disable;
uniform vec2 terrain_origin = vec2(-256.0, -256.0);
uniform vec2 terrain_size = vec2(512.0, 512.0);

varying vec2 world_xz;


void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


void fragment() {
	vec2 mask_uv = (world_xz - terrain_origin) / terrain_size;
	vec4 surface_value = texture(surface_render, clamp(mask_uv, vec2(0.0), vec2(1.0)));

	ALBEDO = surface_value.rgb;
	ROUGHNESS = surface_value.a;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
