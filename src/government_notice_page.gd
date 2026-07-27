extends Control
class_name GovernmentNoticePage

signal closed

const PANEL_COLOR := Color("#17202A")
const BORDER_COLOR := Color("#D6A94F")
const TITLE_COLOR := Color("#F2CE78")
const TEXT_COLOR := Color("#F4EBD5")

var title_label: Label
var notice_label: Label


func _ready() -> void:
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	visible = false


func open_for(board: GovernmentBoard) -> void:
	if not is_instance_valid(board):
		return
	notice_label.text = board.get_notice_text()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _build_interface() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360.0
	panel.offset_top = -220.0
	panel.offset_right = 360.0
	panel.offset_bottom = 220.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	title_label = Label.new()
	title_label.text = "政府公告栏"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "关闭公告栏"
	close_button.custom_minimum_size = Vector2(48.0, 42.0)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	content.add_child(HSeparator.new())
	notice_label = Label.new()
	notice_label.text = "近期树林内发现黑熊出没，请居民小心"
	notice_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", 28)
	notice_label.add_theme_color_override("font_color", TEXT_COLOR)
	content.add_child(notice_label)

	var footer := Label.new()
	footer.text = "按 E 或 Esc 关闭"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 16)
	footer.add_theme_color_override("font_color", Color("#B9B2A3"))
	content.add_child(footer)
