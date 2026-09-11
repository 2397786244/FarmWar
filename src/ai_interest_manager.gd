extends RefCounted
class_name AIInterestManager

## Authority-side activity manager for AI and autonomous wild animals.
##
## A human player keeps the current 256m world chunk and the four cardinal
## neighbour chunks active. Entities outside that set stay visible and keep
## their collision objects, but their AI/process callbacks are suspended.

const CHUNK_SIZE_METERS := 256.0
const REFRESH_INTERVAL_SECONDS := 0.25
const ACTIVE_CHUNK_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]
const AI_GROUPS: Array[StringName] = [
	&"farmer_ai",
	&"future_warrior_ai",
	&"road_blockers",
	&"assistant_ai",
	&"ai_normal_drones",
]

var _authority: Node
var _refresh_remaining := 0.0
var _refresh_requested := true
var _sleeping_entities: Dictionary = {}
var _saved_process_states: Dictionary = {}
var _active_chunks: Dictionary = {}


func setup(authority: Node) -> void:
	_authority = authority
	request_refresh(true)


func reset() -> void:
	for entity_value: Variant in _sleeping_entities.values():
		var entity := entity_value as Node
		if is_instance_valid(entity):
			_wake_entity(entity)
	_sleeping_entities.clear()
	_saved_process_states.clear()
	_active_chunks.clear()
	_refresh_remaining = 0.0
	_refresh_requested = true


func request_refresh(immediate := false) -> void:
	if _authority == null or not (_authority.is_server_authority() or _authority.is_local_authority()):
		return
	_refresh_requested = true
	if immediate:
		_refresh()


func tick(delta: float) -> void:
	if _authority == null or not is_instance_valid(_authority):
		return
	if not (_authority.is_server_authority() or _authority.is_local_authority()):
		return
	_refresh_remaining -= maxf(0.0, delta)
	if _refresh_requested or _refresh_remaining <= 0.0:
		_refresh()


func is_sleeping(node: Node) -> bool:
	var entity := _find_tracked_entity(node)
	return entity != null and _sleeping_entities.has(entity.get_instance_id())


func wake_node(node: Node) -> void:
	var entity := _find_tracked_entity(node)
	if entity != null:
		_wake_entity(entity)


func get_active_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for chunk_value: Variant in _active_chunks.keys():
		if chunk_value is Vector2i:
			result.append(chunk_value as Vector2i)
	return result


func get_sleeping_count() -> int:
	return _sleeping_entities.size()


func get_chunk_for_position(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / CHUNK_SIZE_METERS),
		floori(position.z / CHUNK_SIZE_METERS)
	)


func _refresh() -> void:
	_refresh_requested = false
	_refresh_remaining = REFRESH_INTERVAL_SECONDS
	_active_chunks = _build_active_chunks()
	var entities := _collect_entities()

	for entity_value: Variant in entities.values():
		var entity := entity_value as Node3D
		if not is_instance_valid(entity):
			continue
		if not _can_sleep(entity):
			# Dead entities must keep their existing death/cleanup path alive.
			_wake_entity(entity)
			continue
		var entity_chunk := get_chunk_for_position(entity.global_position)
		if _active_chunks.has(entity_chunk):
			_wake_entity(entity)
		else:
			_sleep_entity(entity)

	for id_value: Variant in _sleeping_entities.keys():
		var entity_id := int(id_value)
		var entity: Node = _sleeping_entities[entity_id]
		if not is_instance_valid(entity) or not entities.has(entity_id):
			_sleeping_entities.erase(entity_id)
			_saved_process_states.erase(entity_id)


