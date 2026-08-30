extends Control
class_name VehicleServicePage

signal closed

const VehicleColorCatalogScript := preload("res://src/vehicle_color_catalog.gd")
const VehicleSalesCatalogScript := preload("res://src/vehicle_sales_catalog.gd")

const REQUEST_TIMEOUT_SECONDS := 8.0
const HEARTBEAT_INTERVAL_SECONDS := 10.0
const COLOR_FEE := 500
const MODULE_FEE := 500
const SERVICE_MODULES := [
	{
		"id": "high_performance_motor",
		"name": "高性能电机",
		"item_id": "high_performance_motor",
		"item_amount": 1.0,
	},
	{
		"id": "composite_armor_panel",
		"name": "复合装甲板",
		"item_id": "composite_armor_panel",
		"item_amount": 1.0,
	},
	{"id": "vehicle_harvest_reel", "name": "收割模块"},
	{"id": "vehicle_extended_seat", "name": "扩展座椅"},
	{"id": "vehicle_roof_headlights", "name": "车顶大灯"},
	{"id": "vehicle_machine_gun", "name": "车载机枪"},
	{"id": "vehicle_nitro_boost", "name": "氮气加速装置"},
	{"id": "vehicle_signal_augment", "name": "车载信号增强塔"},
	{
		"id": "vehicle_metal_defense_net",
		"name": "金属网防护",
		"item_id": "metal_defense_net",
		"item_amount": 5.0,
	},
]

const COLOR_BACKGROUND := Color("0b0f13")
const COLOR_PANEL := Color("182027")
const COLOR_PANEL_DARK := Color("10161b")
const COLOR_TEXT := Color("eef3f5")
const COLOR_MUTED := Color("a8b5bd")
const COLOR_ACCENT := Color("72c9e8")
const COLOR_SUCCESS := Color("6fd18a")
const COLOR_ERROR := Color("ff8178")

var player: GamePlayer
var terminal: VehicleServiceTerminal
var vehicle: VehicleBase
var vehicle_id := ""
var terminal_id := ""

var _window: PanelContainer
var _title: Label
var _vehicle_label: Label
var _hp_label: Label
var _money_label: Label
var _status_label: Label
var _repair_hp_button: Button
var _body_option: OptionButton
var _wheel_option: OptionButton
var _body_button: Button
var _wheel_button: Button
var _body_color_selection_id := ""
var _wheel_color_selection_id := ""
var _service_tabs: TabContainer
var _upgrade_scroll: ScrollContainer
var _upgrade_list: VBoxContainer
var _retry_button: Button

var _quote: Dictionary = {}
var _pending_request: Dictionary = {}
var _pending_request_id := ""
var _pending_action := ""
var _request_elapsed := 0.0
var _request_timed_out := false
var _request_counter := 0
var _heartbeat_elapsed := 0.0
var _heartbeat_request_ids: Dictionary = {}
var _refresh_elapsed := 0.0
var _last_status := ""
var _last_status_color := COLOR_MUTED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	_build_interface()
	_layout_window()
	if not get_viewport().size_changed.is_connected(_layout_window):
		get_viewport().size_changed.connect(_layout_window)
	visible = false
	set_process(false)


func bind_player(next_player: GamePlayer) -> void:
	player = next_player


func is_open() -> bool:
	return visible


