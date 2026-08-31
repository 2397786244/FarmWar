shader_type spatial;

render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 grid_color : source_color = vec4(0.08, 0.55, 1.0, 0.72);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float longitude_lines = 48.0;
uniform float latitude_lines = 24.0;


float grid_line(float coordinate, float count, float width) {
	float repeated = fract(coordinate * count);
	float cell = min(repeated, 1.0 - repeated);
	return 1.0 - smoothstep(width, width + fwidth(coordinate * count), cell);
}


void fragment() {
	float longitude = grid_line(UV.x, longitude_lines, 0.045);
	float latitude = grid_line(UV.y, latitude_lines, 0.045);
	float grid = max(longitude, latitude);
	ALBEDO = grid_color.rgb;
	EMISSION = grid_color.rgb * (1.4 + grid * 1.2);
	ALPHA = grid * grid_color.a * fade;
}
