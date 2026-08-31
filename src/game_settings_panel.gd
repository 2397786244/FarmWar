extends Control
class_name GameSettingsPanel

signal closed

const WORLD_POST_PROCESS_PATH := "EffectLayer/WorldPostProcess"

var bound_player: Node
var shader_material: ShaderMaterial
var default_values: Dictionary = {}
var slider_controls: Dictionary = {}
var slider_value_labels: Dictionary = {}
var color_controls: Dictionary = {}
var toggle_controls: Dictionary = {}
var render_toggle_controls: Dictionary = {}
var render_option_controls: Dictionary = {}
var render_option_values: Dictionary = {}
var render_slider_controls: Dictionary = {}
var render_slider_value_labels: Dictionary = {}
var display_settings: Node
var _close_button: Button
var _status_label: Label
var _vignette_start_slider: HSlider
var _vignette_end_slider: HSlider
var _built := false


func _ready() -> void:
	UITheme.apply(self)
	default_values = _make_default_values()
	_build_ui()
	visible = false


func bind_player(player: Node) -> void:
	bound_player = player
	display_settings = get_node_or_null("/root/DisplaySettings")
	if is_instance_valid(display_settings) and display_settings.has_method("apply_to_player"):
		display_settings.call("apply_to_player", player)
	_resolve_shader_material()
	_refresh_controls_from_shader()
	_refresh_render_controls()


func open() -> void:
	display_settings = get_node_or_null("/root/DisplaySettings")
	if is_instance_valid(display_settings):
		display_settings.call("apply_settings")
	_resolve_shader_material()
	_refresh_controls_from_shader()
	_refresh_render_controls()
	visible = true
	if is_instance_valid(_close_button):
		_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _make_default_values() -> Dictionary:
	return {
		"effect_strength": 1.0,
		"brightness": 1.0,
		"contrast": 1.05,
		"saturation": 1.08,
		"grade_strength": 0.18,
		"shadow_tint": Color(0.97, 0.99, 1.02, 1.0),
		"highlight_tint": Color(1.02, 0.99, 0.95, 1.0),
		"sharpen_strength": 0.12,
		"atmospheric_fog_enabled": true,
		"atmospheric_fog_strength": 0.65,
		"depth_of_field_enabled": true,
		"depth_of_field_strength": 0.34,
		"vignette_strength": 0.10,
		"vignette_start": 1.50,
		"vignette_end": 1.95,
		"motion_blur_enabled": 1.0,
		"motion_blur_strength": 0.22,
		"soft_glow_enabled": 1.0,
		"soft_glow_strength": 0.24,
		"soft_glow_threshold": 0.72,
		"chromatic_aberration_enabled": 1.0,
		"chromatic_aberration_strength": 0.16,
	}