func open_for(next_terminal: VehicleServiceTerminal, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_terminal) or not is_instance_valid(next_player):
		return
	var next_terminal_id := next_terminal.get_terminal_id()
	var next_vehicle := next_terminal.get_active_vehicle()
	var next_vehicle_id := next_terminal.active_vehicle_id
	if next_vehicle == null or next_vehicle_id.is_empty():
		return
	var resumes_same_request := not _pending_request.is_empty() \
		and terminal == next_terminal and terminal_id == next_terminal_id \
		and vehicle_id == next_vehicle_id and player == next_player
	if not resumes_same_request and not _pending_request.is_empty():
		# A late reply for a previous terminal/vehicle must not be applied to a
		# newly opened page.  The server keeps the old request idempotent; this page
		# simply starts a fresh acquire for the new context.
		_clear_pending_request()
	terminal = next_terminal
	player = next_player
	terminal_id = next_terminal_id
	vehicle = next_vehicle
	vehicle_id = next_vehicle_id
	if not resumes_same_request:
		_body_color_selection_id = ""
		_wheel_color_selection_id = ""
	_layout_window()
	visible = true
	set_process(true)
	_heartbeat_elapsed = 0.0
	_heartbeat_request_ids.clear()
	_refresh_elapsed = 0.0
	_update_ui(true)
	call_deferred("_layout_window")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if resumes_same_request:
		_update_action_buttons()
		if _request_timed_out:
			_set_status("请求超时，服务器可能仍在处理；可重试确认。", COLOR_ERROR)
		else:
			_set_status("正在等待服务端确认……", COLOR_MUTED)
		return
	_request_timed_out = false
	_set_status("正在申请终端操作权限……", COLOR_MUTED)
	_request_action("acquire", {})


func close() -> void:
	if not visible:
		return
	if is_instance_valid(player) and player.has_method("end_vehicle_service_view"):
		player.call(
			"end_vehicle_service_view",
			terminal if is_instance_valid(terminal) else null
		)
	# Release is best-effort and intentionally does not replace a mutation
	# request that may still receive a late authoritative result.
	if is_instance_valid(terminal) and is_instance_valid(player):
		_send_untracked_request("release", {})
	_heartbeat_request_ids.clear()
	visible = false
	set_process(false)
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _clear_pending_request() -> void:
	_pending_request.clear()
	_pending_request_id = ""
	_pending_action = ""
	_request_elapsed = 0.0
	_request_timed_out = false


func refresh_if_open() -> void:
	if visible:
		_update_ui(true)


func apply_terminal_state(state_or_event: Dictionary) -> void:
	var state_value: Variant = state_or_event.get("state", state_or_event)
	if not state_value is Dictionary:
		return
	if is_instance_valid(terminal):
		terminal.apply_network_state(state_value as Dictionary)
	if not visible:
		return
	var next_vehicle_id := str((state_value as Dictionary).get("active_vehicle_id", ""))
	var next_user := int((state_value as Dictionary).get("active_user_peer_id", 0))
	if next_vehicle_id.is_empty() or next_vehicle_id != vehicle_id \
			or (next_user > 0 and next_user != _player_peer_id()):
		_set_status("终端占用已释放或载具已离开。", COLOR_ERROR)
		close()
		return
	_update_ui(true)


func apply_vehicle_state(state: Dictionary) -> void:
	if not visible or str(state.get("vehicle_id", "")) != vehicle_id:
		return
	var current_vehicle := terminal.get_active_vehicle() if is_instance_valid(terminal) else null
	# Local/listen-server transactions have already changed the authoritative
	# vehicle. Reapplying their response here can replay an older transform and
	# teleport a parked vehicle. Only a remote client needs the visual state; its
	# movement is still supplied by the regular replicated vehicle snapshots.
	if current_vehicle != null and GameAuthority.is_client_proxy():
		current_vehicle.apply_network_state(state)
	_update_ui(true)


