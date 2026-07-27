extends PanelContainer
class_name PlayerBackpackTooltip

const PRIMARY_WEAPON_PATH := "res://data/primary_weapon_definitions.json"
const SPECIAL_TOOL_PATH := "res://data/special_tool_definitions.json"
const RUNTIME_TOOL_PATH := "res://data/tool_definitions.json"
const TOOLTIP_SIZE := Vector2(390.0, 310.0)

@onready var title_label: Label = $Margin/VBox/Title
@onready var type_label: Label = $Margin/VBox/Type
@onready var description_label: Label = $Margin/VBox/Description
@onready var stats_label: Label = $Margin/VBox/Stats
@onready var price_label: Label = $Margin/VBox/Price

var primary_weapons_by_id: Dictionary = {}
var special_tools_by_id: Dictionary = {}
var runtime_tools_by_id: Dictionary = {}


func _ready() -> void:
	primary_weapons_by_id = _load_definitions(PRIMARY_WEAPON_PATH, "weapons")
	special_tools_by_id = _load_definitions(SPECIAL_TOOL_PATH, "tools")
	runtime_tools_by_id = _load_definitions(RUNTIME_TOOL_PATH, "tools")
	size = TOOLTIP_SIZE
	visible = false


func show_for_item(item: Dictionary, anchor_rect: Rect2) -> void:
	var details := _resolve_item(item)
	if details.is_empty():
		hide_tooltip()
		return
	title_label.text = str(details.get("title", ""))
	type_label.text = str(details.get("type", ""))
	description_label.text = str(details.get("description", ""))
	stats_label.text = str(details.get("stats", ""))
	price_label.text = str(details.get("price", ""))
	size = TOOLTIP_SIZE
	visible = true
	_place_next_to(anchor_rect)


func hide_tooltip() -> void:
	visible = false


func _resolve_item(item: Dictionary) -> Dictionary:
	match str(item.get("kind", "")):
		"tool", "weapon":
			return _resolve_tool(str(item.get("tool_id", "")), item)
		"ingredient":
			return _resolve_ingredient(item)
		"dish":
			return _resolve_dish(item)
		"equipment":
			return _resolve_equipment(item)
		"cargo_crate":
			var crate := CargoCrateData.normalize(item)
			var contents := CargoCrateData.describe_contents(crate)
			return {
				"title": str(crate.get("display_name", "货运箱")),
				"type": "货运箱 · 独立容器",
				"description": "牢固的木制单格货运箱。当前内容：%s。" % contents,
				"stats": "内容重量：%.2f / %.2f kg\n箱体自重：%.2f kg\n总重量：%.2f kg\n耐久：%d / 500 HP" % [
					float(crate.get("content_weight_kg", 0.0)), float(crate.get("capacity_kg", 0.0)),
					float(crate.get("tare_weight_kg", 0.0)), float(crate.get("total_weight_kg", 0.0)),
					roundi(float(crate.get("current_hp", 500.0))),
				],
				"price": "",
			}
	return {}


func _resolve_equipment(item: Dictionary) -> Dictionary:
	var equipment_id := str(item.get("equipment_id", ""))
	var definition := EquipmentCatalog.get_definition(equipment_id)
	if definition.is_empty():
		return {}
	var equipment_type := str(definition.get("equipment_type", ""))
	var type_text := "装备"
	var stats_lines: Array[String] = []
	match equipment_type:
		"backpack":
			type_text = "装备 · 背包"
			stats_lines.append("额外格子：+%d" % int(definition.get("extra_slots", 0)))
			stats_lines.append("额外载重：+%.0f kg" % float(definition.get("extra_weight_kg", 0.0)))
		"chest_armor":
			type_text = "装备 · 胸甲"
			var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
			stats_lines.append("耐久：%.0f / %.0f HP" % [
				float(item.get("current_hp", max_hp)),
				max_hp,
			])
		"legwear":
			type_text = "装备 · 护腿"
			var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
			stats_lines.append("耐久：%.0f / %.0f HP" % [
				float(item.get("current_hp", max_hp)),
				max_hp,
			])
			var speed_bonus := (EquipmentCatalog.get_movement_speed_multiplier(equipment_id) - 1.0) * 100.0
			stats_lines.append("移动速度：+%.0f%%" % speed_bonus)
	return {
		"title": str(definition.get("name", equipment_id)),
		"type": type_text,
		"description": str(definition.get("description", "暂无说明。")),
		"stats": "\n".join(stats_lines),
		"price": _get_price_text(equipment_id),
	}


