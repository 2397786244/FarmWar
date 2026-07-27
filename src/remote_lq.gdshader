shader_type canvas_item;
render_mode unshaded;

/*
黑白监控 / 夜视图传后处理 Shader
适用于 Godot 4.x 的 ColorRect 全屏覆盖层。

用途：
- BoomBuggy 自爆小车监控画面
- SmallMouse 机器鼠双目/侦察监控画面

特点：
1. 真正灰度图像链路：不保留 RGB 色偏、饱和度或彩色噪点
2. 低分辨率图传像素化
3. 轻微桶形畸变
4. 灰度扫描线、数字噪点、横向信号抖动
5. 横向撕裂与黑色丢包条带
6. 信号差时的黑屏闪烁和暗角
7. 灰阶级数可控，可模拟低清监控/夜视传感器
8. effect_strength = 0 时恢复原始彩色画面
*/

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;


/* =========================
   总开关与信号参数
   ========================= */

/* 0 = 原始屏幕画面；1 = 完整黑白图传效果 */
uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

/* 1 = 信号很好；0 = 信号极差 */
uniform float signal_strength : hint_range(0.0, 1.0) = 1.0;


/* =========================
   图传分辨率与像素感
   ========================= */

/*
推荐：
480x270：普通低清黑白监控
640x360：较清晰的机器鼠侦察画面
320x180：强干扰 / 老旧无线监控
*/
uniform vec2 transmit_resolution = vec2(480.0, 270.0);

/* 1.0 正常，越大像素越粗 */
uniform float pixelation_scale : hint_range(0.5, 4.0) = 1.0;


/* =========================
   单色成像与灰阶
   ========================= */

/* 基础亮度 */
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

/* 基础对比度 */
uniform float contrast : hint_range(0.0, 2.5) = 1.18;

/* 黑位抬升/压暗。越大，阴影越容易变黑。 */
uniform float black_level : hint_range(0.0, 0.45) = 0.06;

/* 白位裁切。越大，高亮区域越容易变白。 */
uniform float white_level : hint_range(0.55, 1.50) = 1.00;

/* 灰度曲线；< 1 让暗部更亮，> 1 让暗部更压暗。 */
uniform float monochrome_gamma : hint_range(0.35, 2.20) = 0.90;

/*
灰阶数量：
256 = 正常黑白摄像头
64  = 常见压缩监控感
24  = 较差图传
8   = 强干扰/极低清
*/
uniform float grayscale_steps : hint_range(2.0, 256.0) = 64.0;


/* =========================
   镜头与图传干扰
   ========================= */

/* 桶形畸变，0.02~0.04 比较自然 */
uniform float barrel_distortion : hint_range(0.0, 0.15) = 0.025;

/* 扫描线强度 */
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.14;

/* 黑白数字雪花强度 */
uniform float noise_amount : hint_range(0.0, 0.50) = 0.045;

/* 每条扫描线的横向抖动最大量 */
uniform float horizontal_jitter : hint_range(0.0, 0.08) = 0.008;

/* 横向撕裂条带强度 */
uniform float tear_strength : hint_range(0.0, 0.12) = 0.025;

/* 横向丢包条带概率 */
uniform float packet_loss_amount : hint_range(0.0, 1.0) = 0.10;

/* 信号差时黑色条带强度 */
uniform float blackout_amount : hint_range(0.0, 1.0) = 0.48;

/* 镜头边缘暗角 */
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.42;


/* =========================
   随机函数
   ========================= */

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


/* =========================
   辅助函数
   ========================= */

vec2 clamp_uv(vec2 uv) {
	return clamp(uv, vec2(0.001), vec2(0.999));
}


float to_luminance(vec3 color) {
	/* Rec. 601 风格亮度权重，适合监控画面灰度化。 */
	return dot(color, vec3(0.299, 0.587, 0.114));
}


float adjust_monochrome_levels(float value) {
	value *= brightness;
	value = (value - 0.5) * contrast + 0.5;

	/* 压黑黑位。 */
	value = max(value - black_level, 0.0);
	value /= max(1.0 - black_level, 0.001);

	/* 白位裁切与灰度曲线。 */
	value /= max(white_level, 0.001);
	value = clamp(value, 0.0, 1.0);
	value = pow(value, 1.0 / max(monochrome_gamma, 0.001));

	/* 模拟有限位深的黑白图传。 */
	float steps = max(floor(grayscale_steps), 2.0);
	value = floor(value * (steps - 1.0) + 0.5) / (steps - 1.0);

	return clamp(value, 0.0, 1.0);
}


/* =========================
   主流程
   ========================= */

