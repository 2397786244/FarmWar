shader_type spatial;

render_mode blend_mix,
			depth_draw_opaque,
			cull_disabled,
			diffuse_burley,
			specular_schlick_ggx;


// ====================
// 颜色
// ====================

uniform vec4 shallow_color : source_color = vec4(
	0.12, 0.62, 0.72, 1.0
);

uniform vec4 deep_color : source_color = vec4(
	0.025, 0.22, 0.34, 1.0
);

uniform vec4 crest_color : source_color = vec4(
	0.65, 0.95, 1.0, 1.0
);


// ====================
// 河水流动参数
// ====================

// UV 中的流动方向。
// 河流沿 Z 轴时通常使用 (0, 1) 或 (0, -1)。
uniform vec2 flow_direction = vec2(0.0, 1.0);

uniform float flow_speed : hint_range(0.0, 3.0) = 0.55;


// ====================
// 顶点波浪参数
// ====================

uniform float wave_height : hint_range(0.0, 0.5) = 0.08;

uniform float wave_scale : hint_range(0.5, 30.0) = 7.0;

uniform float secondary_wave_scale : hint_range(0.5, 30.0) = 12.0;


// ====================
// 表面波纹参数
// ====================

uniform float ripple_scale : hint_range(1.0, 50.0) = 18.0;

uniform float ripple_strength : hint_range(0.0, 1.0) = 0.32;

uniform float normal_strength : hint_range(0.0, 2.0) = 0.65;

uniform float crest_strength : hint_range(0.0, 1.0) = 0.23;


// ====================
// 材质参数
// ====================

uniform float water_alpha : hint_range(0.0, 1.0) = 0.82;

uniform float water_roughness : hint_range(0.0, 1.0) = 0.16;

uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.7;


// 计算顶点高度
float get_wave_height(vec2 uv, float time_value) {
	vec2 direction = normalize(flow_direction);

	vec2 wave_uv = uv * wave_scale;

	float primary_wave = sin(
		dot(wave_uv, direction) * 6.28318
		- time_value * flow_speed * 4.0
		+ sin(wave_uv.x * 1.7) * 0.45
	);

	vec2 secondary_direction = normalize(
		vec2(-direction.y, direction.x) * 0.65
		+ direction * 0.35
	);

	float secondary_wave = sin(
		dot(uv * secondary_wave_scale, secondary_direction) * 6.28318
		- time_value * flow_speed * 2.6
	);

	return (
		primary_wave * 0.68
		+ secondary_wave * 0.32
	) * wave_height;
}


void vertex() {
	// PlaneMesh 默认位于 XZ 平面，因此 Y 是高度。
	VERTEX.y += get_wave_height(UV, TIME);
}


void fragment() {
	vec2 direction = normalize(flow_direction);
	vec2 side_direction = vec2(-direction.y, direction.x);

	// 让 UV 持续向河流方向移动。
	vec2 flowing_uv = UV * ripple_scale;
	flowing_uv -= direction * TIME * flow_speed;

	// 第一层：顺着河流方向的波纹。
	float ripple_a = sin(
		dot(flowing_uv, direction) * 6.28318
		+ sin(dot(flowing_uv, side_direction) * 1.8) * 0.7
	);

	// 第二层：斜向的小波纹，避免水面过于规则。
	vec2 diagonal_direction = normalize(
		direction * 0.75 + side_direction * 0.45
	);

	float ripple_b = sin(
		dot(flowing_uv * 1.37, diagonal_direction) * 6.28318
		- TIME * flow_speed * 1.8
	);

	float ripple = ripple_a * 0.65 + ripple_b * 0.35;
	ripple = ripple * 0.5 + 0.5;

	// 波峰区域。
	float crest = smoothstep(0.72, 0.96, ripple);

	// 简单的程序化法线扰动。
	float slope_x =
		cos(flowing_uv.x * 3.4 + TIME * flow_speed * 2.0)
		* normal_strength;

	float slope_y =
		cos(flowing_uv.y * 5.1 - TIME * flow_speed * 3.2)
		* normal_strength;

	NORMAL_MAP = vec3(
		0.5 + slope_x * 0.12,
		0.5 + slope_y * 0.12,
		1.0
	);

	NORMAL_MAP_DEPTH = normal_strength;

	// 根据波纹混合深浅颜色。
	vec3 water_color = mix(
		deep_color.rgb,
		shallow_color.rgb,
		ripple * ripple_strength + 0.25
	);

	// 波峰浅色高光。
	water_color += crest_color.rgb * crest * crest_strength;

	// Fresnel：斜视水面时更加明亮。
	float fresnel = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		3.0
	);

	water_color += shallow_color.rgb
		* fresnel
		* fresnel_strength;

	ALBEDO = water_color;
	ROUGHNESS = mix(
		water_roughness,
		0.05,
		fresnel
	);
	METALLIC = 0.04;
	SPECULAR = 0.9;
	ALPHA = water_alpha;
}