func apply_transaction_result(result: Dictionary) -> void:
	if str(result.get("shop_category", "")) != "vehicle_service":
		return
	var result_request_id := str(result.get("request_id", ""))
	var result_action := str(result.get("action", ""))
	if result_action == "touch" and _heartbeat_request_ids.has(result_request_id):
		_heartbeat_request_ids.erase(result_request_id)
		if not bool(result.get("ok", false)) or str(result.get("phase", "failed")) != "completed":
			if visible:
				_set_status(_reason_text(str(result.get("reason", "service_lock_lost"))), COLOR_ERROR)
				close()
		return
	if _pending_request_id.is_empty() or result_request_id != _pending_request_id:
		# Results for another page/request are deliberately ignored. Shared
		# terminal/vehicle state arrives through its own event.
		return
	var action_name := str(result.get("action", _pending_action))
	var phase := str(result.get("phase", "failed"))
	var completed_color_slot := str(result.get("color_slot", _pending_request.get("color_slot", ""))) \
		if action_name == "change_color" else ""
	if phase == "pending":
		_request_timed_out = false
		_request_elapsed = 0.0
		_set_status("服务请求已受理，等待载具交付……", COLOR_MUTED)
		return
	_pending_request.clear()
	_pending_request_id = ""
	_pending_action = ""
	_request_elapsed = 0.0
	_request_timed_out = false
	set_process(visible)
	if result.has("service_state") and result.get("service_state") is Dictionary:
		apply_terminal_state(result.get("service_state") as Dictionary)
	if result.has("vehicle_state") and result.get("vehicle_state") is Dictionary:
		apply_vehicle_state(result.get("vehicle_state") as Dictionary)
	var slots_value: Variant = result.get("player_slots", null)
	if slots_value is Array and is_instance_valid(player):
		player.apply_cargo_backpack_slots(slots_value as Array)
	if result.has("quote") and result.get("quote") is Dictionary:
		_quote = (result.get("quote") as Dictionary).duplicate(true)
	if action_name == "change_color":
		# The request is now authoritative.  Until this point the local selection
		# must win over periodic vehicle-state refreshes; after it completes, let
		# the next refresh read the committed vehicle color again.
		_clear_color_selection(completed_color_slot)
	var succeeded := bool(result.get("ok", false)) and phase == "completed"
	if not succeeded:
		_set_status(_reason_text(str(result.get("reason", "操作失败"))), COLOR_ERROR)
	else:
		_set_status(_success_text(action_name), COLOR_SUCCESS)
	_update_ui(true)
	if succeeded and action_name == "acquire" and is_instance_valid(player) \
			and player.has_method("begin_vehicle_service_view") \
			and is_instance_valid(terminal) and is_instance_valid(vehicle):
		player.call("begin_vehicle_service_view", terminal, vehicle)
	elif succeeded and action_name in ["repair_hp", "change_color", "install_module", "uninstall_module"] \
			and is_instance_valid(terminal) and is_instance_valid(vehicle):
		terminal.refresh_service_camera(vehicle, get_viewport().get_visible_rect().size)
		terminal.play_service_effect(action_name, vehicle)


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(player) or player.is_respawning or not is_instance_valid(terminal):
		close()
		return
	vehicle = terminal.get_active_vehicle()
	if vehicle == null or vehicle.is_queued_for_deletion() or terminal.active_vehicle_id != vehicle_id \
			or not terminal.is_player_in_player_area(player) \
			or (terminal.active_user_peer_id > 0 and terminal.active_user_peer_id != _player_peer_id()):
		close()
		return
	if not _pending_request.is_empty():
		_request_elapsed += maxf(0.0, delta)
		if _request_elapsed >= REQUEST_TIMEOUT_SECONDS and not _request_timed_out:
			_request_timed_out = true
			_set_status("请求超时，服务器可能仍在处理；可重试确认。", COLOR_ERROR)
			_update_action_buttons()
	_heartbeat_elapsed += maxf(0.0, delta)
	_refresh_elapsed += maxf(0.0, delta)
	if _heartbeat_elapsed >= HEARTBEAT_INTERVAL_SECONDS \
			and terminal.active_user_peer_id == _player_peer_id():
		_heartbeat_elapsed = 0.0
		_send_heartbeat_request()
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_update_ui(false)
		if is_instance_valid(player) and player.has_method("is_vehicle_service_view_active") \
				and bool(player.call("is_vehicle_service_view_active")):
			terminal.refresh_service_camera(vehicle, get_viewport().get_visible_rect().size)


