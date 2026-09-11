extends Node3D

const BLACK_BEAR_SCENE := "res://items/BlackBear.tscn"

var failures := 0
var replicator: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	replicator = get_node("/root/MultiplayerWorldReplicator")
	replicator.set_process(false)
	GlobalVar.gameworld = self
	replicator.call("_clear_all")
	replicator.set("world_root", self)

	_check(load(BLACK_BEAR_SCENE) is PackedScene, "BlackBear proxy scene loads")
	await _test_freed_snapshot_proxy_is_recreated()
	await _test_spawn_event_replaces_freed_proxy()
	await _test_freed_world_root_clears_proxy_cache()
	await _test_stale_snapshot_proxy_is_removed()
	await _test_dead_proxy_ignores_stale_snapshot_and_is_not_recreated()

	replicator.call("_clear_all")
	_finish()


func _test_freed_snapshot_proxy_is_recreated() -> void:
	var animal_id := "validation_freed_snapshot"
	replicator.call("_sync_wild_animals", [_animal_state(animal_id, Vector3.ZERO)])
	await get_tree().process_frame
	var original_value: Variant = _get_visual(animal_id)
	_check(is_instance_valid(original_value), "snapshot creates a valid wild-animal proxy")
	if not is_instance_valid(original_value):
		return
	var original_instance_id: int = int(original_value.get_instance_id())
	original_value.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(original_value), "test leaves a freed proxy reference in the dictionary")

	replicator.call("_sync_wild_animals", [_animal_state(animal_id, Vector3(2.0, 0.0, 0.0))])
	await get_tree().process_frame
	var recreated_value: Variant = _get_visual(animal_id)
	_check(is_instance_valid(recreated_value), "freed snapshot proxy is safely recreated")
	if is_instance_valid(recreated_value):
		_check(recreated_value.get_instance_id() != original_instance_id, "recreated proxy is a new instance")


func _test_spawn_event_replaces_freed_proxy() -> void:
	var animal_id := "validation_freed_spawn_event"
	var stale_proxy := Node3D.new()
	stale_proxy.name = "FreedLivestockProxy"
	add_child(stale_proxy)
	replicator.get("wild_animal_visuals")[animal_id] = stale_proxy
	stale_proxy.queue_free()
	await get_tree().process_frame

	replicator.call("_apply_livestock_spawned", _animal_state(animal_id, Vector3(4.0, 0.0, 0.0)))
	await get_tree().process_frame
	var replacement: Variant = _get_visual(animal_id)
	_check(is_instance_valid(replacement), "livestock_spawned recreates a freed proxy")
	_check(replacement is Node3D, "livestock_spawned replacement is a Node3D")


func _test_freed_world_root_clears_proxy_cache() -> void:
	var old_world := Node3D.new()
	old_world.name = "FreedWildAnimalWorld"
	add_child(old_world)
	var stale_proxy := Node3D.new()
	old_world.add_child(stale_proxy)
	replicator.get("wild_animal_visuals")["validation_old_world"] = stale_proxy
	replicator.set("world_root", old_world)
	old_world.queue_free()
	await get_tree().process_frame

	var resolved_root: Variant = replicator.call("_resolve_world_root")
	_check(resolved_root == self, "released world root switches to the current world")
	var visuals: Variant = replicator.get("wild_animal_visuals")
	_check(visuals is Dictionary and (visuals as Dictionary).is_empty(), "world switch clears wild-animal proxy cache")


func _test_stale_snapshot_proxy_is_removed() -> void:
	var present_id := "validation_present_snapshot"
	var removed_id := "validation_removed_snapshot"
	replicator.call(
		"_sync_wild_animals",
		[_animal_state(present_id, Vector3(6.0, 0.0, 0.0)), _animal_state(removed_id, Vector3(8.0, 0.0, 0.0))]
	)
	await get_tree().process_frame
	_check(is_instance_valid(_get_visual(removed_id)), "snapshot creates a proxy that can later become stale")

	replicator.call("_sync_wild_animals", [_animal_state(present_id, Vector3(6.0, 0.0, 0.0))])
	var removed_value: Variant = _get_visual(removed_id)
	_check(removed_value == null, "animal missing from the snapshot is removed from the cache")
	await get_tree().process_frame
	_check(not is_instance_valid(removed_value), "animal missing from the snapshot is safely freed")


func _test_dead_proxy_ignores_stale_snapshot_and_is_not_recreated() -> void:
	var animal_id := "validation_dead_snapshot"
	var alive := _animal_state(animal_id, Vector3(10.0, 0.0, 0.0))
	replicator.call("_sync_wild_animals", [alive], 100)
	await get_tree().process_frame
	var dead := alive.duplicate(true)
	dead["state"] = "dead"
	dead["hp"] = 0.0
	dead["animation"] = "Death"
	dead["death_cleanup_left"] = 1.0
	replicator.call("_sync_wild_animals", [dead], 101)
	await get_tree().process_frame
	_check(is_instance_valid(_get_visual(animal_id)), "death transition keeps its proxy for the cleanup window")

	## A delayed alive snapshot must not undo the later dead transition.
	replicator.call("_sync_wild_animals", [alive], 100)
	_check(
		replicator.get("wild_animal_death_cleanup_deadlines").has(animal_id),
		"older alive snapshot cannot revive a dead wild-animal proxy"
	)
	replicator.get("wild_animal_death_cleanup_deadlines")[animal_id] = 0
	replicator.call("_update_wild_animal_death_cleanup")
	await get_tree().process_frame
	_check(_get_visual(animal_id) == null, "central cleanup removes an expired dead proxy")
	replicator.call("_sync_wild_animals", [dead], 102)
	_check(_get_visual(animal_id) == null, "late dead snapshot cannot recreate an expired proxy")


func _animal_state(animal_id: String, position: Vector3) -> Dictionary:
	return {
		"animal_id": animal_id,
		"scene_path": BLACK_BEAR_SCENE,
		"position": position,
		"velocity": Vector3.ZERO,
		"yaw": 0.0,
		"hp": 1000.0,
		"max_hp": 1000.0,
		"state": "idle",
		"animation": "Idle",
		"animation_speed": 1.0,
	}


func _get_visual(animal_id: String) -> Variant:
	var visuals: Variant = replicator.get("wild_animal_visuals")
	if visuals is Dictionary:
		return (visuals as Dictionary).get(animal_id, null)
	return null


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[WildAnimalReplicatorValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[WildAnimalReplicatorValidation] FAIL: %s" % description)


func _finish() -> void:
	if failures == 0:
		print("[WildAnimalReplicatorValidation] PASS all checks")
	else:
		push_error("[WildAnimalReplicatorValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
