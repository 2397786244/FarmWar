extends PanelContainer
class_name CargoInventorySlot

var page: CargoCarStoragePage
var slot_kind := "player"
var slot_index := -1
var item: Dictionary = {}
var disabled := false
var _name_label: Label
var _detail_label: Label
var _icon: ItemIcon


func setup(owner_page: CargoCarStoragePage, kind: String, index: int) -> void:
	page = owner_page
	slot_kind = kind
	slot_index = index
	custom_minimum_size = Vector2(112.0, 108.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)
	_icon = preload("res://ui/item_icon.tscn").instantiate() as ItemIcon
	_icon.custom_minimum_size = Vector2(54.0, 54.0)
	box.add_child(_icon)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_name_label)
	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 13)
	_detail_label.add_theme_color_override("font_color", Color("#AFC2CC"))
	box.add_child(_detail_label)
	_refresh_style()


func set_item(value: Dictionary, unavailable := false) -> void:
	item = value.duplicate(true)
	disabled = unavailable
	if is_instance_valid(_icon):
		_icon.set_item(item)
	if disabled:
		_name_label.text = "损坏槽位"
		_detail_label.text = "维修后恢复"
	elif item.is_empty():
		_name_label.text = "空"
		_detail_label.text = ""
	else:
		_name_label.text = str(item.get("display_name", "货运箱"))
		_detail_label.text = "%.1f kg" % float(item.get("total_weight_kg", item.get("weight_kg", 0.0)))
	_refresh_style()


func _refresh_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151B1F") if not disabled else Color("#241D1D")
	style.border_color = Color("#D8842E") if not disabled else Color("#704747")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)


func _get_drag_data(_position: Vector2) -> Variant:
	if disabled or item.is_empty() or page == null:
		return null
	var preview := Label.new()
	preview.text = str(item.get("display_name", "货运箱"))
	preview.add_theme_font_size_override("font_size", 18)
	preview.z_as_relative = false
	preview.z_index = 4096
	set_drag_preview(preview)
	return {"cargo_page": page, "slot_kind": slot_kind, "slot_index": slot_index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not disabled and page != null and data is Dictionary \
		and page.can_drop(slot_kind, slot_index, data as Dictionary)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		page.drop_item(slot_kind, slot_index, data as Dictionary)
