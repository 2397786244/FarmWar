class_name ManualGrassRuntime
extends RefCounted

const LOW_GRASS_SCENE := preload("res://assets/nature/GrassLow.glb")
const TALL_GRASS_SCENE := preload("res://assets/nature/GrassTall.glb")
const DRY_GRASS_SCENE := preload("res://assets/nature/GrassDry.glb")
const BLACK_EYED_SUSAN_SCENE := preload("res://assets/nature/Wildflower_BlackEyedSusan.glb")
const CONEFLOWER_SCENE := preload("res://assets/nature/Wildflower_Coneflower.glb")
const FERN_SCENE := preload("res://assets/nature/Fern_Clump.glb")

const SPECIES := {
	"small": {"scene": LOW_GRASS_SCENE, "visibility": 100.0},
	"tall": {"scene": TALL_GRASS_SCENE, "visibility": 120.0},
	"dry": {"scene": DRY_GRASS_SCENE, "visibility": 100.0},
	"black_eyed_susan": {"scene": BLACK_EYED_SUSAN_SCENE, "visibility": 90.0},
	"coneflower": {"scene": CONEFLOWER_SCENE, "visibility": 90.0},
	"fern": {"scene": FERN_SCENE, "visibility": 100.0},
}


static func rebuild(manual_grass_root: Node3D, species_data: Dictionary) -> void:
	if manual_grass_root == null:
		return
	for child in manual_grass_root.get_children():
		child.free()

	for species_value: Variant in species_data.keys():
		var species := str(species_value)
		var definition_value: Variant = SPECIES.get(species, null)
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		var chunks_value: Variant = species_data.get(species, {})
		if not chunks_value is Dictionary:
			continue
		for key_value: Variant in (chunks_value as Dictionary).keys():
			_rebuild_chunk(
				manual_grass_root,
				species,
				str(key_value),
				(chunks_value as Dictionary).get(key_value, []),
				definition
			)


static func _rebuild_chunk(
	manual_grass_root: Node3D,
	species: String,
	key: String,
	transforms_value: Variant,
	definition: Dictionary
) -> void:
	if not transforms_value is Array:
		return
	var transforms: Array[Transform3D] = []
	for transform_value: Variant in transforms_value as Array:
		if transform_value is Transform3D:
			transforms.append(transform_value as Transform3D)
	if transforms.is_empty():
		return

	var source_scene := definition.get("scene", null) as PackedScene
	if source_scene == null:
		return
	var source_root := source_scene.instantiate() as Node3D
	if source_root == null:
		return
	var components: Array[Dictionary] = []
	_collect_mesh_components(source_root, source_root, components)
	source_root.free()
	if components.is_empty():
		return

	var chunk_root := Node3D.new()
	chunk_root.name = "%s_%s" % [species.capitalize(), key.replace(":", "_")]
	manual_grass_root.add_child(chunk_root)
	for component_index in range(components.size()):
		var component := components[component_index] as Dictionary
		var mesh := component.get("mesh", null) as Mesh
		if mesh == null:
			continue
		var source_transform := component.get("transform", Transform3D.IDENTITY) as Transform3D
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index] * source_transform)

		var instance := MultiMeshInstance3D.new()
		instance.name = "Mesh_%d" % component_index
		instance.multimesh = multimesh
		instance.material_override = component.get("material", null) as Material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.visibility_range_end = float(definition.get("visibility", 100.0))
		instance.extra_cull_margin = 2.0
		chunk_root.add_child(instance)


static func _collect_mesh_components(node: Node, root: Node3D, result: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		if source.mesh != null:
			result.append({
				"mesh": source.mesh,
				"material": source.material_override,
				"transform": _relative_transform_to_root(source, root),
			})
	for child in node.get_children():
		_collect_mesh_components(child, root, result)


static func _relative_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var cursor := node.get_parent() as Node3D
	while cursor != null and cursor != root:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result
