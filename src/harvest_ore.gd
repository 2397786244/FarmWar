extends StaticBody3D
class_name HarvestOre

const NatureResourceIdentity = preload("res://src/nature_resource_identity.gd")
const CombatBalance = preload("res://src/combat_balance.gd")
const NatureResourceHitEffect = preload("res://src/nature_resource_hit_effect.gd")

const NATURE_RESOURCE_LAYER := 16384
const BULLET_LAYER := 32
const HIT_FRAGMENT_COLOR := Color("858b90")

@export var resource_id := ""
@export var resource_type := "ore"
@export var resource_kind := "ore"
@export var display_name := "矿石"
@export var max_hp := 400.0
@export var respawn_seconds := 90.0
@export var drops: Array[Dictionary] = []
@export var show_hit_particles := true
@export var destroy_reward_description := ""

var current_hp := 0.0
var destroyed := false
var forest_manager: Node = null
var _mesh_initial_transform := Transform3D.IDENTITY
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0

@onready var mesh_root: Node3D = get_node_or_null("Mesh") as Node3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	add_to_group("nature_resources")
	add_to_group("harvest_ores")
	if resource_kind == "mushroom":
		add_to_group("harvest_mushrooms")
	add_to_group("regrowing_resources")
	if resource_id.is_empty():
		resource_id = NatureResourceIdentity.make_stable_id(self)
	current_hp = max_hp
	collision_layer = NATURE_RESOURCE_LAYER
	collision_mask = BULLET_LAYER
	if is_instance_valid(mesh_root):
		_mesh_initial_transform = mesh_root.transform
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null:
		hit_area.collision_layer = NATURE_RESOURCE_LAYER
		hit_area.collision_mask = BULLET_LAYER
		if not hit_area.body_entered.is_connected(_on_hit_body_entered):
			hit_area.body_entered.connect(_on_hit_body_entered)
	_update_health_label()


func _on_hit_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or destroyed:
		return
	if not body.has_method("get_bullet_owner"):
		return
	var strength := float(body.get("bullet_strength"))
	if strength <= 0.0:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = str(body.get("bullet_effect"))
	var owner_team := str(body.call("get_bullet_owner"))
	var owner_peer_id := GameAuthority.resolve_attacker_peer_id(owner_team)
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, owner_team, -1, owner_peer_id
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(owner_team)


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
	if not GameAuthority.is_server_authority() and show_hit_particles:
		play_hit_effect()
	elif GameAuthority.is_server_authority() and show_hit_particles:
		GameAuthority.visual_world_event_ready.emit({
			"type": "nature_resource_hit",
			"resource_id": resource_id,
			"resource_kind": resource_kind,
			"tick": GameAuthority.server_tick,
		})
	if GameAuthority.is_server_authority():
		_emit_health_event(current_hp <= 0.0)
	if current_hp <= 0.0:
		destroyed = true
		var reward_description := destroy_reward_description
		if reward_description.is_empty():
			reward_description = "采集了%s" % display_name if resource_kind == "mushroom" else "开采了%s" % display_name
		GameAuthority.award_action_reward(
			_last_attacker_peer_id,
			CombatBalance.get_int("team_rewards", "ore_mined", 50),
			reward_description
		)
		_play_destroy(true)
	return true


func play_hit_effect() -> void:
	var approximate_position := global_position + Vector3(
		randf_range(-0.4, 0.4),
		randf_range(0.2, 0.8),
		randf_range(-0.4, 0.4)
	)
	NatureResourceHitEffect.spawn(get_tree().current_scene, approximate_position, HIT_FRAGMENT_COLOR)


func impact_from_peer(effect: String, strength: float, attacker_team: String, attacker_peer_id: int) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	return impact(effect, strength, attacker_team)


func apply_network_health(hp: float) -> void:
	current_hp = clampf(hp, 0.0, max_hp)
	_update_health_label()


func apply_network_destroyed(_direction: Vector3 = Vector3.ZERO) -> void:
	if destroyed:
		return
	destroyed = true
	current_hp = 0.0
	_update_health_label()
	_play_destroy(false)


func apply_network_respawned() -> void:
	respawn_from_forest()


func respawn_from_forest() -> void:
	destroyed = false
	current_hp = max_hp
	collision_layer = NATURE_RESOURCE_LAYER
	collision_mask = BULLET_LAYER
	_enable_collision_nodes()
	if is_instance_valid(mesh_root):
		mesh_root.transform = _mesh_initial_transform
		mesh_root.visible = not is_instance_valid(forest_manager)
	if is_instance_valid(forest_manager):
		forest_manager.call("_set_resource_instance_visible", self, true)
	_update_health_label()


func _play_destroy(spawn_drops: bool) -> void:
	collision_layer = 0
	collision_mask = 0
	_disable_collision_nodes()
	if is_instance_valid(forest_manager):
		forest_manager.call("on_resource_destroyed", self)
	if is_instance_valid(health_label):
		health_label.visible = false
	if is_instance_valid(mesh_root):
		mesh_root.visible = false
	_spawn_drops_if_authority(spawn_drops)


func _spawn_drops_if_authority(spawn_drops: bool) -> void:
	if spawn_drops and not drops.is_empty() and is_instance_valid(GameAuthority):
		GameAuthority.grant_ore_harvest(_last_attacker_peer_id, global_position, drops)


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
		var area := node as Area3D
		area.collision_layer = NATURE_RESOURCE_LAYER
		area.collision_mask = BULLET_LAYER
		area.monitoring = true
		area.monitorable = true


func _emit_health_event(is_destroyed: bool) -> void:
	GameAuthority.reliable_world_event_ready.emit({
		"type": "nature_resource_health",
		"resource_id": resource_id,
		"resource_kind": resource_kind,
		"hp": current_hp,
		"destroyed": is_destroyed,
		"tick": GameAuthority.server_tick,
	})


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = not destroyed
	health_label.text = "%d" % int(ceil(current_hp))
