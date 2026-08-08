extends Node3D
class_name TreeForestManager

const MIN_RESPAWN_SECONDS := 60.0
const RESPAWN_BY_TYPE := {
	"oak": 90.0,
	"redcedar": 75.0,
	"redmaple": 105.0,
	"cottonwood": 120.0,
	"stump_fresh": 60.0,
	"stump_mossy": 60.0,
	"stump_rotten": 60.0,
}

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
	for resource_value in resources:
		var resource := resource_value as Node3D
		if resource == null:
			continue
		var visual: Node3D = resource.get("mesh_root") if _has_property(resource, "mesh_root") else null
		if not is_instance_valid(visual):
			continue
		resource.set_meta("forest_multimesh_bindings", [])
		resource.remove_meta("forest_multimesh_key")
		resource.remove_meta("forest_multimesh_index")
		if _has_property(resource, "forest_manager"):
			resource.set("forest_manager", self)
		var sources: Array[MeshInstance3D] = []
		_collect_mesh_instances(visual, sources)
		for source in sources:
			if source.mesh == null or not source.visible:
				continue
			var key := _mesh_group_key(resource, source)
			if not groups.has(key):
				groups[key] = {
					"mesh": source.mesh,
					"entries": [],
					# Harvest resources are gameplay-near geometry.  Do not inherit an
					# accidental disabled import flag from a GLB: trees and rocks must
					# always cast onto the playable terrain.
					"cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
					"material_override": source.material_override,
				}
			(groups[key]["entries"] as Array).append({
				"resource": resource,
				"source_path": resource.get_path_to(source),
			})
	var group_number := 0
	for key: String in groups.keys():
		var group: Dictionary = groups[key]
		var entries: Array = group["entries"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = group["mesh"]
		multi.instance_count = entries.size()
		for index in range(entries.size()):
			var entry := entries[index] as Dictionary
			var resource := entry.get("resource", null) as Node3D
			var source_path := entry.get("source_path", NodePath()) as NodePath
			var source := resource.get_node_or_null(source_path) as MeshInstance3D \
				if resource != null else null
			if source != null:
				multi.set_instance_transform(index, source.global_transform)
			var bindings := resource.get_meta("forest_multimesh_bindings", []) as Array
			bindings.append({"key": key, "index": index, "source_path": source_path})
			resource.set_meta("forest_multimesh_bindings", bindings)
		var instance := MultiMeshInstance3D.new()
		instance.name = "ResourceMultiMesh_%03d_%s" % [
			group_number, _safe_mesh_name(group["mesh"] as Mesh)
		]
		instance.multimesh = multi
		instance.cast_shadow = int(group.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)) \
			as GeometryInstance3D.ShadowCastingSetting
		instance.material_override = group.get("material_override", null) as Material
		add_child(instance)
		multimeshes[key] = multi
		group_number += 1


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
	var bindings_value: Variant = resource.get_meta("forest_multimesh_bindings", [])
	if not bindings_value is Array:
		return
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			continue
		var binding := binding_value as Dictionary
		var key := str(binding.get("key", ""))
		var index := int(binding.get("index", -1))
		var multi := multimeshes.get(key, null) as MultiMesh
		if multi == null or index < 0 or index >= multi.instance_count:
			continue
		var transform := Transform3D(Basis.IDENTITY, Vector3(0, -10000, 0))
		if visible:
			var source_path := binding.get("source_path", NodePath()) as NodePath
			var source := resource.get_node_or_null(source_path) as MeshInstance3D
			if source == null:
				continue
			transform = source.global_transform
		multi.set_instance_transform(index, transform)


func _resource_id(resource: Node) -> String:
	if _has_property(resource, "resource_id"):
		return str(resource.get("resource_id"))
	if _has_property(resource, "tree_id"):
		return str(resource.get("tree_id"))
	return str(resource.get_path())


func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		_collect_mesh_instances(child, result)


func _mesh_group_key(resource: Node3D, source: MeshInstance3D) -> String:
	var scene_identity := resource.scene_file_path
	if scene_identity.is_empty() and source.mesh != null:
		scene_identity = source.mesh.resource_path
	if scene_identity.is_empty() and source.mesh != null:
		scene_identity = "mesh_%d" % source.mesh.get_instance_id()
	return "%s::%s" % [scene_identity, str(resource.get_path_to(source))]


func _safe_mesh_name(mesh: Mesh) -> String:
	if mesh == null:
		return "Mesh"
	var result := mesh.resource_name.validate_node_name()
	return result if not result.is_empty() else "Mesh"


func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
