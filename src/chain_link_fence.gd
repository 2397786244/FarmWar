extends StaticBody3D
class_name ChainLinkFence

const DAMAGE_PER_SECOND := 20.0
const TARGET_SPEED_MULTIPLIER := 0.5
const FENCE_HALF_LENGTH := 2.0
const FENCE_RADIUS := 0.6
const FENCE_CENTER_HEIGHT := 0.6
const TARGET_COLLISION_MASK := (
	GameAuthority.COLLISION_LAYER_BULLET
	| GameAuthority.COLLISION_LAYER_CHARACTER
	| GameAuthority.COLLISION_LAYER_TOOL
	| GameAuthority.COLLISION_LAYER_VEHICLES
	| GameAuthority.COLLISION_LAYER_WILD_ANIMAL
)

@export var tool_owner := ""
@export var max_hp := 300.0
@export var activate_on_ready := false
@export var network_device_id := ""

var current_hp := 0.0
var active := false
var destroyed := false
var _network_visual_only := false

@onready var body_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var hit_area: Area3D = get_node_or_null("Hit3D") as Area3D
@onready var hit_shape: CollisionShape3D = get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D


func _ready() -> void:
	add_to_group("chain_link_fences")
	add_to_group("network_map_devices")
	add_to_group("network_placed_tools")
	current_hp = maxf(0.0, max_hp)
	if network_device_id.is_empty() and has_meta("network_device_id"):
		network_device_id = str(get_meta("network_device_id"))
	if not is_instance_valid(hit_area):
		push_error("ChainLinkFence: missing Hit3D Area3D.")
	else:
		if not hit_area.body_entered.is_connected(_on_hit_body_entered):
			hit_area.body_entered.connect(_on_hit_body_entered)
		if not hit_area.area_entered.is_connected(_on_hit_area_entered):
			hit_area.area_entered.connect(_on_hit_area_entered)
	_set_gameplay_active(false)
	if activate_on_ready:
		activate_tool()


func _physics_process(delta: float) -> void:
	if not active or destroyed or _network_visual_only \
			or GameAuthority.should_send_network_requests():
		return
	if not is_instance_valid(hit_area) or not hit_area.monitoring:
		return
	var amount := DAMAGE_PER_SECOND * maxf(delta, 0.0)
	if amount <= 0.0:
		return
	var processed_targets: Dictionary = {}
	for body_value: Variant in hit_area.get_overlapping_bodies():
		if body_value is Node3D and is_instance_valid(body_value):
			var body := body_value as Node3D
			var target_key := body.get_instance_id()
			if GameAuthority.has_method("_chain_link_target_root"):
				var resolved: Variant = GameAuthority.call("_chain_link_target_root", body)
				if resolved is Node3D and is_instance_valid(resolved):
					target_key = (resolved as Node3D).get_instance_id()
			if processed_targets.has(target_key):
				continue
			processed_targets[target_key] = true
			GameAuthority.apply_chain_link_fence_effect(self, body, amount)


func activate_tool() -> void:
	_network_visual_only = false
	destroyed = false
	current_hp = maxf(current_hp, max_hp)
	active = current_hp > 0.0
	visible = active
	_set_gameplay_active(active)


func enable_network_visuals() -> void:
	_network_visual_only = true
	active = current_hp > 0.0 and not destroyed
	visible = active
	_set_gameplay_active(false)
	set_process(false)
	set_physics_process(false)


func apply_network_health(value: float) -> void:
	current_hp = clampf(value, 0.0, maxf(max_hp, 0.0))
	destroyed = current_hp <= 0.0
	active = not destroyed
	visible = active
	_set_gameplay_active(active and not _network_visual_only)


func apply_network_destroyed() -> void:
	current_hp = 0.0
	destroyed = true
	active = false
	visible = false
	_set_gameplay_active(false)


func impact(_effect: String, strength: float, attacker_team := "") -> bool:
	if destroyed or strength <= 0.0 or current_hp <= 0.0:
		return false
	if not attacker_team.is_empty() and not tool_owner.is_empty() \
			and attacker_team == tool_owner:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	if current_hp <= 0.0:
		destroyed = true
		active = false
		visible = false
		_set_gameplay_active(false)
	return true


func is_target_slowed(target_team := "", target_kind := "") -> bool:
	if not active or destroyed or current_hp <= 0.0:
		return false
	if target_kind == "wild_animal":
		return true
	if target_kind == "remote":
		return tool_owner.is_empty() or target_team.is_empty() or target_team != tool_owner
	if target_kind not in ["player", "ai", "vehicle"]:
		return false
	if tool_owner.is_empty():
		return true
	return target_team.is_empty() or target_team != tool_owner


func contains_world_position(world_position: Vector3) -> bool:
	if not active or destroyed or current_hp <= 0.0:
		return false
	var local_position := to_local(world_position)
	return absf(local_position.x) <= FENCE_HALF_LENGTH + FENCE_RADIUS \
		and absf(local_position.z) <= FENCE_RADIUS + 0.35 \
		and absf(local_position.y - FENCE_CENTER_HEIGHT) <= FENCE_RADIUS + 0.45


func _on_hit_body_entered(body: Node3D) -> void:
	_handle_hit_contact(body)


func _on_hit_area_entered(area: Area3D) -> void:
	_handle_hit_contact(area)


func _handle_hit_contact(contact: Node) -> void:
	if not active or destroyed or _network_visual_only \
			or GameAuthority.should_send_network_requests():
		return
	var bullet := _find_bullet_root(contact)
	if bullet == null or not bullet.has_method("get_bullet_owner"):
		return
	var attacker_team := str(bullet.call("get_bullet_owner"))
	var strength := _bullet_strength(bullet)
	if strength <= 0.0:
		return
	var effect := "Explosion" if bullet is BoomBullet else "None"
	if bullet is ColorBullet or bullet is DetectLaserBullet:
		effect = str(bullet.get("bullet_effect"))
	var attacker_peer_id := GameAuthority.resolve_attacker_peer_id(attacker_team)
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, attacker_team, -1, attacker_peer_id
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(attacker_team)
		if is_instance_valid(bullet):
			bullet.queue_free()


func _find_bullet_root(contact: Node) -> Node3D:
	var cursor: Node = contact
	var depth := 0
	while cursor != null and depth < 14:
		if cursor is Node3D and cursor.has_method("get_bullet_owner"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


func _bullet_strength(bullet: Node) -> float:
	for property_name in ["bullet_strength", "damage", "bullet_damage"]:
		if _has_property(bullet, property_name):
			return maxf(0.0, float(bullet.get(property_name)))
	return 0.0


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _set_gameplay_active(enabled: bool) -> void:
	var active_for_gameplay := enabled and not _network_visual_only
	_set_navigation_obstacle_active(active_for_gameplay)
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(body_shape):
		body_shape.set_deferred("disabled", true)
	if not is_instance_valid(hit_area):
		return
	hit_area.collision_layer = GameAuthority.COLLISION_LAYER_TOOL if active_for_gameplay else 0
	hit_area.collision_mask = TARGET_COLLISION_MASK if active_for_gameplay else 0
	hit_area.monitoring = active_for_gameplay
	hit_area.monitorable = active_for_gameplay
	if is_instance_valid(hit_shape):
		hit_shape.set_deferred("disabled", not active_for_gameplay)


func _set_navigation_obstacle_active(value: bool) -> void:
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
