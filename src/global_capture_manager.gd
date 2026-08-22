extends Node

const CAPTURE_DIRECTORY := "user://captures"

var _capture_pending := false
var _notice_label: Label
var _notice_timer: Timer
var _chat_capture_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_notice_ui()


func _input(event: InputEvent) -> void:
	if _is_chat_input_active():
		# Do not consume ordinary key events here: LineEdit receives them after
		# the input phase. Gameplay action events are consumed by the owning
		# player, while this gate prevents global shortcuts from leaking through.
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo \
			and (key_event.keycode == KEY_F12 or key_event.physical_keycode == KEY_F12):
		capture_current_view()
		get_viewport().set_input_as_handled()


func set_chat_input_active(active: bool) -> void:
	if active:
		_chat_capture_count += 1
	else:
		_chat_capture_count = maxi(0, _chat_capture_count - 1)


func is_chat_input_capturing() -> bool:
	return _chat_capture_count > 0


func _is_chat_input_active() -> bool:
	if is_chat_input_capturing():
		return true
	for node: Node in get_tree().get_nodes_in_group("human_players"):
		if is_instance_valid(node) and node.has_method("is_chat_input_active") \
				and bool(node.call("is_chat_input_active")):
			return true
	return false


func capture_current_view() -> void:
	if _capture_pending:
		return
	_capture_pending = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	var path := "%s/screenshot_%s.png" % [CAPTURE_DIRECTORY, _timestamp()]
	# Keep the current post-process/weather/remote visual effects, but remove the
	# local player's own body, held model, and active remote device from the
	# captured frame.
	var image := await capture_viewport_without_ui(get_viewport(), true)
	var error := image.save_png(path)
	_capture_pending = false
	if error == OK:
		_show_notice("截图已保存\n%s" % ProjectSettings.globalize_path(path))
	else:
		_show_notice("截图保存失败：%s" % error_string(error))


func capture_viewport_without_ui(
	viewport: Viewport,
	hide_local_player := false
) -> Image:
	var visible_ui_roots: Array[Node] = []
	_collect_visible_ui_roots(viewport, viewport, visible_ui_roots)
	for node in visible_ui_roots:
		_set_ui_root_visible(node, false)
	var hidden_player_visuals: Array[Dictionary] = []
	if hide_local_player:
		_hide_local_player_visuals(viewport, hidden_player_visuals)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	for node in visible_ui_roots:
		if is_instance_valid(node):
			_set_ui_root_visible(node, true)
	_restore_capture_nodes(hidden_player_visuals)
	return image


func _collect_visible_ui_roots(node: Node, viewport: Viewport, result: Array[Node]) -> void:
	for child in node.get_children():
		if not child is Node or (child as Node).get_viewport() != viewport:
			continue
		var child_node := child as Node
		if child_node is CanvasLayer:
			# EffectLayer contains the active world post-process and remote visual
			# shaders. It is a screen effect, not UI, so it must remain enabled for
			# screenshots to match the current game view.
			if _is_capture_visual_effect_layer(child_node):
				continue
			if (child_node as CanvasLayer).visible:
				result.append(child_node)
			continue
		if child_node is Control:
			if (child_node as Control).visible:
				result.append(child_node)
			continue
		_collect_visible_ui_roots(child_node, viewport, result)


func _is_capture_visual_effect_layer(node: Node) -> bool:
	if node == null:
		return false
	if node.name == "EffectLayer":
		return true
	return node.find_child("WorldPostProcess", true, false) != null


func _hide_local_player_visuals(
	viewport: Viewport,
	hidden_nodes: Array[Dictionary]
) -> void:
	for player in get_tree().get_nodes_in_group("human_players"):
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		var remote_proxy: Variant = player.get("is_remote_proxy")
		if remote_proxy == null:
			continue
		if bool(remote_proxy):
			continue
		if player.get_viewport() != viewport:
			continue
		for node_path in [
				"AppearanceNode",
				"RightHandSocket/ToolPivot",
				"TeamMarker",
			]:
			_hide_capture_node(player.get_node_or_null(node_path), hidden_nodes)

		# When the local player is viewing a remote device, that device owns the
		# active camera. Hide only its render tree; the Camera3D remains current and
		# the player's EffectLayer (including RemoteEffect/RemoteLQEffect) remains
		# visible so the saved frame matches the remote feed.
		if bool(player.get("remote_is_active")):
			var remote_node_value: Variant = player.get("remote_tool_node")
			if remote_node_value is Node:
				var remote_node := remote_node_value as Node
				if remote_node.get_viewport() == viewport:
					_hide_capture_node(remote_node, hidden_nodes)


func _hide_capture_node(node: Node, hidden_nodes: Array[Dictionary]) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not _capture_node_is_visible(node):
		return
	hidden_nodes.append({
		"node": node,
		"visible": true,
	})
	_set_capture_node_visible(node, false)


func _restore_capture_nodes(hidden_nodes: Array[Dictionary]) -> void:
	for entry in hidden_nodes:
		var node := entry.get("node") as Node
		if is_instance_valid(node):
			_set_capture_node_visible(node, bool(entry.get("visible", true)))


func _capture_node_is_visible(node: Node) -> bool:
	if node is CanvasLayer:
		return (node as CanvasLayer).visible
	if node is Control:
		return (node as Control).visible
	if node is Node3D:
		return (node as Node3D).visible
	return false


func _set_capture_node_visible(node: Node, visible: bool) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = visible
	elif node is Control:
		(node as Control).visible = visible
	elif node is Node3D:
		(node as Node3D).visible = visible


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
