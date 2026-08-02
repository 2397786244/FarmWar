shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.12, 0.62, 0.72, 1.0);
uniform vec4 deep_color : source_color = vec4(0.025, 0.22, 0.34, 1.0);
uniform vec4 crest_color : source_color = vec4(0.65, 0.95, 1.0, 1.0);
uniform float wave_scale : hint_range(0.5, 30.0) = 7.0;
uniform float secondary_wave_scale : hint_range(0.5, 30.0) = 12.0;
uniform float ripple_scale : hint_range(1.0, 50.0) = 18.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.32;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.65;
uniform float crest_strength : hint_range(0.0, 1.0) = 0.23;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.82;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.16;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.7;
uniform float depth_factor : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	// A single fixed direction and a low speed keep the water readable and
	// stylized without exposing a flow-direction setting in map data.
	const vec2 FLOW_DIRECTION = vec2(0.0, 1.0);
	const float FLOW_SPEED = 0.075;
	vec2 uv = UV * ripple_scale - FLOW_DIRECTION * TIME * FLOW_SPEED;
	vec2 side_direction = vec2(-1.0, 0.0);
	float ripple_a = sin(dot(uv, vec2(0.0, 1.0)) * 6.28318 + sin(dot(uv, side_direction) * 1.8) * 0.7);
	vec2 diagonal_direction = normalize(vec2(0.75, 0.45));
	float ripple_b = sin(dot(uv * 1.37, diagonal_direction) * 6.28318 - TIME * FLOW_SPEED * 1.4);
	float ripple = (ripple_a * 0.65 + ripple_b * 0.35) * 0.5 + 0.5;
	// Quantized bands give the surface a low-poly/cartoon highlight instead of
	// the fine noisy ripples of the old stream shader.
	float band = floor(ripple * 5.0) / 5.0;
	float crest = smoothstep(0.72, 0.96, band);

	float slope_x = cos(uv.x * 3.4) * normal_strength;
	float slope_y = cos(uv.y * 5.1) * normal_strength;
	NORMAL_MAP = vec3(0.5 + slope_x * 0.12, 0.5 + slope_y * 0.12, 1.0);
	NORMAL_MAP_DEPTH = normal_strength;

	float shallow_visibility = 1.0 - depth_factor;
	vec3 water_color = mix(
		deep_color.rgb,
		shallow_color.rgb,
		band * ripple_strength + 0.25 + shallow_visibility * 0.18
	);
	water_color += crest_color.rgb * crest * crest_strength;
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	water_color += shallow_color.rgb * fresnel * fresnel_strength;
	ALBEDO = water_color;
	ROUGHNESS = mix(water_roughness, 0.05, fresnel);
	METALLIC = 0.04;
	SPECULAR = 0.9;
	// Shallow water is more transparent, so the seabed remains visible. Deep
	// water becomes opaque and darkens toward deep_color.
	ALPHA = water_alpha * mix(0.62, 1.0, depth_factor);
}
