extends RefCounted
class_name UnitWeightItem


static func get_unit_weight_kg(item: Dictionary) -> float:
	match str(item.get("kind", "")):
		"ingredient":
			var ingredient_id := str(item.get("ingredient_id", ""))
			if IngredientCatalog.get_definition(ingredient_id).is_empty():
				return 0.0
			return minf(IngredientCatalog.get_pickup_unit_kg(ingredient_id), get_weight_kg(item))
		"dish":
			var dish_id := str(item.get("dish_id", ""))
			var definition := DishCatalog.get_definition(dish_id)
			if definition.is_empty() or int(item.get("servings", 0)) <= 0:
				return 0.0
			return minf(float(definition.get("serving_weight_kg", 0.0)), get_weight_kg(item))
		_:
			var total_weight := get_weight_kg(item)
			var stack_count := maxi(0, int(item.get("count", item.get("quantity", 0))))
			var inferred_unit := total_weight / float(stack_count) if stack_count > 0 else total_weight
			var configured_unit := maxf(0.0, float(item.get(
				"unit_weight_kg", item.get("pickup_unit_kg", inferred_unit)
			)))
			return minf(configured_unit, total_weight)


static func get_weight_kg(item: Dictionary) -> float:
	return maxf(0.0, float(item.get("weight_kg", 0.0)))


static func can_extract_unit(item: Dictionary) -> bool:
	return get_unit_weight_kg(item) > 0.0001


