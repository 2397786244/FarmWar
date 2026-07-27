extends Control
class_name CargoCrateStoragePage

var player: GamePlayer
var crate: CargoCrateGround
var crate_id := ""
var crate_data: Dictionary = {}
var _slot: CargoCrateStorageSlot
var _panel: PanelContainer
var _weight_label: Label
var _notice: Label


func _ready() -> void:
	visible = false
	_build_ui()


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(player) or not is_instance_valid(crate) \
			or player.global_position.distance_to(crate.global_position) > 4.5):
		close()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var panel := _panel
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 80.0
	panel.offset_top = -340.0
	panel.offset_right = 840.0
	panel.offset_bottom = 340.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111719")
	style.border_color = Color("#E7B84D")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	var title := Label.new()
	title.text = "货运箱"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#F0C75E"))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "单格容器：拖动物品在背包与箱子之间转移"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	box.add_child(hint)
	_slot = CargoCrateStorageSlot.new()
	_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_slot)
	_slot.setup(self)
	_weight_label = Label.new()
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weight_label.add_theme_font_size_override("font_size", 24)
	_weight_label.add_theme_color_override("font_color", Color("#75D49B"))
	box.add_child(_weight_label)
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_color_override("font_color", Color("#FF8B75"))
	box.add_child(_notice)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(180.0, 50.0)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	box.add_child(close_button)


func open_for(next_crate: CargoCrateGround, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_crate) or not is_instance_valid(next_player):
		return
	crate = next_crate
	player = next_player
	crate_id = str(crate.get_meta("network_device_id", crate.get_path()))
	visible = true
	player.player_backpack.show_companion(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_submit({"action": "open"})


func close() -> void:
	if not visible:
		return
	if not crate_id.is_empty():
		_submit({"action": "close"})
	visible = false
	if is_instance_valid(player):
		player.player_backpack.hide_companion()
		if not player.is_remote_proxy:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	crate = null
	crate_id = ""


func is_open() -> bool:
	return visible


func contains_storage_screen_point(screen_point: Vector2) -> bool:
	return visible and is_instance_valid(_panel) and _panel.get_global_rect().has_point(screen_point)


func drop_dragged_item_outside(data: Dictionary, direction: Vector3) -> void:
	if str(data.get("slot_kind", "")) != "crate":
		return
	_submit({
		"action": "drop",
		"requested_weight_kg": float(data.get("unit_weight_kg", 0.0)) \
			if bool(data.get("unit_weight_transfer", false)) else 0.0,
		"direction": direction,
	})


func apply_authoritative_result(result: Dictionary) -> void:
	if not is_instance_valid(player) or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	if not bool(result.get("ok", false)):
		_notice.text = _reason_text(str(result.get("reason", "rejected")))
		if str(result.get("action", "")) == "open":
			close()
		return
	var slots_value: Variant = result.get("player_slots", null)
	if slots_value is Array:
		player.apply_cargo_backpack_slots(slots_value as Array)
	var crate_value: Variant = result.get("crate_data", null)
	if crate_value is Dictionary:
		crate_data = CargoCrateData.normalize(crate_value as Dictionary)
		if is_instance_valid(crate):
			crate.setup_crate(crate_data)
	if bool(result.get("crate_removed", false)):
		visible = false
		player.player_backpack.hide_companion()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		crate = null
		crate_id = ""
		return
	if str(result.get("action", "")) == "store" and float(result.get("requested_weight_kg", 0.0)) > float(result.get("transferred_weight_kg", 0.0)) + 0.001:
		_notice.text = "已装入 %.2f kg，剩余 %.2f kg 保留在背包" % [
			float(result.get("transferred_weight_kg", 0.0)),
			float(result.get("remaining_in_backpack_kg", 0.0)),
		]
		_notice.add_theme_color_override("font_color", Color("#F0C75E"))
	else:
		_notice.text = ""
	_refresh()


func can_drop(target_kind: String, _target_index: int, data: Dictionary) -> bool:
	var source_kind := str(data.get("slot_kind", ""))
	var source_index := int(data.get("slot_index", -1))
	if target_kind == "crate":
		if data.get("backpack") != player.player_backpack or source_kind != "inventory":
			return false
		return CargoCrateData.can_store(crate_data, player.get_backpack_item(source_index))
	var unit_item: Dictionary = data.get("unit_item", {}) as Dictionary
	return target_kind == "player" and data.get("cargo_page") == self \
		and source_kind == "crate" and not (crate_data.get("stored_item", {}) as Dictionary).is_empty() \
		and _target_index >= 0 and _target_index < player.get_active_bag_slot_count() \
		and (player.get_backpack_item(_target_index).is_empty() \
			or UnitWeightItem.can_merge(player.get_backpack_item(_target_index), unit_item)) \
		and _can_player_accept_item(unit_item)


func drop_item(target_kind: String, target_index: int, data: Dictionary) -> void:
	var source_kind := str(data.get("slot_kind", ""))
	if target_kind == "crate" and source_kind == "inventory":
		_submit({
			"action": "store",
			"player_slot": int(data.get("slot_index", -1)),
			"requested_weight_kg": float(data.get("unit_weight_kg", 0.0)) \
				if bool(data.get("unit_weight_transfer", false)) else 0.0,
		})
	elif target_kind == "player" and source_kind == "crate":
		_submit({
			"action": "take",
			"player_slot": target_index,
			"requested_weight_kg": float(data.get("unit_weight_kg", 0.0)) \
				if bool(data.get("unit_weight_transfer", false)) else 0.0,
		})


func _submit(extra: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	var action := {"station_kind": "cargo_crate", "crate_id": crate_id}
	action.merge(extra, true)
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_authoritative_result(GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action))


func _refresh() -> void:
	var stored: Dictionary = crate_data.get("stored_item", {}) as Dictionary \
		if crate_data.get("stored_item", {}) is Dictionary else {}
	_slot.set_item(stored)
	_weight_label.text = "内容  %.2f / %.2f kg    箱体 %.1f kg" % [
		float(crate_data.get("content_weight_kg", 0.0)),
		float(crate_data.get("capacity_kg", 0.0)),
		float(crate_data.get("tare_weight_kg", 0.0)),
	]


func _reason_text(reason: String) -> String:
	return {
		"crate_in_use": "另一名玩家正在使用该箱子",
		"crate_out_of_range": "距离箱子过远",
		"crate_overweight": "物品超过该箱子的容量",
		"crate_not_empty": "箱子已经存放了物品",
		"nested_crate": "货运箱不能放入另一个货运箱",
		"personal_bag_full": "背包已满或超重",
	}.get(reason, "操作失败：%s" % reason)


func _can_player_accept_item(item: Dictionary) -> bool:
	match str(item.get("kind", "")):
		"ingredient":
			return player.can_add_personal_ingredient(
				str(item.get("ingredient_id", "")),
				float(item.get("weight_kg", 0.0)),
				bool(item.get("is_chopped", false))
			)
		"dish":
			return player.can_add_personal_dish(
				str(item.get("dish_id", "")),
				int(item.get("servings", 0)),
				float(item.get("weight_kg", 0.0))
			)
	return player.get_personal_bag_weight_kg() + UnitWeightItem.get_weight_kg(item) \
		<= player.get_personal_bag_capacity_kg() + 0.001
