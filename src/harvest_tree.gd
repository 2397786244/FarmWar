extends StaticBody3D
class_name HarvestTree

const NatureResourceIdentity = preload("res://src/nature_resource_identity.gd")
const CombatBalance = preload("res://src/combat_balance.gd")
const NatureResourceHitEffect = preload("res://src/nature_resource_hit_effect.gd")

const MAX_HP := 500.0
const LOG_DROP_COUNT := 4
const FALL_DURATION := 0.8
const FALL_SETTLE_DELAY := 0.18
const HIT_FRAGMENT_COLOR := Color("75452b")

@export var tree_id := ""
@export var resource_id := ""
@export var display_name := ""
@export var log_drop_count := LOG_DROP_COUNT
@export var drops: Array[Dictionary] = [{"item_id": "log", "count": LOG_DROP_COUNT, "weight_kg": 2.0, "model_path": "res://assets/other_items/Material/Log_Drop.glb"}]
var fall_direction := Vector3.ZERO
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D
@onready var mesh_root: Node3D = get_node_or_null("Mesh") as Node3D

var current_hp := MAX_HP
var destroyed := false
var forest_manager: Node = null
var _mesh_initial_transform := Transform3D.IDENTITY
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0


func _ready() -> void:
	add_to_group("harvest_trees")
	add_to_group("regrowing_resources")
	if tree_id.is_empty():
		tree_id = "tree"
	if display_name.is_empty():
		display_name = _localized_tree_name(tree_id)
	if resource_id.is_empty():
		resource_id = NatureResourceIdentity.make_stable_id(self)
	collision_layer = 128
	collision_mask = 32
	_update_health_label()
	if is_instance_valid(mesh_root):
		_mesh_initial_transform = mesh_root.transform
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null:
		hit_area.collision_layer = 128
		hit_area.collision_mask = 32
		if not hit_area.body_entered.is_connected(_on_hit_body_entered):
			hit_area.body_entered.connect(_on_hit_body_entered)


func _on_hit_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or destroyed:
		return
	if not body.has_method("get_bullet_owner"):
		return
	var owner := str(body.call("get_bullet_owner"))
	var owner_peer_id := GameAuthority.resolve_attacker_peer_id(owner)
	var strength := float(body.get("bullet_strength"))
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = str(body.get("bullet_effect"))
	if strength <= 0.0:
		return
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, owner, -1, owner_peer_id
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(owner)


func impact(_effect: String, strength: float, _attacker_team: String = "") -> bool:
	if destroyed or strength <= 0.0:
		_pending_attacker_peer_id = 0
		return false
	_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
		_attacker_team, _pending_attacker_peer_id
	)
	_pending_attacker_peer_id = 0
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	if not GameAuthority.is_server_authority():
		play_hit_effect()
	else:
		GameAuthority.visual_world_event_ready.emit({
			"type": "nature_resource_hit",
			"resource_id": resource_id,
			"resource_kind": "tree",
			"tick": GameAuthority.server_tick,
		})
	if GameAuthority.is_server_authority() and current_hp > 0.0:
		GameAuthority.reliable_world_event_ready.emit({
			"type": "nature_resource_health",
			"resource_id": resource_id,
			"resource_kind": "tree",
			"hp": current_hp,
			"destroyed": false,
			"tick": GameAuthority.server_tick,
		})
	if current_hp <= 0.0:
		destroyed = true
		GameAuthority.award_action_reward(
			_last_attacker_peer_id,
			CombatBalance.get_int("team_rewards", "tree_chopped", 50),
			"砍伐了「%s」" % display_name
		)
		GameAuthority.destroy_harvest_tree(self, maxi(1, log_drop_count))
	return true


func play_hit_effect() -> void:
	var approximate_position := global_position + Vector3(
		randf_range(-0.35, 0.35),
		randf_range(1.2, 2.2),
		randf_range(-0.35, 0.35)
	)
	NatureResourceHitEffect.spawn(get_tree().current_scene, approximate_position, HIT_FRAGMENT_COLOR)


func impact_from_peer(effect: String, strength: float, attacker_team: String, attacker_peer_id: int) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	return impact(effect, strength, attacker_team)


