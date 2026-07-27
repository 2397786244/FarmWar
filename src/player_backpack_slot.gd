extends PanelContainer
class_name PlayerBackpackSlot

@export var slot_index := -1
@export var interactive := true
@export var highlight_selection := false
@export_enum("inventory", "equipment") var slot_kind := "inventory"
@export var equipment_type := ""
@export var empty_label := ""
@onready var item_name: Label = $Margin/VBox/ItemName
@onready var item_icon: ItemIcon = $Margin/VBox/ItemIcon

var backpack: PlayerBackpack
var current_item: Dictionary = {}


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func configure(next_backpack: PlayerBackpack) -> void:
	backpack = next_backpack

func set_item(item: Dictionary, selected := false, cooldown := 0.0) -> void:
	current_item = item.duplicate(true)
	item_icon.set_item(item)
	var is_empty := item.is_empty()
	item_name.text = empty_label if is_empty else str(item.get("display_name", ""))
	var color := Color("#8A96A3") if is_empty else Color("#F4F7FA")
	if selected:
		color = Color("#FFE08A")
	elif cooldown > 0.0:
		color = Color("#8A96A3")
	item_name.add_theme_color_override("font_color", color)
	var base_style := get_theme_stylebox("panel") as StyleBoxFlat
	if base_style != null:
		var slot_style := base_style.duplicate() as StyleBoxFlat
		slot_style.border_color = Color("#FFD34E") if highlight_selection and selected else Color("#4D6E80")
		slot_style.border_width_left = 3 if highlight_selection and selected else 2
		slot_style.border_width_top = 3 if highlight_selection and selected else 2
		slot_style.border_width_right = 3 if highlight_selection and selected else 2
		slot_style.border_width_bottom = 3 if highlight_selection and selected else 2
		add_theme_stylebox_override("panel", slot_style)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not interactive or backpack == null or not backpack.can_drag_slot(slot_index, slot_kind, equipment_type):
		return null
	var preview := preload("res://ui/player_backpack_drag_preview.tscn").instantiate() as Control
	preview.get_node("Label").text = item_name.text
	set_drag_preview(preview)
	backpack.hide_item_tooltip()
	return {"backpack": backpack, "slot_index": slot_index, "slot_kind": slot_kind, "equipment_type": equipment_type}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return interactive and backpack != null and backpack.can_drop_slot(self, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		backpack.drop_on_slot(self, data)


func _on_mouse_entered() -> void:
	if backpack != null and not current_item.is_empty():
		backpack.show_item_tooltip(current_item, get_global_rect())


func _on_mouse_exited() -> void:
	if backpack != null:
		backpack.hide_item_tooltip()


func _on_gui_input(event: InputEvent) -> void:
	if not interactive or slot_kind != "inventory" or backpack == null or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		backpack.select_personal_slot(slot_index)
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var drag_data := backpack.make_unit_drag_data(slot_index)
		if not drag_data.is_empty():
			accept_event()
			backpack.hide_item_tooltip()
			UnitWeightItem.begin_unit_drag(self, drag_data)


func _input(event: InputEvent) -> void:
	if not interactive or slot_kind != "inventory" or backpack == null \
			or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if UnitWeightItem.accumulate_active_drag(
		get_viewport(), current_item,
		func(data: Dictionary) -> bool:
			return data.get("backpack", null) == backpack \
				and str(data.get("slot_kind", "")) == "inventory" \
				and int(data.get("slot_index", -1)) == slot_index
	):
		get_viewport().set_input_as_handled()
