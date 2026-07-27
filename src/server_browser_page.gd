extends Control
class_name ServerBrowserPage

signal join_server_requested(address: String, port: int)
signal back_requested

const OFFICIAL_SERVERS_PATH := "res://data/official_servers.json"
const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_SELECTED := Color("#54D6A2")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_WARN := Color("#FFB36B")

var official_servers: Array[Dictionary] = []
var online_servers: Array[Dictionary] = []
var selected_server_index := -1
var pending_queries := 0

var status_label: Label
var list_box: VBoxContainer
var manual_ip_edit: LineEdit
var manual_port_edit: SpinBox
var join_button: Button
var refresh_button: Button


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()
	_load_official_servers()
	refresh_servers()


func refresh_servers() -> void:
	online_servers.clear()
	selected_server_index = -1
	_clear_server_rows()
	_update_join_button()
	if official_servers.is_empty():
		status_label.text = "没有配置官方服务器：%s" % OFFICIAL_SERVERS_PATH
		return
	pending_queries = official_servers.size()
	status_label.text = "正在查询官方服务器..."
	refresh_button.disabled = true
	for server: Dictionary in official_servers:
		_query_one_server(server)


func _load_official_servers() -> void:
	official_servers.clear()
	if not FileAccess.file_exists(OFFICIAL_SERVERS_PATH):
		push_warning("official_servers.json missing: " + OFFICIAL_SERVERS_PATH)
		return
	var file := FileAccess.open(OFFICIAL_SERVERS_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("Invalid official_servers.json")
		return
	var source: Variant = json.data.get("servers", [])
	if not source is Array:
		return
	for item: Variant in source:
		if item is Dictionary:
			var entry := (item as Dictionary).duplicate(true)
			entry["address"] = str(entry.get("address", "")).strip_edges()
			entry["game_port"] = int(entry.get("game_port", entry.get("port", 2002)))
			entry["query_port"] = int(entry.get("query_port", 2003))
			if not str(entry["address"]).is_empty():
				official_servers.append(entry)


func _query_one_server(server: Dictionary) -> void:
	var request := HTTPRequest.new()
	request.timeout = 2.0
	add_child(request)
	var started_msec := Time.get_ticks_msec()
	request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			_on_query_completed(request, server, started_msec, result, response_code, body)
	)
	var url := "http://%s:%d/status" % [
		str(server.get("address", "")),
		int(server.get("query_port", 2003)),
	]
	var err := request.request(url)
	if err != OK:
		print("FAILED!")
		_on_query_completed(request, server, started_msec, HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())


func _on_query_completed(
	request: HTTPRequest,
	server: Dictionary,
	started_msec: int,
	result: int,
	response_code: int,
	body: PackedByteArray
) -> void:
	if is_instance_valid(request):
		request.queue_free()
	pending_queries = maxi(0, pending_queries - 1)

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json := JSON.new()
		var text := body.get_string_from_utf8()
		if json.parse(text) == OK and json.data is Dictionary:
			var info := (json.data as Dictionary).duplicate(true)
			var merged := server.duplicate(true)
			for key in info.keys():
				merged[key] = info[key]
			merged["address"] = str(server.get("address", ""))
			merged["game_port"] = int(info.get("game_port", server.get("game_port", 2002)))
			merged["query_port"] = int(info.get("query_port", server.get("query_port", 2003)))
			merged["ping_ms"] = Time.get_ticks_msec() - started_msec
			online_servers.append(merged)

	if pending_queries <= 0:
		refresh_button.disabled = false
		_rebuild_server_list()
		status_label.text = "找到 %d 个可连接官方服务器。" % online_servers.size()


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

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(1260, 820)
	root.add_theme_constant_override("separation", 18)
	center.add_child(root)

	var title := Label.new()
	title.text = "官方战局服务器"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(status_label)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	var back_button := _make_action_button("返回")
	back_button.pressed.connect(func(): back_requested.emit())
	footer.add_child(back_button)

	refresh_button = _make_action_button("刷新")
	refresh_button.pressed.connect(refresh_servers)
	footer.add_child(refresh_button)

	manual_ip_edit = LineEdit.new()
	manual_ip_edit.placeholder_text = "手动填写 IP"
	manual_ip_edit.text = "127.0.0.1"
	manual_ip_edit.custom_minimum_size = Vector2(320, 58)
	manual_ip_edit.add_theme_font_size_override("font_size", 24)
	footer.add_child(manual_ip_edit)

	manual_port_edit = SpinBox.new()
	manual_port_edit.min_value = 1
	manual_port_edit.max_value = 65535
	manual_port_edit.value = 2002
	manual_port_edit.custom_minimum_size = Vector2(150, 58)
	manual_port_edit.add_theme_font_size_override("font_size", 24)
	footer.add_child(manual_port_edit)

	join_button = _make_action_button("加入服务器")
	join_button.pressed.connect(_join_selected_or_manual)
	footer.add_child(join_button)


func _clear_server_rows() -> void:
	if list_box == null:
		return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()


func _rebuild_server_list() -> void:
	_clear_server_rows()
	if online_servers.is_empty():
		var empty := Label.new()
		empty.text = "没有查询到可连接的官方服务器。可以在下方手动输入 IP 和端口。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 26)
		empty.add_theme_color_override("font_color", COLOR_WARN)
		empty.custom_minimum_size.y = 120
		list_box.add_child(empty)
		return
	for index in range(online_servers.size()):
		list_box.add_child(_make_server_row(index, online_servers[index]))
	_update_join_button()


func _make_server_row(index: int, server: Dictionary) -> Control:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 76)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override(
		"normal",
		_style_box(COLOR_SELECTED if index == selected_server_index else COLOR_PANEL_2, 18)
	)
	button.add_theme_stylebox_override("hover", _style_box(Color("#314766"), 18))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_SELECTED, 18))
	button.text = _server_row_text(server)
	button.pressed.connect(_select_server.bind(index))
	button.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mouse_event := event as InputEventMouseButton
				if mouse_event.double_click and mouse_event.button_index == MOUSE_BUTTON_LEFT:
					_select_server(index)
					_join_selected_or_manual()
	)
	return button


func _server_row_text(server: Dictionary) -> String:
	var state := str(server.get("state", ""))
	var state_text := "等待中" if state == "WAITING_PLAYERS" else "游戏中" if state == "IN_GAME" else state
	return "服务器：%s     地图：%s     人数：%s/%s     模式：%s     延迟：%d ms     状态：%s" % [
		str(server.get("server_name", server.get("name", "Unknown Server"))),
		str(server.get("map_name", "")),
		str(int(server.get("current_players", 0))),
		str(int(server.get("max_players", 0))),
		str(server.get("game_mode", "")),
		int(server.get("ping_ms", 0)),
		state_text
	]


func _select_server(index: int) -> void:
	selected_server_index = index
	var server := online_servers[index]
	manual_ip_edit.text = str(server.get("address", ""))
	manual_port_edit.value = int(server.get("game_port", 2002))
	_rebuild_server_list()


func _join_selected_or_manual() -> void:
	var address := manual_ip_edit.text.strip_edges()
	var port := int(manual_port_edit.value)
	if address.is_empty():
		status_label.text = "请输入服务器 IP。"
		return
	join_server_requested.emit(address, port)


func _update_join_button() -> void:
	if join_button != null:
		join_button.disabled = false


func _make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170, 58)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 18))
	button.add_theme_stylebox_override("hover", _style_box(Color("#314766"), 18))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_SELECTED, 18))
	return button


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
