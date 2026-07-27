extends CharacterBody3D
class_name RiftAnchor

const CombatBalance = preload("res://src/combat_balance.gd")

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


func _ready() -> void:
	speed = CombatBalance.get_float("rift_book", "anchor_speed", 32.0)
	max_hp = CombatBalance.get_float("rift_book", "anchor_hp", 100.0)
	current_hp = max_hp
	teleport_beam = find_child("TeleportBeam", true, false) as Node3D
	if is_instance_valid(teleport_beam):
		teleport_beam.visible = false


func launch(spawn_position: Vector3, launch_direction: Vector3, peer_id: int, team: String) -> void:
	global_position = spawn_position
	direction = launch_direction.normalized()
	owner_peer_id = peer_id
	owner_team = team
	running = direction.length_squared() > 0.001
	landed = false
	lifetime = 0.0
	if running:
		look_at(global_position + direction, Vector3.UP)


func apply_network_launch(spawn_position: Vector3, launch_direction: Vector3, peer_id: int, team: String) -> void:
	owner_peer_id = peer_id
	owner_team = team
	global_position = spawn_position
	direction = launch_direction.normalized()
	lifetime = 0.0
	landed = false
	running = direction.length_squared() > 0.001
	if running:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not running or landed:
		return
	lifetime += delta
	var collision := move_and_collide(direction * speed * delta)
	if collision != null:
		_activate_at_surface(collision.get_position())
		return
	if lifetime >= CombatBalance.get_float("rift_book", "anchor_lifetime", 0.8):
		_activate_at_surface(global_position)


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


func apply_network_activated() -> void:
	_running_visual_activation()


func _running_visual_activation() -> void:
	landed = true
	running = false
	if is_instance_valid(teleport_beam):
		teleport_beam.visible = true
