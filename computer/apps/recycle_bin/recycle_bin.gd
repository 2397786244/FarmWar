extends ChocolateOSAppBase
class_name ChocolateOSRecycleBinApp

var recycle_icon: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func on_launch(context: ChocolateOSAppContext) -> void:
	super.on_launch(context)
	_apply_theme()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#ffffff")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "回收站"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#292929"))
	root.add_child(title)

	var separator := HSeparator.new()
	root.add_child(separator)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)

	recycle_icon = TextureRect.new()
	recycle_icon.custom_minimum_size = Vector2(112.0, 112.0)
	recycle_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	recycle_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	recycle_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(recycle_icon)

	var empty_label := Label.new()
	empty_label.text = "回收站为空"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 20)
	empty_label.add_theme_color_override("font_color", Color("#555555"))
	content.add_child(empty_label)


func _apply_theme() -> void:
	var os_id := app_context.get_os_id() if app_context != null else "OS08"
	var icon_path := "res://assets/icons/ChocolateOS/%s/system/recycle_bin.png" % os_id
	recycle_icon.texture = load(icon_path) as Texture2D