void fragment() {
	vec2 original_uv = SCREEN_UV;
	vec3 original_color = texture(
		screen_texture,
		clamp_uv(original_uv)
	).rgb;

	/* 1 = 干扰最强。 */
	float interference = 1.0 - signal_strength;
	float fx = effect_strength;


	/* ==================================================
	   1. 轻微桶形畸变
	   ================================================== */

	vec2 centered_uv = original_uv * 2.0 - 1.0;
	float radius_sq = dot(centered_uv, centered_uv);

	vec2 barrel_uv = original_uv + (
		centered_uv
		* radius_sq
		* barrel_distortion
	);

	vec2 distorted_uv = clamp_uv(
		mix(original_uv, barrel_uv, fx)
	);


	/* ==================================================
	   2. 模拟低分辨率图传
	   effect_strength=0 时回到原始 UV，不发生像素化。
	   ================================================== */

	vec2 effective_resolution = max(
		transmit_resolution / max(pixelation_scale, 0.01),
		vec2(8.0)
	);

	vec2 quantized_uv = floor(
		distorted_uv * effective_resolution
	) / effective_resolution;

	quantized_uv += 0.5 / effective_resolution;
	quantized_uv = clamp_uv(quantized_uv);

	vec2 pixel_uv = mix(distorted_uv, quantized_uv, fx);


	/* ==================================================
	   3. 行级横向抖动
	   ================================================== */

	float time_30fps = floor(TIME * 30.0);
	float row_id = floor(pixel_uv.y * effective_resolution.y);
	float row_random = hash21(vec2(row_id, time_30fps));

	float line_jitter = (
		(row_random - 0.5)
		* horizontal_jitter
		* (0.15 + interference * 1.45)
		* fx
	);

	pixel_uv.x += line_jitter;


	/* ==================================================
	   4. 数字图传横向撕裂
	   ================================================== */

	float tear_time = floor(TIME * 8.0);
	float tear_band_id = floor(pixel_uv.y * 42.0);
	float tear_random = hash21(vec2(tear_band_id, tear_time));

	float tear_trigger = step(
		0.975 - interference * 0.18,
		tear_random
	);

	float tear_offset = (
		(hash21(vec2(tear_band_id + 17.0, tear_time)) - 0.5)
		* tear_strength
		* (0.2 + interference * 1.5)
		* tear_trigger
		* fx
	);

	pixel_uv.x += tear_offset;
	pixel_uv = clamp_uv(pixel_uv);


	/* ==================================================
	   5. 灰度摄像头采样
	   不做 RGB 分离，整个画面从这里开始是单色信号。
	   ================================================== */

	vec3 sampled_color = texture(screen_texture, pixel_uv).rgb;
	float gray = to_luminance(sampled_color);
	gray = adjust_monochrome_levels(gray);


	/* ==================================================
	   6. 横向扫描线
	   ================================================== */

	float scanline_wave = sin(
		original_uv.y
		* effective_resolution.y
		* 3.14159265
	);

	float scanline = 1.0 - (
		(0.5 + 0.5 * scanline_wave)
		* scanline_strength
		* fx
	);

	gray *= scanline;


	/* ==================================================
	   7. 黑白数字雪花
	   ================================================== */

	vec2 noise_grid = floor(original_uv * effective_resolution);

	float static_noise = hash31(
		vec3(noise_grid, floor(TIME * 24.0))
	) - 0.5;

	float noise_strength = (
		noise_amount
		* (0.2 + interference * 1.6)
		* fx
	);

	gray += static_noise * noise_strength;


	/* ==================================================
	   8. 横向亮度干扰条带
	   ================================================== */

	float band_row = floor(original_uv.y * 120.0);
	float band_time = floor(TIME * 10.0);

	float band_random = hash21(vec2(band_row, band_time));

	float interference_band = step(
		0.992 - interference * 0.15,
		band_random
	);

	float band_noise = (
		hash21(vec2(band_row + 91.0, band_time)) - 0.5
	) * 0.85;

	gray += (
		band_noise
		* interference_band
		* interference
		* fx
	);


	/* ==================================================
	   9. 信号差时的黑色丢包条带
	   ================================================== */

	float packet_row = floor(original_uv.y * 72.0);
	float packet_time = floor(TIME * 5.0);

	float packet_random = hash21(
		vec2(packet_row + 203.0, packet_time)
	);

	float packet_threshold = (
		0.998
		- packet_loss_amount * interference * 0.12
	);

	float packet_drop = step(packet_threshold, packet_random);

	float packet_darkness = (
		packet_drop
		* blackout_amount
		* interference
		* fx
	);

	gray = mix(gray, 0.0, packet_darkness);


	/* ==================================================
	   10. 偶发强干扰闪烁
	   ================================================== */

	float flicker_tick = floor(TIME * 12.0);

	float global_flicker_random = hash11(flicker_tick);
	float global_flicker = step(
		0.992 - interference * 0.10,
		global_flicker_random
	);

	gray *= 1.0 - global_flicker * interference * 0.45 * fx;


	/* ==================================================
	   11. 暗角
	   ================================================== */

	float vignette = smoothstep(0.25, 1.35, radius_sq);
	gray *= 1.0 - vignette * vignette_strength * fx;


	/* ==================================================
	   12. 输出
	   effect_strength=0：原始彩色画面
	   effect_strength=1：完整黑白监控画面
	   ================================================== */

	gray = clamp(gray, 0.0, 1.0);

	vec3 monochrome_color = vec3(gray);
	vec3 final_color = mix(
		original_color,
		monochrome_color,
		fx
	);

	COLOR = vec4(final_color, 1.0);
}
