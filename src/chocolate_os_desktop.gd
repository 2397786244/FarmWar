extends Control
class_name ChocolateOSDesktop

signal closed

const LOGICAL_SIZE := Vector2(1280.0, 720.0)
const TASKBAR_HEIGHT := 58.0
const HEARTBEAT_SECONDS := 10.0
const DESKTOP_DOUBLE_CLICK_INTERVAL_MSEC := 450
const ICON_CELL_SIZE := Vector2(92.0, 98.0)
const ICON_ORIGIN := Vector2(20.0, 20.0)

var player: GamePlayer
var computer: ComputerTerminal
var computer_state: Dictionary = {}
var shell: Panel
var wallpaper: TextureRect
var icon_layer: Control
var window_layer: Control
var taskbar: Panel
var dock: HBoxContainer
var clock_label: Label
var shutdown_overlay: ColorRect
var shutdown_label: Label
var icon_controls: Dictionary = {}
var app_windows: Dictionary = {}
var app_instances: Dictionary = {}
var browser_sessions: Dictionary = {}
var next_window_z := 10
var heartbeat_elapsed := 0.0
var time_elapsed := 0.0
var last_viewport_size := Vector2.ZERO
var drag_app_id := ""
var drag_start_mouse := Vector2.ZERO
var drag_start_position := Vector2.ZERO
var drag_moved := false
var last_icon_click_app_id := ""
var last_icon_click_msec := 0
var suppressed_icon_activation_app_id := ""
var dock_refresh_queued := false
var shutting_down := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	visible = false
	_build_shell()
	set_process(true)


