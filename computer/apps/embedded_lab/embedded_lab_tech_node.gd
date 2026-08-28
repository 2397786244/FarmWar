extends Control
class_name EmbeddedLabTechNode

signal selected(program_id: String)

const NODE_SIZE := Vector2(118.0, 78.0)
const CIRCLE_CENTER := Vector2(29.0, 28.0)
const CIRCLE_RADIUS := 23.0

var program: Dictionary = {}
var unlocked := false
var available := false
var active := false
var progress := 0.0
var code_label: Label
var title_label: Label
var status_label: Label


func _ready() -> void:
	size = NODE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_labels()
	queue_redraw()


func _build_labels() -> void:
	code_label = Label.new()
	code_label.position = Vector2(5.0, 14.0)
	code_label.size = Vector2(48.0, 28.0)
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 16)
	code_label.add_theme_color_override("font_color", Color.WHITE)
	code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(code_label)

	title_label = Label.new()
	title_label.position = Vector2(58.0, 8.0)
	title_label.size = Vector2(58.0, 36.0)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)

	status_label = Label.new()
	status_label.position = Vector2(58.0, 47.0)
	status_label.size = Vector2(58.0, 22.0)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)


func configure(value: Dictionary, is_unlocked: bool, is_available: bool, is_active: bool, current_progress: float) -> void:
	program = value.duplicate(true)
	unlocked = is_unlocked
	available = is_available
	active = is_active
	progress = clampf(current_progress, 0.0, 1.0)
	if not is_instance_valid(code_label):
		return
	code_label.text = str(program.get("short_label", "P1"))
	title_label.text = str(program.get("display_name", "程序"))
	status_label.text = _status_text()
	status_label.add_theme_color_override("font_color", _track_color())
	title_label.add_theme_color_override("font_color", Color("#252a30") if unlocked or available else Color("#73777c"))
	tooltip_text = str(program.get("description", ""))
	queue_redraw()


func _status_text() -> String:
	if active:
		return "%d%%" % roundi(progress * 100.0)
	if unlocked:
		return "已解锁"
	if available:
		return "可开发"
	return "需前置"


func _track_color() -> Color:
	return program.get("color", Color("#8b9096")) as Color


func _draw() -> void:
	var track_color := _track_color()
	var circle_color := track_color if unlocked else Color("#8b9096")
	if not available and not unlocked and not active:
		circle_color = Color("#9da1a6")
	draw_circle(CIRCLE_CENTER, CIRCLE_RADIUS, Color("#eef0f2"))
	draw_circle(CIRCLE_CENTER, CIRCLE_RADIUS - 3.0, circle_color)
	if active:
		var end_angle := -PI * 0.5 + TAU * progress
		if progress > 0.001:
			draw_arc(CIRCLE_CENTER, CIRCLE_RADIUS + 4.0, -PI * 0.5, end_angle, 32, Color("#3d91ff"), 4.0, true)
		else:
			draw_arc(CIRCLE_CENTER, CIRCLE_RADIUS + 4.0, -PI * 0.5, -PI * 0.49, 4, Color("#3d91ff"), 4.0, true)
	else:
		draw_arc(CIRCLE_CENTER, CIRCLE_RADIUS + 2.0, 0.0, TAU, 32, Color("#c7cbd0"), 1.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(str(program.get("program_id", "")))
