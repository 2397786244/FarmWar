extends CharacterBody3D
class_name AntiAirTool

@export var defend_bullet_speed = 30
@export var cooldown_time:float = 10.0
@export var intercept_range: float = 15.0
@export var magazine_size: int = 8
@export var tool_owner:String = ""
@export var hp_debug_label: bool = true
var current_hp = 500
var bullet_amount = magazine_size
var current_time :float = 0
var _protection_enabled:bool = true
var burn_remaining:float
var burn_dps:float
var disable_remaining:float  # for lightening
var placed:bool = false
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

func _on_area_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if tool_owner == "":
		return
	if not placed:
		return
		
	if _protection_enabled == false:
		return
	if body is BoomBullet:
		if body.get_bullet_owner() == tool_owner:
			return		
		if current_time <= 0:
			# 发射一个高速的DefendBullet将其引爆
			var defend_bullet = load("res://character/weapons/DefendBullet.tscn").instantiate()
			GlobalVar.gameworld.add_child(defend_bullet)
			defend_bullet.bullet_owner = tool_owner
			defend_bullet.track(body,defend_bullet_speed)
			defend_bullet.global_position = self.global_position + Vector3(0,2,0)
			bullet_amount -= 1
			if bullet_amount == 0:
				bullet_amount = magazine_size
				current_time = cooldown_time

var visual_obj:Node3D
var user_node:GamePlayer
var raycast:RayCast3D
func _ready() -> void:
	_update_label()
	#user_node = get_node_or_null("../../../")  # 这里是根据玩家来的，因为这个工具放到了ToolPivot下面，如果是AIPlayer，注意这里要修改类型
	#print(user_node)
	#if not user_node:
		#queue_free()
		#return
	#raycast = user_node.find_child("LookAtTarget",true)  # 这是玩家注视的Raycast。将手持的可放置工具放置玩家正视的位置				
			
func _physics_process(delta: float) -> void:		
	if current_time > 0:
		current_time -= delta
	else:
		current_time = 0
	_update_status_effects(delta)
	
func _apply_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - amount)
	_update_label()
	if current_hp <= 0.0:
		_protection_enabled = false
		call_deferred("queue_free")
		
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not attacker_team.is_empty() and tool_owner == attacker_team:
		return false
	var last_effect = effect.to_lower()
	if last_effect == "repair_laser":
		disable_remaining = maxf(
			disable_remaining,
			CombatBalance.get_electronic_disable_duration("anti_air", "repair_laser")
		)
		_protection_enabled = false
		return true
	if strength <= 0.0:
		return false
	_apply_damage(strength)
	if current_hp <= 0.0:
		return true
	match last_effect:
		"flame":
			burn_remaining = 3.0
			burn_dps = maxf(burn_dps, strength)
		"lightening":
			disable_remaining = maxf(disable_remaining, CombatBalance.get_electronic_disable_duration("anti_air", "lightning"))
			_protection_enabled = false
	return true
	

func _update_status_effects(delta: float) -> void:
	if disable_remaining > 0.0:
		disable_remaining = maxf(0.0, disable_remaining - delta)
	if disable_remaining <= 0.0 and current_hp > 0.0:
		_protection_enabled = true

	if burn_remaining > 0.0:
		var tick_time := minf(delta, burn_remaining)
		burn_remaining = maxf(0.0, burn_remaining - delta)
		_apply_damage(burn_dps * tick_time)
		if burn_remaining <= 0.0:
			burn_dps = 0.0
	_update_label()


func _update_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and placed
	var status := ""
	if burn_remaining > 0.0:
		status = " 灼烧"
	elif disable_remaining > 0.0:
		status = "短路"
	health_label.text = "%d%s" % [int(ceil(current_hp)), status]


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	placed = true
	_update_label()


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet \
	or body is DetectLaserBullet):
		return
	var projectile_owner = str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()

func activate_tool():
	collision_layer = 128
	placed = true
	$CollisionShape3D.disabled = false
	_update_label()
	
func emit():
	user_node = get_node_or_null("../../../")  # 这里是根据玩家来的，因为这个工具放到了ToolPivot下面，如果是AIPlayer，注意这里要修改类型
	if not user_node:
		queue_free()
		return
	raycast = user_node.find_child("LookAtTarget",true)  # 这是玩家注视的Raycast。将手持的可放置工具放置玩家正视的位置				
	if tool_owner.is_empty() or not user_node:
		return
	if not raycast or  not raycast.is_colliding():
		return
	var gvec3 = raycast.get_collision_point()
	var antiair = load("res://character/weapons/AntiAir.tscn").instantiate()
	GlobalVar.gameworld.add_child(antiair)
	antiair.global_position = gvec3
	
	antiair.tool_owner = self.tool_owner
	#print(user_node.rotation)
	antiair.rotation.y = user_node.rotation.y
	#if is_instance_valid(visual_obj):
		#visual_obj.queue_free()
	antiair.activate_tool()
