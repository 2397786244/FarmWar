extends Node3D

const SHIELD_SCENE := preload("res://character/weapons/MedievalShield.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")

const ATTACKER_PEER_ID := 1
const TARGET_PEER_ID := 2
const TARGET_POSITION := Vector3(0.0, 0.0, -3.0)
const SHIELD_SLOT_INDEX := 0
const SECOND_SHIELD_SLOT_INDEX := 2

var failures := 0
var hit_confirmations: Array[Dictionary] = []
var shield_break_events: Array[Dictionary] = []
var presentation_player: GamePlayer


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_scene_and_configuration()
	GameAuthority.start_local_mode({
		"display_name": "ShieldAttacker",
		"team": "red",
		"primary_weapon_ids": ["long_spear"],
		"special_tool_ids": [],
		"current_tool_index": 0,
		"current_tool_id": "long_spear",
		"position": Vector3.ZERO,
	})
	if not GameAuthority.reliable_world_event_ready.is_connected(_capture_reliable_event):
		GameAuthority.reliable_world_event_ready.connect(_capture_reliable_event)
	GameAuthority.set_physics_process(false)
	GameAuthority.register_or_update_player(TARGET_PEER_ID, {
		"display_name": "ShieldTarget",
		"team": "blue",
		"primary_weapon_ids": ["medieval_shield", "medieval_shield"],
		"special_tool_ids": [],
		"current_tool_index": SHIELD_SLOT_INDEX,
		"current_tool_id": "medieval_shield",
		"position": TARGET_POSITION,
		"backpack_slot_items": _shield_slots(1000.0),
	})
	presentation_player = PLAYER_SCENE.instantiate() as GamePlayer
	presentation_player.authority_peer_id = ATTACKER_PEER_ID
	presentation_player.team = "red"
	add_child(presentation_player)
	await get_tree().process_frame
	presentation_player.global_position = Vector3.ZERO
	presentation_player.set_physics_process(false)
	_check(is_instance_valid(presentation_player.hit_marker), "single-player player has the existing hit marker")
	GameAuthority.call("_ensure_player_physics_node", ATTACKER_PEER_ID, Vector3.ZERO)
	GameAuthority.call("_ensure_player_physics_node", TARGET_PEER_ID, TARGET_POSITION)

	var projectile_result := GameAuthority.call(
		"_server_hitscan",
		ATTACKER_PEER_ID,
		_hitscan_request(),
		20.0,
		30.0,
		0.0,
		"nail",
		true
	) as Dictionary
	_check(str(projectile_result.get("hit_kind", "")) == "shield", "hitscan resolves the held shield before the player")
	_check(_target_hp() == 200.0, "bullet damage is fully blocked while shield HP remains")
	_check(is_equal_approx(_shield_hp(), 970.0), "bullet damage reduces shield HP by the incoming amount")
	_check(_last_confirmation_source() == "shield", "shield hit uses the existing hit confirmation event")
	var layout_result := GameAuthority.server_inventory_layout_action(TARGET_PEER_ID, {
		"slots": (GameAuthority.player_states[TARGET_PEER_ID].get("backpack_slot_items", []) as Array).duplicate(true),
		"selected_slot": SHIELD_SLOT_INDEX,
		"selected_id": "medieval_shield",
	})
	_check(bool(layout_result.get("ok", false)) and is_equal_approx(_shield_hp(), 970.0),
		"inventory layout synchronization preserves authoritative shield HP")
	await get_tree().process_frame
	_check(presentation_player.hit_marker.visible, "shield hit keeps the existing red hit marker visible")

	var idle_hp := _shield_hp()
	for _frame in range(3):
		await get_tree().physics_frame
	_check(is_equal_approx(_shield_hp(), idle_hp), "holding a shield without an attack does not cause static damage")

	_reset_target(1000.0, 200.0, Vector3(0.0, 0.0, -1.5), PI)
	hit_confirmations.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var melee_result := GameAuthority.call(
		"_server_long_spear",
		ATTACKER_PEER_ID,
		{
			"tool_id": "long_spear",
			"tool_index": 0,
			"melee_center": Vector3(0.0, 1.2, -1.35),
			"origin": Vector3(0.0, 1.2, 0.0),
			"direction": Vector3(0.0, 0.0, -1.0),
		}
	) as Dictionary
	_check(int(melee_result.get("target_count", 0)) == 1, "melee damage is intercepted by the held shield")
	_check(_target_hp() == 200.0 and is_equal_approx(_shield_hp(), 980.0),
		"melee damage is absorbed by the shield without damaging player HP")

	_reset_target(1000.0, 200.0, TARGET_POSITION, PI)
	var front_bear_blocked := GameAuthority.damage_player_from_wild_animal(
		TARGET_PEER_ID,
		Vector3(0.0, 0.0, 0.0),
		50.0,
		4.0,
		Vector3(0.0, 0.0, -1.0)
	)
	_check(front_bear_blocked, "BlackBear front attack is intercepted by the shield")
	_check(_target_hp() == 200.0 and is_equal_approx(_shield_hp(), 950.0),
		"BlackBear front attack is fully blocked and only damages shield HP")

	_reset_target(1000.0, 200.0, TARGET_POSITION, PI)
	var rear_bear_hit := GameAuthority.damage_player_from_wild_animal(
		TARGET_PEER_ID,
		Vector3(0.0, 0.0, -8.0),
		50.0,
		8.0,
		Vector3(0.0, 0.0, 1.0)
	)
	_check(rear_bear_hit, "BlackBear rear attack still reaches the player")
	_check(is_equal_approx(_shield_hp(), 1000.0) and is_equal_approx(_target_hp(), 150.0),
		"BlackBear rear attack bypasses shield protection")

	_reset_target(1000.0, 200.0, TARGET_POSITION, PI)
	hit_confirmations.clear()
	var front_projectile_id := 91001
	GameAuthority.projectile_states[front_projectile_id] = _explosion_state()
	GameAuthority.call("_explode_projectile", front_projectile_id, Vector3(0.0, 0.0, 0.0), TARGET_PEER_ID, true)
	_check(is_equal_approx(_shield_hp(), 920.0), "front explosion makes the shield absorb 80 percent of blast damage")
	_check(is_equal_approx(_target_hp(), 180.0), "front explosion leaves 20 percent of blast damage for the player")

	_reset_target(1000.0, 200.0, TARGET_POSITION, PI)
	hit_confirmations.clear()
	var back_projectile_id := 91002
	GameAuthority.projectile_states[back_projectile_id] = _explosion_state()
	GameAuthority.call("_explode_projectile", back_projectile_id, Vector3(0.0, 0.0, -8.0), TARGET_PEER_ID, true)
	_check(is_equal_approx(_shield_hp(), 1000.0), "back explosion does not consume shield HP")
	_check(is_equal_approx(_target_hp(), 100.0), "back explosion receives no shield protection")

	_reset_target(10.0, 200.0, TARGET_POSITION, PI)
	hit_confirmations.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var break_result := GameAuthority.call(
		"_server_hitscan",
		ATTACKER_PEER_ID,
		_hitscan_request(),
		20.0,
		30.0,
		0.0,
		"nail",
		true
	) as Dictionary
	_check(str(break_result.get("hit_kind", "")) == "shield", "last shield HP still blocks the breaking bullet")
	_check(_shield_hp() == 0.0, "shield reaches zero HP")
	_check(_slot_item(SHIELD_SLOT_INDEX).is_empty(), "broken shield is removed from the currently held backpack slot")
	_check(str(_slot_item(SECOND_SHIELD_SLOT_INDEX).get("tool_id", "")) == "medieval_shield",
		"breaking the held shield does not remove a second shield in the backpack")
	_check(not shield_break_events.is_empty(), "shield break emits a reliable visual event")
	var break_position: Variant = shield_break_events.back().get("position", null) \
		if not shield_break_events.is_empty() else null
	_check(break_position is Vector3, "shield break event carries the held shield position")
	if break_position is Vector3:
		var break_particles := GameAuthority.spawn_shield_break_effect(
			break_position as Vector3,
			float(shield_break_events.back().get("particle_scale", 1.8))
		)
		_check(is_instance_valid(break_particles), "shield break spawns the brown fragment particle effect")
		_check(
			is_instance_valid(break_particles)
				and break_particles.is_in_group("shield_break_effects")
				and is_equal_approx(float(break_particles.get_meta("shield_break_particle_scale", 0.0)), 1.8),
			"shield break particle effect uses the enlarged fragment scale"
		)
		if is_instance_valid(break_particles):
			break_particles.queue_free()

	if failures == 0:
		print("[MedievalShieldValidation] PASS all checks")
	else:
		push_error("[MedievalShieldValidation] FAIL count=%d" % failures)
	GameAuthority.stop_authority()
	GameAuthority.set_physics_process(true)
	get_tree().quit(0 if failures == 0 else 1)


