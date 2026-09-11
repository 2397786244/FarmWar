extends Node3D

class FakePlayer extends StaticBody3D:
	var authority_peer_id := 1
	var team := "red"

class FakeBlocker extends Node3D:
	func _ready() -> void:
		add_to_group("road_blockers")

class FakeVehicle extends StaticBody3D:
	var owner_team := ""
	var driver_peer_id := 0
	var seat_occupants: Dictionary = {}
	var vehicle_id := "validation_vehicle"

	func _ready() -> void:
		add_to_group("vehicles")

	func get_vehicle_id() -> String:
		return vehicle_id

const CHECKPOINT_SCENE := "res://buildings/auxiliary/RoadCheckpoint.tscn"
const BARRIER_SCENE := "res://buildings/RoadBarrierLeft.tscn"
const DEFENSE_SCENES := [
	"res://character/weapons/ChainLinkFence.tscn",
	"res://character/weapons/TallLogWall.tscn",
	"res://character/weapons/TallBrick.tscn",
	"res://character/weapons/TallMeshWall.tscn",
	"res://character/weapons/WireMeshGate.tscn",
]

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({"team": "red", "position": Vector3.ZERO})
	GlobalVar.team_storage["red"]["road_access_card"] = 0
	GlobalVar.team_storage["blue"]["road_access_card"] = 0
	var checkpoint := (load(CHECKPOINT_SCENE) as PackedScene).instantiate() as RoadCheckpoint
	checkpoint.checkpoint_id = "validation_checkpoint"
	checkpoint.allowed_team_ids = PackedStringArray(["red"])
	checkpoint.area_size = Vector3(40.0, 8.0, 40.0)
	checkpoint.barrier_lower_delay_seconds = 0.05
	add_child(checkpoint)
	for index in range(DEFENSE_SCENES.size()):
		var packed := load(DEFENSE_SCENES[index]) as PackedScene
		_check(packed != null, "defense scene %d loads" % index)
		if packed == null:
			continue
		var defense := packed.instantiate() as Node3D
		defense.position = Vector3(float(index * 3 - 6), 0.0, 4.0)
		add_child(defense)
	var barrier := (load(BARRIER_SCENE) as PackedScene).instantiate() as RoadBarrier
	barrier.position = Vector3(0.0, 0.0, 0.0)
	add_child(barrier)
	var blocker := FakeBlocker.new()
	blocker.position = Vector3(0.0, 0.0, -4.0)
	add_child(blocker)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check(checkpoint.get_registered_members().size() >= 6, "checkpoint registers five defenses and barrier")
	_check(checkpoint.get_registered_blockers().size() == 1, "checkpoint registers road_blockers group members")
	_check(checkpoint.get_registered_barriers().size() == 1, "checkpoint registers RoadBarrier")
	_check(barrier.is_checkpoint_managed(), "checkpoint takes over barrier decisions")

	var player := FakePlayer.new()
	player.add_to_group("human_players")
	player.team = "red"
	var player_shape := CollisionShape3D.new()
	player_shape.name = "CollisionShape3D"
	var player_box := BoxShape3D.new()
	player_box.size = Vector3(0.8, 1.8, 0.8)
	player_shape.shape = player_box
	player.add_child(player_shape)
	player.collision_layer = 8
	player.collision_mask = 1
	player.position = Vector3(0.0, 0.8, 0.0)
	add_child(player)
	GameAuthority.player_states[1] = {
		"team": "red",
		"backpack_slot_items": [],
		"vehicle_id": "",
	}
	# Drive the same public signal-producing entry path used by a physics
	# overlap; this keeps the validation deterministic in headless mode where
	# static test bodies may be culled by the renderer's physics broadphase.
	barrier.call("_on_test_enter_body_entered", player)
	checkpoint.call("_on_body_entered", player)
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(not barrier.is_barrier_raised(), "allowed team without an access card keeps barrier lowered")

	player.team = "green"
	GameAuthority.player_states[1]["team"] = "green"
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(not barrier.is_barrier_raised(), "unauthorized entrant keeps barrier lowered")
	player.team = "red"
	GameAuthority.player_states[1]["team"] = "red"
	GameAuthority.player_states[1]["backpack_slot_items"] = [{"kind": "key_item", "item_id": "road_access_card"}]
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(barrier.is_barrier_raised(), "personal road access card raises barrier")

	GameAuthority.player_states[1]["backpack_slot_items"] = []
	GlobalVar.team_storage["red"]["road_access_card"] = 1
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(barrier.is_barrier_raised(), "team inventory road access card raises barrier")
	barrier.call("_on_test_body_exited", player)
	checkpoint.call("_on_body_exited", player)

	var vehicle := FakeVehicle.new()
	vehicle.position = Vector3(2.0, 0.8, 0.0)
	vehicle.owner_team = "red"
	var vehicle_shape := CollisionShape3D.new()
	var vehicle_box := BoxShape3D.new()
	vehicle_box.size = Vector3(2.0, 1.4, 3.0)
	vehicle_shape.shape = vehicle_box
	vehicle.add_child(vehicle_shape)
	vehicle.collision_layer = 8192
	add_child(vehicle)
	checkpoint.call("_on_body_entered", vehicle)
	GlobalVar.team_storage["red"]["road_access_card"] = 1
	player.team = "green"
	GameAuthority.player_states[1]["team"] = "green"
	vehicle.owner_team = "red"
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(barrier.is_barrier_raised(), "vehicle owner team access card grants checkpoint access")
	GlobalVar.team_storage["red"]["road_access_card"] = 0
	vehicle.owner_team = "green"
	vehicle.driver_peer_id = 1
	GameAuthority.player_states[1]["backpack_slot_items"] = [{"kind": "key_item", "item_id": "road_access_card"}]
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(barrier.is_barrier_raised(), "vehicle driver card grants checkpoint access")
	GameAuthority.player_states[1]["backpack_slot_items"] = []
	vehicle.driver_peer_id = 0
	vehicle.seat_occupants[1] = 1
	GameAuthority.player_states[1]["backpack_slot_items"] = [{"kind": "key_item", "item_id": "road_access_card"}]
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(barrier.is_barrier_raised(), "vehicle passenger card grants checkpoint access")
	vehicle.seat_occupants.clear()
	GameAuthority.player_states[1]["backpack_slot_items"] = []
	barrier.lower_barrier()
	checkpoint.call("_update_access_and_barriers", 0.0)
	_check(not barrier.is_barrier_raised(), "unauthorized vehicle keeps barrier lowered")

	barrier.raise_barrier()
	player.position = Vector3(15.0, 1.0, 15.0)
	barrier.call("_on_test_body_exited", player)
	checkpoint.call("_on_body_exited", player)
	checkpoint.call("_on_body_exited", vehicle)
	checkpoint.call("_update_access_and_barriers", 0.04)
	_check(barrier.is_barrier_raised(), "barrier stays raised during lower delay")
	checkpoint.call("_update_access_and_barriers", 0.02)
	_check(not barrier.is_barrier_raised(), "empty TestEnterArea lowers barrier after delay")

	var damage_target := checkpoint.get_registered_members()[1] as Node
	checkpoint.notify_member_damage(damage_target, 99.0, {"player_owned": true})
	_check(not checkpoint.alarm_active, "99 damage does not alarm")
	checkpoint.notify_member_damage(damage_target, 1.0, {"player_owned": true})
	_check(not checkpoint.alarm_active, "100 damage is still below strict threshold")
	checkpoint.notify_member_damage(damage_target, 1.0, {"player_owned": true})
	_check(checkpoint.alarm_active, "101 cumulative damage alarms")
	if damage_target.has_method("apply_network_respawned"):
		damage_target.call("apply_network_respawned")
	_check(not checkpoint.alarm_active, "facility respawn clears its damage alarm source")
	checkpoint.notify_member_damage(damage_target, 50.0, {"player_owned": false})
	_check(not checkpoint.alarm_active, "non-player damage is ignored")
	checkpoint.notify_blocker_attacked(blocker, {"player_owned": true})
	_check(checkpoint.alarm_active, "player attack on blocker alarms immediately")
	checkpoint.alarm_timeout_seconds = 0.05
	checkpoint.alarm_remaining = 0.05
	await get_tree().create_timer(0.10).timeout
	_check(not checkpoint.alarm_active, "alarm clears after timeout")

	GameAuthority.start_client_mode()
	checkpoint.notify_member_damage(damage_target, 250.0, {"player_owned": true})
	_check(not checkpoint.alarm_active, "client cannot calculate a local damage alarm")
	checkpoint.apply_network_state({
		"checkpoint_id": checkpoint.checkpoint_id,
		"alarm_active": true,
		"alarm_reason": "network",
		"alarm_remaining": 12.0,
		"barrier_raised": true,
	})
	_check(checkpoint.alarm_active and barrier.is_barrier_raised(), "client applies replicated checkpoint state")

	player.queue_free()
	vehicle.queue_free()
	barrier.queue_free()
	checkpoint.queue_free()
	if failures.is_empty():
		print("[RoadCheckpointValidation] PASS")
	else:
		for failure in failures:
			push_error("[RoadCheckpointValidation] " + failure)
	get_tree().quit(1 if not failures.is_empty() else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
