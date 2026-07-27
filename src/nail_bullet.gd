extends CharacterBody3D
class_name NailBullet

@export var speed := 60.0
@export var max_distance := 60.0
@export var max_lifetime := 10.0
@export var knockback_force := 15.0
@export var bullet_strength:float = 20
var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var bullet_owner := ""
var lifetime := 0.0
var running := false
var base_bullet_strength := 0.0


func make_visual_only() -> void:
	bullet_strength = 0.0
	base_bullet_strength = 0.0
	collision_layer = 0
	collision_mask = 0
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.disabled = true


func run(
	spawn_position: Vector3,
	shoot_direction: Vector3,
	shooter_team: String
) -> void:
	global_position = spawn_position
	direction = shoot_direction.normalized()
	start_position = spawn_position
	bullet_owner = shooter_team
	base_bullet_strength = bullet_strength
	running = true
	if direction.length_squared() > 0.001:
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
	if lifetime >= max_lifetime or global_position.distance_to(start_position) >= max_distance:
		queue_free()
		return

	var collision := move_and_collide(direction * speed * delta)
	if collision == null:
		return
	# Player/AI Hit3D areas own character-hit handling. A physics collision
	# here only means the bullet struck world geometry.
	queue_free()
