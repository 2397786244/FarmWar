extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")

class AllDropModeManager:
	extends Node

	func get_death_drop_mode() -> String:
		return "all"


class AIRefreshProbe:
	extends RefCounted

	var observation: Dictionary

	func _init(target_observation: Dictionary) -> void:
		observation = target_observation

	func request_refresh(_immediate := false) -> void:
		observation["ai_refresh_called"] = true
		observation["respawn_event_preceded_ai_refresh"] = bool(
			observation.get("respawn_event_seen", false)
		)

	func get_sleeping_count() -> int:
		return 0


var failures := 0
var observed_respawn_player_index := -1
var observed_respawn_random_seed := 0


func get_team_spawn_position(_team: String, player_index: int, random_seed: int) -> Vector3:
	observed_respawn_player_index = player_index
	observed_respawn_random_seed = random_seed
	return Vector3(float(player_index), 1.0, 0.0)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene creates a GamePlayer")
	if player == null:
		_finish()
		return
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	# The local authority path owns the death camera and overlay in a normal
	# single-player/listen-server presentation.
	GameAuthority.mode = GameAuthority.MODE_LOCAL
	player.authority_peer_id = GameAuthority.local_player_id
	_check(
		player.appearance_player != null
			and player.appearance_player.has_animation(&"DeathFallForward"),
		"default hero provides DeathFallForward"
	)

	player.appearance_player.play(&"ShootOneHand")
	player.apply_respawn_state(10.0)
	_check(player.is_respawning, "respawn state enters the death presentation")
	_check(
		player.appearance_player.current_animation == &"DeathFallForward",
		"death animation replaces the firing animation immediately"
	)
	_check(player.get_node("AppearanceNode").visible, "corpse stays visible")
	_check(
		is_instance_valid(player.respawn_label)
			and player.respawn_label.visible
			and player.respawn_label.text == "你死了",
		"death UI shows only the large death message"
	)
	_check(
		is_instance_valid(player.respawn_overlay)
			and is_zero_approx(player.respawn_overlay.color.a),
		"death overlay remains transparent instead of black"
	)

	# Reproduce the tail of _use_current_tool(): its animation request must be
	# rejected after authoritative damage has already killed the shooter.
	player._play_character_animation(&"ShootOneHand")
	player._set_tool_action()
	_check(
		player.appearance_player.current_animation == &"DeathFallForward",
		"late firing animation cannot overwrite death animation"
	)
	player._play_death_animation()
	_check(
		player.death_animation_started
			and player.appearance_player.current_animation == &"DeathFallForward",
		"death animation starts exactly once during the death presentation"
	)

	player.respawn_left = 4.0
	player._update_death_appearance_visibility()
	player._update_respawn_overlay()
	_check(player.get_node("AppearanceNode").visible, "corpse remains visible near respawn")
	_check(player.respawn_label.visible, "death message remains visible near respawn")
	_check(is_zero_approx(player.respawn_overlay.color.a), "overlay stays transparent near respawn")

	player.apply_respawn_state(0.0, Vector3.ZERO)
	_check(not player.is_respawning, "respawn state exits normally")
	_check(not player.respawn_label.visible, "death message hides after respawn")

	# Reliable lifecycle events and Channel 0 world snapshots may arrive out of
	# order. A stale death state must not return the player to the death view
	# after a newer respawn was already accepted.
	player.apply_network_respawn_state(10.0, null, 100)
	_check(player.is_respawning, "newer death tick enters respawn state")
	player.apply_network_respawn_state(0.0, Vector3(3.0, 1.0, 2.0), 101)
	_check(not player.is_respawning, "newer respawn tick restores the player")
	player.apply_network_respawn_state(10.0, null, 100)
	_check(
		not player.is_respawning and player.global_position.is_equal_approx(Vector3(3.0, 1.0, 2.0)),
		"older death tick cannot overwrite a confirmed respawn"
	)
	player.cooldown_ring.call("set_progress", 0.4, 1.0)
	player.mounted_machine_gun_is_active = true
	player._set_mounted_machine_gun_runtime(true)
	_check(not player.cooldown_ring.visible, "mounted machine gun hides the hand-tool cooldown ring")
	player.mounted_machine_gun_is_active = false
	player._set_mounted_machine_gun_runtime(false)
	_test_all_drop_death_commits_before_pickup_generation()
	_test_authority_dropped_item_batch()

	player.queue_free()
	GameAuthority.stop_authority()
	await get_tree().process_frame
	_finish()