func _build_interface() -> void:
	_window = PanelContainer.new()
	_window.name = "Window"
	_window.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_window.add_theme_stylebox_override("panel", _style_box(COLOR_BACKGROUND, 12, Color("4c788b"), 2))
	add_child(_window)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_window.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	_title = Label.new()
	_title.text = "升级维修终端"
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", COLOR_TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_theme_color_override("font_color", Color("e8bd67"))
	header.add_child(_money_label)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(42, 38)
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_vehicle_label = Label.new()
	_vehicle_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_vehicle_label.add_theme_font_size_override("font_size", 19)
	_vehicle_label.clip_text = true
	_vehicle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_vehicle_label)
	_hp_label = Label.new()
	_hp_label.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(_hp_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 28)
	root.add_child(_status_label)

	_service_tabs = TabContainer.new()
	_service_tabs.name = "ServiceTabs"
	_service_tabs.custom_minimum_size = Vector2(0, 390)
	_service_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_service_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_service_tabs.set("tab_alignment", 1)
	_service_tabs.tab_changed.connect(func(_tab: int) -> void: call_deferred("_layout_window"))
	root.add_child(_service_tabs)
	var repair_tab := VBoxContainer.new()
	repair_tab.name = "Repair"
	repair_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	repair_tab.add_theme_constant_override("separation", 10)
	_service_tabs.add_child(repair_tab)
	_build_repair_tab(repair_tab)
	var upgrade_tab := VBoxContainer.new()
	upgrade_tab.name = "Upgrade"
	upgrade_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upgrade_tab.add_theme_constant_override("separation", 8)
	_service_tabs.add_child(upgrade_tab)
	_build_upgrade_tab(upgrade_tab)
	_retry_button = Button.new()
	_retry_button.text = "重试上一次请求"
	_retry_button.visible = false
	_retry_button.pressed.connect(_retry_request)
	root.add_child(_retry_button)
	var footer := Label.new()
	footer.text = "服务期间请保持玩家在终端旁、载具留在白色区域内。按 Esc 退出。"
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size = Vector2(0.0, 36.0)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(footer)


func _layout_window() -> void:
	if not is_instance_valid(_window):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := clampf(viewport_size.x * 0.38, 520.0, 680.0)
	var panel_height := clampf(viewport_size.y - 48.0, 480.0, 720.0)
	_window.position = Vector2(24.0, maxf(24.0, (viewport_size.y - panel_height) * 0.5))
	_window.size = Vector2(panel_width, panel_height)


func _build_repair_tab(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "维修"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	parent.add_child(title)
	_repair_hp_button = Button.new()
	_repair_hp_button.custom_minimum_size = Vector2(0, 46)
	_repair_hp_button.pressed.connect(func() -> void: _request_action("repair_hp", {}))
	parent.add_child(_repair_hp_button)
	parent.add_child(_separator_label("车身颜色更换（每个颜色槽 500 队伍资金）"))
	var body_row := HBoxContainer.new()
	parent.add_child(body_row)
	body_row.add_child(_label("车身颜色"))
	_body_option = _make_color_option()
	_body_option.item_selected.connect(_on_color_option_selected.bind("body"))
	body_row.add_child(_body_option)
	_body_button = Button.new()
	_body_button.text = "更换车身颜色"
	_body_button.pressed.connect(func() -> void: _request_selected_color("body"))
	body_row.add_child(_body_button)
	var wheel_row := HBoxContainer.new()
	parent.add_child(wheel_row)
	wheel_row.add_child(_label("轮毂颜色"))
	_wheel_option = _make_color_option()
	_wheel_option.item_selected.connect(_on_color_option_selected.bind("wheel"))
	wheel_row.add_child(_wheel_option)
	_wheel_button = Button.new()
	_wheel_button.text = "更换轮毂颜色"
	_wheel_button.pressed.connect(func() -> void: _request_selected_color("wheel"))
	wheel_row.add_child(_wheel_button)


func _build_upgrade_tab(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "升级"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	parent.add_child(title)
	var description := Label.new()
	description.text = "高性能电机适用于六种常规载具；其余模块仅 FarmBaseVehicle 可用。\n安装或切换消耗 1 个背包物品和 500 队伍资金；卸下返还物品且不收费。"
	description.autowrap_mode = TextServer.AUTOWRAP_OFF
	description.clip_text = true
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.custom_minimum_size = Vector2(0.0, 48.0)
	description.add_theme_color_override("font_color", COLOR_MUTED)
	parent.add_child(description)
	_upgrade_scroll = ScrollContainer.new()
	_upgrade_scroll.name = "UpgradeScroll"
	_upgrade_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_upgrade_scroll)
	_upgrade_list = VBoxContainer.new()
	_upgrade_list.add_theme_constant_override("separation", 6)
	_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_scroll.add_child(_upgrade_list)


func _make_color_option() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180, 38)
	for color_option: Dictionary in VehicleColorCatalogScript.get_options():
		option.add_item(str(color_option.get("label", color_option.get("id", ""))))
		option.set_item_metadata(option.item_count - 1, str(color_option.get("id", "black")))
	return option


