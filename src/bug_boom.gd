extends CharacterBody3D
class_name BugBoom

@export var explosion_radius := 8.0
@export var bullet_strength := 0.0
@export var gravity_strength := 18.0
@export var max_lifetime := 8.0
## Local-authority firing already creates the real storm in GameAuthority.
## Keep this projectile as a flight-only presentation in that mode.
@export var visual_only := false

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
	var speed_multiplier := AreaProtectorTool.get_cannonball_speed_multiplier_at(
		self, global_position, bullet_owner
	)
	bullet_strength = base_bullet_strength * AreaProtectorTool.get_damage_multiplier_at(
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
	if collision != null:
		_explode()
		return

	if velocity.length_squared() <= 0.001:
		_explode()
		return
	look_at(global_position + velocity, Vector3.UP)


func run(start_pos: Vector3, initial_velocity: Vector3, shooter: String) -> void:
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
	#_damage_nearby_plots(global_position)
	#_damage_nearby_players(global_position)
	_generate_boom_effect()
	queue_free()
#
#
#func _damage_nearby_plots(hit_position: Vector3) -> void:
	#var manager := get_node_or_null("/root/Farmlandmanager")
	#if manager == null:
		#return
	#for plot in manager.get_plots_in_radius(hit_position, explosion_radius):
		#if is_instance_valid(plot):
			#plot.impact("Explosion", bullet_strength, bullet_owner)
#
### TODO，需要从BoomBuggy那边获得更好的伤害Tools、Player、AI的代码判断
### 爆炸伤害附近的 AI/玩家（不伤害同队）
#func _damage_nearby_players(hit_position: Vector3) -> void:
	#for node in get_tree().get_nodes_in_group("ai_players"):
		#if not is_instance_valid(node) or not node is CharacterBody3D:
			#continue
		#var player := node as CharacterBody3D
		## 同队不伤害
		#if player.has_method("get_combat_team") and \
				#str(player.call("get_combat_team")) == bullet_owner:
			#continue
		#var dist := player.global_position.distance_to(hit_position)
		#if dist <= explosion_radius:
			## 距离越远伤害越低（线性衰减）
			#var damage_ratio := 1.0 - (dist / explosion_radius) * 0.5
			#var damage := bullet_strength * damage_ratio
			#if player.has_method("impact"):
				#player.impact("Explosion", damage, bullet_owner)
			#elif player.has_method("_take_damage"):
				#player.call("_take_damage", damage)

func _generate_boom_effect() -> void:
	if visual_only:
		return
	var world_parent: Node = GlobalVar.gameworld
	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return
	var effect := load(
		"res://character/weapons/BugStorm.tscn"
	).instantiate() as Node3D
	if effect == null:
		return
	
	effect.source_team = bullet_owner
	world_parent.add_child(effect)
	effect.global_position = global_position
	
## 从外部引爆，没有接触附近的
func explode():
	_generate_boom_effect()
	queue_free()