func _validate_scene_and_configuration() -> void:
	var shield := SHIELD_SCENE.instantiate() as Node3D
	_check(shield != null, "MedievalShield scene loads")
	if shield == null:
		return
	add_child(shield)
	var absorb_area := shield.find_child("AbsorbArea", true, false) as Area3D
	var collision := absorb_area.find_child("CollisionShape3D", true, false) as CollisionShape3D \
		if absorb_area != null else null
	_check(absorb_area != null, "AbsorbArea is found recursively")
	_check(collision != null and collision.shape is ConcavePolygonShape3D,
		"AbsorbArea has its authored collision shape")
	_check(absorb_area != null and not absorb_area.monitoring and not absorb_area.monitorable,
		"AbsorbArea does not continuously apply damage")
	_check(is_equal_approx(CombatBalance.get_float("medieval_shield", "max_hp"), 1000.0),
		"shield max HP is 1000")
	var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get("medieval_shield", {})
	_check(str(definition.get("category", "")) == "shield", "shield is registered as a passive shield tool")
	_check(not definition.has("magazine_size"), "shield has no ammunition state")
	_check(not bool(definition.get("show_crosshair", true)), "shield does not show a firing crosshair")
	shield.queue_free()


func _shield_slots(hp: float) -> Array:
	var slots: Array = []
	slots.resize(12)
	for index in range(slots.size()):
		slots[index] = {}
	slots[SHIELD_SLOT_INDEX] = {
		"kind": "tool",
		"tool_id": "medieval_shield",
		"shield_instance_id": "test-shield-current",
		"current_hp": hp,
		"max_hp": 1000.0,
	}
	slots[SECOND_SHIELD_SLOT_INDEX] = {
		"kind": "tool",
		"tool_id": "medieval_shield",
		"shield_instance_id": "test-shield-spare",
		"current_hp": 1000.0,
		"max_hp": 1000.0,
	}
	return slots