func _label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size = Vector2(110, 36)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _separator_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label


func _update_ui(force: bool) -> void:
	if not is_instance_valid(terminal):
		return
	vehicle = terminal.get_active_vehicle()
	if vehicle == null:
		return
	if force or _quote.is_empty():
		_quote = GameAuthority.get_vehicle_service_quote(vehicle, _player_peer_id())
	_title.text = "升级维修终端"
	_vehicle_label.text = "当前载具：%s（%s）" % [_vehicle_display_name(vehicle), vehicle_id]
	var maximum_hp := float(_quote.get("max_hp", vehicle.get_max_hp()))
	var current_hp := float(_quote.get("current_hp", vehicle.current_hp))
	_hp_label.text = "载具 HP：%.0f / %.0f" % [current_hp, maximum_hp]
	_money_label.text = "队伍资金：%d" % _team_money()
	_refresh_color_options()
	_refresh_repair_button()
	_refresh_upgrade_list()
	_update_action_buttons()


func _refresh_color_options() -> void:
	if _body_option == null or _wheel_option == null or vehicle == null:
		return
	var vehicle_body_id := vehicle.get_body_color_id() if vehicle.has_method("get_body_color_id") else "black"
	var vehicle_wheel_id := vehicle.get_wheel_color_id() if vehicle.has_method("get_wheel_color_id") else "black"
	var body_id := _body_color_selection_id if not _body_color_selection_id.is_empty() else vehicle_body_id
	var wheel_id := _wheel_color_selection_id if not _wheel_color_selection_id.is_empty() else vehicle_wheel_id
	_select_color_option(_body_option, body_id)
	_select_color_option(_wheel_option, wheel_id)


func _on_color_option_selected(index: int, slot: String) -> void:
	var option := _body_option if slot == "body" else _wheel_option
	if option == null or index < 0 or index >= option.item_count:
		return
	var selected_id := str(option.get_item_metadata(index))
	if slot == "body":
		_body_color_selection_id = selected_id
	else:
		_wheel_color_selection_id = selected_id


func _clear_color_selection(slot: String) -> void:
	if slot == "body":
		_body_color_selection_id = ""
	elif slot == "wheel":
		_wheel_color_selection_id = ""


