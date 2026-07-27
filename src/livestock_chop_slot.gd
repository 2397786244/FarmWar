extends PanelContainer
class_name LivestockChopSlot

var page: LivestockChopPage
var slot_index := -1
var item: Dictionary = {}
var _name_label: Label
var _progress: ProgressBar


func setup(owner_page: LivestockChopPage, index: int) -> void:
	page = owner_page
	slot_index = index
	custom_minimum_size = Vector2(150.0, 120.0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_name_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(130.0, 24.0)
	_progress.show_percentage = true
	box.add_child(_progress)


func set_item(next_item: Dictionary) -> void:
	item = next_item.duplicate(true)
	if item.is_empty():
		_name_label.text = "空槽位"
		_progress.value = 0.0
		_progress.visible = false
	else:
		_name_label.text = str(item.get("display_name", item.get("species_id", "动物")))
		_progress.value = clampf(float(item.get("growth_progress", 0.0)), 0.0, 100.0)
		_progress.visible = true


func _get_drag_data(_position: Vector2) -> Variant:
	if item.is_empty() or page == null:
		return null
	var preview := Label.new()
	preview.text = str(item.get("display_name", "动物"))
	preview.z_index = 4096
	set_drag_preview(preview)
	return {"companion_page": page, "slot_kind": "chop", "slot_index": slot_index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return page != null and data is Dictionary and page.can_drop("chop", slot_index, data as Dictionary)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		page.drop_item("chop", slot_index, data as Dictionary)
