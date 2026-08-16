extends Node

const BOX_ID := "ammo_supply_box"
const BOX_CAPACITY := 200
const WEAPON_ID := "m4"

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var box_definition: Dictionary = GameAuthority.authoritative_tool_definitions.get(BOX_ID, {})
	_check(not box_definition.is_empty(), "AmmoSupplyBox is in the authoritative tool definitions")
	_check(str(box_definition.get("path", "")) == "res://assets/other_items/weapons/AmmoSupplyBox.glb", "AmmoSupplyBox uses the supplied GLB")
	var box_scene := load(str(box_definition.get("path", ""))) as PackedScene
	_check(box_scene != null, "AmmoSupplyBox GLB loads as a PackedScene")
	if box_scene != null:
		var box_node := box_scene.instantiate()
		_check(box_node is Node3D, "AmmoSupplyBox can instantiate as a Node3D")
		if box_node != null:
			box_node.free()

	var slots: Array[Dictionary] = []
	for _index in range(GameAuthority.BASE_PLAYER_BAG_SLOTS):
		slots.append({})
	slots[0] = {"kind": "tool", "tool_id": WEAPON_ID}
	slots[1] = {"kind": "tool", "tool_id": BOX_ID, "ammo_remaining": BOX_CAPACITY}
	GameAuthority.start_local_mode({
		"display_name": "AmmoValidation",
		"team": "red",
		"position": Vector3.ZERO,
		"primary_weapon_ids": [WEAPON_ID],
		"special_tool_ids": [BOX_ID],
		"backpack_slot_items": slots,
		"current_tool_index": 0,
		"current_tool_id": WEAPON_ID,
	})
	GameAuthority.set_physics_process(false)
	var state: Dictionary = GameAuthority.player_states.get(GameAuthority.LOCAL_PLAYER_ID, {})
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var ammo_state: Dictionary = ammo_states.get(WEAPON_ID, {})
	_check(int(ammo_state.get("ammo_in_mag", 0)) == 45, "new weapon starts with one full magazine")
	_check(int(ammo_state.get("reserve_ammo", -1)) == 0, "new weapon has no free reserve ammunition")
	var state_slots: Array = state.get("backpack_slot_items", [])
	var box_item: Dictionary = state_slots[1] as Dictionary if state_slots.size() > 1 else {}
	_check(int(box_item.get("ammo_remaining", 0)) == BOX_CAPACITY, "AmmoSupplyBox starts with 200 rounds")

	ammo_state["ammo_in_mag"] = 15
	ammo_states[WEAPON_ID] = ammo_state
	state["weapon_ammo_states"] = ammo_states
	GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] = state
	var reload_result := GameAuthority.server_reload_weapon(GameAuthority.LOCAL_PLAYER_ID, WEAPON_ID)
	_check(bool(reload_result.get("ok", false)), "reload accepts a non-empty AmmoSupplyBox")
	state = GameAuthority.player_states.get(GameAuthority.LOCAL_PLAYER_ID, {})
	GameAuthority.call("_tick_weapon_reloads", GameAuthority.LOCAL_PLAYER_ID, state, 3.0)
	ammo_states = state.get("weapon_ammo_states", {})
	ammo_state = ammo_states.get(WEAPON_ID, {})
	state_slots = state.get("backpack_slot_items", [])
	box_item = state_slots[1] as Dictionary if state_slots.size() > 1 else {}
	_check(int(ammo_state.get("ammo_in_mag", 0)) == 45, "reload fills the magazine from the box")
	_check(int(ammo_state.get("reserve_ammo", -1)) == 0, "reload does not recreate a reserve ammo pool")
	_check(int(box_item.get("ammo_remaining", BOX_CAPACITY)) == 170, "reload consumes exactly the missing 30 rounds")

	box_item["ammo_remaining"] = 15
	state_slots[1] = box_item
	state_slots[2] = {
		"kind": "tool",
		"tool_id": BOX_ID,
		"ammo_capacity": BOX_CAPACITY,
		"ammo_remaining": BOX_CAPACITY,
	}
	state["backpack_slot_items"] = state_slots
	GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] = state
	ammo_state["ammo_in_mag"] = 15
	ammo_states[WEAPON_ID] = ammo_state
	state["weapon_ammo_states"] = ammo_states
	var multi_box_reload := GameAuthority.server_reload_weapon(GameAuthority.LOCAL_PLAYER_ID, WEAPON_ID)
	_check(bool(multi_box_reload.get("ok", false)), "reload accepts multiple AmmoSupplyBoxes")
	GameAuthority.call("_tick_weapon_reloads", GameAuthority.LOCAL_PLAYER_ID, state, 3.0)
	state = GameAuthority.player_states.get(GameAuthority.LOCAL_PLAYER_ID, {})
	ammo_states = state.get("weapon_ammo_states", {})
	ammo_state = ammo_states.get(WEAPON_ID, {})
	state_slots = state.get("backpack_slot_items", [])
	var depleted_small_box: Dictionary = state_slots[1] as Dictionary if state_slots.size() > 1 else {}
	var remaining_large_box: Dictionary = state_slots[2] as Dictionary if state_slots.size() > 2 else {}
	_check(int(ammo_state.get("ammo_in_mag", 0)) == 45, "multiple boxes fill the magazine")
	_check(int(depleted_small_box.get("ammo_remaining", -1)) == 0, "the smallest box is consumed first")
	_check(int(remaining_large_box.get("ammo_remaining", -1)) == 185, "the second box supplies the remainder")

	depleted_small_box["ammo_remaining"] = 0
	remaining_large_box["ammo_remaining"] = 0
	state_slots[1] = depleted_small_box
	state_slots[2] = remaining_large_box
	state["backpack_slot_items"] = state_slots
	GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] = state
	ammo_state["ammo_in_mag"] = 10
	ammo_states[WEAPON_ID] = ammo_state
	state["weapon_ammo_states"] = ammo_states
	var empty_reload := GameAuthority.server_reload_weapon(GameAuthority.LOCAL_PLAYER_ID, WEAPON_ID)
	_check(not bool(empty_reload.get("ok", false)) and str(empty_reload.get("reason", "")) == "no_ammo_supply_box", "empty boxes cannot start a reload")
	ammo_state["ammo_in_mag"] = 0
	ammo_states[WEAPON_ID] = ammo_state
	state["weapon_ammo_states"] = ammo_states
	GameAuthority.call("_sync_weapon_ammo_states_to_backpack_slots", state)
	var saved_selection := {
		"peer_id": 2,
		"display_name": "AmmoPersistenceValidation",
		"team": "red",
		"primary_weapon_ids": [WEAPON_ID],
		"special_tool_ids": [BOX_ID],
		"backpack_slot_items": (state.get("backpack_slot_items", []) as Array).duplicate(true),
		"weapon_ammo_states": ammo_states.duplicate(true),
		"position": Vector3.ZERO,
	}
	GameAuthority.register_or_update_player(2, saved_selection)
	var restored_state: Dictionary = GameAuthority.player_states.get(2, {})
	var restored_ammo_states: Dictionary = restored_state.get("weapon_ammo_states", {})
	var restored_ammo: Dictionary = restored_ammo_states.get(WEAPON_ID, {})
	var restored_slots: Array = restored_state.get("backpack_slot_items", [])
	var restored_weapon_slot: Dictionary = restored_slots[0] as Dictionary if not restored_slots.is_empty() else {}
	_check(int(restored_ammo.get("ammo_in_mag", -1)) == 0, "saved empty magazine is not refilled on restore")
	_check(int(restored_weapon_slot.get("ammo_in_mag", -1)) == 0, "saved magazine count is synchronized into the backpack slot")
	var money_before := GlobalVar.check_team_item_amount("red", "money")
	var purchase := GameAuthority.server_shop_transaction(GameAuthority.LOCAL_PLAYER_ID, {
		"action": "trade", "item_id": BOX_ID, "amount": 1, "is_buy": true,
		"shop_category": "gun_store",
	})
	_check(bool(purchase.get("ok", false)), "gun store sells AmmoSupplyBox")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 200.0), "AmmoSupplyBox costs 200 team money")
	state = GameAuthority.player_states.get(GameAuthority.LOCAL_PLAYER_ID, {})
	var full_box_count := 0
	for item_value: Variant in state.get("backpack_slot_items", []):
		if item_value is Dictionary \
				and str((item_value as Dictionary).get("tool_id", "")) == BOX_ID \
				and int((item_value as Dictionary).get("ammo_remaining", 0)) == BOX_CAPACITY:
			full_box_count += 1
	_check(full_box_count == 1, "purchased AmmoSupplyBox contains 200 rounds")

	GameAuthority.stop_authority()
	if failures == 0:
		print("[AmmoSupplyBoxValidation] PASS all checks")
	else:
		push_error("[AmmoSupplyBoxValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[AmmoSupplyBoxValidation] PASS: %s" % message)
	else:
		failures += 1
		push_error("[AmmoSupplyBoxValidation] FAIL: %s" % message)