func _test_all_drop_death_commits_before_pickup_generation() -> void:
	# Steam peer ids are large opaque values. This exact shape previously reached
	# TeamSpawnPoint as player_index and caused hundreds of millions of iterations.
	const TEST_PEER_ID := 879896826
	var original_world: Node = GlobalVar.gameworld
	var original_manager: Node = GameAuthority.server_manager
	var original_ai_manager: Variant = GameAuthority.ai_interest_manager
	var manager := AllDropModeManager.new()
	add_child(manager)
	GlobalVar.gameworld = self
	observed_respawn_player_index = -1
	observed_respawn_random_seed = 0
	GameAuthority.server_manager = manager
	GameAuthority.call("_clear_dropped_items")
	var slots: Array[Dictionary] = []
	for index in range(12):
		if index < 9:
			slots.append({
				"kind": "ingredient",
				"ingredient_id": "wheat",
				"weight_kg": 1.0,
				"is_chopped": false,
			})
		else:
			slots.append({})
	GameAuthority.register_or_update_player(TEST_PEER_ID, {
		"display_name": "DeathBatchValidation",
		"team": "red",
		"spawn_index": 1,
		"hero_id": "farmer",
		"position": Vector3.ZERO,
		"primary_weapon_ids": [],
		"special_tool_ids": [],
		"personal_ingredients": {"wheat|whole": 9.0},
		"backpack_slot_items": slots,
		"backpack_layout_valid": true,
	})
	var observation := {
		"event_seen": false,
		"state_committed": false,
		"no_pickups_created": false,
		"dropped_item_count": 0,
		"respawn_event_seen": false,
		"ai_refresh_called": false,
		"respawn_event_preceded_ai_refresh": false,
	}
	var capture_death := func(event: Dictionary) -> void:
		if int(event.get("peer_id", 0)) != TEST_PEER_ID:
			return
		if str(event.get("type", "")) == "player_respawned":
			observation["respawn_event_seen"] = true
			return
		if str(event.get("type", "")) != "player_died":
			return
		observation["event_seen"] = true
		var state: Dictionary = GameAuthority.player_states.get(TEST_PEER_ID, {})
		observation["state_committed"] = is_equal_approx(
			float(state.get("respawn_left", 0.0)),
			GameAuthority.PLAYER_RESPAWN_SECONDS
		) and is_zero_approx(float(state.get("hp", -1.0)))
		observation["no_pickups_created"] = (GameAuthority.get("dropped_item_nodes") as Dictionary).is_empty()
		var dropped_value: Variant = event.get("dropped_inventory_items", [])
		observation["dropped_item_count"] = (dropped_value as Array).size() if dropped_value is Array else 0
	GameAuthority.reliable_world_event_ready.connect(capture_death)
	GameAuthority.call("_begin_player_respawn", TEST_PEER_ID)
	_check(bool(observation["event_seen"]), "all-drop death emits player_died immediately")
	_check(bool(observation["state_committed"]), "death HP and respawn timer are committed before player_died")
	_check(bool(observation["no_pickups_created"]), "player_died is sent before queued PickupItems are instantiated")
	_check(int(observation["dropped_item_count"]) == 9, "player_died carries every removed all-drop item")
	_check(
		(GameAuthority.get("pending_authoritative_dropped_item_spawns") as Array).size() == 9,
		"all-drop inventory becomes deferred authoritative spawn work"
	)
	GameAuthority.ai_interest_manager = AIRefreshProbe.new(observation)
	for _tick in range(610):
		GameAuthority.call("_simulate_players", GameAuthority.TARGET_TICK_INTERVAL)
	var respawned_state: Dictionary = GameAuthority.player_states.get(TEST_PEER_ID, {})
	_check(
		bool(observation["respawn_event_seen"])
			and is_zero_approx(float(respawned_state.get("respawn_left", -1.0)))
			and is_equal_approx(float(respawned_state.get("hp", 0.0)), GameAuthority.PLAYER_MAX_HP),
		"respawn countdown completes while death drops remain queued"
	)
	_check(
		bool(observation["ai_refresh_called"])
			and bool(observation["respawn_event_preceded_ai_refresh"]),
		"player_respawned is emitted before immediate AI-interest refresh"
	)
	_check(
		observed_respawn_player_index == 1 and observed_respawn_random_seed != 0,
		"large network peer id is used only in the respawn seed, never as player_index"
	)
	GameAuthority.reliable_world_event_ready.disconnect(capture_death)
	GameAuthority.player_states.erase(TEST_PEER_ID)
	GameAuthority.call("_clear_dropped_items")
	GameAuthority.ai_interest_manager = original_ai_manager
	GameAuthority.server_manager = original_manager
	GlobalVar.gameworld = original_world
	manager.queue_free()


