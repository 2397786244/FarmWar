extends RefCounted
class_name CargoCrateData

const DEFINITIONS := {
	"small": {
		"display_name": "小型木质货运箱", "capacity_kg": 10.0, "tare_weight_kg": 1.0,
		"model_path": "res://items/CargoCrateSmall.tscn",
	},
	"medium": {
		"display_name": "中型木质货运箱", "capacity_kg": 20.0, "tare_weight_kg": 2.0,
		"model_path": "res://items/CargoCrateMedium.tscn",
	},
	"large": {
		"display_name": "大型木质货运箱", "capacity_kg": 40.0, "tare_weight_kg": 4.0,
		"model_path": "res://items/CragoCrateLarge.tscn",
	},
}

const ITEM_ID_TO_SIZE := {
	"cargo_crate_small": "small",
	"cargo_crate_medium": "medium",
	"cargo_crate_large": "large",
}


static func create_empty(crate_size: String, instance_id := "") -> Dictionary:
	var size := crate_size.to_lower()
	if not DEFINITIONS.has(size):
		return {}
	var definition: Dictionary = DEFINITIONS[size]
	var crate_id := instance_id
	if crate_id.is_empty():
		crate_id = "crate_%d_%d" % [Time.get_ticks_usec(), randi()]
	return {
		"kind": "cargo_crate",
		"item_id": "cargo_crate_" + size,
		"crate_instance_id": crate_id,
		"crate_size": size,
		"display_name": str(definition["display_name"]),
		"capacity_kg": float(definition["capacity_kg"]),
		"tare_weight_kg": float(definition["tare_weight_kg"]),
		"content_weight_kg": 0.0,
		"total_weight_kg": float(definition["tare_weight_kg"]),
		"stored_item": {},
		"current_hp": 500.0,
		"max_hp": 500.0,
		"model_path": str(definition["model_path"]),
		"content_kind": "",
		"content_id": "",
		"content_quantity": 0.0,
		"content_unit": "count",
		"delivery_content": {},
	}


static func get_size_for_item_id(item_id: String) -> String:
	var normalized := item_id.strip_edges().to_lower().replace("-", "_")
	if ITEM_ID_TO_SIZE.has(normalized):
		return str(ITEM_ID_TO_SIZE[normalized])
	match normalized:
		"cargocratesmall": return "small"
		"cargocratemedium": return "medium"
		"cargocratelarge", "cragocratelarge": return "large"
	return ""


static func normalize(value: Dictionary) -> Dictionary:
	var size := str(value.get("crate_size", "medium")).to_lower()
	if not DEFINITIONS.has(size):
		size = "medium"
	var result := create_empty(size, str(value.get("crate_instance_id", "")))
	if result.is_empty():
		return {}
	var stored_value: Variant = value.get("stored_item", {})
	result["current_hp"] = clampf(float(value.get("current_hp", 500.0)), 0.0, 500.0)
	result["max_hp"] = 500.0
	if stored_value is Dictionary and not (stored_value as Dictionary).is_empty():
		result["stored_item"] = (stored_value as Dictionary).duplicate(true)
	elif not str(value.get("content_id", "")).is_empty() \
			and float(value.get("content_quantity", 0.0)) > 0.0:
		result["stored_item"] = _legacy_stored_item(value)
	return refresh_totals(result)


