extends CharacterBody3D
class_name RiftAnchor

const CombatBalance = preload("res://src/combat_balance.gd")
const NETWORK_FLIGHT_CORRECTION_RATE := 18.0
const NETWORK_FLIGHT_MAX_CORRECTION_DISTANCE := 6.0

var owner_peer_id := 0
var owner_team := ""
var tool_owner := ""
var direction := Vector3.ZERO
var speed := 0.0
var lifetime := 0.0
var running := false
var landed := false
var current_hp := 100.0
var max_hp := 100.0
var teleport_beam: Node3D
var network_flight_proxy := false
var network_flight_target_position := Vector3.ZERO
var network_flight_velocity := Vector3.ZERO
var network_flight_has_snapshot := false
var network_flight_snapshot_tick := -1


func _ready() -> void:
	speed = CombatBalance.get_float("rift_book", "anchor_speed", 32.0)
	max_hp = CombatBalance.get_float("rift_book", "anchor_hp", 100.0)
	current_hp = max_hp
	teleport_beam = find_child("TeleportBeam", true, false) as Node3D
	if is_instance_valid(teleport_beam):
		teleport_beam.visible = false


func launch(spawn_position: Vector3, launch_direction: Vector3, peer_id: int, team: String) -> void:
	network_flight_proxy = false
	network_flight_has_snapshot = false
	network_flight_snapshot_tick = -1
	global_position = spawn_position
	direction = launch_direction.normalized()
	owner_peer_id = peer_id
	owner_team = team
	network_flight_target_position = spawn_position
	network_flight_velocity = direction * speed
	running = direction.length_squared() > 0.001
	landed = false
	lifetime = 0.0
	if running:
		look_at(global_position + direction, Vector3.UP)


func apply_network_launch(spawn_position: Vector3, launch_direction: Vector3, peer_id: int, team: String) -> void:
	var normalized_direction := launch_direction.normalized()
	if network_flight_proxy and landed:
		owner_peer_id = peer_id
		owner_team = team
		return
	if network_flight_proxy and network_flight_has_snapshot:
		owner_peer_id = peer_id
		owner_team = team
		direction = normalized_direction
		network_flight_velocity = direction * speed
		running = direction.length_squared() > 0.001
		landed = false
		return
	network_flight_proxy = true
	network_flight_has_snapshot = false
	network_flight_snapshot_tick = -1
	owner_peer_id = peer_id
	owner_team = team
	global_position = spawn_position
	direction = normalized_direction
	network_flight_target_position = spawn_position
	network_flight_velocity = direction * speed
	lifetime = 0.0
	landed = false
	running = direction.length_squared() > 0.001
	if running:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if network_flight_proxy:
		_simulate_network_flight(delta)
		return
	if not running or landed:
		return
	lifetime += delta
	var collision := move_and_collide(direction * speed * delta)
	if collision != null:
		_activate_at_surface(collision.get_position())
		return
	if lifetime >= CombatBalance.get_float("rift_book", "anchor_lifetime", 0.8):
		_activate_at_surface(global_position)


func _simulate_network_flight(delta: float) -> void:
	if not running or landed:
		return
	var flight_velocity := network_flight_velocity
	if flight_velocity.length_squared() <= 0.001:
		flight_velocity = direction * speed
	global_position += flight_velocity * delta
	if network_flight_has_snapshot:
		var correction := network_flight_target_position - global_position
		if correction.length() > NETWORK_FLIGHT_MAX_CORRECTION_DISTANCE:
			global_position = network_flight_target_position
		else:
			global_position += correction * (1.0 - exp(-NETWORK_FLIGHT_CORRECTION_RATE * delta))
	if flight_velocity.length_squared() > 0.001:
		look_at(global_position + flight_velocity, Vector3.UP)


func _activate_at_surface(position: Vector3) -> void:
	if landed:
		return
	var ground := _find_ground_position(position)
	global_position = ground + Vector3.UP * 0.12
	velocity = Vector3.ZERO
	running = false
	landed = true
	if is_instance_valid(teleport_beam):
		teleport_beam.visible = true
	GameAuthority.activate_rift_anchor(self)


func _find_ground_position(position: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return position
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 12.0, position + Vector3.DOWN * 48.0)
	query.collision_mask = 1 | 2 | 64 | 4096
	query.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.get("position", position) if hit.has("position") else position


func impact(_effect: String, strength: float, attacker_team: String = "") -> bool:
	if strength <= 0.0 or current_hp <= 0.0 or (not attacker_team.is_empty() and attacker_team == owner_team):
		return false
	current_hp = maxf(0.0, current_hp - strength)
	if current_hp <= 0.0:
		GameAuthority.destroy_rift_anchor(self)
	return true


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)


func set_network_flight_proxy(enabled: bool) -> void:
	network_flight_proxy = enabled
	if enabled:
		network_flight_has_snapshot = false
		network_flight_snapshot_tick = -1


func get_network_flight_state() -> Dictionary:
	var active := running and not landed
	return {
		"active": active,
		"position": global_position,
		"velocity": direction * speed if active else Vector3.ZERO,
		"lifetime": lifetime,
	}


func apply_network_flight_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var position_value: Variant = state.get("position", global_position)
	var velocity_value: Variant = state.get("velocity", Vector3.ZERO)
	var active := bool(state.get("active", false))
	var snapshot_tick := int(state.get("snapshot_tick", -1))
	if snapshot_tick >= 0 and network_flight_snapshot_tick >= 0 \
			and snapshot_tick <= network_flight_snapshot_tick:
		return
	network_flight_proxy = true
	if position_value is Vector3:
		network_flight_target_position = position_value as Vector3
		if not network_flight_has_snapshot \
				and global_position.distance_to(network_flight_target_position) > NETWORK_FLIGHT_MAX_CORRECTION_DISTANCE:
			global_position = network_flight_target_position
	if velocity_value is Vector3:
		network_flight_velocity = velocity_value as Vector3
		if network_flight_velocity.length_squared() > 0.001:
			direction = network_flight_velocity.normalized()
			speed = network_flight_velocity.length()
	lifetime = maxf(0.0, float(state.get("lifetime", lifetime)))
	network_flight_has_snapshot = true
	if snapshot_tick >= 0:
		network_flight_snapshot_tick = snapshot_tick
	if active:
		landed = false
		running = true
	else:
		running = false


func apply_network_activated(position_value: Variant = null) -> void:
	if position_value is Vector3:
		global_position = position_value as Vector3
	network_flight_has_snapshot = false
	network_flight_snapshot_tick = -1
	network_flight_target_position = global_position
	network_flight_velocity = Vector3.ZERO
	running = false
	landed = true
	_running_visual_activation()


func _running_visual_activation() -> void:
	landed = true
	running = false
	if is_instance_valid(teleport_beam):
		teleport_beam.visible = true