func apply_network_destroyed(direction: Vector3 = Vector3.ZERO) -> void:
	if destroyed:
		return
	destroyed = true
	current_hp = 0.0
	_update_health_label()
	fall_direction = _normalized_fall_direction(direction)
	_play_fall(false)


func apply_network_health(hp: float) -> void:
	current_hp = clampf(hp, 0.0, MAX_HP)
	_update_health_label()


func apply_network_respawned() -> void:
	if destroyed:
		respawn_from_forest()
	else:
		current_hp = MAX_HP
		_update_health_label()


func begin_authoritative_destroy(log_count: int) -> Vector3:
	if not destroyed:
		destroyed = true
		current_hp = 0.0
		_update_health_label()
		fall_direction = _random_fall_direction()
	_play_fall(true)
	return fall_direction


func _play_fall(spawn_logs: bool) -> void:
	collision_layer = 0
	collision_mask = 0
	_disable_collision_nodes()
	# Hide the optimized forest instance as soon as the tree is destroyed. The
	# independent mesh below is kept only for the short falling animation.
	if is_instance_valid(forest_manager):
		forest_manager.on_resource_destroyed(self)
	if is_instance_valid(health_label):
		health_label.visible = false
	if is_instance_valid(mesh_root):
		mesh_root.visible = true
		# Every tree falls in one deterministic horizontal direction. The axis is
		# perpendicular to that direction, so the trunk's local Y axis ends up
		# parallel to the ground instead of receiving a random tilt.
		var direction := _normalized_fall_direction(fall_direction)
		var rotation_axis := Vector3.UP.cross(direction).normalized()
		var target_basis := Basis(rotation_axis, PI * 0.5) * mesh_root.basis.orthonormalized()
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(mesh_root, "basis", target_basis, FALL_DURATION)
		tween.tween_interval(FALL_SETTLE_DELAY)
		tween.tween_callback(func() -> void:
			mesh_root.visible = false
			if spawn_logs and is_instance_valid(GameAuthority):
				GameAuthority.spawn_nature_resource_drops(global_position, drops)
			if not is_instance_valid(forest_manager):
				queue_free()
		)
	else:
		if spawn_logs and is_instance_valid(GameAuthority):
			GameAuthority.spawn_nature_resource_drops(global_position, drops)
		if not is_instance_valid(forest_manager):
			queue_free()


func respawn_from_forest() -> void:
	destroyed = false
	current_hp = MAX_HP
	fall_direction = Vector3.ZERO
	collision_layer = 128
	collision_mask = 32
	_enable_collision_nodes()
	if is_instance_valid(mesh_root):
		mesh_root.transform = _mesh_initial_transform
		mesh_root.visible = false
	_update_health_label()
	if is_instance_valid(forest_manager):
		forest_manager._set_instance_visible(self, true)


func find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested := find_first_mesh_instance(child)
		if nested != null:
			return nested
	return null


func _random_fall_direction() -> Vector3:
	var angle := randf_range(0.0, TAU)
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


func _normalized_fall_direction(direction: Vector3) -> Vector3:
	var horizontal := direction
	horizontal.y = 0.0
	return horizontal.normalized() if horizontal.length_squared() > 0.001 else Vector3.RIGHT


func _localized_tree_name(id: String) -> String:
	match id.to_lower():
		"oak":
			return "橡树"
		"cottonwood":
			return "棉白杨"
		"redcedar":
			return "红雪松"
		"redmaple":
			return "红枫"
		_:
			return id if not id.is_empty() else "树木"


func _disable_collision_nodes() -> void:
	for node in find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).set_deferred("disabled", true)
	for node in find_children("*", "CollisionPolygon3D", true, false):
		(node as CollisionPolygon3D).set_deferred("disabled", true)
	for node in find_children("*", "Area3D", true, false):
		(node as Area3D).set_deferred("monitoring", false)
		(node as Area3D).set_deferred("monitorable", false)


func _enable_collision_nodes() -> void:
	for node in find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).disabled = false
	for node in find_children("*", "CollisionPolygon3D", true, false):
		(node as CollisionPolygon3D).disabled = false
	for node in find_children("*", "Area3D", true, false):
		(node as Area3D).monitoring = true
		(node as Area3D).monitorable = true


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = not destroyed
	health_label.text = "%d" % int(ceil(current_hp))
