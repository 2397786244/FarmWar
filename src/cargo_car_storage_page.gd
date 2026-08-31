extends Control
class_name CargoCarStoragePage

const SLOT_SCENE_SCRIPT := preload("res://src/cargo_inventory_slot.gd")
const CARGO_CAR_DEBUG := preload("res://src/cargo_car_debug.gd")

var player: GamePlayer
var vehicle: VehicleBase
var vehicle_id := ""
var manifest: Array[Dictionary] = []
var available_slots := 12
var _cargo_grid: GridContainer
var _panel: PanelContainer
var _count_label: Label
var _weight_label: Label
var _notice: Label


func _ready() -> void:
	visible = false
	_build_ui()


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(vehicle) or not is_instance_valid(player):
		CARGO_CAR_DEBUG.log("UI auto-close: vehicle or player became invalid vehicle_id=%s" % vehicle_id)
		close()
		return
	if not vehicle.is_cargo_storage_interaction_available_to(player.global_position):
		CARGO_CAR_DEBUG.log(
			"UI auto-close: out of cargo range player=%s peer=%d vehicle=%s id=%s position=%s"
			% [player.name, player.authority_peer_id, vehicle.name, vehicle_id, str(player.global_position)]
		)
		close()


func _build_ui() -> void:
	UITheme.apply(self)
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
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.apply_panel(panel, UITheme.COLOR_BG, 2, 4)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var title := Label.new()
	title.text = "CARGO CAR STORAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	UITheme.set_tone(title, UITheme.TONE_NEUTRAL)
	root.add_child(title)
	var hint := Label.new()
	hint.text = "仅可装载货运箱；拖动货箱在背包与载具之间转移"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	UITheme.set_tone(hint, UITheme.TONE_MUTED)
	root.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_cargo_grid = GridContainer.new()
	_cargo_grid.columns = 4
	_cargo_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cargo_grid.add_theme_constant_override("h_separation", 12)
	_cargo_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cargo_grid)
	var footer := HBoxContainer.new()
	root.add_child(footer)
	_count_label = Label.new()
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.add_theme_font_size_override("font_size", 24)
	footer.add_child(_count_label)
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 24)
	UITheme.set_tone(_weight_label, UITheme.TONE_INFO)
	footer.add_child(_weight_label)
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	UITheme.set_status(_notice, UITheme.TONE_ERROR)
	root.add_child(_notice)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(180.0, 48.0)
	UITheme.apply_button(close_button)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	root.add_child(close_button)

