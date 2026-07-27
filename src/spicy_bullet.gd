extends CharacterBody3D
class_name SpicyBullet

@export var speed := 20.0
@export var gravity_strength := 4.5
@export var max_distance := 30.0
@export var max_lifetime := 2.0
@export var bullet_strength := 0.0

var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var bullet_owner := ""
var lifetime := 0.0
var running := false
var base_bullet_strength := 0.0


func run(spawn_position: Vector3, shoot_direction: Vector3, shooter_team: String) -> void:
	global_position = spawn_position
	direction = shoot_direction.normalized()
	velocity = direction * speed
	start_position = spawn_position
	bullet_owner = shooter_team
	base_bullet_strength = bullet_strength
	running = direction.length_squared() > 0.001
	if running:
		look_at(global_position + direction, Vector3.UP)


func get_bullet_owner() -> String:
	return bullet_owner


func _physics_process(delta: float) -> void:
	if not running:
		return
	lifetime += delta
	bullet_strength = base_bullet_strength * AreaProtectorTool.get_damage_multiplier_at(
		self, global_position, bullet_owner
	)
	var projectile_delta := delta
	if lifetime >= max_lifetime or global_position.distance_to(start_position) >= max_distance:
		_finish()
		return
	velocity += Vector3.DOWN * gravity_strength * projectile_delta
	if move_and_collide(velocity * projectile_delta) != null:
		_finish()
		return
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)


func _finish() -> void:
	if not running:
		return
	running = false
	queue_free()
