extends Control
class_name IngredientPickupPage

const INTERACTION_DISTANCE := 4.0
const STORAGE_SLOT_COUNT := 96
const STORAGE_BACKPACK_OFFSETS := Rect2(-910.0, -500.0, 940.0, 680.0)

@onready var window: PanelContainer = $Window
@onready var status_label: Label = $Window/Margin/VBox/Status
@onready var storage_grid: GridContainer = $Window/Margin/VBox/StorageScroll/StorageGrid

var player: GamePlayer
var pickup: IngredientPickup
var acquired := false
var storage_buttons: Dictionary = {}
var last_ui_activity_msec := 0
var last_lock_heartbeat_msec := 0


func _ready() -> void:
	window.visible = false
	$Window/Margin/VBox/CloseButton.pressed.connect(close)
	if not GlobalVar.storage_changed.is_connected(_on_storage_changed):
		GlobalVar.storage_changed.connect(_on_storage_changed)
	_build_storage_grid()


func is_open() -> bool:
	return window.visible


func _process(_delta: float) -> void:
	if not is_open():
		return
	if player.is_respawning or _is_out_of_interaction_range() \
			or Time.get_ticks_msec() - last_ui_activity_msec >= KitchenAppliance.USER_LOCK_TIMEOUT_MSEC:
		close()
		return
	if Time.get_ticks_msec() - last_lock_heartbeat_msec >= 10000:
		_send_lock_heartbeat()


func open_for(next_pickup: IngredientPickup, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_pickup) or not is_instance_valid(next_player):
		return
	pickup = next_pickup
	player = next_player
	acquired = false
	window.visible = true
	_touch_ui_activity()
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.show_companion(self, STORAGE_BACKPACK_OFFSETS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = "正在取得库存存取台使用权..."
	_request_action("acquire")
	_refresh()


func close() -> void:
	if not is_open():
		return
	_request_action("release")
	window.visible = false
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.hide_companion()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func contains_storage_screen_point(screen_point: Vector2) -> bool:
	return is_open() and window.get_global_rect().has_point(screen_point)


func apply_authoritative_action_result(result: Dictionary) -> void:
	if not is_open() or not is_instance_valid(player) \
			or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	var action_name := str(result.get("action", ""))
	if not bool(result.get("ok", false)):
		if action_name == "acquire":
			acquired = false
		status_label.text = _reason_text(str(result.get("reason", "操作失败")))
		return
	if action_name == "acquire":
		acquired = true
		status_label.text = ""
	elif action_name in ["withdraw", "deposit"]:
		var slots_value: Variant = result.get("player_slots", null)
		if slots_value is Array:
			player.apply_cargo_backpack_slots(slots_value as Array)
		status_label.text = "已领取物资。" if action_name == "withdraw" else "已存入队伍库存。"
	_refresh()


func _build_storage_grid() -> void:
	for child in storage_grid.get_children():
		storage_grid.remove_child(child)
		child.queue_free()
	storage_buttons.clear()
	var entries: Array[Dictionary] = []
	if is_instance_valid(player) and GlobalVar.team_storage.has(player.team):
		var team_data: Dictionary = GlobalVar.team_storage[player.team]
		for item_id_value: Variant in team_data.keys():
			var item_id := str(item_id_value)
			if item_id == "money" or float(team_data.get(item_id_value, 0.0)) <= 0.0001:
				continue
			if not DishCatalog.get_definition(item_id).is_empty():
				entries.append({"kind": "dish", "id": item_id})
			elif not IngredientCatalog.get_definition(item_id).is_empty():
				entries.append({"kind": "ingredient", "id": item_id})
	entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return _storage_display_name(first) < _storage_display_name(second)
	)
	for index in range(STORAGE_SLOT_COUNT):
		if index < entries.size():
			_add_product_slot(str(entries[index]["kind"]), str(entries[index]["id"]))
		else:
			var empty_slot := IngredientStorageGridSlot.new()
			empty_slot.setup_empty(self)
			storage_grid.add_child(empty_slot)


func _add_product_slot(item_kind: String, item_id: String) -> void:
	var slot := IngredientStorageGridSlot.new()
	slot.setup(self, item_kind, item_id)
	storage_grid.add_child(slot)
	storage_buttons["%s:%s" % [item_kind, item_id]] = slot


func _refresh() -> void:
	if not is_instance_valid(player):
		return
	_build_storage_grid()
	for storage_key_value: Variant in storage_buttons:
		var slot := storage_buttons[str(storage_key_value)] as IngredientStorageGridSlot
		if slot != null:
			slot.set_amount(GlobalVar.check_team_item_amount(player.team, slot.item_id), false)
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.refresh()


func _storage_display_name(entry: Dictionary) -> String:
	var item_kind := str(entry.get("kind", ""))
	var item_id := str(entry.get("id", ""))
	var definition := DishCatalog.get_definition(item_id) if item_kind == "dish" \
		else IngredientCatalog.get_definition(item_id)
	return str(definition.get("display_name", item_id))


