extends Node3D

var _failed := false


func _ready() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var proxy := (load("res://character/player.tscn") as PackedScene).instantiate() as GamePlayer
	proxy.is_remote_proxy = true
	proxy.authority_peer_id = 88
	add_child(proxy)
	await get_tree().process_frame
	proxy.configure_remote_proxy(88, {
		"peer_id": 88,
		"team": "blue",
		"hero_id": "farmer",
		"primary_weapon_ids": ["rubber_revolver"],
		"special_tool_ids": [],
	})
	_check(not is_instance_valid(proxy.tool_node), "remote loadout does not imply a held weapon")
	proxy.apply_remote_tool_selection(0, "rubber_revolver")
	_check(is_instance_valid(proxy.tool_node), "authoritative weapon selection creates remote model")
	proxy.apply_remote_tool_selection(0, "")
	_check(not is_instance_valid(proxy.tool_node), "authoritative empty selection clears remote weapon")
	_check(proxy._selected_tool_id().is_empty(), "empty remote hand reports an empty replication id")

	var original_mode := GameAuthority.mode
	var original_states := GameAuthority.player_states.duplicate(true)
	GameAuthority.mode = GameAuthority.MODE_SERVER
	var slots: Array[Dictionary] = []
	slots.resize(GameAuthority.BASE_PLAYER_BAG_SLOTS)
	for index in range(slots.size()):
		slots[index] = {}
	slots[1] = {"kind": "tool", "tool_id": "rubber_revolver"}
	GameAuthority.player_states[88] = {
		"peer_id": 88,
		"team": "blue",
		"respawn_left": 0.0,
		"primary_weapon_ids": ["rubber_revolver"],
		"special_tool_ids": [],
		"owned_equipment_ids": [],
		"personal_ingredients": {},
		"personal_dishes": {},
		"personal_dish_weights": {},
		"backpack_slot_items": slots.duplicate(true),
		"backpack_layout_valid": true,
		"current_tool_index": 0,
		"current_tool_id": "rubber_revolver",
	}
	var result := GameAuthority.server_inventory_layout_action(88, {
		"slots": slots,
		"selected_slot": 0,
		"selected_id": "",
	})
	_check(bool(result.get("ok", false)), "server accepts synchronized backpack layout")
	var state: Dictionary = GameAuthority.player_states.get(88, {})
	_check(str(state.get("current_tool_id", "")).is_empty(), "empty selected slot clears authoritative held item")

	proxy.queue_free()
	GameAuthority.player_states = original_states
	GameAuthority.mode = original_mode
	await get_tree().process_frame
	await get_tree().process_frame
	print("Remote handheld sync validation: %s" % ("FAILED" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failed = true
		push_error("[FAIL] %s" % message)