func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	shell = Panel.new()
	shell.name = "ComputerScreen"
	shell.size = LOGICAL_SIZE
	shell.pivot_offset = LOGICAL_SIZE * 0.5
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shell)

	wallpaper = TextureRect.new()
	wallpaper.name = "Wallpaper"
	wallpaper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(wallpaper)

	var branding := HBoxContainer.new()
	branding.position = Vector2(462.0, 300.0)
	branding.size = Vector2(356.0, 72.0)
	branding.alignment = BoxContainer.ALIGNMENT_CENTER
	branding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(branding)
	var logo := TextureRect.new()
	logo.name = "BrandLogo"
	logo.custom_minimum_size = Vector2(64.0, 64.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branding.add_child(logo)
	var title := Label.new()
	title.name = "BrandTitle"
	title.text = "ChocolateOS08"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#3a302d"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branding.add_child(title)

	icon_layer = Control.new()
	icon_layer.name = "DesktopIcons"
	icon_layer.position = Vector2.ZERO
	icon_layer.size = Vector2(LOGICAL_SIZE.x, LOGICAL_SIZE.y - TASKBAR_HEIGHT)
	icon_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	shell.add_child(icon_layer)

	window_layer = Control.new()
	window_layer.name = "Windows"
	window_layer.position = Vector2.ZERO
	window_layer.size = Vector2(LOGICAL_SIZE.x, LOGICAL_SIZE.y - TASKBAR_HEIGHT)
	# This full-screen node is only a container. If it accepts mouse input it
	# becomes the hit target above the desktop icons even when no window exists.
	# Individual application panels below it still use their own mouse filters.
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(window_layer)

	taskbar = Panel.new()
	taskbar.name = "Taskbar"
	taskbar.position = Vector2(0.0, LOGICAL_SIZE.y - TASKBAR_HEIGHT)
	taskbar.size = Vector2(LOGICAL_SIZE.x, TASKBAR_HEIGHT)
	taskbar.add_theme_stylebox_override("panel", _stylebox(Color("#e6e3dc"), Color("#a8a49d"), 1, 0))
	shell.add_child(taskbar)

	dock = HBoxContainer.new()
	dock.position = Vector2(12.0, 5.0)
	dock.size = Vector2(1050.0, 48.0)
	dock.add_theme_constant_override("separation", 6)
	taskbar.add_child(dock)

	clock_label = Label.new()
	clock_label.position = Vector2(1090.0, 5.0)
	clock_label.size = Vector2(174.0, 48.0)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_label.add_theme_font_size_override("font_size", 20)
	clock_label.add_theme_color_override("font_color", Color("#292929"))
	taskbar.add_child(clock_label)

	shutdown_overlay = ColorRect.new()
	shutdown_overlay.color = Color.BLACK
	shutdown_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shutdown_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	shutdown_overlay.visible = false
	shutdown_overlay.z_index = 1000
	shell.add_child(shutdown_overlay)
	shutdown_label = Label.new()
	shutdown_label.name = "ShutdownLabel"
	shutdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shutdown_label.text = "已关机"
	shutdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shutdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shutdown_label.add_theme_font_size_override("font_size", 42)
	shutdown_label.add_theme_color_override("font_color", Color.WHITE)
	shutdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shutdown_overlay.add_child(shutdown_label)


func open_for(target: ComputerTerminal, owner: GamePlayer, state: Dictionary) -> void:
	if not is_instance_valid(target) or not is_instance_valid(owner):
		return
	player = owner
	computer = target
	computer_state = state.duplicate(true)
	shutting_down = false
	_reset_icon_click_state()
	shutdown_overlay.visible = false
	heartbeat_elapsed = 0.0
	_apply_theme()
	_refresh_desktop()
	visible = true
	_rescale_shell()
	_use_system_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
	return visible and is_instance_valid(computer)


func close(request_release := true) -> void:
	if not visible:
		return
	var release_player := player
	var release_computer := computer
	visible = false
	shutting_down = false
	shutdown_overlay.visible = false
	_close_all_windows()
	_reset_icon_click_state()
	Input.set_custom_mouse_cursor(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	computer = null
	computer_state.clear()
	if request_release and is_instance_valid(release_player) and is_instance_valid(release_computer):
		release_player.request_computer_action(release_computer, "release")
	closed.emit()


func apply_computer_state(state: Dictionary) -> void:
	if not is_open():
		return
	if str(state.get("computer_id", "")) != computer.get_computer_id():
		return
	computer_state = state.duplicate(true)
	_refresh_desktop()
	if int(state.get("active_user_peer_id", 0)) != player.authority_peer_id:
		close(false)


func apply_action_result(result: Dictionary) -> void:
	if not is_open() or str(result.get("computer_id", "")) != computer.get_computer_id():
		return
	var action := str(result.get("action", ""))
	if action in ["install_app", "uninstall_app"]:
		_refresh_open_management_pages()
	if not bool(result.get("ok", false)) and action != "heartbeat":
		_show_notice(_reason_text(str(result.get("reason", "操作失败"))))


func _process(delta: float) -> void:
	if not is_open():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size != last_viewport_size:
		_rescale_shell()
	heartbeat_elapsed += delta
	if heartbeat_elapsed >= HEARTBEAT_SECONDS:
		heartbeat_elapsed = 0.0
		player.request_computer_action(computer, "heartbeat")
	time_elapsed += delta
	if time_elapsed >= 0.5:
		time_elapsed = 0.0
		_update_clock()


func _rescale_shell() -> void:
	last_viewport_size = get_viewport_rect().size
	var target := last_viewport_size * 0.72
	var scale_value := minf(target.x / LOGICAL_SIZE.x, target.y / LOGICAL_SIZE.y)
	var maximum := minf(last_viewport_size.x * 0.80 / LOGICAL_SIZE.x, last_viewport_size.y * 0.80 / LOGICAL_SIZE.y)
	scale_value = maxf(0.35, minf(scale_value, maximum))
	shell.scale = Vector2.ONE * scale_value
	shell.position = (last_viewport_size - LOGICAL_SIZE * scale_value) * 0.5


func _apply_theme() -> void:
	var os_id := str(computer_state.get("os_id", computer.os_id))
	var os_root := "res://assets/icons/ChocolateOS/%s" % os_id
	wallpaper.texture = load(os_root + "/wallpapers/desktop.png") as Texture2D
	var logo := shell.find_child("BrandLogo", true, false) as TextureRect
	if logo != null:
		logo.texture = load(os_root + "/system/logo.png") as Texture2D
	var title := shell.find_child("BrandTitle", true, false) as Label
	if title != null:
		title.text = "Chocolate%s" % os_id


func _use_system_cursor() -> void:
	# The computer UI uses the platform's normal cursor. Keep the generated
	# ChocolateOS cursor assets available for later optional themes, but do not
	# install them into the active input state.
	Input.set_custom_mouse_cursor(null)


func get_current_os_id() -> String:
	return str(computer_state.get("os_id", computer.os_id if is_instance_valid(computer) else "OS08"))


func _refresh_desktop() -> void:
	for child: Node in icon_layer.get_children():
		child.queue_free()
	icon_controls.clear()
	var installed := _installed_ids()
	var layout_value: Variant = computer_state.get("desktop_layout", {})
	var layout: Dictionary = layout_value as Dictionary if layout_value is Dictionary else {}
	for app_id: String in installed:
		var manifest := ChocolateOSCatalog.get_manifest(app_id)
		if manifest == null:
			continue
		var cell := ChocolateOSCatalog._as_grid_cell(layout.get(app_id, [0, 0]))
		_create_desktop_icon(manifest, cell)
	for app_id: Variant in app_windows.keys().duplicate():
		if not installed.has(str(app_id)):
			_close_app(str(app_id))
	_refresh_dock()


func _refresh_dock() -> void:
	if dock_refresh_queued:
		return
	dock_refresh_queued = true
	call_deferred("_refresh_dock_deferred")


func _refresh_dock_deferred() -> void:
	dock_refresh_queued = false
	if not is_instance_valid(dock):
		return
	for child: Node in dock.get_children():
		dock.remove_child(child)
		child.queue_free()
	var added := {}
	var pinned_ids: Array[String] = []
	var installed := _installed_ids()
	# Shutdown is a fixed system shortcut and must always occupy the leftmost
	# position in the taskbar, regardless of the installed-app array order.
	if installed.has("shutdown"):
		var shutdown_manifest := ChocolateOSCatalog.get_manifest("shutdown")
		if shutdown_manifest != null and shutdown_manifest.pinned_to_dock:
			pinned_ids.append("shutdown")
	for app_id: String in installed:
		if app_id == "shutdown":
			continue
		var manifest := ChocolateOSCatalog.get_manifest(app_id)
		if manifest != null and manifest.pinned_to_dock:
			pinned_ids.append(app_id)
	for app_id: String in pinned_ids:
		var manifest := ChocolateOSCatalog.get_manifest(app_id)
		if manifest != null:
			_create_dock_button(manifest)
			added[app_id] = true
	for app_id: Variant in app_windows.keys():
		var id := str(app_id)
		var manifest := ChocolateOSCatalog.get_manifest(id)
		if manifest != null and not added.has(id):
			_create_dock_button(manifest)


func _installed_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = computer_state.get("installed_app_ids", [])
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	return result


func _create_desktop_icon(manifest: ChocolateOSAppManifest, cell: Vector2i) -> void:
	var button := Button.new()
	button.name = "DesktopIcon_" + manifest.app_id
	button.position = _cell_position(cell)
	button.size = Vector2(78.0, 90.0)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = manifest.description
	button.gui_input.connect(_on_desktop_icon_input.bind(manifest.app_id))
	button.pressed.connect(_on_desktop_icon_pressed.bind(manifest.app_id))
	icon_layer.add_child(button)
	var image := TextureRect.new()
	image.position = Vector2(11.0, 2.0)
	image.size = Vector2(56.0, 56.0)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = load(manifest.icon_path_for_os(str(computer_state.get("os_id", "OS08")))) as Texture2D
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(image)
	var label := Label.new()
	label.position = Vector2(0.0, 60.0)
	label.size = Vector2(78.0, 28.0)
	label.text = manifest.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("#202020"))
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	icon_controls[manifest.app_id] = button


func _create_dock_button(manifest: ChocolateOSAppManifest) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(48.0, 48.0)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = manifest.display_name
	button.icon = load(manifest.icon_path_for_os(str(computer_state.get("os_id", "OS08")))) as Texture2D
	button.expand_icon = true
	button.pressed.connect(_on_dock_pressed.bind(manifest.app_id))
	dock.add_child(button)


func _on_desktop_icon_input(event: InputEvent, app_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_app_id = app_id
			suppressed_icon_activation_app_id = ""
			# The desktop shell is scaled. Use shell-local coordinates so dragging
			# remains correct at every window resolution.
			drag_start_mouse = shell.get_local_mouse_position()
			var icon := icon_controls.get(app_id, null) as Control
			drag_start_position = icon.position if icon != null else Vector2.ZERO
			drag_moved = false
		else:
			if drag_app_id == app_id:
				if drag_moved:
					_reset_icon_click_state()
					suppressed_icon_activation_app_id = app_id
					var icon := icon_controls.get(app_id, null) as Control
					var cell := _position_to_cell(icon.position if icon != null else drag_start_position)
					player.request_computer_action(computer, "move_app", {"app_id": app_id, "cell": [cell.x, cell.y]})
				drag_app_id = ""
	elif event is InputEventMouseMotion and drag_app_id == app_id:
		var offset := shell.get_local_mouse_position() - drag_start_mouse
		if offset.length() > 4.0:
			drag_moved = true
			var icon := icon_controls.get(app_id, null) as Control
			if icon != null:
				icon.position = drag_start_position + offset


func _on_desktop_icon_pressed(app_id: String) -> void:
	# Button.pressed is the reliable activation signal for real mouse clicks.
	# Defer one frame so the gui_input release handler can mark a drag before
	# deciding whether this was a click.
	call_deferred("_handle_desktop_icon_pressed", app_id)


func _handle_desktop_icon_pressed(app_id: String) -> void:
	if not is_open():
		return
	if suppressed_icon_activation_app_id == app_id:
		suppressed_icon_activation_app_id = ""
		return
	if app_id == "shutdown":
		_reset_icon_click_state()
		_begin_shutdown()
		return
	if _register_icon_click(app_id):
		_open_app(app_id)


func _register_icon_click(app_id: String) -> bool:
	var now := Time.get_ticks_msec()
	var is_double_click := last_icon_click_app_id == app_id \
			and now - last_icon_click_msec <= DESKTOP_DOUBLE_CLICK_INTERVAL_MSEC
	last_icon_click_app_id = app_id
	last_icon_click_msec = now
	if is_double_click:
		_reset_icon_click_state()
	return is_double_click


func _reset_icon_click_state() -> void:
	last_icon_click_app_id = ""
	last_icon_click_msec = 0
	suppressed_icon_activation_app_id = ""


func _on_dock_pressed(app_id: String) -> void:
	var existing := app_windows.get(app_id, null) as Control
	if existing != null and is_instance_valid(existing):
		if existing.visible:
			existing.visible = false
		else:
			existing.visible = true
			if app_instances.get(app_id, null) is ChocolateOSAppBase:
				(app_instances[app_id] as ChocolateOSAppBase).on_resume()
			_bring_window_front(existing)
		return
	_open_app(app_id)


func _open_app(app_id: String) -> void:
	if not _installed_ids().has(app_id):
		return
	if app_id == "shutdown":
		_begin_shutdown()
		return
	var existing := app_windows.get(app_id, null) as Control
	if existing != null and is_instance_valid(existing):
		existing.visible = true
		_bring_window_front(existing)
		return
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null:
		return
	var panel := _create_app_window(manifest)
	app_windows[app_id] = panel
	_refresh_dock()
	var content := panel.get_node("Content") as Control
	if manifest.entry_scene != null:
		var instance := manifest.entry_scene.instantiate()
		if instance is Control:
			var app_control := instance as Control
			app_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			content.add_child(app_control)
			app_instances[app_id] = app_control
			if app_control is ChocolateOSAppBase:
				(app_control as ChocolateOSAppBase).on_launch(ChocolateOSAppContext.new(self, app_id))
			return
	match manifest.entry_kind:
		"browser":
			_build_browser(content, app_id)
		"settings":
			_build_settings(content)
		"my_computer":
			_build_my_computer(content)
		_:
			_build_placeholder(content, manifest)


func _create_app_window(manifest: ChocolateOSAppManifest) -> Panel:
	var panel := Panel.new()
	panel.name = "Window_" + manifest.app_id
	panel.position = Vector2(260.0 + app_windows.size() * 24.0, 120.0 + app_windows.size() * 20.0)
	panel.size = Vector2(760.0, 470.0)
	panel.add_theme_stylebox_override("panel", _stylebox(Color("#dedbd4"), Color("#454545"), 2, 2))
	panel.set_meta("normal_position", panel.position)
	panel.set_meta("normal_size", panel.size)
	panel.set_meta("maximized", false)
	panel.gui_input.connect(_on_window_clicked.bind(panel))
	window_layer.add_child(panel)
	_bring_window_front(panel)

	var header := ColorRect.new()
	header.name = "Header"
	header.position = Vector2(2.0, 2.0)
	header.size = Vector2(panel.size.x - 4.0, 34.0)
	header.color = Color("#747d88")
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_window_header_input.bind(panel))
	panel.add_child(header)
	var title := Label.new()
	title.position = Vector2(12.0, 0.0)
	title.size = Vector2(300.0, 34.0)
	title.text = manifest.display_name
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	var controls := HBoxContainer.new()
	controls.position = Vector2((header.size.x - 112.0) * 0.5, 3.0)
	controls.size = Vector2(112.0, 28.0)
	controls.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(controls)
	for spec: Array in [["-", "minimize"], ["+", "maximize"], ["x", "close"]]:
		var button := Button.new()
		button.text = str(spec[0])
		button.custom_minimum_size = Vector2(34.0, 28.0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_window_control.bind(manifest.app_id, str(spec[1])))
		controls.add_child(button)

	var content := Control.new()
	content.name = "Content"
	content.position = Vector2(4.0, 38.0)
	content.size = Vector2(panel.size.x - 8.0, panel.size.y - 42.0)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4.0
	content.offset_top = 38.0
	content.offset_right = -4.0
	content.offset_bottom = -4.0
	content.clip_contents = true
	panel.add_child(content)
	_layout_window(panel)
	return panel


var window_drag_panel: Control
var window_drag_mouse := Vector2.ZERO
var window_drag_origin := Vector2.ZERO


func _on_window_header_input(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			window_drag_panel = panel
			window_drag_mouse = shell.get_local_mouse_position()
			window_drag_origin = panel.position
			_bring_window_front(panel)
		else:
			window_drag_panel = null
	elif event is InputEventMouseMotion and window_drag_panel == panel and not bool(panel.get_meta("maximized", false)):
		var offset := shell.get_local_mouse_position() - window_drag_mouse
		panel.position = Vector2(
			clampf(window_drag_origin.x + offset.x, 0.0, LOGICAL_SIZE.x - 120.0),
			clampf(window_drag_origin.y + offset.y, 0.0, LOGICAL_SIZE.y - TASKBAR_HEIGHT - 50.0)
		)


func _on_window_clicked(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.pressed:
		_bring_window_front(panel)


func _bring_window_front(panel: Control) -> void:
	for app_id: Variant in app_windows.keys():
		var other := app_windows[app_id] as Control
		if other != panel and app_instances.get(app_id, null) is ChocolateOSAppBase:
			(app_instances[app_id] as ChocolateOSAppBase).on_blur()
	next_window_z += 1
	panel.z_index = next_window_z
	for app_id: Variant in app_windows.keys():
		if app_windows[app_id] == panel and app_instances.get(app_id, null) is ChocolateOSAppBase:
			(app_instances[app_id] as ChocolateOSAppBase).on_focus()
			break


func _on_window_control(app_id: String, action: String) -> void:
	var panel := app_windows.get(app_id, null) as Control
	if panel == null or not is_instance_valid(panel):
		return
	match action:
		"minimize":
			panel.visible = false
			if app_instances.get(app_id, null) is ChocolateOSAppBase:
				(app_instances[app_id] as ChocolateOSAppBase).on_suspend()
		"maximize":
			if bool(panel.get_meta("maximized", false)):
				panel.position = panel.get_meta("normal_position", Vector2(260.0, 120.0)) as Vector2
				panel.size = panel.get_meta("normal_size", Vector2(760.0, 470.0)) as Vector2
				panel.set_meta("maximized", false)
			else:
				panel.set_meta("normal_position", panel.position)
				panel.set_meta("normal_size", panel.size)
				panel.position = Vector2.ZERO
				panel.size = window_layer.size
				panel.set_meta("maximized", true)
			_layout_window(panel)
		"close":
			_close_app(app_id)


func _close_app(app_id: String) -> void:
	var panel := app_windows.get(app_id, null) as Control
	app_windows.erase(app_id)
	browser_sessions.erase(app_id)
	var instance: Variant = app_instances.get(app_id, null)
	app_instances.erase(app_id)
	if instance is ChocolateOSAppBase:
		(instance as ChocolateOSAppBase).on_close()
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	if is_instance_valid(dock):
		_refresh_dock()


func _layout_window(panel: Control) -> void:
	var header := panel.get_node_or_null("Header") as Control
	if header == null:
		return
	header.size.x = panel.size.x - 4.0
	var controls := header.get_child(1) as Control if header.get_child_count() > 1 else null
	if controls != null:
		controls.position.x = (header.size.x - controls.size.x) * 0.5


func _close_all_windows() -> void:
	for panel_value: Variant in app_windows.values():
		var panel := panel_value as Control
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	app_windows.clear()
	browser_sessions.clear()
	for instance: Variant in app_instances.values():
		if instance is ChocolateOSAppBase:
			(instance as ChocolateOSAppBase).on_close()
	app_instances.clear()
	_refresh_dock()


func _build_placeholder(content: Control, manifest: ChocolateOSAppManifest) -> void:
	var background := ColorRect.new()
	background.color = Color("#101010")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(background)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "%s\n\n功能将在后续版本中开放" % manifest.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#d8d8d8"))
	label.add_theme_font_size_override("font_size", 22)
	background.add_child(label)


func _build_browser(content: Control, app_id: String) -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	content.add_child(root)
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 38.0
	root.add_child(toolbar)
	for spec: Array in [["<", "back"], [">", "forward"], ["刷新", "reload"]]:
		var button := Button.new()
		button.text = str(spec[0])
		button.custom_minimum_size.x = 54.0
		button.pressed.connect(_on_browser_command.bind(app_id, str(spec[1])))
		toolbar.add_child(button)
	var address := LineEdit.new()
	address.name = "Address"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.placeholder_text = "输入地址，例如 www.osapp.store"
	address.text_submitted.connect(_browser_navigate.bind(app_id, true))
	toolbar.add_child(address)
	var go := Button.new()
	go.text = "进入"
	go.pressed.connect(_on_browser_go.bind(app_id))
	toolbar.add_child(go)
	var page_title := Label.new()
	page_title.name = "PageTitle"
	page_title.custom_minimum_size.y = 26.0
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(page_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var page := VBoxContainer.new()
	page.name = "Page"
	page.custom_minimum_size.x = 720.0
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	browser_sessions[app_id] = {
		"history": [],
		"index": -1,
		"address": address,
		"title": page_title,
		"page": page,
	}
	_browser_navigate(ChocolateOSWebRegistry.DEFAULT_URL, app_id, true)


func _on_browser_command(app_id: String, command: String) -> void:
	var session_value: Variant = browser_sessions.get(app_id, {})
	if not session_value is Dictionary:
		return
	var session := session_value as Dictionary
	var history: Array = session.get("history", []) as Array
	var index := int(session.get("index", -1))
	match command:
		"back": index = maxi(0, index - 1)
		"forward": index = mini(history.size() - 1, index + 1)
		"reload":
			if index >= 0 and index < history.size():
				_render_browser_url(app_id, str(history[index]))
			return
	if index >= 0 and index < history.size():
		session["index"] = index
		browser_sessions[app_id] = session
		_render_browser_url(app_id, str(history[index]))


func _on_browser_go(app_id: String) -> void:
	var session: Dictionary = browser_sessions.get(app_id, {}) as Dictionary
	var address := session.get("address", null) as LineEdit
	if address != null:
		_browser_navigate(address.text, app_id, true)


func _browser_navigate(url: String, app_id: String, add_history: bool) -> void:
	var session_value: Variant = browser_sessions.get(app_id, {})
	if not session_value is Dictionary:
		return
	var session := session_value as Dictionary
	if add_history:
		var history: Array = session.get("history", []) as Array
		var index := int(session.get("index", -1))
		if index + 1 < history.size():
			history = history.slice(0, index + 1)
		history.append(url)
		session["history"] = history
		session["index"] = history.size() - 1
		browser_sessions[app_id] = session
	_render_browser_url(app_id, url)


func _render_browser_url(app_id: String, url: String) -> void:
	var session: Dictionary = browser_sessions.get(app_id, {}) as Dictionary
	var address := session.get("address", null) as LineEdit
	var title := session.get("title", null) as Label
	var page := session.get("page", null) as VBoxContainer
	if page == null:
		return
	for child: Node in page.get_children():
		child.queue_free()
	var route := ChocolateOSWebRegistry.resolve(url)
	if address != null:
		address.text = str(route.get("display_url", url))
	if title != null:
		title.text = str(route.get("title", "Browser"))
	match str(route.get("page_kind", "404")):
		"store": _render_store_page(page)
		"store_detail": _render_store_detail(page, str(route.get("app_id", "")))
		"invalid": _render_browser_error(page, "地址无效", "请输入类似 www.osapp.store 的有效地址。")
		_: _render_browser_error(page, "404\n找不到网页", "无法找到 %s\n请检查地址是否正确。" % str(route.get("display_url", url)))


func _render_store_page(page: VBoxContainer) -> void:
	_add_page_heading(page, "Chocolate 应用库", "当前系统：Chocolate%s · 所有应用免费" % str(computer_state.get("os_id", "OS08")))
	for app_id: String in ChocolateOSCatalog.get_store_app_ids(str(computer_state.get("os_id", "OS08"))):
		var manifest := ChocolateOSCatalog.get_manifest(app_id)
		if manifest != null:
			_add_store_app_row(page, manifest)


func _render_store_detail(page: VBoxContainer, app_id: String) -> void:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null or manifest.system_app or not manifest.app_store_distribution:
		_render_browser_error(page, "404\n找不到应用", "应用库中没有这个应用。")
		return
	_add_page_heading(page, manifest.display_name, "版本 %s" % manifest.version)
	var description := Label.new()
	description.text = manifest.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 80.0
	page.add_child(description)
	_add_store_install_button(page, manifest)


func _add_store_app_row(page: VBoxContainer, manifest: ChocolateOSAppManifest) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 82.0
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(manifest.icon_path_for_os(str(computer_state.get("os_id", "OS08")))) as Texture2D
	row.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = "%s  v%s" % [manifest.display_name, manifest.version]
	name_label.add_theme_font_size_override("font_size", 20)
	text_box.add_child(name_label)
	var description := Label.new()
	description.text = manifest.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(description)
	var detail := Button.new()
	detail.text = "详情"
	detail.custom_minimum_size = Vector2(66.0, 38.0)
	detail.pressed.connect(_browser_navigate.bind("www.osapp.store/apps/%s" % manifest.app_id, "browser", true))
	row.add_child(detail)
	_add_store_install_button(row, manifest)


func _add_store_install_button(parent: Control, manifest: ChocolateOSAppManifest) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(100.0, 38.0)
	if not manifest.supports_os(str(computer_state.get("os_id", "OS08"))):
		button.text = "不兼容"
		button.disabled = true
	elif _installed_ids().has(manifest.app_id):
		button.text = "已安装"
		button.disabled = true
	else:
		button.text = "免费安装"
		button.pressed.connect(_request_store_install.bind(manifest.program_id, button))
	parent.add_child(button)


func _request_store_install(program_id: String, button: Button) -> void:
	button.disabled = true
	button.text = "安装中…"
	player.request_computer_action(computer, "install_app", {"program_id": program_id, "source": "app_store"})


func _render_browser_error(page: VBoxContainer, heading: String, detail: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 80.0
	page.add_child(spacer)
	var title := Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	page.add_child(title)
	var label := Label.new()
	label.text = detail
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)


func _add_page_heading(page: VBoxContainer, heading: String, subtitle: String) -> void:
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 28)
	page.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_color_override("font_color", Color("#555555"))
	page.add_child(sub)
	page.add_child(HSeparator.new())


func _build_settings(content: Control) -> void:
	var root := VBoxContainer.new()
	root.name = "SettingsRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 18.0
	root.offset_top = 14.0
	root.offset_right = -18.0
	root.offset_bottom = -14.0
	root.add_theme_constant_override("separation", 10)
	content.add_child(root)
	_refresh_settings_root(root)


func _refresh_settings_root(root: VBoxContainer) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	_add_page_heading(root, "应用程序", "管理这台电脑上安装的普通应用")
	for app_id: String in _installed_ids():
		var manifest := ChocolateOSCatalog.get_manifest(app_id)
		if manifest == null or not manifest.removable or manifest.system_app:
			continue
		var row := HBoxContainer.new()
		root.add_child(row)
		var label := Label.new()
		label.text = "%s  v%s" % [manifest.display_name, manifest.version]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var uninstall := Button.new()
		uninstall.text = "卸载"
		uninstall.pressed.connect(_request_uninstall.bind(app_id))
		row.add_child(uninstall)


func _request_uninstall(app_id: String) -> void:
	player.request_computer_action(computer, "uninstall_app", {"app_id": app_id})


func _build_my_computer(content: Control) -> void:
	var root := VBoxContainer.new()
	root.name = "MyComputerRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 18.0
	root.offset_top = 14.0
	root.offset_right = -18.0
	root.offset_bottom = -14.0
	content.add_child(root)
	_refresh_my_computer_root(root)


func _refresh_my_computer_root(root: VBoxContainer) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	_add_page_heading(root, "My Computer", "背包中的程序硬盘")
	var found := false
	if is_instance_valid(player):
		for item: Dictionary in player.backpack_items:
			var item_id := str(item.get("item_id", item.get("ingredient_id", "")))
			if item_id != "hard_drive":
				continue
			found = true
			var program_id := str(item.get("program_id", ""))
			var manifest := ChocolateOSCatalog.get_manifest_for_program(program_id)
			var row := HBoxContainer.new()
			root.add_child(row)
			var label := Label.new()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text = "硬盘（空白）" if program_id.is_empty() else "硬盘（%s）" % (manifest.display_name if manifest != null else "未知程序：%s" % program_id)
			row.add_child(label)
			if manifest != null and not _installed_ids().has(manifest.app_id):
				var install := Button.new()
				install.text = "安装"
				install.pressed.connect(_request_drive_install.bind(program_id, install))
				row.add_child(install)
	if not found:
		var empty := Label.new()
		empty.text = "背包中没有程序硬盘。"
		empty.add_theme_color_override("font_color", Color("#666666"))
		root.add_child(empty)


func _request_drive_install(program_id: String, button: Button) -> void:
	button.disabled = true
	button.text = "安装中…"
	player.request_computer_action(computer, "install_app", {"program_id": program_id, "source": "hard_drive"})


func _refresh_open_management_pages() -> void:
	for app_id: Variant in app_windows.keys():
		var panel := app_windows[app_id] as Control
		if panel == null or not is_instance_valid(panel):
			continue
		if str(app_id) == "browser" and browser_sessions.has("browser"):
			var session: Dictionary = browser_sessions["browser"] as Dictionary
			var history: Array = session.get("history", []) as Array
			var index := int(session.get("index", -1))
			if index >= 0 and index < history.size():
				_render_browser_url("browser", str(history[index]))
		elif str(app_id) == "settings":
			var root := panel.get_node_or_null("Content/SettingsRoot") as VBoxContainer
			if root != null:
				_refresh_settings_root(root)
		elif str(app_id) == "my_computer":
			var root := panel.get_node_or_null("Content/MyComputerRoot") as VBoxContainer
			if root != null:
				_refresh_my_computer_root(root)


func _begin_shutdown() -> void:
	if shutting_down or not is_open():
		return
	# Shutdown is a visual desktop action for now. Keep the terminal lock and
	# desktop instance alive so only ESC can close the computer interaction.
	shutting_down = true
	shutdown_overlay.visible = true


func _update_clock() -> void:
	var hour := 0.0
	var system := get_tree().get_first_node_in_group("day_night_systems")
	if system != null and system.has_method("get_current_hour"):
		hour = float(system.call("get_current_hour"))
	var total_minutes := posmod(roundi(hour * 60.0), 24 * 60)
	clock_label.text = "%02d:%02d" % [int(total_minutes / 60), total_minutes % 60]


func _show_notice(text: String) -> void:
	if is_instance_valid(player):
		player.show_gameplay_notice(text)


func query_app_service(app_id: String, service: String, _request: Dictionary) -> Dictionary:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null or not manifest.permissions.has(service):
		return {"ok": false, "reason": "permission_denied"}
	match service:
		"world_time.read":
			var system := get_tree().get_first_node_in_group("day_night_systems")
			var hour := float(system.call("get_current_hour")) if system != null and system.has_method("get_current_hour") else 0.0
			return {"ok": true, "hour": hour}
		"weather.read":
			var weather_system := get_tree().get_first_node_in_group("weather_systems")
			if weather_system != null and weather_system.has_method("get_weather_app_state"):
				return {"ok": true, "state": weather_system.call("get_weather_app_state")}
			return {"ok": true, "state": {}}
		"farm.read":
			var team := str(player.team) if is_instance_valid(player) else ""
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_farm_info_state"):
				return GameAuthority.get_farm_info_state(team)
			return {"ok": true, "ready": false, "team": team}
		"network.read":
			return {"ok": true, "connected": true}
	return {"ok": false, "reason": "unknown_service"}


func command_app_service(app_id: String, service: String, _action: String, payload: Dictionary, expected_revision: int) -> bool:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null or not manifest.permissions.has(service):
		return false
	if service == "app_storage.write" and is_open():
		player.request_computer_action(computer, "write_app_data", {
			"app_id": app_id,
			"payload": payload,
			"expected_revision": expected_revision,
		})
		return true
	return false


func read_app_storage(app_id: String) -> Dictionary:
	var all_data_value: Variant = computer_state.get("app_data", {})
	if not all_data_value is Dictionary:
		return {}
	var value: Variant = (all_data_value as Dictionary).get(app_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func subscribe_app_service(app_id: String, event_name: String, _context: ChocolateOSAppContext) -> bool:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null:
		return false
	var permission := event_name.trim_suffix(".changed") + ".read"
	return manifest.permissions.has(permission) or manifest.permissions.has(event_name)


func _reason_text(reason: String) -> String:
	match reason:
		"computer_in_use": return "其他玩家正在使用这台电脑"
		"computer_out_of_range": return "距离电脑太远"
		"already_installed": return "应用已经安装"
		"incompatible_os": return "应用与当前系统不兼容"
		"missing_dependency": return "缺少应用依赖"
		"app_not_removable": return "系统应用不能卸载"
		"program_drive_not_found": return "背包中没有对应的程序硬盘"
		"required_by_app": return "其他应用仍依赖这个程序"
		_: return "电脑操作失败：%s" % reason


func _cell_position(cell: Vector2i) -> Vector2:
	return ICON_ORIGIN + Vector2(cell.x * ICON_CELL_SIZE.x, cell.y * ICON_CELL_SIZE.y)


func _position_to_cell(position_value: Vector2) -> Vector2i:
	var relative := position_value - ICON_ORIGIN
	return Vector2i(
		clampi(roundi(relative.x / ICON_CELL_SIZE.x), 0, ComputerTerminal.GRID_COLUMNS - 1),
		clampi(roundi(relative.y / ICON_CELL_SIZE.y), 0, ComputerTerminal.GRID_ROWS - 1)
	)


func _stylebox(color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box
