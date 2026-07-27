extends StaticBody3D
class_name AreaProtectorTool

const CombatBalance = preload("res://src/combat_balance.gd")
const BORDER_THICKNESS := 0.08
const BORDER_COLOR := Color(0.82, 0.55, 0.08, 0.92)

@export var tool_owner := ""
@export var activate_on_ready := false
@export var network_device_id := ""

var activated := false
var max_hp := 0.0
var current_hp := 0.0
var protection_size := Vector3.ZERO
var projectile_speed_multiplier := 1.0
var projectile_damage_multiplier := 1.0

@onready var protection_visual: MeshInstance3D = $ProtectionVisual
@onready var protection_border: Node3D = $ProtectionVisual/ProtectionBorder
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var hit_area: Area3D = $Hit3D
@onready var hit_shape: CollisionShape3D = $Hit3D/CollisionShape3D


func _ready() -> void:
	max_hp = CombatBalance.get_tool_max_hp("area_protector")
	current_hp = max_hp
	protection_size = Vector3(
		CombatBalance.get_float("area_protector", "size_x"),
		CombatBalance.get_float("area_protector", "size_y"),
		CombatBalance.get_float("area_protector", "size_z")
	)
	projectile_speed_multiplier = CombatBalance.get_float(
		"area_protector", "speed_multiplier", 0.1
	)
	projectile_damage_multiplier = CombatBalance.get_float(
		"area_protector", "damage_multiplier", 0.5
	)
	_configure_protection_visual()
	_set_gameplay_collision_enabled(false)
	if not network_device_id.is_empty():
		set_meta("network_device_id", network_device_id)
	if activate_on_ready:
		activate_tool()


func activate_tool() -> void:
	if current_hp <= 0.0:
		return
	activated = true
	add_to_group("area_protectors")
	protection_visual.visible = true
	_set_gameplay_collision_enabled(not GameAuthority.is_client_proxy())


func enable_network_visuals() -> void:
	# Client proxies render the field but never participate in authoritative hits.
	activated = true
	add_to_group("area_protectors")
	protection_visual.visible = true


func impact(_effect: String, strength: float, attacker_team: String = "") -> bool:
	if GameAuthority.should_send_network_requests() or not activated \
			or strength <= 0.0 or current_hp <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	if current_hp <= 0.0:
		activated = false
		protection_visual.visible = false
		_set_gameplay_collision_enabled(false)
		remove_from_group("area_protectors")
	return true


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	if current_hp <= 0.0:
		activated = false
		protection_visual.visible = false
		remove_from_group("area_protectors")


func affects_projectile_at_position(world_position: Vector3, projectile_team: String) -> bool:
	if not activated or current_hp <= 0.0:
		return false
	if not tool_owner.is_empty() and projectile_team == tool_owner:
		return false
	var local_position := to_local(world_position)
	return local_position.x >= -protection_size.x * 0.5 \
		and local_position.x <= protection_size.x * 0.5 \
		and local_position.y >= 0.0 \
		and local_position.y <= protection_size.y \
		and local_position.z >= -protection_size.z * 0.5 \
		and local_position.z <= protection_size.z * 0.5


static func get_cannonball_speed_multiplier_at(
	context: Node,
	world_position: Vector3,
	projectile_team: String
) -> float:
	var multiplier := 1.0
	if context == null or not context.is_inside_tree():
		return multiplier
	for node in context.get_tree().get_nodes_in_group("area_protectors"):
		if node is AreaProtectorTool:
			var protector := node as AreaProtectorTool
			if protector.affects_projectile_at_position(world_position, projectile_team):
				multiplier = minf(multiplier, protector.projectile_speed_multiplier)
	return multiplier


static func get_damage_multiplier_at(
	context: Node,
	world_position: Vector3,
	projectile_team: String
) -> float:
	var multiplier := 1.0
	if context == null or not context.is_inside_tree():
		return multiplier
	for node in context.get_tree().get_nodes_in_group("area_protectors"):
		if node is AreaProtectorTool:
			var protector := node as AreaProtectorTool
			if protector.affects_projectile_at_position(world_position, projectile_team):
				multiplier = minf(multiplier, protector.projectile_damage_multiplier)
	return multiplier


func _configure_protection_visual() -> void:
	if not is_instance_valid(protection_visual):
		return
	var box := protection_visual.mesh as BoxMesh
	if box != null:
		box = box.duplicate() as BoxMesh
		box.size = protection_size
		var field_material := box.material as StandardMaterial3D
		if field_material != null:
			field_material = field_material.duplicate() as StandardMaterial3D
			field_material.no_depth_test = false
			box.material = field_material
			protection_visual.material_override = field_material
		protection_visual.mesh = box
	_configure_protection_border()
	protection_visual.position.y = protection_size.y * 0.5
	protection_visual.visible = false


func _configure_protection_border() -> void:
	if not is_instance_valid(protection_border):
		return
	for child in protection_border.get_children():
		child.free()

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = BORDER_COLOR
	material.emission_enabled = true
	material.emission = BORDER_COLOR
	material.emission_energy_multiplier = 0.65
	material.no_depth_test = false

	var half_size := protection_size * 0.5
	for y_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_border_edge(
				Vector3(0.0, half_size.y * y_sign, half_size.z * z_sign),
				Vector3(protection_size.x, BORDER_THICKNESS, BORDER_THICKNESS),
				material
			)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_border_edge(
				Vector3(half_size.x * x_sign, 0.0, half_size.z * z_sign),
				Vector3(BORDER_THICKNESS, protection_size.y, BORDER_THICKNESS),
				material
			)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			_add_border_edge(
				Vector3(half_size.x * x_sign, half_size.y * y_sign, 0.0),
				Vector3(BORDER_THICKNESS, BORDER_THICKNESS, protection_size.z),
				material
			)


func _add_border_edge(
	position_value: Vector3,
	size_value: Vector3,
	material: StandardMaterial3D
) -> void:
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = size_value
	edge_mesh.material = material
	var edge := MeshInstance3D.new()
	edge.name = "Edge"
	edge.position = position_value
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.mesh = edge_mesh
	protection_border.add_child(edge)


func _set_gameplay_collision_enabled(enabled: bool) -> void:
	collision_layer = GameAuthority.COLLISION_LAYER_TOOL if enabled else 0
	collision_mask = (
		GameAuthority.FREE_PLACEMENT_BLOCKING_MASK
		| GameAuthority.COLLISION_LAYER_GROUND
	) if enabled else 0
	if is_instance_valid(body_shape):
		body_shape.set_deferred("disabled", not enabled)
	if is_instance_valid(hit_area):
		hit_area.collision_layer = GameAuthority.COLLISION_LAYER_TOOL if enabled else 0
		hit_area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET if enabled else 0
		hit_area.set_deferred("monitoring", enabled)
		hit_area.set_deferred("monitorable", enabled)
	if is_instance_valid(hit_shape):
		hit_shape.set_deferred("disabled", not enabled)
