extends RefCounted
class_name VehicleColorCatalog

## The same eleven paint choices are used by the runtime vehicle shop and the
## map editor.  Network messages carry only these stable ids; the Color values
## are resolved again on the authority.
const OPTIONS: Array[Dictionary] = [
	{"id": "black", "label": "黑色", "color": Color("000000")},
	{"id": "dark_gray", "label": "深灰色", "color": Color("3f454b")},
	{"id": "white", "label": "白色", "color": Color("ffffff")},
	{"id": "red", "label": "红色", "color": Color("d62828")},
	{"id": "orange", "label": "橙色", "color": Color("f28c28")},
	{"id": "gold", "label": "金黄色", "color": Color("d4a017")},
	{"id": "dark_green", "label": "深绿色", "color": Color("1f6b3a")},
	{"id": "sky_blue", "label": "天蓝色", "color": Color("4db8ff")},
	{"id": "dark_purple", "label": "深紫色", "color": Color("4b1f6f")},
	{"id": "pink", "label": "粉色", "color": Color("ec6fa9")},
	{"id": "silver_gray", "label": "银灰色", "color": Color("aeb4bc")},
]


static func get_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option_value: Variant in OPTIONS:
		if option_value is Dictionary:
			result.append((option_value as Dictionary).duplicate(true))
	return result


static func has_color(color_id: String) -> bool:
	return not _find_option(color_id).is_empty()


static func normalize_id(color_id: String, fallback_id := "black") -> String:
	var option := _find_option(color_id)
	if option.is_empty():
		option = _find_option(fallback_id)
	return str(option.get("id", fallback_id))


static func get_color(color_id: String, fallback_id := "black") -> Color:
	var option := _find_option(color_id)
	if option.is_empty():
		option = _find_option(fallback_id)
	if option.is_empty():
		return Color.BLACK
	var color_value: Variant = option.get("color", Color.BLACK)
	return color_value as Color if color_value is Color else Color.BLACK


static func get_label(color_id: String) -> String:
	var option := _find_option(color_id)
	return str(option.get("label", color_id)) if not option.is_empty() else color_id


static func get_id_for_color(color: Color, fallback_id := "") -> String:
	"""Resolve an authored Color back to its stable catalog id when possible."""
	for option_value: Variant in OPTIONS:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var option_color_value: Variant = option.get("color", Color.BLACK)
		if not option_color_value is Color:
			continue
		var option_color := option_color_value as Color
		if absf(option_color.r - color.r) <= 0.0005 \
				and absf(option_color.g - color.g) <= 0.0005 \
				and absf(option_color.b - color.b) <= 0.0005:
			return str(option.get("id", fallback_id))
	return fallback_id


static func _find_option(color_id: String) -> Dictionary:
	var normalized := color_id.strip_edges().to_lower()
	for option_value: Variant in OPTIONS:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		if str(option.get("id", "")).to_lower() == normalized:
			return option
	return {}
