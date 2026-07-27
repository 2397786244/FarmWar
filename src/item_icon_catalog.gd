extends RefCounted
class_name ItemIconCatalog

const PRIMARY_WEAPON_PATH := "res://data/primary_weapon_definitions.json"
const SPECIAL_TOOL_PATH := "res://data/special_tool_definitions.json"
const RUNTIME_TOOL_PATH := "res://data/tool_definitions.json"

static var _tool_icons: Dictionary = {}
static var _tool_icons_loaded := false
static var _texture_cache: Dictionary = {}


static func get_item_icon(item: Dictionary) -> Texture2D:
	match str(item.get("kind", "")):
		"ingredient":
			return get_ingredient_icon(
				str(item.get("ingredient_id", "")),
				_is_chopped_ingredient(item)
			)
		"dish":
			return get_dish_icon(str(item.get("dish_id", "")))
		"tool":
			return get_tool_icon(str(item.get("tool_id", "")))
		"equipment":
			return get_equipment_icon(str(item.get("equipment_id", "")))
		"cargo_crate":
			match str(item.get("content_kind", "")):
				"dish": return get_dish_icon(str(item.get("content_id", "")))
				"ingredient", "material": return get_ingredient_icon(str(item.get("content_id", "")))
				"tool", "weapon": return get_tool_icon(str(item.get("content_id", "")))
	return get_icon_for_id(str(item.get("item_id", item.get("id", ""))))


static func get_icon_for_id(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null
	var icon := get_ingredient_icon(item_id)
	if icon != null:
		return icon
	icon = get_dish_icon(item_id)
	if icon != null:
		return icon
	icon = get_equipment_icon(item_id)
	if icon != null:
		return icon
	return get_tool_icon(item_id)


static func get_equipment_icon(equipment_id: String) -> Texture2D:
	var definition := EquipmentCatalog.get_definition(equipment_id)
	var definition_icon := _load_definition_icon(definition)
	if definition_icon != null:
		return definition_icon
	return _load_icon_path("res://assets/icons/items/equipment/%s.png" % equipment_id)


static func get_ingredient_icon(ingredient_id: String, chopped := false) -> Texture2D:
	var definition_icon := _load_definition_icon(IngredientCatalog.get_definition(ingredient_id))
	if definition_icon != null and not chopped:
		return definition_icon
	var suffix := "_chopped" if chopped else ""
	return _load_icon_path(
		"res://assets/icons/items/ingredients/%s%s.png" % [ingredient_id, suffix]
	)


static func get_dish_icon(dish_id: String) -> Texture2D:
	var definition_icon := _load_definition_icon(DishCatalog.get_definition(dish_id))
	if definition_icon != null:
		return definition_icon
	return _load_icon_path("res://assets/icons/items/dishes/%s.png" % dish_id)


static func get_tool_icon(tool_id: String) -> Texture2D:
	_ensure_tool_icons_loaded()
	var definition_icon := _load_icon_path(str(_tool_icons.get(tool_id, "")))
	if definition_icon != null:
		return definition_icon
	var weapon_icon := _load_icon_path("res://assets/icons/items/weapons/%s.png" % tool_id)
	if weapon_icon != null:
		return weapon_icon
	return _load_icon_path("res://assets/icons/items/tools/%s.png" % tool_id)


static func _is_chopped_ingredient(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) \
		or str(item.get("preparation", "")) == "chopped" \
		or str(item.get("model_state", "")) == "chopped"


static func _load_definition_icon(definition: Dictionary) -> Texture2D:
	return _load_icon_path(str(definition.get("icon", definition.get("icon_path", ""))))


static func _load_icon_path(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


static func _ensure_tool_icons_loaded() -> void:
	if _tool_icons_loaded:
		return
	_tool_icons_loaded = true
	_load_tool_file(PRIMARY_WEAPON_PATH, "weapons")
	_load_tool_file(SPECIAL_TOOL_PATH, "tools")
	_load_tool_file(RUNTIME_TOOL_PATH, "tools")


static func _load_tool_file(path: String, key: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var entries: Variant = (parsed as Dictionary).get(key, [])
	if not entries is Array:
		return
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var item_id := str(entry.get("id", ""))
		var icon_path := str(entry.get("icon", entry.get("icon_path", "")))
		if not item_id.is_empty() and not icon_path.is_empty():
			_tool_icons[item_id] = icon_path
