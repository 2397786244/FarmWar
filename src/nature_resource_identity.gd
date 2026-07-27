extends RefCounted


static func make_stable_id(resource: Node) -> String:
	if resource == null:
		return ""
	var scene_owner := resource.owner
	if is_instance_valid(scene_owner) and scene_owner != resource:
		var relative_path := str(scene_owner.get_path_to(resource))
		var scene_key := str(scene_owner.scene_file_path).get_file().get_basename()
		if scene_key.is_empty():
			scene_key = scene_owner.name
		return "%s:%s" % [scene_key, relative_path]
	# Runtime-created resources should normally provide an explicit ID. This
	# fallback is still independent from the server/client root hierarchy.
	return "%s:%s" % [resource.get_class(), resource.name]
