extends RefCounted
class_name EquipmentCatalog

const DEFINITIONS_PATH := "res://data/equipment_definitions.json"

static var _definitions: Dictionary = {}
static var _loaded := false


static func get_definition(equipment_id: String) -> Dictionary:
	_ensure_loaded()
	var value: Variant = _definitions.get(equipment_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_scene_path(equipment_id: String) -> String:
	return str(get_definition(equipment_id).get("scene_path", ""))


static func get_leg_scene_path(equipment_id: String, right_leg: bool) -> String:
	var definition := get_definition(equipment_id)
	var key := "right_scene_path" if right_leg else "left_scene_path"
	return str(definition.get(key, definition.get("scene_path", "")))


static func get_extra_slots(equipment_id: String) -> int:
	return maxi(0, int(get_definition(equipment_id).get("extra_slots", 0)))


static func get_extra_weight_kg(equipment_id: String) -> float:
	return maxf(0.0, float(get_definition(equipment_id).get("extra_weight_kg", 0.0)))


static func get_max_hp(equipment_id: String) -> float:
	return maxf(0.0, float(get_definition(equipment_id).get("max_hp", 0.0)))


static func get_movement_speed_multiplier(equipment_id: String) -> float:
	return maxf(1.0, float(get_definition(equipment_id).get("movement_speed_multiplier", 1.0)))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Equipment definitions not found: %s" % DEFINITIONS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid equipment definitions: %s" % DEFINITIONS_PATH)
		return
	var entries: Variant = (parsed as Dictionary).get("equipment", [])
	if not entries is Array:
		return
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var equipment_id := str(entry.get("id", ""))
		if not equipment_id.is_empty():
			_definitions[equipment_id] = entry.duplicate(true)
