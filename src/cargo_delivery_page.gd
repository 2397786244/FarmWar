extends Control
class_name CargoDeliveryPage

var player: GamePlayer
var preview: Dictionary = {}
var _title: Label
var _details: Label
var _confirm: Button


func _ready() -> void:
	visible = false
	_build_ui()


func bind_player(next_player: GamePlayer) -> void:
	player = next_player


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360.0
	panel.offset_top = -250.0
	panel.offset_right = 360.0
	panel.offset_bottom = 250.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111719")
	style.border_color = Color("#6FCF82")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color("#8CE49C"))
	box.add_child(_title)
	_details = Label.new()
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 23)
	box.add_child(_details)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(180.0, 54.0)
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_confirm = Button.new()
	_confirm.text = "确认交付"
	_confirm.custom_minimum_size = Vector2(220.0, 54.0)
	_confirm.pressed.connect(_confirm_delivery)
	buttons.add_child(_confirm)


func show_preview(value: Dictionary, next_player: GamePlayer) -> void:
	player = next_player
	preview = value.duplicate(true)
	_title.text = str(preview.get("task_name", "货运任务交付"))
	_details.text = "交付地点：%s\n本次交付：%d 个货运箱\n本次货物：%s\n任务总需求：%s\n交付后进度：%s" % [
		str(preview.get("building_name", "交付点")),
		int(preview.get("crate_count", 0)),
		str(preview.get("delivery_summary", "--")),
		str(preview.get("requirement_summary", "--")),
		str(preview.get("progress_summary", "--")),
	]
	_confirm.disabled = int(preview.get("crate_count", 0)) <= 0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close(send_cancel := true) -> void:
	if visible and send_cancel and is_instance_valid(player) and not preview.is_empty():
		var cancel_action := {"station_kind": "cargo_delivery", "action": "cancel"}
		if GameAuthority.should_send_network_requests():
			MultiplayerNetwork.submit_ingredient_pickup_action(cancel_action)
		else:
			GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, cancel_action)
	visible = false
	preview.clear()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


func apply_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_details.text = "交付失败：%s" % str(result.get("reason", "货物或任务状态已经变化"))
		_confirm.disabled = true
		return
	close(false)


func _confirm_delivery() -> void:
	if preview.is_empty() or not is_instance_valid(player):
		return
	_confirm.disabled = true
	var action := {
		"station_kind": "cargo_delivery",
		"action": "confirm",
		"building_id": str(preview.get("building_id", "")),
		"task_id": int(preview.get("task_id", 0)),
		"entrant_kind": str(preview.get("entrant_kind", "")),
		"vehicle_id": str(preview.get("vehicle_id", "")),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_result(GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action))
