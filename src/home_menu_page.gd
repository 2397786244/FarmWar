extends Control
class_name HomeMenuPage

signal start_game_requested
signal singleplayer_requested
signal multiplayer_requested
signal settings_requested
signal quit_requested

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_ACCENT := Color("#54D6A2")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 620)
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 30))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_bottom", 48)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	margin.add_child(box)

	var title := Label.new()
	title.text = "FOOD WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "农场厨房对抗游戏"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	box.add_child(spacer)

	var single_button := _make_button("单人游戏")
	single_button.pressed.connect(_on_singleplayer_pressed)
	box.add_child(single_button)

	var multiplayer_button := _make_button("多人游戏")
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	box.add_child(multiplayer_button)

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


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 64)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 18))
	button.add_theme_stylebox_override("hover", _style_box(Color("#314766"), 18))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_ACCENT, 18))
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
