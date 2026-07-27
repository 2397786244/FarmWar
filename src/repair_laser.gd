extends CharacterBody3D
class_name RepairLaser

@export var speed := 60.0
@export var max_distance := 25.0
@export var max_lifetime := 1.0

var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var bullet_owner := ""
var running := false
var visual_only := false
var lifetime := 0.0


func run(spawn_position: Vector3, shoot_direction: Vector3, shooter_team: String) -> void:
	global_position = spawn_position
	direction = shoot_direction.normalized()
	start_position = spawn_position
	bullet_owner = shooter_team
	running = direction.length_squared() > 0.001
	if running:
		look_at(global_position + direction, Vector3.UP)


func get_bullet_owner() -> String:
	return bullet_owner


func _physics_process(delta: float) -> void:
	if not running:
		return
	lifetime += delta
	if lifetime >= max_lifetime or global_position.distance_to(start_position) >= max_distance:
		queue_free()
		return
	if visual_only:
		global_position += direction * speed * delta
		return
	if move_and_collide(direction * speed * delta) != null:
		queue_free()