func _build_ui() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dimmer := ColorRect.new()
	dimmer.name = "SettingsDimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.035, 0.055, 0.08, 0.68)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var window := PanelContainer.new()
	window.name = "SettingsWindow"
	window.anchor_left = 0.5
	window.anchor_top = 0.5
	window.anchor_right = 0.5
	window.anchor_bottom = 0.5
	window.offset_left = -520.0
	window.offset_top = -350.0
	window.offset_right = 520.0
	window.offset_bottom = 350.0
	window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window.grow_vertical = Control.GROW_DIRECTION_BOTH
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override(
		"panel",
		_make_style_box(UITheme.COLOR_PANEL, UITheme.COLOR_BORDER, 2, 4)
	)
	dimmer.add_child(window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	window.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, 44.0)
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	var title := Label.new()
	title.text = "设置"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	header.add_child(title)

	_close_button = _make_button("关闭", Vector2(112.0, 42.0), false)
	header.add_child(_close_button)
	_close_button.pressed.connect(func() -> void: close())

	var tabs := TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 20)
	tabs.add_theme_stylebox_override(
		"tab_selected",
		_make_style_box(UITheme.COLOR_SELECTED, UITheme.COLOR_TEXT, 1, 4)
	)
	tabs.add_theme_stylebox_override(
		"tab_unselected",
		_make_style_box(UITheme.COLOR_CONTROL, UITheme.COLOR_BORDER, 1, 4)
	)
	tabs.add_theme_stylebox_override(
		"tab_hovered",
		_make_style_box(UITheme.COLOR_HOVER, UITheme.COLOR_BORDER, 1, 4)
	)
	tabs.add_theme_stylebox_override(
		"tabbar_background",
		_make_style_box(UITheme.COLOR_PANEL, UITheme.COLOR_BORDER, 1, 4)
	)
	tabs.add_theme_color_override("font_selected_color", UITheme.COLOR_TEXT)
	tabs.add_theme_color_override("font_unselected_color", UITheme.COLOR_MUTED)
	tabs.add_theme_color_override("font_hovered_color", UITheme.COLOR_TEXT)
	content.add_child(tabs)

	var screen_page := ScrollContainer.new()
	screen_page.name = "ScreenSettings"
	screen_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(screen_page)
	tabs.set_tab_title(0, "画面设置")

	var screen_content := VBoxContainer.new()
	screen_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_content.add_theme_constant_override("separation", 9)
	screen_page.add_child(screen_content)

	_add_section_title(screen_content, "全局调色")
	_add_slider_row(screen_content, "effect_strength", "效果强度", 0.0, 1.0, 0.01, true)
	_add_slider_row(screen_content, "brightness", "亮度", 0.5, 1.5, 0.01, false)
	_add_slider_row(screen_content, "contrast", "对比度", 0.5, 1.5, 0.01, false)
	_add_slider_row(screen_content, "saturation", "饱和度", 0.0, 2.0, 0.01, false)
	_add_slider_row(screen_content, "grade_strength", "调色强度", 0.0, 1.0, 0.01, true)
	_add_color_row(screen_content, "shadow_tint", "阴影色调")
	_add_color_row(screen_content, "highlight_tint", "高光色调")

	_add_section_title(screen_content, "镜头效果")
	_add_slider_row(screen_content, "sharpen_strength", "锐化强度", 0.0, 1.0, 0.01, true)
	_add_toggle_row(
		screen_content,
		"chromatic_aberration_enabled",
		"色差",
		"让屏幕边缘产生轻微的红蓝通道分离，营造科幻镜头感"
	)
	_add_slider_row(screen_content, "chromatic_aberration_strength", "色差强度", 0.0, 1.0, 0.01, true)
	_add_slider_row(screen_content, "vignette_strength", "暗角强度", 0.0, 1.0, 0.01, true)
	_vignette_start_slider = _add_slider_row(
		screen_content,
		"vignette_start",
		"暗角开始位置",
		0.0,
		2.5,
		0.01,
		false
	)
	_vignette_end_slider = _add_slider_row(
		screen_content,
		"vignette_end",
		"暗角结束位置",
		0.5,
		2.5,
		0.01,
		false
	)
	_vignette_start_slider.value_changed.connect(_on_vignette_start_changed)
	_vignette_end_slider.value_changed.connect(_on_vignette_end_changed)

	_add_section_title(screen_content, "大气与景深")
	_add_render_toggle_row(
		screen_content,
		"atmospheric_fog_enabled",
		"大气雾",
		"晴天保留远距离朦胧感，雨天会自动增强并缩短可视距离"
	)
	_add_render_slider_row(
		screen_content,
		"atmospheric_fog_strength",
		"大气雾强度",
		0.0,
		1.0,
		0.01,
		true
	)
	_add_render_toggle_row(
		screen_content,
		"depth_of_field_enabled",
		"相机景深",
		"让近处和远处逐渐虚化，中景保持清晰；关闭可节省后处理开销"
	)
	_add_render_slider_row(
		screen_content,
		"depth_of_field_strength",
		"景深强度",
		0.0,
		1.0,
		0.01,
		true
	)

	_add_section_title(screen_content, "动态效果")
	_add_toggle_row(
		screen_content,
		"motion_blur_enabled",
		"运动模糊",
		"角色或载具速度达到 6m/s，或 Camera 晃动/快速转向时生效"
	)
	_add_slider_row(screen_content, "motion_blur_strength", "运动模糊强度", 0.0, 1.0, 0.01, true)
	_add_toggle_row(
		screen_content,
		"soft_glow_enabled",
		"柔光",
		"柔化高亮区域，营造轻微泛光效果"
	)
	_add_slider_row(screen_content, "soft_glow_strength", "柔光强度", 0.0, 1.0, 0.01, true)
	_add_slider_row(screen_content, "soft_glow_threshold", "柔光亮度阈值", 0.5, 1.0, 0.01, true)

	_add_section_title(screen_content, "抗锯齿与渲染")
	_add_render_option_row(
		screen_content,
		"aa_mode",
		"抗锯齿模式",
		["关闭", "FXAA", "SMAA", "TAA", "FSR2"],
		["off", "fxaa", "smaa", "taa", "fsr2"]
	)
	_add_render_option_row(
		screen_content,
		"msaa_3d",
		"3D MSAA",
		["关闭", "2x", "4x", "8x"],
		[0, 1, 2, 3]
	)
	_add_render_option_row(
		screen_content,
		"msaa_2d",
		"2D MSAA",
		["关闭", "2x", "4x", "8x"],
		[0, 1, 2, 3]
	)
	_add_render_slider_row(screen_content, "fsr2_scale", "FSR2渲染比例", 0.5, 1.0, 0.01, true)
	_add_render_toggle_row(
		screen_content,
		"debanding_enabled",
		"去色带",
		"减少天空和雾效中的颜色分层"
	)

	_add_placeholder_tab(tabs, "音频设置", "音频设置将在后续版本加入。")
	_add_placeholder_tab(tabs, "操作设置", "操作设置将在后续版本加入。")

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0.0, 44.0)
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)

	_status_label = Label.new()
	_status_label.text = "修改会立即生效"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
	_status_label.add_theme_font_size_override("font_size", 16)
	footer.add_child(_status_label)

	var reset_button := _make_button("恢复默认", Vector2(132.0, 42.0), false)
	footer.add_child(reset_button)
	reset_button.pressed.connect(_reset_to_defaults)

	var footer_close_button := _make_button("完成", Vector2(112.0, 42.0), true)
	footer.add_child(footer_close_button)
	footer_close_button.pressed.connect(func() -> void: close())


