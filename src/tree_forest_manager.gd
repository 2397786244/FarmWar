extends Node3D
class_name TreeForestManager

const MIN_RESPAWN_SECONDS := 60.0
const RESPAWN_BY_TYPE := {"oak": 90.0, "redcedar": 75.0, "cottonwood": 120.0}

var resources: Array[Node] = []
var trees: Array[HarvestTree] = []
var multimeshes: Dictionary = {}
var _respawn_timers: Dictionary = {}


func _ready() -> void:
	call_deferred("_build_from_scene_trees")


func _build_from_scene_trees() -> void:
	resources.clear()
	trees.clear()
	for group in ["harvest_trees", "regrowing_resources", "harvest_ores", "harvest_mushrooms"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not resources.has(node):
				resources.append(node)
				if node is HarvestTree:
					trees.append(node as HarvestTree)
	for resource in resources:
		var visual: Node3D = resource.get("mesh_root") if _has_property(resource, "mesh_root") else null
		if is_instance_valid(visual):
			visual.visible = false
	_build_multimeshes()


func _build_multimeshes() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()
	multimeshes.clear()
	var groups: Dictionary = {}
	for resource in resources:
		var visual: Node3D = resource.get("mesh_root") if _has_property(resource, "mesh_root") else null
		var source := _find_first_mesh_instance(visual) if is_instance_valid(visual) else null
		if source == null or source.mesh == null:
			continue
		var key := str(source.mesh.resource_path) if not source.mesh.resource_path.is_empty() else str(resource.get_path())
		if not groups.has(key):
			groups[key] = {"mesh": source.mesh, "trees": []}
		(groups[key]["trees"] as Array).append(resource)
	for key: String in groups.keys():
		var group: Dictionary = groups[key]
		var group_trees: Array = group["trees"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = group["mesh"]
		multi.instance_count = group_trees.size()
		for index in range(group_trees.size()):
			var resource: Node3D = group_trees[index]
			var source_transform: Transform3D = source_global_transform(resource, group["mesh"])
			multi.set_instance_transform(index, source_transform)
			resource.set_meta("forest_multimesh_key", key)
			resource.set_meta("forest_multimesh_index", index)
			if _has_property(resource, "forest_manager"):
				resource.set("forest_manager", self)
		var instance := MultiMeshInstance3D.new()
		instance.name = "MultiMesh_%s" % key.get_file().get_basename()
		instance.multimesh = multi
		add_child(instance)
		multimeshes[key] = multi


func on_tree_destroyed(tree: HarvestTree) -> void:
	on_resource_destroyed(tree)


func on_resource_destroyed(resource: Node) -> void:
	if resource == null or not is_instance_valid(resource):
		return
	_set_resource_instance_visible(resource, false)
	if not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	var resource_id := _resource_id(resource)
	var type_id := str(resource.get("resource_type")) if _has_property(resource, "resource_type") \
		else str(resource.get("tree_id")) if _has_property(resource, "tree_id") else resource_id
	var respawn_seconds := maxf(MIN_RESPAWN_SECONDS, float(RESPAWN_BY_TYPE.get(type_id.to_lower(), 60.0)))
	respawn_seconds = maxf(MIN_RESPAWN_SECONDS, float(resource.get("respawn_seconds"))) if _has_property(resource, "respawn_seconds") else respawn_seconds
	_respawn_timers[resource_id] = respawn_seconds


func _process(delta: float) -> void:
	if not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	for tree_id in _respawn_timers.keys():
		_respawn_timers[tree_id] = float(_respawn_timers[tree_id]) - delta
		if float(_respawn_timers[tree_id]) <= 0.0:
			_respawn_timers.erase(tree_id)
			var resource := _find_resource(str(tree_id))
			if resource != null and resource.has_method("respawn_from_forest"):
				resource.call("respawn_from_forest")
				if GameAuthority.is_server_authority():
					GameAuthority.reliable_world_event_ready.emit({
						"type": "nature_resource_health",
						"resource_id": _resource_id(resource),
						"resource_kind": "tree" if resource is HarvestTree else "nature",
						"hp": float(resource.get("current_hp")) if _has_property(resource, "current_hp") else 0.0,
						"destroyed": false,
						"tick": GameAuthority.server_tick,
					})


func _find_tree(tree_id: String) -> HarvestTree:
	for tree in trees:
		if is_instance_valid(tree) and tree.tree_id == tree_id:
			return tree
	return null


func _find_resource(resource_id: String) -> Node:
	for resource in resources:
		if is_instance_valid(resource) and _resource_id(resource) == resource_id:
			return resource
	return null


func _set_instance_visible(tree: HarvestTree, visible: bool) -> void:
	_set_resource_instance_visible(tree, visible)


func _set_resource_instance_visible(resource: Node, visible: bool) -> void:
	var key := str(resource.get_meta("forest_multimesh_key", ""))
	var index := int(resource.get_meta("forest_multimesh_index", -1))
	var multi: MultiMesh = multimeshes.get(key, null)
	if multi != null and index >= 0 and index < multi.instance_count:
		var transform: Transform3D = source_global_transform(resource, multi.mesh) if visible else Transform3D(Basis.IDENTITY, Vector3(0, -10000, 0))
		multi.set_instance_transform(index, transform)


func source_global_transform(resource: Node, mesh: Mesh) -> Transform3D:
	var visual: Node3D = resource.get("mesh_root") if _has_property(resource, "mesh_root") else null
	var source := _find_first_mesh_instance(visual) if is_instance_valid(visual) else null
	return source.global_transform if source != null and source.mesh == mesh else resource.global_transform


func _resource_id(resource: Node) -> String:
	if _has_property(resource, "resource_id"):
		return str(resource.get("resource_id"))
	if _has_property(resource, "tree_id"):
		return str(resource.get("tree_id"))
	return str(resource.get_path())


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested := _find_first_mesh_instance(child)
		if nested != null:
			return nested
	return null


func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