func _select_color_option(option: OptionButton, color_id: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == color_id:
			option.select(index)
			return


func _refresh_repair_button() -> void:
	if _repair_hp_button == null:
		return
	var repair_fee := int(_quote.get("repair_hp_fee", -1))
	var current_hp := float(_quote.get("current_hp", vehicle.current_hp if vehicle != null else 0.0))
	var maximum_hp := float(_quote.get("max_hp", vehicle.get_max_hp() if vehicle != null else 0.0))
	if current_hp >= maximum_hp - 0.001:
		_repair_hp_button.text = "载具已满血，无需维修"
	elif repair_fee < 0:
		_repair_hp_button.text = "维修费用不可用（缺少有效载具价格）"
	else:
		_repair_hp_button.text = "恢复载具 HP（费用：%d）" % repair_fee


func _refresh_upgrade_list() -> void:
	if _upgrade_list == null:
		return
	for child in _upgrade_list.get_children():
		child.queue_free()
	var modules_value: Variant = _quote.get("modules", [])
	var module_states: Dictionary = {}
	if modules_value is Array:
		for value: Variant in modules_value as Array:
			if not value is Dictionary:
				continue
			var module_state_value := value as Dictionary
			var returned_module_id := str(module_state_value.get("module_id", ""))
			if not returned_module_id.is_empty():
				module_states[returned_module_id] = module_state_value
	if module_states.is_empty():
		_upgrade_list.add_child(_separator_label("当前载具没有可用的运行时升级模块。"))
		call_deferred("_layout_window")
		return
	for module_definition: Dictionary in SERVICE_MODULES:
		var module_id := str(module_definition.get("id", ""))
		if not module_states.has(module_id):
			continue
		var module_state: Dictionary = module_states[module_id]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 42)
		var installed := int(module_state.get("installed_count", _local_module_count(module_id)))
		var max_count := int(module_state.get("max_count", 2 if module_id == "vehicle_extended_seat" else 1))
		var item_id := str(module_state.get("item_id", module_definition.get("item_id", module_id)))
		var item_amount := int(round(float(module_state.get(
			"item_amount", module_definition.get("item_amount", 1.0))
		)))
		item_amount = maxi(item_amount, 1)
		var count := _personal_item_count(item_id)
		var can_install := bool(module_state.get(
			"can_install", installed < max_count and count >= item_amount
		))
		var can_uninstall := bool(module_state.get("can_uninstall", installed > 0))
		var can_switch := bool(module_state.get("can_switch", false))
		var is_mutual_exclusion_switch := bool(module_state.get(
			"is_mutual_exclusion_switch", false
		))
		var switch_module_id := str(module_state.get("switch_module_id", ""))
		var label := Label.new()
		var inventory_text := str(count)
		if item_amount > 1:
			inventory_text = "%d/%d" % [count, item_amount]
		var module_name := str(module_definition.get("name", module_id))
		if module_id == "high_performance_motor":
			module_name += "（最高速度+20%，加速度+20%）"
		elif module_id == "composite_armor_panel":
			module_name += "（最大HP+1500，安装时当前HP+1500）"
		label.text = "%s  已安装：%d/%d  背包：%s" % [
			module_name, installed, max_count, inventory_text
		]
		label.custom_minimum_size = Vector2(0.0, 42.0)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", COLOR_TEXT)
		row.add_child(label)
		if installed > 0:
			_add_module_action_button(
				row,
				"uninstall_module",
				module_id,
				"卸下（返还）" if can_uninstall else "暂不可卸下",
				not can_uninstall
			)
			# Extended seats are countable modules. Keep the install action visible
			# until both platform seats are occupied, while uninstall remains a
			# one-item-at-a-time action beside it.
			if module_id == "vehicle_extended_seat" and installed < max_count:
				_add_module_action_button(row, "install_module", module_id, "再安装（500）", not can_install)
		elif is_mutual_exclusion_switch and not switch_module_id.is_empty():
			_add_module_action_button(row, "install_module", module_id, "切换（500）", not can_switch)
		else:
			_add_module_action_button(
				row,
				"install_module",
				module_id,
				"安装（500）" if installed < max_count else "已安装",
				not can_install
			)
		_upgrade_list.add_child(row)
	call_deferred("_layout_window")


func _add_module_action_button(
	row: HBoxContainer,
	action_name: String,
	module_id: String,
	text_value: String,
	initially_disabled: bool
) -> void:
	var button := Button.new()
	button.text = text_value
	button.disabled = initially_disabled or not _pending_request.is_empty() or _request_timed_out
	button.pressed.connect(_request_action.bind(action_name, {"module_id": module_id}))
	row.add_child(button)


func _update_action_buttons() -> void:
	var blocked := not _pending_request.is_empty() or _request_timed_out
	if _repair_hp_button != null:
		_repair_hp_button.disabled = blocked or int(_quote.get("repair_hp_fee", -1)) < 0 \
			or float(_quote.get("current_hp", 0.0)) >= float(_quote.get("max_hp", 0.0)) - 0.001
	if _body_option != null:
		_body_option.disabled = blocked
	if _wheel_option != null:
		_wheel_option.disabled = blocked
	if _body_button != null:
		_body_button.disabled = blocked
	if _wheel_button != null:
		_wheel_button.disabled = blocked
	if _retry_button != null:
		_retry_button.visible = _request_timed_out and not _pending_request.is_empty()
		_retry_button.disabled = false


func _request_selected_color(slot: String) -> void:
	if _request_timed_out:
		return
	var option := _body_option if slot == "body" else _wheel_option
	if option == null or option.selected < 0:
		return
	_request_action("change_color", {
		"color_slot": slot,
		"color_id": str(option.get_item_metadata(option.selected)),
	})