static func refresh_totals(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	var size := str(result.get("crate_size", "medium"))
	var definition: Dictionary = DEFINITIONS.get(size, DEFINITIONS["medium"])
	var stored: Dictionary = result.get("stored_item", {}) as Dictionary \
		if result.get("stored_item", {}) is Dictionary else {}
	var content_weight := item_weight_kg(stored)
	result["capacity_kg"] = float(definition["capacity_kg"])
	result["tare_weight_kg"] = float(definition["tare_weight_kg"])
	result["content_weight_kg"] = content_weight
	result["total_weight_kg"] = float(definition["tare_weight_kg"]) + content_weight
	result["display_name"] = str(definition["display_name"])
	result["model_path"] = str(definition["model_path"])
	result["stored_item"] = stored.duplicate(true)
	_apply_delivery_compatibility(result, stored)
	return result


static func can_store(crate: Dictionary, item: Dictionary) -> bool:
	if item.is_empty() or str(item.get("kind", "")) == "cargo_crate":
		return false
	var normalized := normalize(crate)
	var stored: Dictionary = normalized.get("stored_item", {}) as Dictionary
	var remaining_capacity := maxf(0.0, float(normalized.get("capacity_kg", 0.0)) - item_weight_kg(stored))
	if remaining_capacity <= 0.001:
		return false
	if stored.is_empty():
		return is_unit_weight_item(item) or item_weight_kg(item) <= remaining_capacity + 0.001
	return can_merge_unit_weight_items(stored, item)


static func is_unit_weight_item(item: Dictionary) -> bool:
	return UnitWeightItem.can_extract_unit(item)


static func can_merge_unit_weight_items(stored: Dictionary, incoming: Dictionary) -> bool:
	return is_unit_weight_item(stored) and is_unit_weight_item(incoming) \
		and UnitWeightItem.can_merge(stored, incoming)


static func is_mergeable_crop_item(item: Dictionary) -> bool:
	return str(item.get("kind", "")) == "ingredient" \
		and IngredientCatalog.is_plantable(str(item.get("ingredient_id", ""))) \
		and item_weight_kg(item) > 0.001


static func can_merge_crop_items(stored: Dictionary, incoming: Dictionary) -> bool:
	return is_mergeable_crop_item(stored) and is_mergeable_crop_item(incoming) \
		and str(stored.get("ingredient_id", "")) == str(incoming.get("ingredient_id", "")) \
		and bool(stored.get("is_chopped", false)) == bool(incoming.get("is_chopped", false))


static func take_weight(crate: Dictionary, maximum_weight_kg: float) -> Dictionary:
	var normalized := normalize(crate)
	var stored: Dictionary = normalized.get("stored_item", {}) as Dictionary
	return UnitWeightItem.make_piece(stored, maximum_weight_kg)


static func item_weight_kg(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	match str(item.get("kind", "")):
		"ingredient", "dish", "equipment", "tool", "weapon":
			return maxf(0.0, float(item.get("weight_kg", 0.0)))
		_:
			return maxf(0.0, float(item.get("weight_kg", 0.0)))


static func describe_contents(crate: Dictionary) -> String:
	var normalized := normalize(crate)
	var stored: Dictionary = normalized.get("stored_item", {})
	if stored.is_empty():
		return "空箱"
	return str(stored.get("display_name", stored.get("ingredient_id", stored.get("dish_id", stored.get("tool_id", "物品")))))


static func get_delivery_content(crate: Dictionary) -> Dictionary:
	var normalized := normalize(crate)
	var value: Variant = normalized.get("delivery_content", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func consume_delivery_quantity(crate: Dictionary, quantity: float) -> Dictionary:
	var normalized := normalize(crate)
	var delivery := get_delivery_content(normalized)
	var old_quantity := maxf(0.0, float(delivery.get("quantity", 0.0)))
	if old_quantity <= 0.0001 or quantity <= 0.0:
		return normalized
	var remaining := maxf(0.0, old_quantity - quantity)
	var stored: Dictionary = normalized.get("stored_item", {}) as Dictionary \
		if normalized.get("stored_item", {}) is Dictionary else {}
	match str(stored.get("kind", "")):
		"ingredient":
			stored["weight_kg"] = remaining * IngredientCatalog.get_pickup_unit_kg(
				str(stored.get("ingredient_id", stored.get("item_id", "")))
			) if str(delivery.get("unit", "")) == "count" else remaining
		"dish":
			stored["servings"] = roundi(remaining)
			stored["weight_kg"] = float(stored.get("weight_kg", 0.0)) \
				* remaining / maxf(old_quantity, 0.0001)
		_:
			var old_weight := float(stored.get("weight_kg", 0.0))
			if stored.has("count"):
				stored["count"] = roundi(remaining)
			elif stored.has("quantity"):
				stored["quantity"] = roundi(remaining)
			else:
				remaining = 0.0
			stored["weight_kg"] = old_weight * remaining / maxf(old_quantity, 0.0001)
	if remaining <= 0.0001:
		stored = {}
	normalized["stored_item"] = stored
	return refresh_totals(normalized)


static func _legacy_stored_item(value: Dictionary) -> Dictionary:
	var kind := str(value.get("content_kind", "ingredient"))
	var content_id := str(value.get("content_id", ""))
	var quantity := float(value.get("content_quantity", 0.0))
	var content_weight := maxf(0.0, float(value.get("content_weight_kg", value.get("total_weight_kg", 0.0))))
	if kind == "dish":
		return {"kind": "dish", "dish_id": content_id, "servings": roundi(quantity), "weight_kg": content_weight, "display_name": str(value.get("content_display_name", content_id))}
	if kind == "ingredient":
		return {"kind": "ingredient", "ingredient_id": content_id, "weight_kg": quantity, "display_name": str(value.get("content_display_name", content_id))}
	return {"kind": kind, "item_id": content_id, "count": roundi(quantity), "weight_kg": content_weight, "display_name": str(value.get("content_display_name", content_id))}


static func _apply_delivery_compatibility(crate: Dictionary, stored: Dictionary) -> void:
	crate["content_kind"] = ""
	crate["content_id"] = ""
	crate["content_quantity"] = 0.0
	crate["content_unit"] = "count"
	crate["content_display_name"] = ""
	crate["delivery_content"] = {}
	if stored.is_empty():
		return
	var delivery := _delivery_content_from_stored(stored)
	if delivery.is_empty():
		return
	crate["delivery_content"] = delivery
	crate["content_kind"] = str(delivery.get("kind", ""))
	crate["content_id"] = str(delivery.get("content_id", ""))
	crate["content_quantity"] = float(delivery.get("quantity", 0.0))
	crate["content_unit"] = str(delivery.get("unit", "count"))
	crate["content_display_name"] = str(delivery.get("display_name", ""))


static func _delivery_content_from_stored(stored: Dictionary) -> Dictionary:
	var kind := str(stored.get("kind", ""))
	var result := {
		"kind": kind,
		"content_id": "",
		"quantity": 0.0,
		"unit": "count",
		"display_name": str(stored.get("display_name", "")),
		"content_weight_kg": item_weight_kg(stored),
	}
	match kind:
		"ingredient":
			var ingredient_id := str(stored.get("ingredient_id", stored.get("item_id", "")))
			var definition := IngredientCatalog.get_definition(ingredient_id)
			result["content_id"] = ingredient_id
			if str(definition.get("kind", "")) == "material":
				result["kind"] = "material"
				result["quantity"] = float(stored.get("weight_kg", 0.0)) \
					/ IngredientCatalog.get_pickup_unit_kg(ingredient_id)
				result["unit"] = "count"
			else:
				result["quantity"] = float(stored.get("weight_kg", 0.0))
				result["unit"] = "kg"
		"dish":
			result["content_id"] = str(stored.get("dish_id", stored.get("item_id", "")))
			result["quantity"] = float(stored.get("servings", stored.get("count", 0)))
			result["unit"] = "serving"
		"tool", "weapon":
			result["content_id"] = str(stored.get("tool_id", stored.get("item_id", "")))
			result["quantity"] = 1.0
		"material", "item", "equipment":
			result["content_id"] = str(stored.get("material_id", stored.get("item_id", stored.get("equipment_id", ""))))
			result["quantity"] = float(stored.get("count", stored.get("quantity", 1)))
			result["unit"] = str(stored.get("unit", "count"))
	if str(result.get("content_id", "")).is_empty() \
			or float(result.get("quantity", 0.0)) <= 0.0:
		return {}
	return result
