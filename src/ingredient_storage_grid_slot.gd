extends PanelContainer
class_name IngredientStorageGridSlot

var page: IngredientPickupPage
var item_kind := "ingredient"
var item_id := ""
var available_weight_kg := 0.0
var _label: Label
var _icon: ItemIcon


func setup_empty(owner_page: IngredientPickupPage) -> void:
	page = owner_page
	item_kind = ""
	item_id = ""
	custom_minimum_size = Vector2(86.0, 70.0)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	label.text = "空"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_refresh_style(false)


func setup(owner_page: IngredientPickupPage, next_item_kind: String, next_item_id: String) -> void:
	page = owner_page
	item_kind = next_item_kind
	item_id = next_item_id
	custom_minimum_size = Vector2(86.0, 70.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var definition := DishCatalog.get_definition(item_id) if item_kind == "dish" else IngredientCatalog.get_definition(item_id)
	tooltip_text = "%s\n%s\n连续右键可逐个增加提取量。" % [
		str(definition.get("display_name", item_id)),
		str(definition.get("description", "")),
	]
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 4)
	add_child(content)
	_icon = preload("res://ui/item_icon.tscn").instantiate() as ItemIcon
	_icon.custom_minimum_size = Vector2(34.0, 34.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item_kind == "dish":
		_icon.set_dish(item_id)
	else:
		_icon.set_ingredient(item_id)
	content.add_child(_icon)
	_label = Label.new()
	_label.custom_minimum_size.x = 42.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_label)
	gui_input.connect(_on_gui_input)
	_refresh_style(false)


func set_amount(amount: float, selected: bool) -> void:
	available_weight_kg = maxf(0.0, amount)
	var definition := DishCatalog.get_definition(item_id) if item_kind == "dish" else IngredientCatalog.get_definition(item_id)
	_label.text = "%s\n%d份" % [str(definition.get("display_name", item_id)), roundi(available_weight_kg)] \
		if item_kind == "dish" else "%s\n%.2fkg" % [str(definition.get("display_name", item_id)), available_weight_kg]
	modulate = Color.WHITE if available_weight_kg > 0.0001 else Color(0.55, 0.55, 0.55)
	_refresh_style(selected)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return page != null and data is Dictionary and page.can_drop("storage", -1, data as Dictionary)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		page.drop_item("storage", -1, data as Dictionary)


func _get_drag_data(_position: Vector2) -> Variant:
	if page == null or item_id.is_empty():
		return null
	var drag_data := page.make_storage_drag_data(item_kind, item_id, false)
	if drag_data.is_empty():
		return null
	set_drag_preview(UnitWeightItem.create_drag_preview(
		drag_data.get("unit_item", {}) as Dictionary,
		float(drag_data.get("unit_weight_kg", 0.0))
	))
	return drag_data


func _on_gui_input(event: InputEvent) -> void:
	if page == null or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var drag_data := page.make_storage_drag_data(item_kind, item_id, true)
		if drag_data.is_empty():
			return
		accept_event()
		UnitWeightItem.begin_unit_drag(self, drag_data)


func _input(event: InputEvent) -> void:
	if page == null or item_id.is_empty() or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	var source_data := page.make_storage_drag_data(item_kind, item_id, false)
	var source_item := source_data.get("unit_item", {}) as Dictionary
	if UnitWeightItem.accumulate_active_drag(
		get_viewport(), source_item,
		func(data: Dictionary) -> bool:
			return data.get("companion_page", null) == page \
				and str(data.get("slot_kind", "")) == "storage" \
				and str(data.get("item_kind", "")) == item_kind \
				and str(data.get("item_id", "")) == item_id
	):
		get_viewport().set_input_as_handled()


func _refresh_style(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#172126")
	style.border_color = Color("#F0C75E") if selected else Color("#4D6E80")
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
