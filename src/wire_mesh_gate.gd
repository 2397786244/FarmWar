extends MapDefenseFacility
class_name WireMeshGate

const LOCKPICK_DURATION_SECONDS := 10.0

@export_range(45.0, 135.0, 1.0) var open_angle_degrees := 90.0
@export var starts_open := false

var is_open := false
var _closed_leaf_rotation := Vector3.ZERO

@onready var gate_leaf_pivot: Node3D = _find_gate_leaf_pivot()
@onready var gate_collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var door_area: Area3D = get_node_or_null("DoorArea") as Area3D


func _ready() -> void:
	super._ready()
	add_to_group("wire_mesh_gates")
	if is_instance_valid(door_area):
		door_area.add_to_group("wire_mesh_gate_interaction_areas")
	if is_instance_valid(gate_leaf_pivot):
		_closed_leaf_rotation = gate_leaf_pivot.rotation
	apply_open_state(starts_open)


func _find_gate_leaf_pivot() -> Node3D:
	var mesh_root := get_node_or_null("Mesh")
	if mesh_root != null:
		return mesh_root.find_child("GateLeafPivot", true, false) as Node3D
	return null


func get_gate_id() -> String:
	return str(get_meta("network_device_id", str(get_path())))


func get_interaction_position() -> Vector3:
	return global_position + Vector3.UP * 1.0


func is_direct_open_allowed(actor_team: String) -> bool:
	return tool_owner.is_empty() or tool_owner == actor_team


func get_interaction_hint(actor: Node) -> String:
	if is_open:
		return "[E] 关门"
	var actor_team := ""
	if actor != null and is_instance_valid(actor):
		if _has_property(actor, "team"):
			actor_team = str(actor.get("team"))
		elif _has_property(actor, "team_id"):
			actor_team = str(actor.get("team_id"))
	return "[E] 开门" if is_direct_open_allowed(actor_team) else "长按[E]撬门"


func apply_open_state(value: bool) -> void:
	is_open = value
	if is_instance_valid(gate_leaf_pivot):
		var target_rotation := _closed_leaf_rotation
		if is_open:
			target_rotation.y += deg_to_rad(open_angle_degrees)
		gate_leaf_pivot.rotation = target_rotation
	if is_instance_valid(gate_collision):
		gate_collision.set_deferred("disabled", _network_visual_only or is_open or destroyed)
	_set_navigation_obstacle_active(not is_open and not destroyed and not _network_visual_only)


func _on_defense_active_changed(value: bool) -> void:
	if is_instance_valid(gate_collision):
		gate_collision.set_deferred("disabled", _network_visual_only or not value or is_open)
	_set_navigation_obstacle_active(value and not is_open and not destroyed and not _network_visual_only)


func set_open(value: bool) -> void:
	apply_open_state(value)


func apply_network_respawned(value: float = -1.0) -> void:
	apply_open_state(false)
	super.apply_network_respawned(value)


func enable_network_visuals() -> void:
	super.enable_network_visuals()
	if is_instance_valid(gate_collision):
		gate_collision.set_deferred("disabled", true)
	if is_instance_valid(door_area):
		door_area.collision_layer = 512
		door_area.collision_mask = 8
		door_area.monitoring = true
		door_area.monitorable = true


func apply_network_state(state: Dictionary) -> void:
	if state.has("is_open"):
		apply_open_state(bool(state.get("is_open", false)))
	if state.has("open_angle_degrees"):
		open_angle_degrees = float(state.get("open_angle_degrees", open_angle_degrees))
		apply_open_state(is_open)
	if state.has("team"):
		tool_owner = str(state.get("team", tool_owner))


func get_network_state() -> Dictionary:
	return {
		"is_open": is_open,
		"open_angle_degrees": open_angle_degrees,
		"team": tool_owner,
	}


func is_actor_inside_interaction_area(actor: Node3D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if is_instance_valid(door_area) and door_area.overlaps_body(actor):
		return true
	return global_position.distance_to(actor.global_position) <= 4.0


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
