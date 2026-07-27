extends CharacterBody3D
class_name TranquilizerBullet

const EFFECT_TRANQUILIZER := "tranquilizer"
const PROFILE_ID := "tranquilizer_pistol"

var speed := CombatBalance.get_float(PROFILE_ID, "visual_speed")
var max_distance := CombatBalance.get_float(PROFILE_ID, "range")
var max_lifetime := CombatBalance.get_float(PROFILE_ID, "visual_lifetime")
var knockback_force := 0.0
var bullet_strength := CombatBalance.get_float(PROFILE_ID, "damage")

var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var bullet_owner := ""
var lifetime := 0.0
var running := false
## Local-authority and network shots are resolved once by GameAuthority hitscan.
var gameplay_effect_enabled := true
var base_bullet_strength := 0.0


func make_visual_only() -> void:
	gameplay_effect_enabled = false
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
	shooter_team: String,
	shooter_body: CollisionObject3D = null
) -> void:
	global_position = spawn_position
	direction = shoot_direction.normalized()
	start_position = spawn_position
	bullet_owner = shooter_team
	base_bullet_strength = bullet_strength
	running = true
	if is_instance_valid(shooter_body):
		add_collision_exception_with(shooter_body)
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
	if move_and_collide(direction * speed * delta) != null:
		queue_free()
