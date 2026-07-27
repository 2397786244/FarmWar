extends CharacterBody3D
class_name DetectLaserBullet
# 
@export var speed := 60
@export var max_distance := 100
@export var max_lifetime := 2
@export var knockback_force := 0
@export var bullet_strength = 5
@export_enum("Flame","Freeze","Poison","Lightening","Labeled","None") var bullet_effect:String = "Labeled"
# Labeled表示被标记了
var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var bullet_owner := ""
var lifetime := 0.0
var running := false
var visual_only := false
var base_bullet_strength := 0.0

func _ready() -> void:
	pass
	#$Trace.tracer_color = color
	
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

	if visual_only:
		global_position += direction * speed * delta
		return

	var collision := move_and_collide(direction * speed * delta)
	if collision == null:
		return
	# Player/AI Hit3D areas own character-hit handling. A physics collision
	# here only means the bullet struck world geometry.
	queue_free()