func _test_authority_dropped_item_batch() -> void:
	var original_world: Node = GlobalVar.gameworld
	GlobalVar.gameworld = self
	GameAuthority.call("_clear_dropped_items")
	var batch_sizes: Array[int] = []
	var capture_batch := func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "dropped_items_spawned":
			var items_value: Variant = event.get("items", [])
			batch_sizes.append((items_value as Array).size() if items_value is Array else 0)
	GameAuthority.reliable_world_event_ready.connect(capture_batch)
	var item_states: Array[Dictionary] = []
	for index in range(9):
		item_states.append({
			"item_id": "death_batch_validation_%d" % index,
			"item": {
				"kind": "ingredient",
				"ingredient_id": "death_batch_validation",
				"weight_kg": 1.0,
			},
			# Empty model paths intentionally use PickupItem's built-in fallback
			# mesh, keeping this regression test independent of imported assets.
			"model_path": "",
			"position": Vector3(float(index), 1.0, 0.0),
			"velocity": Vector3.ZERO,
			"angular_velocity": Vector3.ZERO,
			"landed": true,
			"lifetime_remaining": PickupItem.LIFETIME_SECONDS,
		})
	GameAuthority.call("_queue_authoritative_dropped_item_spawns", item_states)
	_check(
		(GameAuthority.get("pending_authoritative_dropped_item_spawns") as Array).size() == 9,
		"death drops are queued without synchronous PickupItem creation"
	)
	GameAuthority.call("_flush_pending_authoritative_dropped_item_spawns")
	_check(
		(GameAuthority.get("dropped_item_nodes") as Dictionary).size() == 4
			and (GameAuthority.get("pending_authoritative_dropped_item_spawns") as Array).size() == 5,
		"authority creates at most four death drops in one tick"
	)
	GameAuthority.call("_flush_pending_authoritative_dropped_item_spawns")
	GameAuthority.call("_flush_pending_authoritative_dropped_item_spawns")
	_check(
		(GameAuthority.get("dropped_item_nodes") as Dictionary).size() == 9
			and (GameAuthority.get("pending_authoritative_dropped_item_spawns") as Array).is_empty(),
		"subsequent ticks eventually create every queued death drop"
	)
	_check(batch_sizes == [4, 4, 1], "authority emits one reliable batch per processed tick")
	GameAuthority.call("_queue_authoritative_dropped_item_spawns", [item_states[0]])
	_check(
		(GameAuthority.get("pending_authoritative_dropped_item_spawns") as Array).is_empty(),
		"already spawned item ids cannot be queued twice"
	)
	GameAuthority.reliable_world_event_ready.disconnect(capture_batch)
	GameAuthority.call("_clear_dropped_items")
	GlobalVar.gameworld = original_world


func _finish() -> void:
	if failures == 0:
		print("[PlayerDeathPresentationValidation] PASS all checks")
	else:
		push_error("[PlayerDeathPresentationValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PlayerDeathPresentationValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[PlayerDeathPresentationValidation] FAIL: %s" % description)
