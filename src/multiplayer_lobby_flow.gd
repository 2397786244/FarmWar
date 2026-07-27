extends Control
class_name MultiplayerLobbyFlow

signal connect_requested(address: String, port: int)
signal loadout_ready_submitted(selection: Dictionary)
signal back_requested

const LOADOUT_SCENE := preload("res://ui/MultiplayerLoadoutSelect.tscn")

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_ACCENT := Color("#54D6A2")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")

@export var auto_mock_connect := false

var connection_panel: PanelContainer
var loadout_holder: Control
var address_edit: LineEdit
var port_edit: SpinBox
var status_label: Label
var loadout_ui: Control
var connect_button: Button
var disconnect_button: Button


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()
	_connect_network_signals()
	set_connected(false)


func set_connected(connected: bool) -> void:
	connection_panel.visible = not connected
	loadout_holder.visible = connected
	if connected:
		status_label.text = "已连接服务器，进入选人准备。"
		loadout_ui.reset_for_lobby()
	else:
		status_label.text = "输入服务器地址，连接成功后进入选人和装备准备界面。"
	_update_connection_buttons()


func set_connection_status(text: String) -> void:
	status_label.text = text


func connect_to_server(address: String, port: int) -> void:
	address_edit.text = address
	port_edit.value = port
	_on_connect_pressed()


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 54)
	root.add_theme_constant_override("margin_top", 38)
	root.add_theme_constant_override("margin_right", 54)
	root.add_theme_constant_override("margin_bottom", 38)
	add_child(root)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	root.add_child(stack)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	stack.add_child(status_label)

	connection_panel = PanelContainer.new()
	connection_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	connection_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 26))
	stack.add_child(connection_panel)

	var center := CenterContainer.new()
	connection_panel.add_child(center)

	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(720, 0)
	form.add_theme_constant_override("separation", 20)
	center.add_child(form)

	var title := Label.new()
	title.text = "多人游戏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	form.add_child(title)

	var hint := Label.new()
	hint.text = "连接服务器后选择角色和装备；队伍会由服务器自动分配。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 26)
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	form.add_child(hint)

	address_edit = LineEdit.new()
	address_edit.text = "127.0.0.1"
	address_edit.placeholder_text = "服务器地址"
	address_edit.custom_minimum_size = Vector2(0, 58)
	address_edit.add_theme_font_size_override("font_size", 24)
	form.add_child(address_edit)

	port_edit = SpinBox.new()
	port_edit.min_value = 1
	port_edit.max_value = 65535
	port_edit.value = 8910
	port_edit.custom_minimum_size = Vector2(0, 58)
	port_edit.add_theme_font_size_override("font_size", 24)
	form.add_child(port_edit)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 14)
	form.add_child(button_row)

	var back_button := _make_action_button("返回")
	back_button.pressed.connect(_on_back_pressed)
	button_row.add_child(back_button)

	var connect_button := _make_action_button("连接服务器")
	self.connect_button = connect_button
	connect_button.pressed.connect(_on_connect_pressed)
	button_row.add_child(connect_button)

	disconnect_button = _make_action_button("断开连接")
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	button_row.add_child(disconnect_button)

	loadout_holder = Control.new()
	loadout_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(loadout_holder)

	loadout_ui = LOADOUT_SCENE.instantiate() as Control
	loadout_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_ui.ready_submitted.connect(_on_loadout_ready_submitted)
	loadout_ui.back_requested.connect(_on_loadout_back_requested)
	loadout_holder.add_child(loadout_ui)


func _on_connect_pressed() -> void:
	var address := address_edit.text.strip_edges()
	var port := int(port_edit.value)
	status_label.text = "正在连接 %s:%d ..." % [address, port]
	connect_requested.emit(address, port)
	var started := MultiplayerNetwork.connect_to_game_server(address, port)
	_update_connection_buttons()
	if auto_mock_connect and not started:
		set_connected(true)


func _on_back_pressed() -> void:
	MultiplayerNetwork.disconnect_from_game_server()
	back_requested.emit()


func _on_loadout_back_requested() -> void:
	MultiplayerNetwork.disconnect_from_game_server()
	set_connected(false)


func _on_loadout_ready_submitted(selection: Dictionary) -> void:
	status_label.text = "已提交角色和装备，等待服务器分配队伍..."
	MultiplayerNetwork.submit_player_setup(selection)


func _on_disconnect_pressed() -> void:
	MultiplayerNetwork.disconnect_from_game_server()
	set_connected(false)
	status_label.text = "已断开服务器连接。"
	_update_connection_buttons()


func _connect_network_signals() -> void:
	if not MultiplayerNetwork.connection_started.is_connected(_on_network_connection_started):
		MultiplayerNetwork.connection_started.connect(_on_network_connection_started)
	if not MultiplayerNetwork.connection_succeeded.is_connected(_on_network_connection_succeeded):
		MultiplayerNetwork.connection_succeeded.connect(_on_network_connection_succeeded)
	if not MultiplayerNetwork.connection_failed.is_connected(_on_network_connection_failed):
		MultiplayerNetwork.connection_failed.connect(_on_network_connection_failed)
	if not MultiplayerNetwork.disconnected.is_connected(_on_network_disconnected):
		MultiplayerNetwork.disconnected.connect(_on_network_disconnected)
	if not MultiplayerNetwork.player_setup_confirmed.is_connected(_on_player_setup_confirmed):
		MultiplayerNetwork.player_setup_confirmed.connect(_on_player_setup_confirmed)
	if not MultiplayerNetwork.player_setup_rejected.is_connected(_on_player_setup_rejected):
		MultiplayerNetwork.player_setup_rejected.connect(_on_player_setup_rejected)


func _on_network_connection_started(address: String, port: int) -> void:
	status_label.text = "正在连接 %s:%d ..." % [address, port]
	_update_connection_buttons()


func _on_network_connection_succeeded(peer_id: int) -> void:
	status_label.text = "已连接服务器，客户端 Peer ID：%d。" % peer_id
	set_connected(true)
	_update_connection_buttons()


func _on_network_connection_failed(reason: String) -> void:
	status_label.text = reason
	set_connected(false)
	_update_connection_buttons()


func _on_network_disconnected(reason: String) -> void:
	status_label.text = reason
	set_connected(false)
	_update_connection_buttons()


func _on_player_setup_confirmed(selection: Dictionary) -> void:
	var team_text := "蓝队" if str(selection.get("team", "")) == "blue" else "红队"
	status_label.text = "服务器已确认配置，你被分配到%s。" % team_text
	loadout_ready_submitted.emit(selection)


func _on_player_setup_rejected(reason: String) -> void:
	status_label.text = "服务器拒绝了配置：%s" % reason
	if loadout_ui != null and loadout_ui.has_method("set_player_ready_state"):
		loadout_ui.call("set_player_ready_state", false)


func _update_connection_buttons() -> void:
	if connect_button == null or disconnect_button == null:
		return
	connect_button.disabled = MultiplayerNetwork.is_connecting_to_game_server() \
		or MultiplayerNetwork.is_connected_to_game_server()
	disconnect_button.disabled = not MultiplayerNetwork.is_connecting_to_game_server() \
		and not MultiplayerNetwork.is_connected_to_game_server()


func _make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 58)
	button.add_theme_font_size_override("font_size", 24)
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