func _request_action(action_name: String, extra: Dictionary) -> void:
	if not visible or not _pending_request.is_empty() or _request_timed_out:
		return
	var request := _make_request(action_name, extra)
	_pending_request = request.duplicate(true)
	_pending_request_id = str(request.get("request_id", ""))
	_pending_action = action_name
	_request_elapsed = 0.0
	_request_timed_out = false
	_update_action_buttons()
	_set_status("正在向服务端提交请求……", COLOR_MUTED)
	_send_request_payload(request)


func _retry_request() -> void:
	if not _request_timed_out or _pending_request.is_empty():
		return
	_request_timed_out = false
	_request_elapsed = 0.0
	_update_action_buttons()
	_set_status("正在使用同一请求编号重试确认……", COLOR_MUTED)
	_send_request_payload(_pending_request)


func _make_request(action_name: String, extra: Dictionary) -> Dictionary:
	_request_counter += 1
	var peer_id := _player_peer_id()
	var request := {
		"shop_category": "vehicle_service",
		"action": action_name,
		"request_id": "vehicle_service_%d_%d_%d" % [peer_id, Time.get_ticks_msec(), _request_counter],
		"terminal_id": terminal_id,
		"terminal_path": str(terminal.get_path()) if is_instance_valid(terminal) else "",
		"vehicle_id": vehicle_id,
	}
	request.merge(extra, true)
	return request


func _send_request_payload(request: Dictionary) -> void:
	if GameAuthority.should_send_network_requests():
		var sent := MultiplayerNetwork.submit_shop_transaction(request)
		if not sent:
			apply_transaction_result(_local_failure_result(request, "request_not_sent"))
		return
	if GameAuthority.is_local_interaction_authority():
		var result := GameAuthority.local_shop_transaction(_player_peer_id(), request)
		apply_transaction_result(result)
		return
	apply_transaction_result(_local_failure_result(request, "request_not_sent"))


func _send_untracked_request(action_name: String, extra: Dictionary) -> void:
	if not is_instance_valid(terminal) or not is_instance_valid(player):
		return
	var request := _make_request(action_name, extra)
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_shop_transaction(request)
	elif GameAuthority.is_local_interaction_authority():
		GameAuthority.local_shop_transaction(_player_peer_id(), request)


func _send_heartbeat_request() -> void:
	if not is_instance_valid(terminal) or not is_instance_valid(player):
		return
	var request := _make_request("touch", {})
	_heartbeat_request_ids[str(request.get("request_id", ""))] = true
	if GameAuthority.should_send_network_requests():
		if not MultiplayerNetwork.submit_shop_transaction(request):
			apply_transaction_result(_local_failure_result(request, "request_not_sent"))
		return
	if GameAuthority.is_local_interaction_authority():
		apply_transaction_result(GameAuthority.local_shop_transaction(_player_peer_id(), request))
		return
	apply_transaction_result(_local_failure_result(request, "request_not_sent"))


func _local_failure_result(request: Dictionary, reason: String) -> Dictionary:
	return {
		"ok": false,
		"phase": "failed",
		"reason": reason,
		"peer_id": _player_peer_id(),
		"shop_category": "vehicle_service",
		"action": str(request.get("action", "")),
		"request_id": str(request.get("request_id", "")),
		"terminal_id": terminal_id,
		"vehicle_id": vehicle_id,
	}


func _player_peer_id() -> int:
	return int(player.authority_peer_id) if is_instance_valid(player) else GameAuthority.LOCAL_PLAYER_ID


func _team_money() -> int:
	if not is_instance_valid(player):
		return 0
	return int(round(GlobalVar.check_team_item_amount(player.team, "money")))


func _vehicle_display_name(next_vehicle: VehicleBase) -> String:
	var catalog_id := ""
	var state_value: Variant = GameAuthority.vehicle_states.get(next_vehicle.get_vehicle_id(), {}) \
		if is_instance_valid(GameAuthority) else {}
	if state_value is Dictionary:
		catalog_id = str((state_value as Dictionary).get("catalog_vehicle_id", ""))
	if catalog_id.is_empty():
		catalog_id = next_vehicle.get_vehicle_id()
	var product := VehicleSalesCatalogScript.get_product(catalog_id)
	return str(product.get("name", catalog_id)) if not product.is_empty() else next_vehicle.name