func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var separator := HSeparator.new()
	separator.add_theme_color_override("color", UITheme.COLOR_BORDER)
	parent.add_child(separator)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	parent.add_child(label)


func _add_toggle_row(
	parent: VBoxContainer,
	parameter: String,
	label_text: String,
	hint_text: String,
	render_setting := false
) -> CheckButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 46.0)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)

	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 17)
	text_column.add_child(label)

	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
	hint.add_theme_font_size_override("font_size", 13)
	text_column.add_child(hint)

	var toggle := CheckButton.new()
	toggle.name = parameter
	toggle.text = "开启"
	toggle.custom_minimum_size = Vector2(110.0, 38.0)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.button_pressed = float(default_values.get(parameter, 0.0)) > 0.5
	toggle.add_theme_font_size_override("font_size", 16)
	UITheme.apply_button(toggle)
	toggle.tooltip_text = hint_text
	row.add_child(toggle)
	if render_setting:
		render_toggle_controls[parameter] = toggle
	else:
		toggle_controls[parameter] = toggle
	toggle.toggled.connect(func(enabled: bool) -> void:
		if render_setting:
			_set_render_setting(parameter, enabled)
		else:
			_set_shader_parameter(parameter, 1.0 if enabled else 0.0)
	)
	return toggle


func _add_render_toggle_row(
	parent: VBoxContainer,
	parameter: String,
	label_text: String,
	hint_text: String
) -> CheckButton:
	return _add_toggle_row(parent, parameter, label_text, hint_text, true)


