extends Node3D
class_name RareResourceService

const CHECK_INTERVAL := 10.0
const GLOBAL_COOLDOWN := 120.0
const PLAYER_CLEAR_RADIUS := 20.0
const SPAWN_CHANCE := 0.50

var _check_timer := 0.0
var _cooldown_remaining := 0.0
var _rng := RandomNumberGenerator.new()
var active_resource: Dictionary = {}
var active_resource_node: Node3D = null
var runtime_enabled := true


func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled
	_check_timer = 0.0

func _ready() -> void:
	_rng.randomize()
	add_to_group("rare_resource_manager")

func _process(delta: float) -> void:
	if not runtime_enabled or not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not active_resource.is_empty():
		active_resource["lifetime_remaining"] = maxf(0.0, float(active_resource.get("lifetime_remaining", 0.0)) - delta)
		if float(active_resource["lifetime_remaining"]) <= 0.0:
			destroy_active_resource("expired")
		return
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0
	if _cooldown_remaining > 0.0 or not active_resource.is_empty():
		return
	var points := get_tree().get_nodes_in_group("rare_resource_spawn_points")
	points.shuffle()
	for point in points:
		if not is_instance_valid(point) or _players_near(point.global_position):
			continue
		if _rng.randf() > SPAWN_CHANCE:
			continue
		if _spawn_at_point(point):
			break

func _players_near(position: Vector3) -> bool:
	for raw_peer_id in GameAuthority.player_states.keys():
		var state: Dictionary = GameAuthority.player_states[raw_peer_id]
		var player_position: Variant = state.get("position", Vector3.ZERO)
		if player_position is Vector3 and (player_position as Vector3).distance_to(position) <= PLAYER_CLEAR_RADIUS:
			return true
	return false

func _spawn_at_point(point: Node3D) -> bool:
	if _is_water_position(point.global_position):
		return false
	var resource := _resource_for_point(point)
	if resource.is_empty():
		return false
	var scene_path := str(resource.get("scene_path", ""))
	var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if packed == null or world == null:
		return false
	active_resource_node = packed.instantiate() as Node3D
	if active_resource_node == null:
		return false
	world.add_child(active_resource_node)
	active_resource_node.global_position = point.global_position
	active_resource_node.set_meta("rare_resource_id", str(resource.get("id", "")))
	var event := EventBoard.add_global_event(str(resource["event_title"]), str(resource["event_description"]), "rare_resource")
	var initial_hp := 1000.0
	if active_resource_node.get_property_list().any(func(property: Dictionary) -> bool: return str(property.get("name", "")) == "current_hp"):
		initial_hp = float(active_resource_node.get("current_hp"))
	active_resource = {
		"resource": resource,
		"resource_id": str(resource.get("id", "")),
		"point_id": str(point.get_path()),
		"position": point.global_position,
		"lifetime_remaining": maxf(60.0, float(resource.get("lifetime_seconds", 300.0))),
		"event_id": int(event.get("event_id", 0)),
		"node_path": str(active_resource_node.get_path()),
		"hp": initial_hp,
	}
	if point.has_method("assign_resource"):
		point.call("assign_resource", active_resource)
	GameAuthority.reliable_world_event_ready.emit({"type": "rare_resource_spawned", "resource": active_resource, "tick": GameAuthority.server_tick})
	return true


func _is_water_position(position: Vector3) -> bool:
	for value in get_tree().get_nodes_in_group("water_bodies"):
		if value != null and value.has_method("contains_world_point") and value.call("contains_world_point", position):
			return true
	return false


func _resource_for_point(point: Node3D) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for value: Variant in RareResourceCatalog.RESOURCES:
		if value is Dictionary:
			var resource := value as Dictionary
			if (not point.has_method("allows_resource")) or bool(point.call("allows_resource", str(resource.get("id", "")))):
				if not str(resource.get("scene_path", "")).is_empty():
					candidates.append(resource.duplicate(true))
	if candidates.is_empty():
		return {}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func destroy_active_resource(reason := "destroyed") -> void:
	if active_resource.is_empty():
		return
	var event_id := int(active_resource.get("event_id", 0))
	if is_instance_valid(active_resource_node):
		active_resource_node.queue_free()
	active_resource_node = null
	var point := get_node_or_null(NodePath(str(active_resource.get("point_id", ""))))
	if is_instance_valid(point) and point.has_method("clear_resource"):
		point.call("clear_resource")
	if event_id > 0:
		EventBoard.remove_global_event(event_id)
	GameAuthority.reliable_world_event_ready.emit({
		"type": "rare_resource_destroyed",
		"resource": active_resource,
		"reason": reason,
		"tick": GameAuthority.server_tick,
	})
	active_resource.clear()
	# The global cooldown starts only after the active resource has been
	# destroyed/harvested. While it exists, the spawn point remains occupied and
	# no cooldown is consumed.
	_cooldown_remaining = GLOBAL_COOLDOWN
