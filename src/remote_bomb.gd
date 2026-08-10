extends StaticBody3D
class_name RemoteBomb

signal destroyed(bomb: Node3D)

@export var max_hp := 50.0
@export var tool_owner := ""

const TOOL_COLLISION_LAYER := 128
const BULLET_COLLISION_LAYER := 32

var current_hp := 0.0
var is_destroyed := false
var is_detonating := false
var engineer_owner: Node

@onready var hit_3d: Area3D = get_node_or_null("Hit3D") as Area3D
@onready var hit_shape: CollisionShape3D = get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D


func _ready() -> void:
	add_to_group("remote_bombs")
	current_hp = maxf(0.0, max_hp)
	collision_layer = TOOL_COLLISION_LAYER
	collision_mask = 0
	if is_instance_valid(hit_3d):
		hit_3d.collision_layer = TOOL_COLLISION_LAYER
		hit_3d.collision_mask = BULLET_COLLISION_LAYER
		hit_3d.monitoring = true
		hit_3d.monitorable = true
		if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
			hit_3d.body_entered.connect(_on_hit_3d_body_entered)
		if not hit_3d.area_entered.is_connected(_on_hit_3d_area_entered):
			hit_3d.area_entered.connect(_on_hit_3d_area_entered)
	if is_instance_valid(hit_shape):
		hit_shape.set_deferred("disabled", false)


func setup(owner: Node, owner_team: String, health := -1.0) -> void:
	engineer_owner = owner
	tool_owner = owner_team
	if health >= 0.0:
		max_hp = health
	current_hp = maxf(0.0, max_hp)


func _on_hit_3d_body_entered(body: Node3D) -> void:
	_handle_hit_contact(body)


func _on_hit_3d_area_entered(area: Area3D) -> void:
	_handle_hit_contact(area)


func _handle_hit_contact(contact: Node) -> void:
	if is_destroyed or is_detonating or contact == null:
		return
	var projectile := _find_projectile_root(contact)
	if projectile == null or not projectile.has_method("get_bullet_owner"):
		return
	var attacker_team := str(projectile.call("get_bullet_owner"))
	var damage := _projectile_damage(projectile)
	if damage <= 0.0:
		return
	var effect := "Explosion" if projectile is BoomBullet else "bullet"
	if _has_property(projectile, "bullet_effect"):
		effect = str(projectile.get("bullet_effect"))
	var authority := get_node_or_null("/root/GameAuthority")
	if authority == null:
		return
	var attacker_peer_id := int(authority.call("resolve_attacker_peer_id", attacker_team))
	var applied := bool(authority.call(
		"_apply_hit_to_collider",
		self,
		effect,
		damage,
		attacker_team,
		-1,
		attacker_peer_id
	))
	if applied and is_instance_valid(projectile):
		projectile.queue_free()


func impact(effect: String, strength: float, _attacker_team := "") -> bool:
	## RemoteBomb 的受击不检查攻击者队伍，包括自身队伍的攻击。
	## 这里是“被摧毁”路径，不调用 consume_for_detonation()，因此 HP 归零
	## 时只发出 destroyed 信号并移除炸弹，不会触发 RemoteBomb 爆炸。
	if is_destroyed or is_detonating or strength <= 0.0:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	if current_hp <= 0.0:
		_destroy_without_explosion(effect)
	return true


func receive_bullet_hit(_hit_direction: Vector3, _force: float, _attacker_team: String) -> void:
	return


func consume_for_detonation() -> bool:
	if is_destroyed or is_detonating:
		return false
	is_detonating = true
	_disable_collision()
	queue_free()
	return true


func disarm() -> void:
	if is_destroyed or is_detonating:
		return
	is_detonating = true
	_disable_collision()
	queue_free()


func _destroy_without_explosion(effect: String) -> void:
	if is_destroyed or is_detonating:
		return
	is_destroyed = true
	_disable_collision()
	destroyed.emit(self)
	print("[RemoteBomb] destroyed effect=%s owner_team=%s" % [effect, tool_owner])
	queue_free()


func _disable_collision() -> void:
	## impact() can be entered from Hit3D.body_entered/area_entered while
	## PhysicsServer3D is flushing queries; defer Area3D state changes.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(hit_3d):
		hit_3d.set_deferred("collision_layer", 0)
		hit_3d.set_deferred("collision_mask", 0)
		hit_3d.set_deferred("monitoring", false)
		hit_3d.set_deferred("monitorable", false)
	if is_instance_valid(hit_shape):
		hit_shape.set_deferred("disabled", true)


func _find_projectile_root(contact: Node) -> Node3D:
	var cursor := contact
	var depth := 0
	while cursor != null and depth < 16:
		if cursor is Node3D and cursor.has_method("get_bullet_owner"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


func _projectile_damage(projectile: Node3D) -> float:
	for property_name in ["bullet_strength", "damage", "bullet_damage"]:
		if _has_property(projectile, property_name):
			return maxf(0.0, float(projectile.get(property_name)))
	return 0.0


func _has_property(object: Object, property_name: String) -> bool:
	for info in object.get_property_list():
		if str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false