func _reset_target(hp: float, player_hp: float, position: Vector3, yaw: float) -> void:
	var state: Dictionary = GameAuthority.player_states[TARGET_PEER_ID]
	state["hp"] = player_hp
	state["position"] = position
	state["yaw"] = yaw
	state["pitch"] = 0.0
	state["current_tool_index"] = SHIELD_SLOT_INDEX
	state["current_tool_id"] = "medieval_shield"
	state["backpack_slot_items"] = _shield_slots(hp)
	GameAuthority.player_states[TARGET_PEER_ID] = state
	var proxy: Node3D = GameAuthority.player_physics_nodes.get(TARGET_PEER_ID, null) as Node3D
	if proxy != null and is_instance_valid(proxy):
		proxy.global_position = position


func _hitscan_request() -> Dictionary:
	return {
		"tool_id": "m4",
		"tool_index": 0,
		"origin": Vector3(0.0, 1.2, 0.0),
		"direction": Vector3(0.0, 0.0, -1.0),
	}


func _explosion_state() -> Dictionary:
	return {
		"type": "boom",
		"team": "red",
		"owner_peer_id": ATTACKER_PEER_ID,
		"radius": 6.0,
		"damage": 100.0,
		"knockback": 0.0,
		"effect": "Explosion",
		"show_owner_hit_marker": true,
	}


func _slot_item(index: int) -> Dictionary:
	var slots_value: Variant = GameAuthority.player_states[TARGET_PEER_ID].get("backpack_slot_items", [])
	if not slots_value is Array or index < 0 or index >= (slots_value as Array).size():
		return {}
	var item_value: Variant = (slots_value as Array)[index]
	return item_value as Dictionary if item_value is Dictionary else {}


func _shield_hp() -> float:
	return float(_slot_item(SHIELD_SLOT_INDEX).get("current_hp", 0.0))


func _target_hp() -> float:
	return float(GameAuthority.player_states[TARGET_PEER_ID].get("hp", 0.0))


func _capture_reliable_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "hit_confirmed":
		hit_confirmations.append(event.duplicate(true))
	elif str(event.get("type", "")) == "shield_broken":
		shield_break_events.append(event.duplicate(true))


func _last_confirmation_source() -> String:
	return str(hit_confirmations.back().get("source", "")) if not hit_confirmations.is_empty() else ""


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[MedievalShieldValidation] PASS " + label)
	else:
		failures += 1
		push_error("[MedievalShieldValidation] FAIL " + label)
