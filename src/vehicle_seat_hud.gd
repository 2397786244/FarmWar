extends Control
class_name VehicleSeatHud

const PANEL_COLOR := UITheme.COLOR_PANEL
const PANEL_BORDER_COLOR := UITheme.COLOR_BORDER
const SEAT_BAR_COLOR := UITheme.COLOR_CONTROL
const SEAT_BAR_BORDER_COLOR := UITheme.COLOR_BORDER
const OCCUPIED_COLOR := UITheme.COLOR_WARNING
const EMPTY_COLOR := UITheme.COLOR_PANEL
const CURRENT_SEAT_BORDER_COLOR := UITheme.COLOR_TEXT
const HINT_TEXT_COLOR := UITheme.COLOR_TEXT
const DOT_RADIUS := 8.0
const SEAT_COLUMN_OFFSET := 24.0
const SEAT_ROW_OFFSET := 10.0
const HINT_FONT_SIZE := 14
const HINT_LINE_HEIGHT := 20.0

var displayed_seat_count := 0
var displayed_occupants: Array[int] = []
var displayed_current_seat := -1
var displayed_key_hints: Array[String] = []


func _ready() -> void:
	UITheme.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	queue_redraw()


func configure(seat_count: int, occupants: Array, current_seat: int) -> void:
	displayed_seat_count = clampi(seat_count, 0, 4)
	displayed_occupants.clear()
	for occupant_value: Variant in occupants:
		displayed_occupants.append(int(occupant_value))
	displayed_current_seat = current_seat if current_seat >= 0 and current_seat < displayed_seat_count else -1
	_update_key_hints()
	visible = displayed_seat_count > 0
	queue_redraw()


func clear() -> void:
	displayed_seat_count = 0
	displayed_occupants.clear()
	displayed_current_seat = -1
	displayed_key_hints.clear()
	visible = false
	queue_redraw()


func _draw() -> void:
	if displayed_seat_count <= 0:
		return
	var panel_rect := Rect2(8.0, 8.0, maxf(0.0, size.x - 16.0), maxf(0.0, size.y - 16.0))
	draw_rect(panel_rect, PANEL_COLOR, true)
	draw_rect(panel_rect, PANEL_BORDER_COLOR, false, 1.0)

	var hint_width := maxf(0.0, size.x - 24.0)
	for hint_index in range(displayed_key_hints.size()):
		draw_string(
			ThemeDB.fallback_font,
			Vector2(12.0, 28.0 + float(hint_index) * HINT_LINE_HEIGHT),
			displayed_key_hints[hint_index],
			HORIZONTAL_ALIGNMENT_CENTER,
			hint_width,
			HINT_FONT_SIZE,
			HINT_TEXT_COLOR
		)

	var base_rect := _seat_bar_rect()
	draw_rect(base_rect, SEAT_BAR_COLOR, true)
	draw_rect(base_rect, SEAT_BAR_BORDER_COLOR, false, 1.0)

	var positions := _seat_positions()
	for seat_index in range(positions.size()):
		var occupant := int(displayed_occupants[seat_index]) if seat_index < displayed_occupants.size() else 0
		var dot_color := OCCUPIED_COLOR if occupant > 0 else EMPTY_COLOR
		var position := positions[seat_index]
		draw_circle(position, DOT_RADIUS, dot_color)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(position.x - DOT_RADIUS - 2.0, position.y + 4.5),
			str(seat_index + 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			DOT_RADIUS * 2.0 + 4.0,
			12,
			UITheme.COLOR_TEXT
		)
		if seat_index == displayed_current_seat:
			draw_arc(position, DOT_RADIUS + 3.0, 0.0, TAU, 32, CURRENT_SEAT_BORDER_COLOR, 1.5, true)


func _seat_positions() -> Array[Vector2]:
	var center_x := size.x * 0.5
	var seat_bar := _seat_bar_rect()
	var center_y := seat_bar.position.y + seat_bar.size.y * 0.5
	var left_x := center_x - SEAT_COLUMN_OFFSET
	var right_x := center_x + SEAT_COLUMN_OFFSET
	match displayed_seat_count:
		1:
			return [Vector2(center_x, center_y)]
		2:
			return [Vector2(left_x, center_y), Vector2(right_x, center_y)]
		3:
			return [
				Vector2(left_x, center_y - SEAT_ROW_OFFSET),
				Vector2(right_x, center_y - SEAT_ROW_OFFSET),
				Vector2(center_x, center_y + SEAT_ROW_OFFSET),
			]
		_:
			return [
				Vector2(left_x, center_y - SEAT_ROW_OFFSET),
				Vector2(right_x, center_y - SEAT_ROW_OFFSET),
				Vector2(left_x, center_y + SEAT_ROW_OFFSET),
				Vector2(right_x, center_y + SEAT_ROW_OFFSET),
			]


func _seat_bar_rect() -> Rect2:
	var bar_width := 56.0 if displayed_seat_count == 1 else 82.0
	var bar_height := 28.0 if displayed_seat_count <= 2 else 42.0
	var center := Vector2(size.x * 0.5, size.y - 31.0)
	return Rect2(
		center.x - bar_width * 0.5,
		center.y - bar_height * 0.5,
		bar_width,
		bar_height
	)


func _update_key_hints() -> void:
	displayed_key_hints.clear()
	if displayed_seat_count <= 1:
		return
	if displayed_current_seat != 0:
		displayed_key_hints.append("按[1]坐到主驾驶位")
	var passenger_keys := PackedStringArray()
	for seat_index in range(1, displayed_seat_count):
		if seat_index == displayed_current_seat:
			continue
		passenger_keys.append("[%d]" % (seat_index + 1))
	if not passenger_keys.is_empty():
		displayed_key_hints.append("按%s坐到乘客位" % "/".join(passenger_keys))
