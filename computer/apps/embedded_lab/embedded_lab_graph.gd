extends Control
class_name EmbeddedLabTechGraph

const NODE_ORIGIN := Vector2(12.0, 18.0)
const COLUMN_STEP := 140.0
const ROW_STEP := 76.0
const NODE_CONNECT_OFFSET := Vector2(118.0, 39.0)


func node_position(row: int, column: int) -> Vector2:
	return NODE_ORIGIN + Vector2(float(column) * COLUMN_STEP, float(row) * ROW_STEP)


func _ready() -> void:
	custom_minimum_size = Vector2(690.0, 330.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	for row in range(4):
		var track_color: Color = EmbeddedLabCatalog.TRACKS[row].get("color", Color("#aeb3b9"))
		for column in range(4):
			var start := node_position(row, column) + NODE_CONNECT_OFFSET
			var end := node_position(row, column + 1) + Vector2(0.0, NODE_CONNECT_OFFSET.y)
			draw_line(start, end, Color(track_color, 0.48), 2.0, true)
			draw_colored_polygon(PackedVector2Array([
				end,
				end - Vector2(8.0, 4.0),
				end - Vector2(8.0, -4.0),
			]), Color(track_color, 0.7))
