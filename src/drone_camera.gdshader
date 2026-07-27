shader_type canvas_item;
render_mode unshaded;

/*
无人机 FPV / 图传后处理 Shader
适用于 Godot 4.x 的 ColorRect 全屏覆盖层。

包含：
1. 低分辨率图传像素化
2. 轻微镜头桶形畸变
3. RGB 色偏
4. 扫描线
5. 数字噪点 / 雪花
6. 横向信号抖动
7. 横向丢包条纹
8. 信号差时的黑条、画面干扰
9. 暗角
10. 可调亮度、对比度、饱和度
*/

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;


/* =========================
   总开关与信号参数
   ========================= */

/* 0 = 原始画面，1 = 完整图传效果 */
uniform float effect_strength : hint_range(0.0, 1.0) = 1.0;

/* 1 = 信号很好；0 = 信号极差 */
uniform float signal_strength : hint_range(0.0, 1.0) = 1.0;


/* =========================
   图传分辨率与像素感
   ========================= */

/*
模拟实际图传分辨率。
推荐：
480x270：普通低清 FPV
640x360：较清晰图传
320x180：信号很差或老旧设备
*/
uniform vec2 transmit_resolution = vec2(480.0, 270.0);

/* 像素化程度。1.0 正常，越大越粗糙 */
uniform float pixelation_scale : hint_range(0.5, 4.0) = 1.0;


/* =========================
   镜头与色彩
   ========================= */

/* 桶形畸变，0.02~0.04 比较自然 */
uniform float barrel_distortion : hint_range(0.0, 0.15) = 0.025;

/* RGB 通道错位强度 */
uniform float chroma_shift : hint_range(0.0, 0.02) = 0.0025;

/* 图传画面的基础亮度 */
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

/* 图传画面的基础对比度 */
uniform float contrast : hint_range(0.0, 2.0) = 1.08;

/* 图传画面的基础饱和度 */
uniform float saturation : hint_range(0.0, 2.0) = 0.78;


/* =========================
   扫描线、噪点、抖动
   ========================= */

/* 扫描线强度 */
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.14;

/* 雪花 / 数字噪点强度 */
uniform float noise_amount : hint_range(0.0, 0.5) = 0.045;

/* 横向信号抖动最大量 */
uniform float horizontal_jitter : hint_range(0.0, 0.08) = 0.008;

/* 横向撕裂条带的强度 */
uniform float tear_strength : hint_range(0.0, 0.12) = 0.025;

/* 横向丢包条纹概率 */
uniform float packet_loss_amount : hint_range(0.0, 1.0) = 0.10;

/* 信号差时的暗条强度 */
uniform float blackout_amount : hint_range(0.0, 1.0) = 0.45;

/* 镜头边缘暗角 */
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.38;


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


vec3 adjust_saturation(vec3 color, float amount) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, amount);
}


vec3 adjust_contrast(vec3 color, float amount) {
	return (color - 0.5) * amount + 0.5;
}


