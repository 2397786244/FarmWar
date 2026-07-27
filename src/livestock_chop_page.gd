extends Control
class_name LivestockChopPage

var player: GamePlayer
var chop: LivestockChop
var station_path := ""
var station_state: Dictionary = {}
var _panel: PanelContainer
var _title: Label
var _requirements: Label
var _progress: ProgressBar
var _slots: GridContainer
var _start_button: Button
var _notice: Label
var _refresh_elapsed := 0.0


func _ready() -> void:
	visible = false
	_build_ui()


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(player) or not is_instance_valid(chop) \
			or player.global_position.distance_to(chop.global_position) > 5.5:
		close()
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 1.0:
		_refresh_elapsed = 0.0
		_submit("refresh")
	if not bool(station_state.get("completed", false)) and is_instance_valid(chop):
		_progress.value = chop.get_construction_progress() * 100.0


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 55
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(80.0, -330.0)
	_panel.size = Vector2(780.0, 660.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#101416")
	style.border_color = Color("#D98A32")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color("#F2A443"))
	root.add_child(_title)
	_requirements = Label.new()
	_requirements.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_requirements.add_theme_font_size_override("font_size", 20)
	root.add_child(_requirements)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 34.0
	_progress.show_percentage = true
	root.add_child(_progress)
	_slots = GridContainer.new()
	_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_slots.add_theme_constant_override("h_separation", 12)
	_slots.add_theme_constant_override("v_separation", 12)
	root.add_child(_slots)
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_color", Color("#FF9B75"))
	root.add_child(_notice)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	root.add_child(buttons)
	_start_button = Button.new()
	_start_button.text = "开始建造"
	_start_button.custom_minimum_size = Vector2(190.0, 48.0)
	_start_button.pressed.connect(func() -> void: _submit("start_construction"))
	buttons.add_child(_start_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(160.0, 48.0)
	close_button.pressed.connect(close)
	buttons.add_child(close_button)


func open_for(next_chop: LivestockChop, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_chop) or not is_instance_valid(next_player):
		return
	chop = next_chop
	player = next_player
	station_path = str(chop.get_path())
	station_state = chop.get_chop_state()
	visible = true
	_refresh_elapsed = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_submit("open")


func close() -> void:
	if not visible:
		return
	if not station_path.is_empty():
		_submit("close")
	visible = false
	station_path = ""
	chop = null
	if is_instance_valid(player) and is_instance_valid(player.player_backpack):
		player.player_backpack.hide_companion()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


func contains_storage_screen_point(point: Vector2) -> bool:
	return visible and _panel.get_global_rect().has_point(point)


func apply_authoritative_result(result: Dictionary) -> void:
	if not is_instance_valid(player) or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	if not bool(result.get("ok", false)):
		_notice.text = _reason_text(str(result.get("reason", "rejected")))
		if str(result.get("action", "")) in ["open", "refresh"] and str(result.get("reason", "")) == "station_in_use":
			close()
		return
	_notice.text = ""
	var slots_value: Variant = result.get("player_slots", null)
	if slots_value is Array:
		player.apply_cargo_backpack_slots(slots_value as Array)
	var state_value: Variant = result.get("station_state", {})
	if state_value is Dictionary:
		station_state = (state_value as Dictionary).duplicate(true)
		if is_instance_valid(chop):
			chop.apply_authoritative_chop_state(station_state)
	_refresh()


func can_drop(target_kind: String, target_index: int, data: Dictionary) -> bool:
	if not bool(station_state.get("completed", false)):
		return false
	var source_kind := str(data.get("slot_kind", ""))
	if target_kind == "chop":
		if source_kind != "inventory" or data.get("backpack") != player.player_backpack:
			return false
		var item := player.get_backpack_item(int(data.get("slot_index", -1)))
		var species := str(item.get("species_id", str(item.get("tool_id", "")).trim_prefix("animal_")))
		var slots: Array = station_state.get("slots", [])
		return target_index >= 0 and target_index < slots.size() \
			and (slots[target_index] as Dictionary).is_empty() and chop.accepts_species(species)
	return target_kind == "player" and source_kind == "chop" \
		and data.get("companion_page") == self \
		and player.get_backpack_item(target_index).is_empty()


func drop_item(target_kind: String, target_index: int, data: Dictionary) -> void:
	if target_kind == "chop":
		_submit("place", {
			"player_slot": int(data.get("slot_index", -1)), "chop_slot": target_index,
		})
	elif target_kind == "player":
		_submit("take", {
			"chop_slot": int(data.get("slot_index", -1)), "player_slot": target_index,
		})


func _submit(action_name: String, extra := {}) -> void:
	if not is_instance_valid(player):
		return
	var action := {
		"station_kind": "livestock_chop", "action": action_name,
		"station_path": station_path,
		"station_position": chop.global_position if is_instance_valid(chop) else Vector3.ZERO,
	}
	if extra is Dictionary:
		action.merge(extra as Dictionary, true)
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_authoritative_result(GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action))


func _refresh() -> void:
	if station_state.is_empty():
		return
	var built := bool(station_state.get("completed", false))
	var building := bool(station_state.get("constructing", false))
	_title.text = ("鸡舍" if str(station_state.get("chop_kind", "")) == "chicken" else "牲畜棚") \
		+ ("养殖" if built else "建造")
	_requirements.visible = not built
	_requirements.text = "需要 %.0f kg 原木 + %.0f kg 铁矿石" % [
		float(station_state.get("required_log_kg", 0.0)),
		float(station_state.get("required_iron_kg", 0.0)),
	]
	_progress.visible = not built
	_progress.value = float(station_state.get("construction_progress", 0.0)) * 100.0
	_start_button.visible = not built
	_start_button.disabled = building
	_start_button.text = "正在建造" if building else "开始建造"
	_slots.visible = built
	if not built:
		return
	var items: Array = station_state.get("slots", [])
	_slots.columns = 4
	while _slots.get_child_count() < items.size():
		var next_index := _slots.get_child_count()
		var next_slot := LivestockChopSlot.new()
		_slots.add_child(next_slot)
		next_slot.setup(self, next_index)
	while _slots.get_child_count() > items.size():
		var extra := _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(extra)
		extra.queue_free()
	for index in range(items.size()):
		var slot := _slots.get_child(index) as LivestockChopSlot
		slot.set_item(items[index] as Dictionary if items[index] is Dictionary else {})
	if not player.player_backpack.is_companion_display():
		player.player_backpack.show_companion(self)


func _reason_text(reason: String) -> String:
	return {
		"station_in_use": "另一名队员正在使用该养殖建筑",
		"station_out_of_range": "距离养殖建筑过远",
		"materials_unavailable": "原木或铁矿石不足",
		"construction_started": "建造已经开始",
		"invalid_livestock": "该动物不能放入这个养殖建筑",
		"slot_occupied": "这个养殖槽位已经被占用",
		"personal_bag_full": "背包无法容纳该动物",
	}.get(reason, "操作失败：%s" % reason)
