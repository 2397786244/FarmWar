extends StaticBody3D
class_name AutoShooterTool

@export var tool_owner := ""
@export var shoot_cd_time := 10.0
@export var max_hp := 500.0
@export var target_range := 35.0
@export var projectile_speed := 30.0
@export var projectile_damage := 80.0
@export var projectile_radius := 3.0
@export var hp_debug_label: bool = true

var current_hp := 500.0
var is_working := false
var shoot_counter := 0.0
var frozen_remaining := 0.0
var burn_remaining := 0.0
var burn_dps := 0.0
var last_effect := ""
var disable_remaining:float = 0.0
var _health_label_activated := false
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

func _ready() -> void:
	current_hp = max_hp
	_update_label()


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)
	if not is_deployed_on_farm_tile():
		is_working = false
		shoot_counter = 0.0
		return
	if not is_working or current_hp <= 0.0 or frozen_remaining > 0.0:
		return
	shoot_counter += delta
	if shoot_counter >= shoot_cd_time:
		shoot_counter = 0.0
		tool_working()


func activate_tool() -> void:
	self.collision_layer = 128
	$CollisionShape3D.disabled = false
	is_working = is_deployed_on_farm_tile()
	_health_label_activated = true
	_update_label()


func tool_working() -> void:
	if GameAuthority.is_server_authority() or not is_deployed_on_farm_tile():
		return
	var world_parent: Node = GlobalVar.gameworld
	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return
	var boom := load(
		"res://character/weapons/boom.tscn"
	).instantiate() as BoomBullet
	if boom == null:
		return
	world_parent.add_child(boom)
	var direction: Vector3 = (
		$ShootingLine.to_global($ShootingLine.target_position) -
		$ShootingLine.global_position
	).normalized()
	boom.bullet_strength = projectile_damage
	boom.explosion_radius = projectile_radius
	boom.run(
		$ShootingLine.global_position,
		direction * projectile_speed,
		tool_owner
	)


func _on_area_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet or \
	body is DetectLaserBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()
		
		
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false

	last_effect = effect.to_lower()
	if last_effect == "repair_laser":
		disable_remaining = maxf(
			disable_remaining,
			CombatBalance.get_electronic_disable_duration("auto_shooter", "repair_laser")
		)
		is_working = false
		_update_label()
		return true
	if strength <= 0.0:
		return false
	_apply_damage(strength)
	if current_hp <= 0.0:
		return true

	match last_effect:
		"freeze":
			frozen_remaining = maxf(
				frozen_remaining,
				clampf(strength / 5 , 10.0 , 20.0)
			)
		"burn":
			burn_remaining = 3.0
			burn_dps = maxf(burn_dps, strength)
		"lightening":
			disable_remaining = maxf(disable_remaining, CombatBalance.get_electronic_disable_duration("auto_shooter", "lightning"))
			is_working = false
	_update_label()
	return true


func emit() -> void:
	if tool_owner.is_empty():
		return
	var setting_player = get_node_or_null("../../../")  # 这里是根据玩家来的，因为这个工具放到了ToolPivot下面，如果是AIPlayer，注意这里要修改类型
	if not setting_player:
		queue_free()
		return
	var raycast = setting_player.find_child("LookAtTarget",true)  # 这是玩家注视的Raycast。将手持的可放置工具放置玩家正视的位置	
	if raycast == null:
		return
	var tile := Farmlandmanager.resolve_raycast_tile(raycast as RayCast3D)
	if tile != null:
		tile.setting_tool("AutoShooter", tool_owner,setting_player)


func is_deployed_on_farm_tile() -> bool:
	var tile := get_parent() as FarmTile
	return tile != null and is_instance_valid(tile.tool_child) and tile.tool_child == self


func _update_status_effects(delta: float) -> void:
	if frozen_remaining > 0.0:
		frozen_remaining = maxf(0.0, frozen_remaining - delta)
	
	if disable_remaining > 0.0:
		disable_remaining = maxf(0.0, disable_remaining - delta)
	if disable_remaining <= 0.0 and current_hp > 0.0:
		is_working = is_deployed_on_farm_tile()
	
	if burn_remaining > 0.0:
		var tick_time := minf(delta, burn_remaining)
		burn_remaining = maxf(0.0, burn_remaining - delta)
		_apply_damage(burn_dps * tick_time)
		if burn_remaining <= 0.0:
			burn_dps = 0.0
	_update_label()


func _apply_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - amount)
	_update_label()
	if current_hp <= 0.0:
		call_deferred("queue_free")


func _update_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _health_label_activated
	var status := ""
	if frozen_remaining > 0.0:
		status = " 冻结"
	elif burn_remaining > 0.0:
		status = " 灼烧"
	elif disable_remaining > 0.0:
		status = "短路"
	health_label.text = "%d%s" % [int(ceil(current_hp)), status]


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_health_label_activated = true
	_update_label()