func _resolve_tool(tool_id: String, item: Dictionary = {}) -> Dictionary:
	if tool_id.is_empty():
		return {}
	var runtime_definition: Dictionary = runtime_tools_by_id.get(tool_id, {})
	var title := str(runtime_definition.get("name", tool_id))
	var description := str(runtime_definition.get("description", runtime_definition.get("hint", "暂无说明。")))
	var item_type := "道具"
	var stats := ""
	if primary_weapons_by_id.has(tool_id):
		var weapon: Dictionary = primary_weapons_by_id[tool_id]
		title = str(weapon.get("name", title))
		description = str(weapon.get("description", description))
		item_type = "武器"
		var cooldown := float(weapon.get("cooldown", runtime_definition.get("cooldown", 0.0)))
		var damage := CombatBalance.get_float(tool_id, "damage", float(weapon.get("power", 0.0)))
		var power_text := "%d" % roundi(damage) if damage > 0.0 else "功能型"
		var fire_rate_text := "--" if cooldown <= 0.0 else "%.1f 次/秒" % (1.0 / cooldown)
		stats = "威力：%s\n射速：%s\n冷却：%s" % [power_text, fire_rate_text, _format_seconds(cooldown)]
	elif special_tools_by_id.has(tool_id):
		var special_tool: Dictionary = special_tools_by_id[tool_id]
		title = str(special_tool.get("name", title))
		description = str(special_tool.get("description", description))
		item_type = "道具"
		stats = "冷却：%s" % _format_seconds(float(special_tool.get("cooldown", runtime_definition.get("cooldown", 0.0))))
	elif runtime_definition.has("cooldown"):
		stats = "冷却：%s" % _format_seconds(float(runtime_definition.get("cooldown", 0.0)))
	var weight_kg := float(item.get("weight_kg", runtime_definition.get("weight_kg", 0.0)))
	if weight_kg > 0.0:
		stats += ("\n" if not stats.is_empty() else "") + "重量：%.2f kg" % weight_kg
	if tool_id.begins_with("animal_"):
		var max_hp := float(item.get("max_hp", 0.0))
		var growth_progress := clampf(float(item.get("growth_progress", 0.0)), 0.0, 100.0)
		stats += "\n成长进度：%d%% %s" % [
			roundi(growth_progress), "(已成熟)" if growth_progress >= 99.999 else ""
		]
		if max_hp > 0.0:
			stats += "\n当前生命：%d / %d HP" % [
				roundi(float(item.get("current_hp", max_hp))), roundi(max_hp)
			]
	return {
		"title": title,
		"type": item_type,
		"description": description,
		"stats": stats,
		"price": _get_price_text(tool_id, item),
	}


func _resolve_ingredient(item: Dictionary) -> Dictionary:
	var ingredient_id := str(item.get("ingredient_id", ""))
	if ingredient_id.is_empty():
		return {}
	var definition := IngredientCatalog.get_definition(ingredient_id)
	if definition.is_empty():
		return {}
	var display_name := str(definition.get("display_name", ingredient_id))
	if _is_chopped_ingredient(item):
		display_name = "切碎的" + display_name
	var item_type := "材料" if str(definition.get("kind", "")) == "material" else "食材"
	return {
		"title": display_name,
		"type": item_type,
		"description": str(definition.get("description", "暂无说明。")),
		"stats": "携带量：%.2f kg" % float(item.get("weight_kg", 0.0)),
		"price": _get_price_text(ingredient_id),
	}


func _is_chopped_ingredient(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) \
		or str(item.get("preparation", "")) == "chopped" \
		or str(item.get("model_state", "")) == "chopped"


func _resolve_dish(item: Dictionary) -> Dictionary:
	var definition := DishCatalog.get_definition(str(item.get("dish_id", "")))
	if definition.is_empty():
		return {}
	return {
		"title": str(definition.get("display_name", "成品菜")),
		"type": "成品菜",
		"description": str(definition.get("description", "暂无说明。")),
		"stats": "数量：%d份\n重量：%.2f kg" % [int(item.get("servings", 0)), float(item.get("weight_kg", 0.0))],
		"price": _get_price_text(str(item.get("dish_id", ""))),
}


func _get_price_text(item_id: String, item: Dictionary = {}) -> String:
	var product := GlobalVar.get_shop_product(item_id)
	if product.is_empty():
		return "商店：不可交易"
	var unit := "kg" if str(product.get("unit", "item")) == "kg" else "件"
	var buy_text := "%d 金币/%s" % [int(product.get("buy_price", 0)), unit] if bool(product.get("can_buy", false)) else "不可购买"
	var sell_price := int(product.get("sell_price", 0))
	var sell_text := "%d 金币/%s" % [sell_price, unit] if bool(product.get("can_sell", false)) else "不可回收"
	if str(product.get("kind", "")) == "livestock" and bool(product.get("can_sell", false)):
		var progress := clampf(float(item.get("growth_progress", 0.0)), 0.0, 100.0)
		var current_sell_price := roundi(float(sell_price) * (1.0 + 2.0 * progress / 100.0))
		sell_text = "%d 金币/件（成熟价 %d）" % [current_sell_price, sell_price * 3]
	return "购买：%s\n回收：%s" % [buy_text, sell_text]


func _format_seconds(value: float) -> String:
	return "%.1f 秒" % value if value > 0.0 else "无"


func _place_next_to(anchor_rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	var tooltip_size := TOOLTIP_SIZE
	var next_position := anchor_rect.position + Vector2(anchor_rect.size.x + 12.0, 0.0)
	if next_position.x + tooltip_size.x > viewport_size.x - 8.0:
		next_position.x = anchor_rect.position.x - tooltip_size.x - 12.0
	next_position.x = clampf(next_position.x, 8.0, maxf(8.0, viewport_size.x - tooltip_size.x - 8.0))
	next_position.y = clampf(next_position.y, 8.0, maxf(8.0, viewport_size.y - tooltip_size.y - 8.0))
	position = next_position


func _load_definitions(path: String, key: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("背包 tooltip 无法读取定义：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("背包 tooltip 定义格式无效：%s" % path)
		return {}
	var records: Variant = (parsed as Dictionary).get(key, [])
	if not records is Array:
		return {}
	var result: Dictionary = {}
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var item_id := str(record.get("id", ""))
		if not item_id.is_empty():
			result[item_id] = record.duplicate(true)
	return result