func make_storage_drag_data(item_kind: String, item_id: String, one_unit: bool) -> Dictionary:
	if not acquired or not is_instance_valid(player):
		return {}
	var available := GlobalVar.check_team_item_amount(player.team, item_id)
	if available <= 0.0001:
		return {}
	var amount := available
	var item: Dictionary
	if item_kind == "dish":
		var definition := DishCatalog.get_definition(item_id)
		if definition.is_empty():
			return {}
		amount = 1.0 if one_unit else floorf(available)
		item = {
			"kind": "dish", "dish_id": item_id, "servings": roundi(amount),
			"weight_kg": float(definition.get("serving_weight_kg", 0.0)) * amount,
			"display_name": str(definition.get("display_name", item_id)),
		}
	else:
		var definition := IngredientCatalog.get_definition(item_id)
		if definition.is_empty():
			return {}
		amount = minf(IngredientCatalog.get_pickup_unit_kg(item_id), available) if one_unit else available
		item = {
			"kind": "ingredient", "ingredient_id": item_id, "is_chopped": false,
			"weight_kg": amount, "display_name": str(definition.get("display_name", item_id)),
		}
	return {
		"unit_weight_transfer": one_unit,
		"unit_weight_kg": UnitWeightItem.get_weight_kg(item),
		"unit_item": item,
		"companion_page": self,
		"slot_kind": "storage",
		"slot_index": -1,
		"item_kind": item_kind,
		"item_id": item_id,
		"amount": amount,
	}


func can_drop(target_kind: String, target_index: int, data: Dictionary) -> bool:
	if not acquired or not is_instance_valid(player):
		return false
	var source_kind := str(data.get("slot_kind", ""))
	if target_kind == "storage":
		if data.get("backpack") != player.player_backpack or source_kind != "inventory":
			return false
		var source_index := int(data.get("slot_index", -1))
		return source_index >= 0 and _is_storable_item(player.get_backpack_item(source_index))
	if target_kind != "player" or data.get("companion_page") != self or source_kind != "storage":
		return false
	if target_index < 0 or target_index >= player.get_active_bag_slot_count():
		return false
	var item: Dictionary = data.get("unit_item", {}) as Dictionary
	var target_item := player.get_backpack_item(target_index)
	return (target_item.is_empty() or UnitWeightItem.can_merge(target_item, item)) and _can_player_accept_item(item)


func drop_item(target_kind: String, target_index: int, data: Dictionary) -> void:
	if not can_drop(target_kind, target_index, data):
		return
	_touch_ui_activity()
	if target_kind == "storage":
		var source_item := player.get_backpack_item(int(data.get("slot_index", -1)))
		var amount := _item_storage_amount(data.get("unit_item", {}) as Dictionary) \
			if bool(data.get("unit_weight_transfer", false)) else _item_storage_amount(source_item)
		_request_action(
			"deposit", str(source_item.get("kind", "")),
			str(source_item.get("dish_id", source_item.get("ingredient_id", ""))), amount
		)
	else:
		_request_action(
			"withdraw", str(data.get("item_kind", "")), str(data.get("item_id", "")),
			float(data.get("amount", 0.0)), target_index
		)


func _is_storable_item(item: Dictionary) -> bool:
	if str(item.get("kind", "")) == "dish":
		return not DishCatalog.get_definition(str(item.get("dish_id", ""))).is_empty()
	if str(item.get("kind", "")) != "ingredient":
		return false
	var is_chopped := bool(item.get("is_chopped", false)) \
		or str(item.get("preparation", "")) == "chopped" \
		or str(item.get("model_state", "")) == "chopped"
	return not is_chopped and not IngredientCatalog.get_definition(str(item.get("ingredient_id", ""))).is_empty()


func _item_storage_amount(item: Dictionary) -> float:
	return float(item.get("servings", 0)) if str(item.get("kind", "")) == "dish" \
		else float(item.get("weight_kg", 0.0))


func _can_player_accept_item(item: Dictionary) -> bool:
	if str(item.get("kind", "")) == "dish":
		return player.can_add_personal_dish(
			str(item.get("dish_id", "")), int(item.get("servings", 0)), float(item.get("weight_kg", 0.0))
		)
	return player.can_add_personal_ingredient(
		str(item.get("ingredient_id", "")), float(item.get("weight_kg", 0.0)), false
	)


func _request_action(
	action_name: String, item_kind := "", item_id := "", amount := 0.0, player_slot := -1
) -> void:
	if not is_instance_valid(pickup) or not is_instance_valid(player):
		return
	if action_name != "release":
		_touch_ui_activity()
	var action := {
		"action": action_name,
		"item_kind": item_kind,
		"item_id": item_id,
		"amount": amount,
		"player_slot": player_slot,
		"station_path": str(pickup.get_path()),
		"station_position": pickup.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	elif GameAuthority.is_local_authority():
		apply_authoritative_action_result(
			GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
		)


func _touch_ui_activity() -> void:
	last_ui_activity_msec = Time.get_ticks_msec()


func _send_lock_heartbeat() -> void:
	last_lock_heartbeat_msec = Time.get_ticks_msec()
	_request_action("acquire")


func _on_storage_changed(team: String, _item_id: String, _amount: float) -> void:
	if is_open() and is_instance_valid(player) and team == player.team:
		_refresh()


func _reason_text(reason: String) -> String:
	match reason:
		"station_in_use": return "库存存取台正在被另一名玩家使用。"
		"personal_bag_full": return "个人背包格子已满或载重量不足。"
		"team_storage_insufficient": return "队伍库存数量不足。"
		"personal_item_insufficient": return "个人背包中的物资数量不足。"
		"invalid_storage_item": return "该物品不能存入库存存取台。"
		_: return reason


func _is_out_of_interaction_range() -> bool:
	return not is_instance_valid(player) or not is_instance_valid(pickup) \
		or Vector2(player.global_position.x, player.global_position.z).distance_to(
			Vector2(pickup.global_position.x, pickup.global_position.z)
		) > INTERACTION_DISTANCE
