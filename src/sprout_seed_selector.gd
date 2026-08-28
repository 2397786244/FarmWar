extends Control
class_name SproutSeedSelector

## A compact, non-interactive seed carousel for the SproutBlaster HUD.
## The center item is fully opaque and focused; items farther from the center
## are slightly smaller and more transparent. Only the previous, current and
## next seed are rendered so the selector remains compact and easy to read.

const SELECTOR_WIDTH := 560.0
const SELECTOR_HEIGHT := 154.0
const CAROUSEL_HEIGHT := 104.0
const CENTER_X := SELECTOR_WIDTH * 0.5
const SLOT_SPACING := 110.0
const VISIBLE_RADIUS := 1
const ICON_SIZES := [82.0, 68.0]
const ICON_ALPHAS := [1.0, 0.72]

var _carousel: Control
var _focus_panel: Panel
var _seed_name_label: Label
var _left_arrow_hint: Label
var _right_arrow_hint: Label
var _last_seed_ids: Array[String] = []
var _last_selected_index := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 24.0
	offset_top = -322.0
	offset_right = 24.0 + SELECTOR_WIDTH
	offset_bottom = -168.0
	custom_minimum_size = Vector2(SELECTOR_WIDTH, SELECTOR_HEIGHT)
	_build_ui()
	visible = false


func _build_ui() -> void:
	var background := Panel.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override(
		"panel",
		_make_style(Color(0.07, 0.08, 0.10, 0.91), Color(0.78, 0.82, 0.86, 0.72), 1, 9)
	)
	add_child(background)

	_carousel = Control.new()
	_carousel.name = "Carousel"
	_carousel.position = Vector2(0.0, 5.0)
	_carousel.size = Vector2(SELECTOR_WIDTH, CAROUSEL_HEIGHT)
	_carousel.clip_contents = true
	_carousel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carousel.z_index = 1
	add_child(_carousel)

	_left_arrow_hint = _make_arrow_hint("LeftArrowHint", "<-")
	_left_arrow_hint.position = Vector2(78.0, 40.0)
	_left_arrow_hint.size = Vector2(48.0, 28.0)
	_left_arrow_hint.z_index = 3
	add_child(_left_arrow_hint)

	_right_arrow_hint = _make_arrow_hint("RightArrowHint", "->")
	_right_arrow_hint.position = Vector2(SELECTOR_WIDTH - 126.0, 40.0)
	_right_arrow_hint.size = Vector2(48.0, 28.0)
	_right_arrow_hint.z_index = 3
	add_child(_right_arrow_hint)

	_focus_panel = Panel.new()
	_focus_panel.name = "SelectedFocus"
	_focus_panel.position = Vector2(CENTER_X - 47.0, 9.0)
	_focus_panel.size = Vector2(94.0, 94.0)
	_focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_panel.z_index = 2
	_focus_panel.add_theme_stylebox_override(
		"panel",
		_make_style(Color(0.98, 0.84, 0.33, 0.10), Color(1.0, 0.84, 0.32, 0.92), 2, 8)
	)
	add_child(_focus_panel)

	_seed_name_label = Label.new()
	_seed_name_label.name = "SelectedSeedName"
	_seed_name_label.position = Vector2(8.0, 108.0)
	_seed_name_label.size = Vector2(SELECTOR_WIDTH - 16.0, 32.0)
	_seed_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seed_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seed_name_label.z_index = 4
	_seed_name_label.add_theme_font_size_override("font_size", 20)
	_seed_name_label.add_theme_color_override("font_color", Color("#FFF1B8"))
	add_child(_seed_name_label)


func _make_arrow_hint(node_name: String, text_value: String) -> Label:
	var hint := Label.new()
	hint.name = node_name
	hint.text = text_value
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.90, 0.93, 0.96, 0.88))
	return hint


func refresh(seed_ids: Array[String], selected_index: int) -> void:
	if seed_ids.is_empty():
		visible = false
		return
	var normalized_index := clampi(selected_index, 0, seed_ids.size() - 1)
	if _last_selected_index == normalized_index and _last_seed_ids == seed_ids:
		return
	_last_seed_ids = seed_ids.duplicate()
	_last_selected_index = normalized_index
	if not is_instance_valid(_carousel):
		return
	for child in _carousel.get_children():
		child.queue_free()

	for offset in range(-VISIBLE_RADIUS, VISIBLE_RADIUS + 1):
		var index := wrapi(normalized_index + offset, 0, seed_ids.size())
		_add_seed_visual(seed_ids[index], offset)

	var selected_seed_id := seed_ids[normalized_index]
	var definition := IngredientCatalog.get_definition(selected_seed_id)
	_seed_name_label.text = str(definition.get("display_name", selected_seed_id))
	visible = true


func reset() -> void:
	_last_seed_ids.clear()
	_last_selected_index = -1
	visible = false


func _add_seed_visual(seed_id: String, offset: int) -> void:
	var distance := mini(abs(offset), ICON_SIZES.size() - 1)
	var icon_size: float = ICON_SIZES[distance]
	var icon := TextureRect.new()
	icon.name = "Seed_%s_%d" % [seed_id, offset]
	icon.size = Vector2(icon_size, icon_size)
	icon.position = Vector2(
		CENTER_X + float(offset) * SLOT_SPACING - icon_size * 0.5,
		(CAROUSEL_HEIGHT - icon_size) * 0.5
	)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1.0, 1.0, 1.0, ICON_ALPHAS[distance])
	icon.z_index = 20 - distance
	icon.texture = ItemIconCatalog.get_ingredient_icon(seed_id)
	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = "?"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.add_theme_font_size_override("font_size", int(icon_size * 0.55))
		fallback.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, ICON_ALPHAS[distance]))
		icon.add_child(fallback)
	_carousel.add_child(icon)


func _make_style(
	background: Color,
	border_color: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