func _build_active_chunks() -> Dictionary:
	var active: Dictionary = {}
	if _authority == null:
		return active
	var player_states_value: Variant = _authority.get("player_states")
	if not player_states_value is Dictionary:
		return active
	var player_states := player_states_value as Dictionary
	for state_value: Variant in player_states.values():
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		# A dead player has not relocated yet.  Keep the chunks around the last
		# authoritative death position active through the respawn countdown so AI
		# combat, projectiles and short-lived presentation effects can finish.
		# Once respawn writes the new position, this same normal distance policy
		# naturally releases the old chunks and activates the new ones.
		var position_value: Variant = state.get("position", null)
		if not position_value is Vector3:
			if position_value is Array and (position_value as Array).size() >= 3:
				var components := position_value as Array
				position_value = Vector3(
					float(components[0]),
					float(components[1]),
					float(components[2])
				)
		if not position_value is Vector3:
			continue
		var center := get_chunk_for_position(position_value as Vector3)
		for offset in ACTIVE_CHUNK_OFFSETS:
			active[center + offset] = true
	return active


func _collect_entities() -> Dictionary:
	var entities: Dictionary = {}
	if _authority == null:
		return entities
	var tree := _authority.get_tree()
	if tree == null:
		return entities
	for group_name in AI_GROUPS:
		for node_value: Node in tree.get_nodes_in_group(group_name):
			if _is_interest_entity(node_value):
				entities[node_value.get_instance_id()] = node_value
	for node_value: Node in tree.get_nodes_in_group("wild_animals"):
		if node_value.is_in_group("farm_livestock"):
			continue
		if _is_interest_entity(node_value):
			entities[node_value.get_instance_id()] = node_value
	return entities


func _is_interest_entity(node: Node) -> bool:
	if not is_instance_valid(node) or not node is Node3D:
		return false
	if node.has_meta("network_ai_proxy") or node.has_meta("network_ai_drone_proxy"):
		return false
	if _has_property(node, "network_proxy") and bool(node.get("network_proxy")):
		return false
	return node.has_method("set_interest_sleeping")


func _can_sleep(node: Node) -> bool:
	if node.has_method("can_enter_interest_sleep"):
		return bool(node.call("can_enter_interest_sleep"))
	if node.has_method("get_network_state"):
		var state_value: Variant = node.call("get_network_state")
		if state_value is Dictionary and bool((state_value as Dictionary).get("dead", false)):
			return false
	return true


func _sleep_entity(entity: Node) -> void:
	var entity_id := entity.get_instance_id()
	if _sleeping_entities.has(entity_id):
		return
	_saved_process_states[entity_id] = {
		"process_mode": entity.process_mode,
		"process": entity.is_processing(),
		"physics_process": entity.is_physics_processing(),
	}
	_sleeping_entities[entity_id] = entity
	_stop_entity_muzzle_flashes(entity)
	entity.call("set_interest_sleeping", true)
	entity.process_mode = Node.PROCESS_MODE_DISABLED


func _stop_entity_muzzle_flashes(entity: Node) -> void:
	## A sleeping node stops its child Tween processing.  Explicitly close every
	## held weapon flash first so no frozen flame/light remains after the last
	## player in an area dies or leaves.
	for flash_value in entity.find_children("*", "MuzzleFlashVisual", true, false):
		var flash := flash_value as Node
		if flash.has_method("stop"):
			flash.call("stop")
	for particle_value in entity.find_children("MuzzleFlash", "GPUParticles3D", true, false):
		if particle_value is GPUParticles3D:
			var particle := particle_value as GPUParticles3D
			particle.emitting = false
			particle.visible = false


func _wake_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
	var entity_id := entity.get_instance_id()
	if not _sleeping_entities.has(entity_id):
		return
	var saved: Dictionary = _saved_process_states.get(entity_id, {})
	entity.process_mode = int(saved.get("process_mode", Node.PROCESS_MODE_INHERIT))
	entity.set_process(bool(saved.get("process", true)))
	entity.set_physics_process(bool(saved.get("physics_process", true)))
	entity.call("set_interest_sleeping", false)
	_sleeping_entities.erase(entity_id)
	_saved_process_states.erase(entity_id)


func _find_tracked_entity(node: Node) -> Node:
	var cursor := node
	var depth := 0
	while cursor != null and depth < 16:
		if _sleeping_entities.has(cursor.get_instance_id()):
			return cursor
		cursor = cursor.get_parent()
		depth += 1
	return null


func _has_property(node: Object, property_name: String) -> bool:
	for property_info: Dictionary in node.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
