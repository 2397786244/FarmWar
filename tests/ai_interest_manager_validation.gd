extends Node3D

const MANAGER_SCRIPT := preload("res://src/ai_interest_manager.gd")

var failures := 0
var _authority: Node
var _manager
var _entities: Array[Node] = []


class FakeAuthority extends Node:
	var player_states: Dictionary = {}

	func is_server_authority() -> bool:
		return true

	func is_local_authority() -> bool:
		return false


class FakeInterestEntity extends Node3D:
	var interest_sleeping := false
	var dead := false
	var interest_state_changes := 0

	func can_enter_interest_sleep() -> bool:
		return not dead

	func set_interest_sleeping(value: bool) -> void:
		interest_sleeping = value
		interest_state_changes += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var required_ai_scenes := {
		"FarmerAI": "res://character/FarmerAI.tscn",
		"AssistantAI": "res://character/AssistantAI.tscn",
		"BanditAI": "res://character/BanditAI.tscn",
		"FutureEngineerAI": "res://character/FutureEngineerAI.tscn",
		"BlackBear": "res://items/BlackBear.tscn",
	}
	for scene_name: String in required_ai_scenes:
		var packed := load(str(required_ai_scenes[scene_name])) as PackedScene
		_check(packed != null, "%s scene loads" % scene_name)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_check(instance != null and instance.has_method("set_interest_sleeping"), "%s exposes interest sleep hooks" % scene_name)
		if instance != null:
			instance.free()

	_authority = FakeAuthority.new()
	_authority.name = "FakeAuthority"
	add_child(_authority)
	_authority.player_states = {
		1: {"position": Vector3(0.0, 0.0, 0.0), "respawn_left": 0.0},
	}
	_manager = MANAGER_SCRIPT.new()
	_manager.setup(_authority)

	var current := _add_entity("Farmer_Current", Vector3(1.0, 0.0, 1.0), &"farmer_ai")
	var east := _add_entity("Bandit_East", Vector3(257.0, 0.0, 1.0), &"future_warrior_ai")
	var west := _add_entity("FutureEngineer_West", Vector3(-255.0, 0.0, 1.0), &"future_warrior_ai")
	var south := _add_entity("Assistant_South", Vector3(1.0, 0.0, 257.0), &"assistant_ai")
	var north := _add_entity("Drone_North", Vector3(1.0, 0.0, -255.0), &"ai_normal_drones")
	var diagonal := _add_entity("BlackBear_Diagonal", Vector3(257.0, 0.0, 257.0), &"wild_animals")
	var far := _add_entity("BlackBear_Far", Vector3(513.0, 0.0, 1.0), &"wild_animals")
	var livestock := _add_entity("FarmLivestock_Far", Vector3(513.0, 0.0, 257.0), &"wild_animals")
	livestock.add_to_group("farm_livestock")

	_manager.request_refresh(true)
	_check(_manager.get_active_chunks().size() == 5, "one player activates exactly five chunk coordinates")
	_check(_manager.get_active_chunks().has(Vector2i(0, 0)), "current chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(1, 0)), "east cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(-1, 0)), "west cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(0, 1)), "south cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(0, -1)), "north cardinal chunk is active")
	_check(not _manager.get_active_chunks().has(Vector2i(1, 1)), "diagonal chunk is not active")
	_check(_manager.get_sleeping_count() == 2, "only inactive non-livestock entities enter sleep")
	_check(not current.interest_sleeping, "farmer AI remains active in the current chunk")
	_check(not east.interest_sleeping, "Bandit/FutureWarrior group remains active in a cardinal chunk")
	_check(not west.interest_sleeping, "FutureEngineer inherited group remains active in a cardinal chunk")
	_check(not south.interest_sleeping, "Assistant AI remains active in a cardinal chunk")
	_check(not north.interest_sleeping, "normal AI drone remains active in a cardinal chunk")
	_check(diagonal.interest_sleeping and diagonal.process_mode == Node.PROCESS_MODE_DISABLED, "diagonal BlackBear enters idle sleep")
	_check(far.interest_sleeping and far.process_mode == Node.PROCESS_MODE_DISABLED, "far BlackBear enters idle sleep")
	_check(livestock.process_mode != Node.PROCESS_MODE_DISABLED and not livestock.interest_sleeping, "FarmLivestock stays active for its timers")
	_check(diagonal.visible and far.visible, "sleeping entities remain visible")

	# This models the immediate refresh performed after a newly spawned player
	# receives its final position, rather than waiting for the periodic tick.
	_authority.player_states[1]["position"] = Vector3(257.0, 0.0, 257.0)
	_manager.request_refresh(true)
	_check(not diagonal.interest_sleeping, "new player position immediately wakes its chunk")
	_check(current.interest_sleeping, "old chunk sleeps after the player leaves it")
	_check(_manager.get_active_chunks().has(Vector2i(1, 1)), "new current chunk is active immediately")
	_check(_manager.get_active_chunks().has(Vector2i(2, 1)), "new east cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(0, 1)), "new west cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(1, 2)), "new south cardinal chunk is active")
	_check(_manager.get_active_chunks().has(Vector2i(1, 0)), "new north cardinal chunk is active")

	# Direct damage/interaction paths can wake an out-of-interest entity before
	# applying the existing impact handler.
	_manager.wake_node(far)
	_check(not far.interest_sleeping and far.process_mode != Node.PROCESS_MODE_DISABLED, "damage path wake restores processing")
	far.dead = true
	_manager.request_refresh(true)
	_check(not far.interest_sleeping, "dead entities are not put back to sleep")

	_manager.reset()
	_check(_manager.get_sleeping_count() == 0, "reset wakes all tracked entities")
	_check(current.interest_sleeping == false and current.process_mode != Node.PROCESS_MODE_DISABLED, "reset restores the previous process mode")

	_finish()


func _add_entity(entity_name: String, position: Vector3, group_name: StringName) -> FakeInterestEntity:
	var entity := FakeInterestEntity.new()
	entity.name = entity_name
	entity.add_to_group(group_name)
	_authority.add_child(entity)
	entity.global_position = position
	_entities.append(entity)
	return entity


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[AIInterestManagerValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[AIInterestManagerValidation] FAIL: %s" % description)


func _finish() -> void:
	if failures == 0:
		print("[AIInterestManagerValidation] PASS all checks")
	else:
		push_error("[AIInterestManagerValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
