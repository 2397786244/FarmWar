extends StaticBody3D
class_name ShieldTool

## TODO:游戏中存在以下子弹、炮弹效果：
# Explosion
# Flame
# Freeze
# Recue
# Poison
# Lightening
@export var tool_owner := ""
@export var max_hp := 3000.0
@export var hp_debug_label: bool = true

var current_hp := 3000.0
var is_working := false
var frozen_remaining := 0.0
var burn_remaining := 0.0
var burn_dps := 0.0
var last_effect := ""
var protection_enabled := true
var _health_label_activated := false
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	current_hp = max_hp
	_update_label()


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)


func activate_tool() -> void:
	self.collision_layer = 128
	is_working = true
	_health_label_activated = true
	$CollisionShape3D.disabled = false
	_set_protection_enabled(true)
	_update_label()


func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if strength <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false

	last_effect = effect.to_lower()
	_apply_damage(strength)
	if current_hp <= 0.0:
		return true

	match last_effect:
		"freeze":
			frozen_remaining = maxf(
				frozen_remaining,
				clampf(strength / 5, 10.0, 20.0)
			)
			_set_protection_enabled(false)
		"flame":
			burn_remaining = 5.0
			burn_dps = maxf(burn_dps, strength)
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
		tile.setting_tool("ShieldDoor", tool_owner,setting_player)


func _on_area_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not protection_enabled:
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()


func _update_status_effects(delta: float) -> void:
	var was_frozen := frozen_remaining > 0.0
	if frozen_remaining > 0.0:
		frozen_remaining = maxf(0.0, frozen_remaining - delta)
	if was_frozen and frozen_remaining <= 0.0 and current_hp > 0.0:
		_set_protection_enabled(true)

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
		_set_protection_enabled(false)
		call_deferred("queue_free")


func _set_protection_enabled(enabled: bool) -> void:
	protection_enabled = enabled
	if enabled:
		# 如果开启，那么显示辉光
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_BaseGlow.visible=true
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_Core.visible=true
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_PillarGlow_Left.visible=true
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_PillarGlow_Right.visible=true
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_EnergySurface.visible=true
	else:
		# 不显示光
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_BaseGlow.visible=false
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_Core.visible=false
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_PillarGlow_Left.visible=false
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_PillarGlow_Right.visible=false
		$Mesh/ASSET_FTF_Energy_Shield_Blue_5m/EnergyShield_EnergySurface.visible=false
	if is_instance_valid($Area3D):
		$Area3D.set_deferred("monitoring", enabled)


func _update_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _health_label_activated
	var status := ""
	if frozen_remaining > 0.0:
		status = " 冻结/失效"
	elif burn_remaining > 0.0:
		status = " 灼烧"
	health_label.text = "%d%s" % [int(ceil(current_hp)), status]


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_health_label_activated = true
	_update_label()