func _personal_item_count(item_id: String) -> int:
	if not is_instance_valid(player):
		return 0
	var total := 0
	var state_value: Variant = GameAuthority.player_states.get(_player_peer_id(), {}) \
		if is_instance_valid(GameAuthority) else {}
	if state_value is Dictionary:
		var personal: Variant = (state_value as Dictionary).get("personal_ingredients", {})
		if personal is Dictionary:
			total = floori(float((personal as Dictionary).get(item_id + "|whole", 0.0)))
	if total > 0:
		return total
	for item_value: Dictionary in player.backpack_items:
		if str(item_value.get("ingredient_id", "")) == item_id:
			total += 1
	return total


func _local_module_count(module_id: String) -> int:
	if module_id == "high_performance_motor":
		return 1 if vehicle != null and vehicle.high_performance_motor_installed else 0
	if module_id == "composite_armor_panel":
		return 1 if vehicle != null and vehicle.composite_armor_panel_installed else 0
	if not vehicle is FarmBaseVehicle:
		return 0
	var farm_vehicle := vehicle as FarmBaseVehicle
	match module_id:
		"vehicle_harvest_reel": return 1 if farm_vehicle.harvest_reel_installed else 0
		"vehicle_extended_seat": return farm_vehicle.platform_passenger_seat_count
		"vehicle_roof_headlights": return 1 if farm_vehicle.roof_headlights_installed else 0
		"vehicle_machine_gun": return 1 if farm_vehicle.platform_machine_gun_installed else 0
		"vehicle_nitro_boost": return 1 if farm_vehicle.nitro_boost_installed else 0
		"vehicle_signal_augment": return 1 if farm_vehicle.platform_signal_station_installed else 0
		"vehicle_metal_defense_net": return 1 if farm_vehicle.reinforced_variant else 0
	return 0


func _set_status(message: String, color: Color) -> void:
	_last_status = message
	_last_status_color = color
	if _status_label != null:
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", color)


func _reason_text(reason: String) -> String:
	match reason:
		"service_in_use": return "其他玩家正在操作这台载具。"
		"service_lock_not_owned": return "终端操作锁已失效，请重新进入终端。"
		"service_lock_lost": return "终端心跳已失效，请重新进入终端。"
		"service_out_of_range": return "玩家已经离开终端交互区域。"
		"vehicle_service_unavailable": return "载具已经离开维修区域或不可用。"
		"vehicle_service_vehicle_mismatch": return "载具状态已变化，请重新进入终端。"
		"custom_color_unsupported": return "当前载具不支持颜色更换。"
		"invalid_vehicle_color": return "颜色选项无效。"
		"color_change_failed": return "颜色更换失败，队伍资金已回滚。"
		"repair_unavailable": return "无法解析有效维修费用，服务端不会免费维修。"
		"repair_failed": return "载具维修失败，队伍资金已回滚。"
		"insufficient_money": return "队伍资金不足。"
		"module_unavailable": return "当前载具没有这个升级模块。"
		"module_already_installed": return "该模块已经安装到上限。"
		"module_item_missing": return "背包内没有对应模块物品。"
		"module_install_failed": return "模块安装失败，资金和物品已回滚。"
		"module_not_installed": return "该模块当前没有安装。"
		"module_uninstall_failed": return "模块卸下失败，载具和物品已回滚。"
		"module_passenger_occupied": return "平台上仍有乘客，不能卸下扩展座椅。"
		"module_machine_gun_in_use": return "车载机枪正在被操作，不能卸下或切换。"
		"module_switch_failed": return "模块切换失败，资金、载具和物品已回滚。"
		"module_bag_full": return "背包没有空间接收返还的模块。"
		"request_not_sent": return "网络未连接，请稍后重试。"
	return reason if not reason.is_empty() else "服务请求失败。"


func _success_text(action_name: String) -> String:
	match action_name:
		"acquire": return "已连接终端，可以进行维修或升级。"
		"repair_hp": return "载具 HP 已恢复。"
		"change_color": return "载具配色已更新。"
		"install_module": return "模块安装完成。"
		"uninstall_module": return "模块卸下完成，物品已返还。"
	return "操作完成。"


func _style_box(fill: Color, radius: int, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	return style
