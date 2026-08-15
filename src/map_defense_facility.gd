extends StaticBody3D
class_name MapDefenseFacility

signal defense_destroyed
signal defense_respawned

@export var tool_owner := ""
@export var max_hp := 1800.0
@export var auto_respawn := false
@export_range(1.0, 3600.0, 1.0) var respawn_seconds := 60.0

var current_hp := 0.0
var respawn_left := 0.0
var destroyed := false
var _initial_collision_layer := 0
var _initial_collision_mask := 0
var _initial_hit_layer := 0
var _initial_hit_mask := 0
var _network_visual_only := false


func _ready() -> void:
	add_to_group("map_defense_facilities")
	add_to_group("network_map_devices")
	_initial_collision_layer = collision_layer
	_initial_collision_mask = collision_mask
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if is_instance_valid(hit_area):
		_initial_hit_layer = hit_area.collision_layer
		_initial_hit_mask = hit_area.collision_mask
		if not hit_area.body_entered.is_connected(_on_hit_3d_body_entered):
			hit_area.body_entered.connect(_on_hit_3d_body_entered)
	current_hp = maxf(0.0, max_hp)
	respawn_left = 0.0
	destroyed = false
	_set_defense_active(true)


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or destroyed:
		return
	if body == null or not is_instance_valid(body) or not body.has_method("get_bullet_owner"):
		return
	var attacker_team := str(body.call("get_bullet_owner"))
	var strength := float(body.get("bullet_strength")) if _has_property(body, "bullet_strength") else 0.0
	if strength <= 0.0:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = str(body.get("bullet_effect"))
	var attacker_peer_id := GameAuthority.resolve_attacker_peer_id(attacker_team)
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, attacker_team, -1, attacker_peer_id
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(attacker_team)


func _has_property(object: Object, property_name: String) -> bool:
	for info in object.get_property_list():
		if str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func impact(_effect: String, strength: float, attacker_team := "") -> bool:
	if destroyed or strength <= 0.0 or current_hp <= 0.0:
		return false
	if not attacker_team.is_empty() and not tool_owner.is_empty() and attacker_team == tool_owner:
		return false
	return _apply_impact_strength(strength)


## RemoteBomb 的 friendly_fire 由 GameAuthority 显式传入，不能通过普通 impact()
## 的队伍参数绕过，以免同队普通子弹也能误伤防御设施。
func impact_with_friendly_fire(_effect: String, strength: float, _attacker_team := "") -> bool:
	if destroyed or strength <= 0.0 or current_hp <= 0.0:
		return false
	return _apply_impact_strength(strength)


func _apply_impact_strength(strength: float) -> bool:
	current_hp = maxf(0.0, current_hp - strength)
	if current_hp <= 0.0:
		destroyed = true
		_set_defense_active(false)
		defense_destroyed.emit()
	return true


func apply_network_health(value: float) -> void:
	current_hp = clampf(value, 0.0, maxf(max_hp, 0.0))
	destroyed = current_hp <= 0.0
	_set_defense_active(not destroyed)


func apply_network_destroyed() -> void:
	destroyed = true
	current_hp = 0.0
	_set_defense_active(false)


func apply_network_respawned(value: float = -1.0) -> void:
	current_hp = maxf(0.0, max_hp if value < 0.0 else value)
	respawn_left = 0.0
	destroyed = false
	_set_defense_active(true)
	defense_respawned.emit()


func enable_network_visuals() -> void:
	_network_visual_only = true
	set_process(false)
	set_physics_process(false)
	_set_defense_active(not destroyed)


func get_network_state() -> Dictionary:
	return {
		"hp": current_hp,
		"max_hp": max_hp,
		"team": tool_owner,
		"auto_respawn": auto_respawn,
		"respawn_seconds": respawn_seconds,
		"respawn_left": respawn_left,
		"destroyed": destroyed,
	}


func _set_defense_active(value: bool) -> void:
	visible = value
	var gameplay_active := value and not _network_visual_only
	_set_navigation_obstacle_active(gameplay_active)
	collision_layer = _initial_collision_layer if gameplay_active else 0
	collision_mask = _initial_collision_mask if gameplay_active else 0
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if is_instance_valid(hit_area):
		## impact() can be called from Area3D.body_entered while PhysicsServer3D is
		## flushing queries. Defer the complete Hit3D state change so an explosion
		## cannot trigger the "Function blocked during in/out signal" error.
		hit_area.set_deferred(
			"collision_layer",
			_initial_hit_layer if gameplay_active else 0
		)
		hit_area.set_deferred(
			"collision_mask",
			_initial_hit_mask if gameplay_active else 0
		)
		hit_area.set_deferred("monitoring", gameplay_active)
		hit_area.set_deferred("monitorable", gameplay_active)
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if is_instance_valid(body_shape):
		body_shape.set_deferred("disabled", not gameplay_active)
	var hit_shape := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
	if is_instance_valid(hit_shape):
		hit_shape.set_deferred("disabled", not gameplay_active)
	if has_method("_on_defense_active_changed"):
		call("_on_defense_active_changed", value)


func _set_navigation_obstacle_active(value: bool) -> void:
	## 这里仅切换可爆破防御设施自身的导航障碍。普通建筑的导航障碍由
	## DynamicNavigationChunkGrid 根据 Buildings 下的物理碰撞体统一生成，
	## 不通过防御设施的生命状态接口管理。
	var obstacle := find_child("NavigationObstacle3D", true, false) as NavigationObstacle3D
	if obstacle == null:
		return
	obstacle.set_deferred("affect_navigation_mesh", value)
	obstacle.set_deferred("avoidance_enabled", value)
	var navigation_grid := get_tree().get_first_node_in_group(
		"dynamic_navigation_chunk_grids"
	)
	if navigation_grid != null and navigation_grid.has_method("register_dynamic_obstacle"):
		navigation_grid.call("register_dynamic_obstacle", self, value)