func open_for(next_vehicle: VehicleBase, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_vehicle) or not is_instance_valid(next_player):
		CARGO_CAR_DEBUG.log("open UI rejected: invalid vehicle or player")
		return
	player = next_player
	vehicle = next_vehicle
	vehicle_id = vehicle.get_vehicle_id()
	CARGO_CAR_DEBUG.log(
		"UI open_for player=%s peer=%d vehicle=%s id=%s capacity=%.1f"
		% [player.name, player.authority_peer_id, vehicle.name, vehicle_id, vehicle.get_cargo_capacity_kg()]
	)
	visible = true
	player.player_backpack.show_companion(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_submit({"action": "open"})


func close() -> void:
	if not visible:
		return
	if not vehicle_id.is_empty():
		_submit({"action": "close"})
	visible = false
	vehicle = null
	vehicle_id = ""
	if is_instance_valid(player) and is_instance_valid(player.player_backpack):
		player.player_backpack.hide_companion()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return visible


func contains_storage_screen_point(screen_point: Vector2) -> bool:
	return visible and is_instance_valid(_panel) and _panel.get_global_rect().has_point(screen_point)


func drop_dragged_item_outside(data: Dictionary, direction: Vector3) -> void:
	if str(data.get("slot_kind", "")) != "cargo":
		return
	_submit({
		"action": "drop",
		"cargo_slot": int(data.get("slot_index", -1)),
		"direction": direction,
	})


func apply_authoritative_result(result: Dictionary) -> void:
	if int(result.get("peer_id", 0)) != player.authority_peer_id:
		CARGO_CAR_DEBUG.log(
			"UI result ignored peer=%d expected=%d action=%s"
			% [int(result.get("peer_id", 0)), player.authority_peer_id, str(result.get("action", ""))]
		)
		return
	CARGO_CAR_DEBUG.log(
		"UI result player=%s peer=%d vehicle=%s action=%s ok=%s reason=%s"
		% [player.name, player.authority_peer_id, vehicle_id, str(result.get("action", "")), bool(result.get("ok", false)), str(result.get("reason", ""))]
	)
	if not bool(result.get("ok", false)):
		_notice.text = _reason_text(str(result.get("reason", "rejected")))
		if str(result.get("action", "")) == "open":
			close()
		return
	_notice.text = ""
	var slots_value: Variant = result.get("player_slots", [])
	if slots_value is Array:
		player.apply_cargo_backpack_slots(slots_value as Array)
	var manifest_value: Variant = result.get("cargo_manifest", [])
	manifest.clear()
	if manifest_value is Array:
		for value: Variant in manifest_value:
			manifest.append((value as Dictionary).duplicate(true) if value is Dictionary else {})
	available_slots = int(result.get("available_slots", 12))
	_refresh()


func can_drop(target_kind: String, target_index: int, data: Dictionary) -> bool:
	var source_kind := str(data.get("slot_kind", ""))
	var source_index := int(data.get("slot_index", -1))
	if target_kind == "cargo":
		if data.get("backpack") != player.player_backpack or source_kind != "inventory":
			return false
		return target_index >= 0 and target_index < available_slots \
			and target_index < manifest.size() and manifest[target_index].is_empty() \
			and str(player.get_backpack_item(source_index).get("kind", "")) == "cargo_crate"
	return target_kind == "player" and data.get("cargo_page") == self \
		and source_kind == "cargo" \
		and target_index >= 0 and target_index < player.get_active_bag_slot_count() \
		and player.get_backpack_item(target_index).is_empty() \
		and source_index >= 0 and source_index < manifest.size() and not manifest[source_index].is_empty()


func drop_item(target_kind: String, target_index: int, data: Dictionary) -> void:
	var source_kind := str(data.get("slot_kind", ""))
	var source_index := int(data.get("slot_index", -1))
	if target_kind == "cargo" and source_kind == "inventory" \
			and data.get("backpack") == player.player_backpack:
		_submit({"action": "load", "player_slot": source_index, "cargo_slot": target_index})
	elif target_kind == "player" and source_kind == "cargo":
		_submit({"action": "unload", "cargo_slot": source_index, "player_slot": target_index})


func _submit(extra: Dictionary) -> void:
	if not is_instance_valid(player):
		CARGO_CAR_DEBUG.log("submit ignored: player is invalid action=%s" % str(extra.get("action", "")))
		return
	var action := {"station_kind": "cargo_car", "vehicle_id": vehicle_id}
	action.merge(extra, true)
	if GameAuthority.should_send_network_requests():
		CARGO_CAR_DEBUG.log(
			"submit network player=%s peer=%d action=%s vehicle_id=%s"
			% [player.name, player.authority_peer_id, str(action.get("action", "")), vehicle_id]
		)
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		CARGO_CAR_DEBUG.log(
			"submit local player=%s peer=%d action=%s vehicle_id=%s"
			% [player.name, player.authority_peer_id, str(action.get("action", "")), vehicle_id]
		)
		apply_authoritative_result(GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action))


func _refresh() -> void:
	for child in _cargo_grid.get_children():
		child.queue_free()
	for index in range(12):
		var slot := CargoInventorySlot.new()
		_cargo_grid.add_child(slot)
		slot.setup(self, "cargo", index)
		slot.set_item(manifest[index] if index < manifest.size() else {}, index >= available_slots)
	var count := 0
	var weight := 0.0
	for crate: Dictionary in manifest:
		if not crate.is_empty():
			count += 1
			weight += float(crate.get("total_weight_kg", crate.get("weight_kg", 0.0)))
	_count_label.text = "货箱  %d / 12    可用槽位 %d / 12" % [count, available_slots]
	_weight_label.text = "载重  %.1f / %.1f kg" % [weight, vehicle.get_cargo_capacity_kg() if is_instance_valid(vehicle) else 480.0]


func _reason_text(reason: String) -> String:
	return {
		"cargo_overweight": "超过载具最大载重量",
		"cargo_slot_damaged": "该槽位已因载具损坏而禁用",
		"invalid_cargo_crate": "货运库只能放置货运箱",
		"station_in_use": "另一名玩家正在使用货运库",
		"vehicle_out_of_range": "距离货运车过远",
		"personal_bag_full": "玩家背包无法容纳该货箱",
	}.get(reason, "操作失败：%s" % reason)
