extends Control
class_name HomeMenuPage

signal start_game_requested
signal singleplayer_requested
signal multiplayer_requested
signal map_editor_requested
signal settings_requested
signal quit_requested

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL_2 := Color("#171B1F")
const COLOR_ACCENT := Color("#54D6A2")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const START_SCENE := preload("res://ui/start_scene.tscn")


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var transition_shade := ColorRect.new()
	transition_shade.color = Color(0.0, 0.0, 0.0, 0.0)
	transition_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var studio := START_SCENE.instantiate() as StartSceneShowcase
	studio.transition_alpha_changed.connect(
		func(alpha: float) -> void:
			transition_shade.color.a = alpha
	)
	add_child(studio)

	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.025, 0.16)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	add_child(transition_shade)

	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 58.0
	box.offset_top = -520.0
	box.offset_right = 398.0
	box.offset_bottom = -48.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 13)
	add_child(box)

	var title := Label.new()
	title.text = "农场大乱斗"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FarmWar"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	subtitle.add_theme_constant_override("outline_size", 5)
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	box.add_child(spacer)

	var single_button := _make_button("单人游戏")
	single_button.pressed.connect(_on_singleplayer_pressed)
	box.add_child(single_button)

	var multiplayer_button := _make_button("多人游戏")
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	box.add_child(multiplayer_button)

	var map_editor_button := _make_button("地图编辑器")
	map_editor_button.pressed.connect(_on_map_editor_pressed)
	box.add_child(map_editor_button)

	var settings_button := _make_button("设置")
	settings_button.pressed.connect(func(): settings_requested.emit())
	box.add_child(settings_button)

	var quit_button := _make_button("退出游戏")
	quit_button.pressed.connect(func(): quit_requested.emit())
	box.add_child(quit_button)


func _on_singleplayer_pressed() -> void:
	print("[MenuFlow] Home: single-player button pressed")
	singleplayer_requested.emit()


func _on_multiplayer_pressed() -> void:
	print("[MenuFlow] Home: multiplayer button pressed")
	multiplayer_requested.emit()


func _on_map_editor_pressed() -> void:
	print("[MenuFlow] Home: map editor button pressed")
	map_editor_requested.emit()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(310, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 6))
	button.add_theme_stylebox_override("hover", _style_box(Color("#C56D31"), 6))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_ACCENT, 6))
	button.add_theme_stylebox_override("focus", _style_box(Color("#28302D"), 6))
	return button


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
