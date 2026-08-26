shader_type spatial;

// The mask pass deliberately ignores every authored vehicle material. The
// screen-space pass receives one opaque union of all vehicle geometry instead
// of trying to outline each MeshInstance3D independently.
render_mode unshaded, cull_disabled, depth_draw_opaque;


void fragment() {
	// R is the binary vehicle mask. G stores the same camera-space depth as the
	// main viewport so the outline pass can reject pixels hidden by world objects.
	ALBEDO = vec3(1.0, FRAGCOORD.z, 0.0);
	ROUGHNESS = 1.0;
}
