extends PanelContainer
class_name CargoCrateStorageSlot

var page: CargoCrateStoragePage
var item: Dictionary = {}
var _icon: ItemIcon
var _name_label: Label
var _detail_label: Label


func setup(owner_page: CargoCrateStoragePage) -> void:
	page = owner_page
	custom_minimum_size = Vector2(220.0, 220.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)
	_icon = preload("res://ui/item_icon.tscn").instantiate() as ItemIcon
	_icon.custom_minimum_size = Vector2(96.0, 96.0)
	box.add_child(_icon)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_name_label)
	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 17)
	_detail_label.add_theme_color_override("font_color", Color("#AFC2CC"))
	box.add_child(_detail_label)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151B1F")
	style.border_color = Color("#E7B84D")
	style.set_border_width_all(3)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)
	gui_input.connect(_on_gui_input)


func set_item(value: Dictionary) -> void:
	item = value.duplicate(true)
	_icon.set_item(item)
	_name_label.text = "空" if item.is_empty() else str(item.get("display_name", "物品"))
	_detail_label.text = "拖入一种物品" if item.is_empty() else "%.2f kg" % CargoCrateData.item_weight_kg(item)


func _get_drag_data(_position: Vector2) -> Variant:
	if item.is_empty() or page == null:
		return null
	var preview := Label.new()
	preview.text = str(item.get("display_name", "物品"))
	preview.add_theme_font_size_override("font_size", 18)
	preview.z_as_relative = false
	preview.z_index = 4096
	set_drag_preview(preview)
	return {"cargo_page": page, "slot_kind": "crate", "slot_index": 0}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return page != null and data is Dictionary \
		and page.can_drop("crate", 0, data as Dictionary)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		page.drop_item("crate", 0, data as Dictionary)


func _on_gui_input(event: InputEvent) -> void:
	if item.is_empty() or page == null or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var unit_weight := UnitWeightItem.get_unit_weight_kg(item)
	var piece := UnitWeightItem.make_piece(item, unit_weight)
	if piece.is_empty():
		return
	accept_event()
	var drag_data := {
		"unit_weight_transfer": true,
		"unit_weight_kg": UnitWeightItem.get_weight_kg(piece),
		"unit_item": piece,
		"companion_page": page,
		"cargo_page": page,
		"slot_kind": "crate",
		"slot_index": 0,
	}
	UnitWeightItem.begin_unit_drag(self, drag_data)


func _input(event: InputEvent) -> void:
	if item.is_empty() or page == null or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if UnitWeightItem.accumulate_active_drag(
		get_viewport(), item,
		func(data: Dictionary) -> bool:
			return data.get("cargo_page", null) == page \
				and str(data.get("slot_kind", "")) == "crate" \
				and int(data.get("slot_index", -1)) == 0
	):
		get_viewport().set_input_as_handled()
