extends Node

const CAPTURE_DIRECTORY := "user://captures"

var _capture_pending := false
var _notice_label: Label
var _notice_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_notice_ui()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo \
			and (key_event.keycode == KEY_F12 or key_event.physical_keycode == KEY_F12):
		capture_current_view()
		get_viewport().set_input_as_handled()


func capture_current_view() -> void:
	if _capture_pending:
		return
	_capture_pending = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	var path := "%s/screenshot_%s.png" % [CAPTURE_DIRECTORY, _timestamp()]
	var image := await capture_viewport_without_ui(get_viewport())
	var error := image.save_png(path)
	_capture_pending = false
	if error == OK:
		_show_notice("截图已保存\n%s" % ProjectSettings.globalize_path(path))
	else:
		_show_notice("截图保存失败：%s" % error_string(error))


func capture_viewport_without_ui(viewport: Viewport) -> Image:
	var visible_ui_roots: Array[Node] = []
	_collect_visible_ui_roots(viewport, viewport, visible_ui_roots)
	for node in visible_ui_roots:
		_set_ui_root_visible(node, false)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	for node in visible_ui_roots:
		if is_instance_valid(node):
			_set_ui_root_visible(node, true)
	return image


func _collect_visible_ui_roots(node: Node, viewport: Viewport, result: Array[Node]) -> void:
	for child in node.get_children():
		if not child is Node or (child as Node).get_viewport() != viewport:
			continue
		var child_node := child as Node
		if child_node is CanvasLayer:
			if (child_node as CanvasLayer).visible:
				result.append(child_node)
			continue
		if child_node is Control:
			if (child_node as Control).visible:
				result.append(child_node)
			continue
		_collect_visible_ui_roots(child_node, viewport, result)


func _set_ui_root_visible(node: Node, visible: bool) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = visible
	elif node is Control:
		(node as Control).visible = visible


func _create_notice_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_notice_label.position = Vector2(-680.0, -116.0)
	_notice_label.size = Vector2(650.0, 92.0)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_label.add_theme_color_override("font_color", Color.WHITE)
	_notice_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	_notice_label.add_theme_constant_override("outline_size", 6)
	_notice_label.add_theme_font_size_override("font_size", 18)
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.visible = false
	layer.add_child(_notice_label)

	_notice_timer = Timer.new()
	_notice_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_notice_timer.one_shot = true
	_notice_timer.wait_time = 5.0
	_notice_timer.timeout.connect(func():
		if is_instance_valid(_notice_label):
			_notice_label.visible = false
	)
	add_child(_notice_timer)


func _show_notice(message: String) -> void:
	if not is_instance_valid(_notice_label):
		return
	_notice_label.text = message
	_notice_label.visible = true
	_notice_timer.start()


func _timestamp() -> String:
	var time := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(time.year), int(time.month), int(time.day),
		int(time.hour), int(time.minute), int(time.second),
		Time.get_ticks_msec() % 1000,
	]
