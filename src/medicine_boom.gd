extends CharacterBody3D
class_name MedicineBoom

@export var gravity_strength := 18.0
@export var max_lifetime := 8.0
## Set by the local-authority presentation path to avoid duplicate storm logic.
@export var visual_only := false

const STORM_SCENE := preload("res://character/weapons/MedicineStorm.tscn")

var current_lifetime := 0.0
var is_running := false
var bullet_owner := ""


func get_bullet_owner() -> String:
	return bullet_owner


func run(start_pos: Vector3, initial_velocity: Vector3, shooter: String) -> void:
	global_position = start_pos
	velocity = initial_velocity
	bullet_owner = shooter
	current_lifetime = 0.0
	is_running = true
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_running:
		return
	current_lifetime += delta
	var speed_multiplier := AreaProtectorTool.get_cannonball_speed_multiplier_at(
		self, global_position, bullet_owner
	)
	var projectile_delta := delta * speed_multiplier
	if current_lifetime >= max_lifetime:
		_explode()
		return
	velocity += Vector3.DOWN * gravity_strength * projectile_delta
	var collision := move_and_collide(velocity * projectile_delta)
	rotate_x(16.0 * delta)
	rotate_y(20.0 * delta)
	if collision != null or velocity.length_squared() <= 0.001:
		_explode()
		return
	look_at(global_position + velocity, Vector3.UP)


func explode() -> void:
	_explode()


func _explode() -> void:
	_generate_storm()
	queue_free()


func _generate_storm() -> void:
	if visual_only:
		return
	var world_parent: Node = GlobalVar.gameworld
	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return
	var storm := STORM_SCENE.instantiate() as Node3D
	if storm == null:
		return
	storm.set("source_team", bullet_owner)
	world_parent.add_child(storm)
	storm.global_position = global_position