void fragment() {
	vec2 original_uv = SCREEN_UV;
	vec2 uv = original_uv;

	/* 信号干扰：1 表示最强干扰 */
	float interference = 1.0 - signal_strength;

	/* effect_strength=0 时等价于关闭全部图传效果 */
	float fx = effect_strength * 1.0;


	/* ==================================================
	   1. 镜头轻微桶形畸变
	   ================================================== */

	vec2 centered_uv = uv * 2.0 - 1.0;
	float radius_sq = dot(centered_uv, centered_uv);

	vec2 distorted_uv = uv + centered_uv * radius_sq * barrel_distortion * fx;
	distorted_uv = clamp_uv(distorted_uv);


	/* ==================================================
	   2. 模拟低分辨率图传
	   ================================================== */

	vec2 effective_resolution = max(
		transmit_resolution / max(pixelation_scale, 0.01),
		vec2(8.0)
	);

	vec2 pixel_uv = floor(distorted_uv * effective_resolution) / effective_resolution;
	pixel_uv += 0.5 / effective_resolution;
	pixel_uv = clamp_uv(pixel_uv);


	/* ==================================================
	   3. 每条扫描线的轻微横向抖动
	   ================================================== */

	float time_30fps = floor(TIME * 30.0);
	float row_id = floor(pixel_uv.y * effective_resolution.y);

	float row_random = hash21(vec2(row_id, time_30fps));

	float line_jitter =
		(row_random - 0.5)
		* horizontal_jitter
		* (0.15 + interference * 1.45)
		* fx;

	pixel_uv.x += line_jitter;


	/* ==================================================
	   4. 模拟数字图传横向撕裂 / 画面错位
	   ================================================== */

	float tear_time = floor(TIME * 8.0);
	float tear_band_id = floor(pixel_uv.y * 42.0);

	float tear_random = hash21(vec2(tear_band_id, tear_time));

	/*
	某些横向条带短暂发生偏移。
	signal_strength 越低，出现频率越高。
	*/
	float tear_trigger = step(
		0.975 - interference * 0.18,
		tear_random
	);

	float tear_offset =
		(hash21(vec2(tear_band_id + 17.0, tear_time)) - 0.5)
		* tear_strength
		* (0.2 + interference * 1.5)
		* tear_trigger
		* fx;

	pixel_uv.x += tear_offset;
	pixel_uv = clamp_uv(pixel_uv);


	/* ==================================================
	   5. RGB 通道分离 / 色偏
	   ================================================== */

	float channel_shift =
		chroma_shift
		* (0.2 + interference * 1.2)
		* fx;

	vec2 red_uv = clamp_uv(pixel_uv + vec2(channel_shift, 0.0));
	vec2 green_uv = clamp_uv(pixel_uv);
	vec2 blue_uv = clamp_uv(pixel_uv - vec2(channel_shift, 0.0));

	float red = texture(screen_texture, red_uv).r;
	float green = texture(screen_texture, green_uv).g;
	float blue = texture(screen_texture, blue_uv).b;

	vec3 color = vec3(red, green, blue);


	/* ==================================================
	   6. 基础颜色处理
	   ================================================== */

	color *= brightness;
	color = adjust_contrast(color, contrast);
	color = adjust_saturation(color, saturation);


	/* ==================================================
	   7. 横向扫描线
	   ================================================== */

	float scanline_wave = sin(
		original_uv.y * effective_resolution.y * 3.14159265
	);

	float scanline =
		1.0 - (
			(0.5 + 0.5 * scanline_wave)
			* scanline_strength
			* fx
		);

	color *= scanline;


	/* ==================================================
	   8. 数字雪花噪点
	   ================================================== */

	vec2 noise_grid = floor(original_uv * effective_resolution);

	float static_noise = hash31(
		vec3(noise_grid, floor(TIME * 24.0))
	) - 0.5;

	float noise_strength =
		noise_amount
		* (0.2 + interference * 1.6)
		* fx;

	color += vec3(static_noise * noise_strength);


	/* ==================================================
	   9. 横向亮度干扰条带
	   ================================================== */

	float band_row = floor(original_uv.y * 120.0);
	float band_time = floor(TIME * 10.0);

	float interference_band_random = hash21(
		vec2(band_row, band_time)
	);

	float interference_band = step(
		0.992 - interference * 0.15,
		interference_band_random
	);

	float band_noise = (
		hash21(vec2(band_row + 91.0, band_time)) - 0.5
	) * 0.85;

	color += vec3(
		band_noise
		* interference_band
		* interference
		* fx
	);


	/* ==================================================
	   10. 信号差时的黑色丢包条带
	   ================================================== */

	float packet_row = floor(original_uv.y * 72.0);
	float packet_time = floor(TIME * 5.0);

	float packet_random = hash21(
		vec2(packet_row + 203.0, packet_time)
	);

	float packet_threshold = 0.998 - packet_loss_amount * interference * 0.12;

	float packet_drop = step(packet_threshold, packet_random);

	float packet_darkness =
		packet_drop
		* blackout_amount
		* interference
		* fx;

	color = mix(color, vec3(0.005, 0.012, 0.018), packet_darkness);


	/* ==================================================
	   11. 偶发强干扰闪烁
	   ================================================== */

	float flicker_tick = floor(TIME * 12.0);

	float global_flicker_random = hash11(flicker_tick);
	float global_flicker = step(
		0.992 - interference * 0.10,
		global_flicker_random
	);

	color *= 1.0 - global_flicker * interference * 0.45 * fx;


	/* ==================================================
	   12. 画面边缘暗角
	   ================================================== */

	float vignette = smoothstep(0.25, 1.35, radius_sq);

	color *= 1.0 - vignette * vignette_strength * fx;


	/* ==================================================
	   13. 最终输出
	   ================================================== */

	color = clamp(color, vec3(0.0), vec3(1.0));

	COLOR = vec4(color, 1.0);
}