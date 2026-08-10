extends StaticBody3D
class_name WoodTower

const PLAYER_LAYER := 8
const DEFAULT_CLIMB_SPEED := 2.6
const PLAYER_INTERACTION_RADIUS := 0.55
const PLAYER_INTERACTION_HALF_HEIGHT := 1.05

@export var climb_speed := DEFAULT_CLIMB_SPEED

@onready var climb_area := $ClimbArea as Area3D
@onready var climb_top := $ClimbTop as Area3D
@onready var top_pos := $TopPos as Marker3D
@onready var climb_down_pos := get_node_or_null("ClimbDownPos") as Marker3D

func _ready() -> void:
	add_to_group("wood_towers")
	for area in [climb_area, climb_top]:
		if area == null:
			continue
		area.collision_layer = 0
		area.collision_mask = PLAYER_LAYER

func get_tower_id() -> String:
	return str(get_path())

func get_top_position() -> Vector3:
	return top_pos.global_position if top_pos != null else global_position + Vector3.UP * 10.0

func get_climb_down_position() -> Vector3:
	if climb_down_pos != null and is_instance_valid(climb_down_pos):
		return climb_down_pos.global_position
	return climb_top.global_position if climb_top != null else global_position + Vector3.UP * 10.0

func get_climb_down_yaw() -> float:
	var forward := -global_transform.basis.z
	if climb_down_pos != null and is_instance_valid(climb_down_pos):
		var marker_forward := -climb_down_pos.global_transform.basis.z
		marker_forward.y = 0.0
		if marker_forward.length_squared() > 0.001:
			forward = marker_forward.normalized()
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return global_rotation.y
	return atan2(-forward.x, -forward.z)

func _area_contains_point(area: Area3D, world_position: Vector3, include_player_extent := false) -> bool:
	if area == null:
		return false
	for child in area.get_children():
		if not child is CollisionShape3D:
			continue
		var shape_node := child as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled:
			continue
		var local_position := shape_node.to_local(world_position)
		if _shape_contains_local_position(shape_node.shape, local_position, include_player_extent):
			return true
	return false

func _shape_contains_local_position(
	shape: Shape3D,
	local_position: Vector3,
	include_player_extent := false
) -> bool:
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		var horizontal_margin := PLAYER_INTERACTION_RADIUS if include_player_extent else 0.0
		var vertical_margin := PLAYER_INTERACTION_HALF_HEIGHT if include_player_extent else 0.0
		return absf(local_position.x) <= half_size.x + horizontal_margin \
			and absf(local_position.y) <= half_size.y + vertical_margin \
			and absf(local_position.z) <= half_size.z + horizontal_margin
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		var radius_margin := PLAYER_INTERACTION_RADIUS if include_player_extent else 0.0
		var effective_radius := radius + radius_margin
		return local_position.length_squared() <= effective_radius * effective_radius
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radial := Vector2(local_position.x, local_position.z).length()
		var half_cylinder := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		var radius_margin := PLAYER_INTERACTION_RADIUS if include_player_extent else 0.0
		var height_margin := PLAYER_INTERACTION_HALF_HEIGHT if include_player_extent else 0.0
		var axial := maxf(0.0, absf(local_position.y) - half_cylinder - height_margin)
		var effective_radius := capsule.radius + radius_margin
		return radial * radial + axial * axial <= effective_radius * effective_radius
	return false

func _area_overlaps_actor(area: Area3D, actor: Node3D) -> bool:
	if area == null or actor == null or not is_instance_valid(actor):
		return false
	return area.overlaps_body(actor)

func is_climb_area_position(world_position: Vector3, actor: Node3D = null) -> bool:
	return _area_overlaps_actor(climb_area, actor) \
		or _area_contains_point(climb_area, world_position, true)

func is_climb_top_position(world_position: Vector3, actor: Node3D = null) -> bool:
	return _area_overlaps_actor(climb_top, actor) \
		or _area_contains_point(climb_top, world_position, true)

func can_start_from_bottom(world_position: Vector3, grounded: bool, actor: Node3D = null) -> bool:
	return grounded and is_climb_area_position(world_position, actor)

func can_start_from_top(world_position: Vector3, grounded: bool, actor: Node3D = null) -> bool:
	return grounded and is_climb_top_position(world_position, actor)

func get_climb_speed() -> float:
	return maxf(0.1, climb_speed)