func _add_slider_row(
	parent: VBoxContainer,
	parameter: String,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	display_as_percent: bool
) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = parameter
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(default_values.get(parameter, minimum))
	slider.tooltip_text = label_text
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", UITheme.COLOR_INFO)
	value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(value_label)

	slider_controls[parameter] = slider
	slider_value_labels[parameter] = value_label
	value_label.text = _format_slider_value(slider.value, display_as_percent)
	slider.value_changed.connect(func(value: float) -> void:
		_set_shader_parameter(parameter, value)
		value_label.text = _format_slider_value(value, display_as_percent)
	)
	return slider


func _add_render_option_row(
	parent: VBoxContainer,
	parameter: String,
	label_text: String,
	labels: Array,
	values: Array
) -> OptionButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var option := OptionButton.new()
	option.name = parameter
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0.0, 36.0)
	option.focus_mode = Control.FOCUS_ALL
	option.tooltip_text = label_text
	for item: Variant in labels:
		option.add_item(str(item))
	row.add_child(option)

	render_option_controls[parameter] = option
	render_option_values[parameter] = values.duplicate()
	var current_value: Variant = _get_render_setting(parameter, values[0] if not values.is_empty() else null)
	var selected_index := values.find(current_value)
	option.select(maxi(0, selected_index))
	option.item_selected.connect(func(index: int) -> void:
		if index >= 0 and index < values.size():
			_set_render_setting(parameter, values[index])
	)
	return option


func _add_render_slider_row(
	parent: VBoxContainer,
	parameter: String,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	display_as_percent: bool
) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = parameter
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(_get_render_setting(parameter, minimum))
	slider.tooltip_text = label_text
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", UITheme.COLOR_INFO)
	value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(value_label)

	render_slider_controls[parameter] = slider
	render_slider_value_labels[parameter] = value_label
	value_label.text = _format_slider_value(slider.value, display_as_percent)
	slider.value_changed.connect(func(value: float) -> void:
		_set_render_setting(parameter, value)
		value_label.text = _format_slider_value(value, display_as_percent)
	)
	return slider


func _add_color_row(parent: VBoxContainer, parameter: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var picker := ColorPickerButton.new()
	picker.name = parameter
	picker.custom_minimum_size = Vector2(170.0, 36.0)
	picker.color = default_values.get(parameter, Color.WHITE)
	picker.tooltip_text = "点击选择颜色"
	row.add_child(picker)
	color_controls[parameter] = picker
	picker.color_changed.connect(func(color: Color) -> void:
		_set_shader_parameter(parameter, color)
	)


func _add_placeholder_tab(tabs: TabContainer, title: String, description: String) -> void:
	var page := CenterContainer.new()
	page.name = title
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(page)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)

	var label := Label.new()
	label.text = description
	label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
	label.add_theme_font_size_override("font_size", 20)
	page.add_child(label)


func _make_button(text: String, minimum_size: Vector2, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 17)
	UITheme.apply_button(button)
	return button


