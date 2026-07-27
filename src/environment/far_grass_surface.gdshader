shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_palette : filter_nearest, repeat_disable;


void fragment() {
	// Surface ID 0 is CrestonTown/Ground/Grass.
	vec4 grass_surface = texture(surface_palette, vec2(0.5 / 256.0, 0.5));
	ALBEDO = grass_surface.rgb;
	ROUGHNESS = grass_surface.a;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
