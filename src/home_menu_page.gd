extends Control
class_name HomeMenuPage

signal start_game_requested
signal singleplayer_requested
signal multiplayer_requested
signal map_editor_requested
signal settings_requested
signal quit_requested

const COLOR_BG := UITheme.COLOR_BG
const COLOR_PANEL_2 := UITheme.COLOR_CONTROL
const COLOR_ACCENT := UITheme.COLOR_INFO
const COLOR_TEXT := UITheme.COLOR_TEXT
const COLOR_MUTED := UITheme.COLOR_MUTED
const START_SCENE := preload("res://ui/start_scene.tscn")
const RELEASE_CHANNEL := "Alpha"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UITheme.apply(self)
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
	title.text = "丰收行动"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Harvest Operation"
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

	var version_label := Label.new()
	version_label.text = "v%s-%s" % [
		str(ProjectSettings.get_setting("application/config/version", "0.3.7")),
		RELEASE_CHANNEL,
	]
	version_label.anchor_left = 0.0
	version_label.anchor_top = 1.0
	version_label.anchor_right = 0.0
	version_label.anchor_bottom = 1.0
	version_label.offset_left = 58.0
	version_label.offset_top = -34.0
	version_label.offset_right = 220.0
	version_label.offset_bottom = -10.0
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color(0.69, 0.76, 0.81, 0.82))
	version_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	version_label.add_theme_constant_override("outline_size", 4)
	add_child(version_label)


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
	UITheme.apply_button(button)
	return button
