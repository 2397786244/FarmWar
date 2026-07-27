extends StaticBody3D
class_name BrickTool

@export var tool_owner := ""
@export var max_hp := 1000.0
@export var hp_debug_label: bool = true

var current_hp := max_hp
var is_working := false
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

func _ready() -> void:
	current_hp = max_hp
	_update_health_label()

func activate_tool() -> void:
	collision_layer = 128
	is_working = true
	_update_health_label()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	is_working = true
	_update_health_label()

func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if strength <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	_apply_damage(strength)
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
		tile.setting_tool("Brick", tool_owner,setting_player)

func _on_area_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not is_working:
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

func _apply_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - amount)
	_update_health_label()
	if current_hp <= 0.0:
		call_deferred("queue_free")


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and is_working
	health_label.text = "%d" % int(ceil(current_hp))
