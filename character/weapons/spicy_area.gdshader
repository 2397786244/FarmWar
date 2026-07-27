shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;


float hash(float n) {
	return fract(sin(n * 91.173) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash(dot(cell, vec2(17.0, 59.4)));
	float b = hash(dot(cell + vec2(1.0, 0.0), vec2(17.0, 59.4)));
	float c = hash(dot(cell + vec2(0.0, 1.0), vec2(17.0, 59.4)));
	float d = hash(dot(cell + vec2(1.0, 1.0), vec2(17.0, 59.4)));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float liquid_droplets(vec2 p) {
	float droplets = 0.0;
	for (int index = 0; index < 8; index++) {
		float i = float(index);
		float along = mix(-0.90, 0.90, (i + 0.35) / 8.0);
		float radius = mix(0.055, 0.125, hash(i + 3.0));
		float top_offset = mix(-0.012, 0.080, hash(i + 17.0));
		float side_offset = mix(-0.012, 0.080, hash(i + 31.0));
		vec2 top = vec2(along, 1.0 + top_offset);
		vec2 bottom = vec2(-along, -1.0 - top_offset);
		vec2 right = vec2(1.0 + side_offset, along);
		vec2 left = vec2(-1.0 - side_offset, -along);
		droplets = max(droplets, 1.0 - smoothstep(radius * 0.72, radius, length(p - top)));
		droplets = max(droplets, 1.0 - smoothstep(radius * 0.72, radius, length(p - bottom)));
		droplets = max(droplets, 1.0 - smoothstep(radius * 0.72, radius, length(p - right)));
		droplets = max(droplets, 1.0 - smoothstep(radius * 0.72, radius, length(p - left)));
	}
	return droplets;
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge_wobble_x = (value_noise(vec2(p.y * 5.0, 2.0)) - 0.5) * 0.10;
	float edge_wobble_y = (value_noise(vec2(p.x * 5.0, 7.0)) - 0.5) * 0.10;
	float core = step(abs(p.x), 1.0 + edge_wobble_x) * step(abs(p.y), 1.0 + edge_wobble_y);
	float liquid = max(core, liquid_droplets(p));
	if (liquid < 0.01) {
		discard;
	}

	float pool = value_noise(p * 4.5 + vec2(TIME * 0.12, -TIME * 0.08));
	float fine_grain = value_noise(p * 18.0 - vec2(TIME * 0.22, TIME * 0.10));
	float ripples = 0.5 + 0.5 * sin((p.x * 11.0 + p.y * 7.0) + TIME * 1.2 + pool * 4.0);
	float highlight = smoothstep(0.66, 0.93, pool) * smoothstep(0.42, 0.82, ripples);
	vec3 deep_red = vec3(0.20, 0.004, 0.002);
	vec3 chili_red = vec3(0.78, 0.018, 0.006);
	vec3 hot_red = vec3(1.0, 0.105, 0.018);
	ALBEDO = mix(deep_red, chili_red, 0.38 + pool * 0.48);
	ALBEDO = mix(ALBEDO, hot_red, highlight * 0.42 + fine_grain * 0.08);
	EMISSION = ALBEDO * (0.18 + highlight * 0.42);
	ALPHA = (0.82 + fine_grain * 0.12) * liquid * opacity;
}
