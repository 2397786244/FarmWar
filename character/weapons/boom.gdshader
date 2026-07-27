shader_type spatial;

render_mode unshaded,
			cull_disabled,
			shadows_disabled;


uniform vec4 core_color : source_color = vec4(
	0.12, 0.22, 0.85, 1.0
);

uniform vec4 energy_color : source_color = vec4(
	0.62, 0.20, 1.0, 1.0
);

uniform vec4 hot_color : source_color = vec4(
	0.90, 0.72, 1.0, 1.0
);


uniform float emission_strength :
	hint_range(0.0, 10.0) = 3.0;

uniform float pulse_speed :
	hint_range(0.0, 10.0) = 3.2;

uniform float pulse_amount :
	hint_range(0.0, 1.0) = 0.22;

uniform float fresnel_power :
	hint_range(0.1, 10.0) = 2.4;

uniform float band_density :
	hint_range(1.0, 30.0) = 10.0;

uniform float band_speed :
	hint_range(-10.0, 10.0) = 3.5;

uniform float band_strength :
	hint_range(0.0, 2.0) = 0.65;


// 将模型局部顶点坐标传给片元阶段，
// 不依赖模型有没有UV。
varying vec3 local_position;


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	// 呼吸亮度。
	float pulse = (
		1.0
		+ sin(TIME * pulse_speed)
		* pulse_amount
	);

	// 第一层流动能量纹。
	float wave_a = sin(
		(
			local_position.y
			+ local_position.x * 0.40
		)
		* band_density
		- TIME * band_speed
	);

	// 第二层交叉能量纹。
	float wave_b = sin(
		(
			local_position.z
			- local_position.x * 0.55
		)
		* band_density
		+ TIME * band_speed * 0.72
	);

	float combined_wave = (
		wave_a * 0.62
		+ wave_b * 0.38
	);

	combined_wave = (
		combined_wave * 0.5
		+ 0.5
	);

	float energy_band = smoothstep(
		0.62,
		0.94,
		combined_wave
	);

	// Fresnel边缘光。
	float facing = clamp(
		dot(
			normalize(NORMAL),
			normalize(VIEW)
		),
		0.0,
		1.0
	);

	float fresnel = pow(
		1.0 - facing,
		fresnel_power
	);

	// 中心、流动纹路和边缘颜色。
	vec3 final_color = mix(
		core_color.rgb,
		energy_color.rgb,
		energy_band * band_strength
	);

	final_color = mix(
		final_color,
		hot_color.rgb,
		fresnel
	);

	ALBEDO = final_color;

	// 大于1的Emission用于触发HDR Glow。
	EMISSION = final_color
		* emission_strength
		* pulse
		* (
			0.65
			+ energy_band * 0.55
			+ fresnel * 0.75
		);
}