func _make_style_box(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	return UITheme.make_style(background, border, border_width, radius)


func _resolve_shader_material() -> void:
	shader_material = null
	if not is_instance_valid(bound_player):
		return
	var world_post := bound_player.get_node_or_null(WORLD_POST_PROCESS_PATH) as ColorRect
	if world_post != null:
		shader_material = world_post.material as ShaderMaterial
	if is_instance_valid(_status_label):
		_status_label.text = "修改会立即生效" if shader_material != null else "未找到画面后处理材质"


func _get_render_setting(parameter: String, fallback: Variant) -> Variant:
	if is_instance_valid(display_settings) and display_settings.has_method("get_setting"):
		return display_settings.call("get_setting", parameter, fallback)
	return fallback


func _set_render_setting(parameter: String, value: Variant) -> void:
	if is_instance_valid(display_settings) and display_settings.has_method("set_setting"):
		display_settings.call("set_setting", parameter, value)


func _refresh_render_controls() -> void:
	if not _built:
		return
	for parameter: Variant in render_option_controls.keys():
		var option := render_option_controls[parameter] as OptionButton
		var values: Array = render_option_values[parameter]
		if values.is_empty():
			continue
		var current_value: Variant = _get_render_setting(str(parameter), values[0])
		var selected_index := values.find(current_value)
		option.select(maxi(0, selected_index))
	for parameter: Variant in render_slider_controls.keys():
		var slider := render_slider_controls[parameter] as HSlider
		var value := float(_get_render_setting(str(parameter), slider.min_value))
		slider.value = clampf(value, slider.min_value, slider.max_value)
		var value_label := render_slider_value_labels[parameter] as Label
		value_label.text = _format_slider_value(slider.value, true)
	for parameter: Variant in render_toggle_controls.keys():
		var toggle := render_toggle_controls[parameter] as CheckButton
		toggle.button_pressed = bool(_get_render_setting(str(parameter), false))


func _refresh_controls_from_shader() -> void:
	if not _built:
		return
	for parameter: Variant in toggle_controls.keys():
		var toggle := toggle_controls[parameter] as CheckButton
		var enabled := float(default_values.get(parameter, 0.0)) > 0.5
		if shader_material != null:
			var shader_value: Variant = shader_material.get_shader_parameter(str(parameter))
			if shader_value is float or shader_value is int:
				enabled = float(shader_value) > 0.5
		toggle.button_pressed = enabled
	for parameter: Variant in slider_controls.keys():
		var slider := slider_controls[parameter] as HSlider
		var value := float(default_values.get(parameter, slider.value))
		if shader_material != null:
			var shader_value: Variant = shader_material.get_shader_parameter(str(parameter))
			if shader_value is float or shader_value is int:
				value = float(shader_value)
		slider.value = clampf(value, slider.min_value, slider.max_value)
	for parameter: Variant in color_controls.keys():
		var picker := color_controls[parameter] as ColorPickerButton
		var color: Color = default_values.get(parameter, Color.WHITE)
		if shader_material != null:
			var shader_value: Variant = shader_material.get_shader_parameter(str(parameter))
			if shader_value is Color:
				color = shader_value
		picker.color = color


func _set_shader_parameter(parameter: String, value: Variant) -> void:
	if shader_material != null:
		shader_material.set_shader_parameter(parameter, value)
	if is_instance_valid(display_settings) and display_settings.has_method("set_setting"):
		display_settings.call("set_setting", parameter, value)


func _reset_to_defaults() -> void:
	if is_instance_valid(display_settings) and display_settings.has_method("reset_to_defaults"):
		display_settings.call("reset_to_defaults")
		if is_instance_valid(bound_player) and display_settings.has_method("apply_to_player"):
			display_settings.call("apply_to_player", bound_player)
		_refresh_controls_from_shader()
		_refresh_render_controls()
		if is_instance_valid(_status_label):
			_status_label.text = "已恢复默认画面设置"
		return
	for parameter: Variant in toggle_controls.keys():
		var toggle := toggle_controls[parameter] as CheckButton
		toggle.button_pressed = float(default_values[parameter]) > 0.5
	for parameter: Variant in slider_controls.keys():
		var slider := slider_controls[parameter] as HSlider
		slider.value = float(default_values[parameter])
	for parameter: Variant in color_controls.keys():
		var picker := color_controls[parameter] as ColorPickerButton
		picker.color = default_values[parameter] as Color
	if is_instance_valid(_status_label):
		_status_label.text = "已恢复默认画面设置"


func _on_vignette_start_changed(value: float) -> void:
	if _vignette_end_slider != null and value >= _vignette_end_slider.value:
		_vignette_end_slider.value = minf(_vignette_end_slider.max_value, value + 0.01)


func _on_vignette_end_changed(value: float) -> void:
	if _vignette_start_slider != null and value <= _vignette_start_slider.value:
		_vignette_start_slider.value = maxf(_vignette_start_slider.min_value, value - 0.01)


func _format_slider_value(value: float, display_as_percent: bool) -> String:
	if display_as_percent:
		return "%d%%" % roundi(value * 100.0)
	return "%.2f" % value