static func can_merge(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty() or str(first.get("kind", "")) != str(second.get("kind", "")):
		return false
	match str(first.get("kind", "")):
		"ingredient":
			return str(first.get("ingredient_id", "")) == str(second.get("ingredient_id", "")) \
				and bool(first.get("is_chopped", false)) == bool(second.get("is_chopped", false))
		"dish":
			return str(first.get("dish_id", "")) == str(second.get("dish_id", ""))
		_:
			return not _identity(first).is_empty() \
				and _identity(first) == _identity(second) \
				and get_unit_weight_kg(first) > 0.0 and get_unit_weight_kg(second) > 0.0


static func make_piece(item: Dictionary, maximum_weight_kg: float) -> Dictionary:
	if item.is_empty() or maximum_weight_kg <= 0.0001:
		return {}
	var result := item.duplicate(true)
	match str(item.get("kind", "")):
		"dish":
			var unit_weight := get_unit_weight_kg(item)
			var available_servings := maxi(0, int(item.get("servings", 0)))
			var serving_count := mini(available_servings, floori((maximum_weight_kg + 0.0001) / maxf(unit_weight, 0.0001)))
			if serving_count <= 0:
				return {}
			result["servings"] = serving_count
			result["weight_kg"] = minf(get_weight_kg(item), unit_weight * float(serving_count))
		_:
			var unit_weight := get_unit_weight_kg(item)
			var stack_count := maxi(0, int(item.get("count", item.get("quantity", 0))))
			var piece_count := mini(stack_count, floori((maximum_weight_kg + 0.0001) / maxf(unit_weight, 0.0001))) \
				if stack_count > 0 else 0
			var piece_weight := minf(
				get_weight_kg(item),
				unit_weight * float(piece_count) if stack_count > 0 else maximum_weight_kg
			)
			if piece_weight <= 0.0001:
				return {}
			result["weight_kg"] = piece_weight
			if item.has("count"):
				result["count"] = piece_count
			elif item.has("quantity"):
				result["quantity"] = piece_count
	return result


static func subtract(item: Dictionary, piece: Dictionary) -> Dictionary:
	if not can_merge(item, piece):
		return item.duplicate(true)
	var result := item.duplicate(true)
	result["weight_kg"] = maxf(0.0, get_weight_kg(item) - get_weight_kg(piece))
	if str(item.get("kind", "")) == "dish":
		result["servings"] = maxi(0, int(item.get("servings", 0)) - int(piece.get("servings", 0)))
		if int(result["servings"]) <= 0:
			return {}
	elif item.has("count"):
		result["count"] = maxi(0, int(item.get("count", 0)) - int(piece.get("count", 0)))
		if int(result["count"]) <= 0:
			return {}
	elif item.has("quantity"):
		result["quantity"] = maxi(0, int(item.get("quantity", 0)) - int(piece.get("quantity", 0)))
		if int(result["quantity"]) <= 0:
			return {}
	if float(result.get("weight_kg", 0.0)) <= 0.0001:
		return {}
	return result


static func merge(first: Dictionary, second: Dictionary) -> Dictionary:
	if first.is_empty():
		return second.duplicate(true)
	if not can_merge(first, second):
		return {}
	var result := first.duplicate(true)
	result["weight_kg"] = get_weight_kg(first) + get_weight_kg(second)
	if str(first.get("kind", "")) == "dish":
		result["servings"] = int(first.get("servings", 0)) + int(second.get("servings", 0))
	elif first.has("count"):
		result["count"] = int(first.get("count", 0)) + int(second.get("count", 0))
	elif first.has("quantity"):
		result["quantity"] = int(first.get("quantity", 0)) + int(second.get("quantity", 0))
	return result


static func _identity(item: Dictionary) -> String:
	for key in ["item_id", "material_id", "tool_id", "equipment_id"]:
		var value := str(item.get(key, ""))
		if not value.is_empty():
			return "%s:%s" % [str(item.get("kind", "")), value]
	return ""


static func create_drag_preview(item: Dictionary, weight_kg: float) -> Control:
	var root := Control.new()
	root.name = "UnitWeightDragPreview"
	root.custom_minimum_size = Vector2(76.0, 76.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_as_relative = false
	root.z_index = 4096
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.07, 0.92)
	style.border_color = Color("#E7B84D")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var icon := preload("res://ui/item_icon.tscn").instantiate() as ItemIcon
	icon.name = "ItemIcon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_item(item)
	panel.add_child(icon)
	var weight_label := Label.new()
	weight_label.name = "WeightLabel"
	weight_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weight_label.offset_left = -72.0
	weight_label.offset_top = -24.0
	weight_label.offset_right = -4.0
	weight_label.offset_bottom = -3.0
	weight_label.text = "%.2f kg" % weight_kg
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	weight_label.add_theme_font_size_override("font_size", 14)
	weight_label.add_theme_color_override("font_color", Color.WHITE)
	weight_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	weight_label.add_theme_constant_override("shadow_offset_x", 2)
	weight_label.add_theme_constant_override("shadow_offset_y", 2)
	weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(weight_label)
	return root


static func begin_unit_drag(control: Control, drag_data: Dictionary) -> void:
	var item := drag_data.get("unit_item", {}) as Dictionary
	var weight_kg := float(drag_data.get("unit_weight_kg", 0.0))
	if item.is_empty() or weight_kg <= 0.0001:
		return
	var preview := create_drag_preview(item, weight_kg)
	drag_data["unit_drag_preview"] = preview
	control.force_drag(drag_data, preview)


static func accumulate_active_drag(viewport: Viewport, source_item: Dictionary, matches_source: Callable) -> bool:
	var active_value: Variant = viewport.gui_get_drag_data()
	if not active_value is Dictionary:
		return false
	var active := active_value as Dictionary
	if not bool(active.get("unit_weight_transfer", false)) or not matches_source.call(active):
		return false
	var unit_weight := get_unit_weight_kg(source_item)
	var current_weight := float(active.get("unit_weight_kg", 0.0))
	var piece := make_piece(source_item, current_weight + unit_weight)
	var next_weight := get_weight_kg(piece)
	if piece.is_empty() or next_weight <= current_weight + 0.0001:
		return true
	active["unit_weight_kg"] = next_weight
	active["unit_item"] = piece
	if active.has("amount"):
		active["amount"] = float(piece.get("servings", 0)) \
			if str(piece.get("kind", "")) == "dish" else next_weight
	update_drag_preview(active.get("unit_drag_preview", null) as Control, piece, next_weight)
	return true


static func update_drag_preview(preview: Control, item: Dictionary, weight_kg: float) -> void:
	if not is_instance_valid(preview):
		return
	var icon := preview.get_node_or_null("ItemIcon") as ItemIcon
	if icon != null:
		icon.set_item(item)
	var weight_label := preview.get_node_or_null("WeightLabel") as Label
	if weight_label != null:
		weight_label.text = "%.2f kg" % weight_kg
