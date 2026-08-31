extends RefCounted
class_name UITheme

## Shared neutral UI palette for all in-game UI outside ChocolateOS.
## Keep this class limited to presentation helpers; it must not contain game
## state, transaction logic, or network behavior.

const SHARED_THEME: Theme = preload("res://ui/shared_ui_theme.tres")

const COLOR_BG := Color("#15171A")
const COLOR_PANEL := Color("#1D2024")
const COLOR_CONTROL := Color("#272B30")
const COLOR_HOVER := Color("#32373D")
const COLOR_SELECTED := Color("#3C4249")
const COLOR_BORDER := Color("#4B5159")
const COLOR_TEXT := Color("#F0F1F2")
const COLOR_MUTED := Color("#A4A8AD")

const COLOR_SUCCESS := Color("#86B59A")
const COLOR_WARNING := Color("#C2A66E")
const COLOR_ERROR := Color("#C98585")
const COLOR_INFO := Color("#8FAAC2")

const TONE_NEUTRAL := &"neutral"
const TONE_SUCCESS := &"success"
const TONE_WARNING := &"warning"
const TONE_ERROR := &"error"
const TONE_INFO := &"info"
const TONE_MUTED := &"muted"


static func apply(root: Control) -> void:
	if not is_instance_valid(root):
		return
	root.theme = SHARED_THEME
	root.set_meta("shared_ui_theme_applied", true)


static func make_style(
	background: Color,
	border_color: Color = COLOR_BORDER,
	border_width: int = 1,
	radius: int = 4
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_top = 6.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 6.0
	return style


static func tone_color(tone: StringName) -> Color:
	match tone:
		TONE_SUCCESS:
			return COLOR_SUCCESS
		TONE_WARNING:
			return COLOR_WARNING
		TONE_ERROR:
			return COLOR_ERROR
		TONE_INFO:
			return COLOR_INFO
		TONE_MUTED:
			return COLOR_MUTED
		_:
			return COLOR_TEXT


static func set_tone(control: Control, tone: StringName) -> void:
	if not is_instance_valid(control):
		return
	var color := tone_color(tone)
	if control is RichTextLabel:
		(control as RichTextLabel).add_theme_color_override("default_color", color)
	else:
		control.add_theme_color_override("font_color", color)


static func set_status(control: Control, tone: StringName) -> void:
	set_tone(control, tone)


static func apply_button(button: Button, tone: StringName = TONE_NEUTRAL) -> void:
	if not is_instance_valid(button):
		return
	button.add_theme_stylebox_override("normal", make_style(COLOR_CONTROL, COLOR_BORDER, 1, 4))
	button.add_theme_stylebox_override("hover", make_style(COLOR_HOVER, COLOR_BORDER, 1, 4))
	button.add_theme_stylebox_override("pressed", make_style(COLOR_SELECTED, COLOR_TEXT, 1, 4))
	button.add_theme_stylebox_override("focus", make_style(COLOR_SELECTED, COLOR_TEXT, 1, 4))
	button.add_theme_stylebox_override("disabled", make_style(COLOR_PANEL, COLOR_BORDER, 1, 4))
	var text_color := COLOR_TEXT if tone == TONE_NEUTRAL else tone_color(tone)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)


static func apply_slot(slot: PanelContainer, selected := false, disabled := false) -> void:
	if not is_instance_valid(slot):
		return
	var background := COLOR_PANEL if disabled else COLOR_SELECTED if selected else COLOR_CONTROL
	var border := COLOR_MUTED if disabled else COLOR_TEXT if selected else COLOR_BORDER
	slot.add_theme_stylebox_override("panel", make_style(background, border, 1, 4))


static func apply_progress(progress: ProgressBar, tone: StringName = TONE_INFO) -> void:
	if not is_instance_valid(progress):
		return
	progress.add_theme_stylebox_override("background", make_style(COLOR_CONTROL, COLOR_BORDER, 1, 3))
	progress.add_theme_stylebox_override("fill", make_style(tone_color(tone), tone_color(tone), 0, 3))


static func apply_panel(panel: PanelContainer, surface := COLOR_PANEL, width := 1, radius := 4) -> void:
	if not is_instance_valid(panel):
		return
	panel.add_theme_stylebox_override("panel", make_style(surface, COLOR_BORDER, width, radius))
