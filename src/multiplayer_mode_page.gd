extends Control
class_name MultiplayerModePage

signal cooperative_requested
signal competitive_requested
signal back_requested

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_COOP := Color("#54D6A2")
const COLOR_PVP := Color("#FFB36B")


func _ready() -> void:
	_build_interface()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(1180, 720)
	root.add_theme_constant_override("separation", 24)
	center.add_child(root)
	var title := Label.new()
	title.text = "多人游戏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)
	var hint := Label.new()
	hint.text = "选择与好友长期经营农场，或进入现有的多人对抗战局。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 26)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(hint)
	var choices := HBoxContainer.new()
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 24)
	root.add_child(choices)
	choices.add_child(_make_choice("联机合作", "创建自己的长期农场世界；通过 Steam 邀请好友加入。", COLOR_COOP, cooperative_requested.emit))
	choices.add_child(_make_choice("多人对抗", "进入官方服务器浏览器，加入现有 PVP 战局。", COLOR_PVP, competitive_requested.emit))
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(180, 56)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func() -> void: back_requested.emit())
	root.add_child(back)


func _make_choice(title_text: String, body_text: String, accent: Color, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 410)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = body_text
	button.text = "%s\n\n%s" % [title_text, body_text]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 32)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL, accent, 26))
	button.add_theme_stylebox_override("hover", _style_box(Color("#263B57"), accent, 26))
	button.pressed.connect(action)
	return button


func _style_box(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	return style
