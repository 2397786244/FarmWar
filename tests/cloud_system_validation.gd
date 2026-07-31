extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://worlds/shared/cloud_system.tscn") as PackedScene
	if packed == null:
		push_error("Cloud validation: cloud_system.tscn could not be loaded.")
		quit(1)
		return
	var system := packed.instantiate() as CloudSystem3D
	root.add_child(system)
	await process_frame
	var generated := system.get_node_or_null("GeneratedClouds") as Node3D
	if generated == null:
		push_error("Cloud validation: GeneratedClouds is missing.")
		quit(1)
		return
	var cloud_counts: Dictionary = {}
	var shadow_count := 0
	var minimum_height := INF
	var maximum_height := -INF
	var states_by_variant := system.get("_variant_states") as Dictionary
	var renderers_by_variant := system.get("_variant_renderers") as Dictionary
	for variant_index in range(4):
		var states := states_by_variant.get(variant_index, []) as Array
		var renderers := renderers_by_variant.get(variant_index, []) as Array
		cloud_counts[str(variant_index)] = states.size()
		if states.size() > 0 and renderers.is_empty():
			push_error("Cloud validation: variant %d has no MultiMesh renderer." % variant_index)
			quit(1)
			return
		for state_value: Variant in states:
			var state := state_value as Dictionary
			var position := state.get("position", Vector3.ZERO) as Vector3
			minimum_height = minf(minimum_height, position.y)
			maximum_height = maxf(maximum_height, position.y)
	for child in generated.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var instance := child as MultiMeshInstance3D
		if instance.multimesh == null:
			continue
		if instance.name == "CloudShadows":
			shadow_count = instance.multimesh.instance_count
	if cloud_counts != {"0": 48, "1": 4, "2": 12, "3": 12}:
		push_error("Cloud validation: unexpected cloud counts %s." % cloud_counts)
		quit(1)
		return
	if shadow_count != 192:
		push_error("Cloud validation: expected 192 shadow lobes, got %d." % shadow_count)
		quit(1)
		return
	if minimum_height < 60.0 or maximum_height > 100.0:
		push_error("Cloud validation: height range %.2f..%.2f is outside 60..100m." % [minimum_height, maximum_height])
		quit(1)
		return
	if not system.find_children("*", "CollisionObject3D", true, false).is_empty():
		push_error("Cloud validation: cloud system must not contain collision objects.")
		quit(1)
		return
	print("Cloud validation: 76 clouds, 192 shadow lobes, height %.2f..%.2fm." % [minimum_height, maximum_height])
	quit(0)
