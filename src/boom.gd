extends CharacterBody3D
class_name BoomBullet

@export var explosion_radius := 12.0
@export var bullet_strength := 200.0
@export var gravity_strength := 18.0
@export var max_lifetime := 8.0

var current_lifetime := 0.0
var is_run := false
var start_absorbing := false
var absorbing_source := Vector3.ZERO
var absorption_start_distance := 0.0
var absorption_initial_scale := Vector3.ONE
var bullet_owner := ""
var base_bullet_strength := 0.0


func _ready() -> void:
	absorption_initial_scale = scale


func get_bullet_owner() -> String:
	return bullet_owner


func _physics_process(delta: float) -> void:
	if not is_run:
		return
	if start_absorbing:
		_update_absorption(delta)
		return

	current_lifetime += delta
	var speed_multiplier = AreaProtectorTool.get_cannonball_speed_multiplier_at(
		self, global_position, bullet_owner
	)
	var projectile_delta = delta * speed_multiplier
	if current_lifetime >= max_lifetime:
		_explode()
		return

	velocity += Vector3.DOWN * gravity_strength * projectile_delta
	var collision := move_and_collide(velocity * projectile_delta)
	rotate_x(16.0 * delta)
	rotate_y(20.0 * delta)
	if collision != null:
		_explode()
		return

	if velocity.length_squared() <= 0.001:
		_explode()
		return
	look_at(global_position + velocity, Vector3.UP)


func run(start_pos: Vector3, initial_velocity: Vector3, shooter: String) -> void:
	#print(initial_velocity.length())
	global_position = start_pos
	velocity = initial_velocity
	bullet_owner = shooter
	base_bullet_strength = bullet_strength
	current_lifetime = 0.0
	is_run = true


func begin_absorbing(absorbing_source_position: Vector3) -> void:
	if start_absorbing:
		return
	start_absorbing = true
	absorbing_source = absorbing_source_position
	absorption_start_distance = maxf(
		absorbing_source.distance_to(global_position),
		0.001
	)
	absorption_initial_scale = scale
	collision_mask = 0


func _update_absorption(delta: float) -> void:
	var offset := absorbing_source - global_position
	var distance := offset.length()
	if distance <= 0.3:
		queue_free()
		return

	var desired_velocity := offset.normalized() * 10.0
	velocity = velocity.move_toward(desired_velocity, 40.0 * delta)
	move_and_collide(velocity * delta)

	var distance_ratio := clampf(
		distance / absorption_start_distance,
		0.2,
		1.0
	)
	scale = absorption_initial_scale * distance_ratio
	rotate_x(8.0 * delta)
	rotate_y(12.0 * delta)


func _explode() -> void:
	if GameAuthority.should_send_network_requests():
		_generate_boom_effect()
		queue_free()
		return
	GameAuthority.apply_local_boom_explosion(
		global_position,
		bullet_owner,
		bullet_strength,
		explosion_radius,
		"Explosion"
	)
	_generate_boom_effect()
	queue_free()


func _generate_boom_effect() -> void:
	var world_parent: Node = GlobalVar.gameworld
	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return
	var effect := load(
		"res://character/weapons/BoomEffect.tscn"
	).instantiate() as Node3D
	if effect == null:
		return
	world_parent.add_child(effect)
	effect.global_position = global_position

## 防空等外部拦截也属于一次真实爆炸，不能只播放视觉效果。
func explode() -> void:
	_explode()
