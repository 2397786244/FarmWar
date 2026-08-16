extends Node3D
class_name FarmCropVisualManager

## Visual-only crop batching. FarmTile keeps its original StaticBody3D and
## CollisionShape3D children; this manager only replaces their MeshInstance3D
## rendering with MultiMesh instances.
const MANAGER_GROUP := "farm_crop_visual_managers"
const CROP_CHUNK_SIZE := 16
const INITIAL_INSTANCE_CAPACITY := 32


class CropBatch:
	var key := ""
	var mesh: Mesh
	var multimesh: MultiMesh
	var instance: MultiMeshInstance3D
	var slots: Array = []
	var transforms: Array = []
	var slot_by_crop: Dictionary = {}
	var active_count := 0
	var has_custom_aabb := false
	var custom_aabb := AABB()


var _batches: Dictionary = {}
var _crop_bindings: Dictionary = {}
var _tile_crop_keys: Dictionary = {}
var _missing_mesh_warnings: Dictionary = {}


func _ready() -> void:
	add_to_group(MANAGER_GROUP)
	process_mode = Node.PROCESS_MODE_DISABLED


static func find_for_node(node: Node) -> FarmCropVisualManager:
	if node == null or node.get_tree() == null:
		return null
	var world: Node = null
	if is_instance_valid(GlobalVar.gameworld):
		world = GlobalVar.gameworld
	elif node.get_tree().current_scene != null:
		world = node.get_tree().current_scene
	if world != null:
		var direct := world.get_node_or_null("FarmCropVisualManager") as FarmCropVisualManager
		if direct != null:
			return direct
	for manager_value: Variant in node.get_tree().get_nodes_in_group(MANAGER_GROUP):
		var manager := manager_value as FarmCropVisualManager
		if manager == null or not is_instance_valid(manager):
			continue
		if world == null or world == manager or world.is_ancestor_of(manager):
			return manager
	return null


static func get_or_create_for_node(node: Node) -> FarmCropVisualManager:
	var existing := find_for_node(node)
	if existing != null:
		return existing
	if node == null or node.get_tree() == null:
		return null
	var world: Node = null
	if is_instance_valid(GlobalVar.gameworld):
		world = GlobalVar.gameworld
	elif node.get_tree().current_scene != null:
		world = node.get_tree().current_scene
	else:
		world = node.get_tree().root
	if world == null:
		return null
	var manager := FarmCropVisualManager.new()
	manager.name = "FarmCropVisualManager"
	world.add_child(manager)
	return manager


func register_tile_crops(tile: FarmTile) -> bool:
	if tile == null or not is_instance_valid(tile):
		return false
	unregister_tile_crops(tile)
	var crop_nodes: Array = tile.plant_children.duplicate()
	if crop_nodes.is_empty():
		return false

	var tile_id := tile.get_instance_id()
	var tile_crop_keys: Array = []
	for crop_index in range(crop_nodes.size()):
		var crop := crop_nodes[crop_index] as Node3D
		if crop == null or not is_instance_valid(crop):
			continue
		var crop_key := _crop_key(tile, crop_index)
		var mesh_parts := _find_mesh_parts(crop)
		if mesh_parts.is_empty():
			_warn_missing_mesh(tile, crop)
			continue

		var bindings: Array = []
		for part_index in range(mesh_parts.size()):
			var visual := mesh_parts[part_index] as MeshInstance3D
			if visual == null or visual.mesh == null:
				continue
			var batch_key := _batch_key(tile, part_index, visual)
			var batch := _get_or_create_batch(batch_key, visual)
			if batch == null:
				continue
			var local_transform := global_transform.affine_inverse() * visual.global_transform
			var slot := _add_instance(batch, crop_key, local_transform)
			bindings.append({"batch_key": batch_key, "slot": slot})
			# Keep the original StaticBody3D and CollisionShape3D alive. Only the
			# authored visual MeshInstance3D is replaced by the MultiMesh.
			visual.visible = false

		if not bindings.is_empty():
			_crop_bindings[crop_key] = bindings
			tile_crop_keys.append(crop_key)
	if tile_crop_keys.is_empty():
		_tile_crop_keys.erase(tile_id)
		return false
	_tile_crop_keys[tile_id] = tile_crop_keys
	return true


func refresh_tile_crops(tile: FarmTile) -> bool:
	return register_tile_crops(tile)


func ensure_tile_registered(tile: FarmTile) -> bool:
	if tile == null or not is_instance_valid(tile):
		return false
	var tile_id := tile.get_instance_id()
	var registered: Array = _tile_crop_keys.get(tile_id, [])
	if not registered.is_empty():
		return true
	return register_tile_crops(tile)


func unregister_tile_crops(tile: FarmTile) -> void:
	if tile == null:
		return
	var tile_id := tile.get_instance_id()
	var keys: Array = (_tile_crop_keys.get(tile_id, []) as Array).duplicate()
	for crop_key: String in keys:
		_remove_crop_key(crop_key)
	_tile_crop_keys.erase(tile_id)


func get_batch_stats() -> Dictionary:
	var active_instances := 0
	for batch_value: Variant in _batches.values():
		var batch := batch_value as CropBatch
		if batch != null:
			active_instances += batch.active_count
	return {
		"batch_count": _batches.size(),
		"registered_tile_count": _tile_crop_keys.size(),
		"active_instance_count": active_instances,
	}


func _find_mesh_parts(crop: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if crop is MeshInstance3D:
		result.append(crop as MeshInstance3D)
	for visual_value: Variant in crop.find_children("*", "MeshInstance3D", true, false):
		var visual := visual_value as MeshInstance3D
		if visual != null:
			result.append(visual)
	return result


func _get_or_create_batch(batch_key: String, template: MeshInstance3D) -> CropBatch:
	var existing := _batches.get(batch_key, null) as CropBatch
	if existing != null:
		return existing
	if template == null or template.mesh == null:
		return null
	var batch := CropBatch.new()
	batch.key = batch_key
	batch.mesh = _build_batch_mesh(template)
	if batch.mesh == null:
		return null
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = batch.mesh
	batch.multimesh.instance_count = INITIAL_INSTANCE_CAPACITY
	batch.multimesh.visible_instance_count = 0
	batch.instance = MultiMeshInstance3D.new()
	batch.instance.name = "CropMultiMesh_%d" % get_instance_id()
	batch.instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	batch.instance.set_meta("farm_crop_visual_batch_key", batch_key)
	batch.instance.multimesh = batch.multimesh
	add_child(batch.instance)
	_batches[batch_key] = batch
	return batch


func _build_batch_mesh(template: MeshInstance3D) -> Mesh:
	var source_mesh := template.mesh
	var has_override := template.material_override != null
	var surface_overrides: Array = []
	for surface_index in range(source_mesh.get_surface_count()):
		var surface_material := template.get_surface_override_material(surface_index)
		surface_overrides.append(surface_material)
		if surface_material != null:
			has_override = true
	if not has_override:
		return source_mesh
	if not source_mesh is ArrayMesh:
		push_warning(
			"FarmCropVisualManager: %s 使用了材质覆盖，但 Mesh 不是 ArrayMesh，"
			+ "将使用原始 Mesh。" % template.get_path()
		)
		return source_mesh
	var copied_mesh := (source_mesh as ArrayMesh).duplicate() as ArrayMesh
	for surface_index in range(copied_mesh.get_surface_count()):
		var surface_material: Material = surface_overrides[surface_index]
		if surface_material == null:
			surface_material = template.material_override
		if surface_material != null:
			copied_mesh.surface_set_material(surface_index, surface_material)
	return copied_mesh


func _add_instance(batch: CropBatch, crop_key: String, transform: Transform3D) -> int:
	_ensure_batch_capacity(batch)
	var slot := batch.active_count
	batch.slots.append(crop_key)
	batch.transforms.append(transform)
	batch.slot_by_crop[crop_key] = slot
	batch.multimesh.set_instance_transform(slot, transform)
	batch.active_count += 1
	batch.multimesh.visible_instance_count = batch.active_count
	batch.instance.visible = true
	_expand_batch_aabb(batch, transform)
	return slot


func _ensure_batch_capacity(batch: CropBatch) -> void:
	if batch.active_count < batch.multimesh.instance_count:
		return
	var old_count := batch.multimesh.instance_count
	var new_count := maxi(old_count * 2, old_count + INITIAL_INSTANCE_CAPACITY)
	batch.multimesh.instance_count = new_count
	for index in range(batch.active_count):
		batch.multimesh.set_instance_transform(index, batch.transforms[index])


func _remove_crop_key(crop_key: String) -> void:
	var bindings: Array = (_crop_bindings.get(crop_key, []) as Array).duplicate()
	for binding_value: Variant in bindings:
		if binding_value is Dictionary:
			_remove_instance(
				crop_key,
				str((binding_value as Dictionary).get("batch_key", "")),
				int((binding_value as Dictionary).get("slot", -1))
			)
	_crop_bindings.erase(crop_key)


func _remove_instance(crop_key: String, batch_key: String, slot: int) -> void:
	var batch := _batches.get(batch_key, null) as CropBatch
	if batch == null or slot < 0 or slot >= batch.active_count:
		return
	var last_slot := batch.active_count - 1
	var moved_key := str(batch.slots[last_slot])
	if slot != last_slot:
		var moved_transform: Transform3D = batch.transforms[last_slot]
		batch.slots[slot] = moved_key
		batch.transforms[slot] = moved_transform
		batch.multimesh.set_instance_transform(slot, moved_transform)
		batch.slot_by_crop[moved_key] = slot
		_update_binding_slot(moved_key, batch_key, slot)
	batch.slots.pop_back()
	batch.transforms.pop_back()
	batch.slot_by_crop.erase(crop_key)
	batch.active_count -= 1
	batch.multimesh.visible_instance_count = batch.active_count
	batch.instance.visible = batch.active_count > 0


func _update_binding_slot(crop_key: String, batch_key: String, slot: int) -> void:
	var bindings: Array = _crop_bindings.get(crop_key, [])
	for binding_value: Variant in bindings:
		if not binding_value is Dictionary:
			continue
		var binding := binding_value as Dictionary
		if str(binding.get("batch_key", "")) == batch_key:
			binding["slot"] = slot
	_crop_bindings[crop_key] = bindings


func _expand_batch_aabb(batch: CropBatch, transform: Transform3D) -> void:
	var transformed_aabb := _transform_aabb(batch.mesh.get_aabb(), transform)
	if not batch.has_custom_aabb:
		batch.custom_aabb = transformed_aabb
		batch.has_custom_aabb = true
	else:
		batch.custom_aabb = batch.custom_aabb.merge(transformed_aabb)
	batch.multimesh.custom_aabb = batch.custom_aabb


func _transform_aabb(source: AABB, transform: Transform3D) -> AABB:
	var corners := [
		Vector3(source.position.x, source.position.y, source.position.z),
		Vector3(source.end.x, source.position.y, source.position.z),
		Vector3(source.position.x, source.end.y, source.position.z),
		Vector3(source.position.x, source.position.y, source.end.z),
		Vector3(source.end.x, source.end.y, source.position.z),
		Vector3(source.end.x, source.position.y, source.end.z),
		Vector3(source.position.x, source.end.y, source.end.z),
		Vector3(source.end.x, source.end.y, source.end.z),
	]
	var result := AABB(transform * corners[0], Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result


func _chunk_key(tile: FarmTile) -> String:
	if not tile.field_id.is_empty():
		var chunk_x := floori(float(tile.grid_coordinate.x) / float(CROP_CHUNK_SIZE))
		var chunk_z := floori(float(tile.grid_coordinate.y) / float(CROP_CHUNK_SIZE))
		return "%s:%d:%d" % [tile.field_id, chunk_x, chunk_z]
	var spacing := maxf(0.1, tile.tile_spacing)
	var chunk_world_size := spacing * float(CROP_CHUNK_SIZE)
	var world_chunk_x := floori(tile.global_position.x / chunk_world_size)
	var world_chunk_z := floori(tile.global_position.z / chunk_world_size)
	return "standalone:%d:%d" % [world_chunk_x, world_chunk_z]


func _crop_key(tile: FarmTile, crop_index: int) -> String:
	return "%d:%d" % [tile.get_instance_id(), crop_index]


func _batch_key(tile: FarmTile, part_index: int, visual: MeshInstance3D) -> String:
	var mesh_key := str(visual.mesh.resource_path)
	if mesh_key.is_empty():
		mesh_key = "instance:%d" % visual.mesh.get_instance_id()
	var material_key := _material_signature(visual)
	return "%s|%s|part:%d|mesh:%s|material:%s" % [
		_chunk_key(tile),
		tile.seed_record,
		part_index,
		mesh_key,
		material_key,
	]


func _material_signature(visual: MeshInstance3D) -> String:
	var values: Array[String] = []
	if visual.material_override != null:
		values.append("override:%d" % visual.material_override.get_instance_id())
	for surface_index in range(visual.mesh.get_surface_count()):
		var material := visual.get_surface_override_material(surface_index)
		if material != null:
			values.append("surface%d:%d" % [surface_index, material.get_instance_id()])
	return ",".join(values)


func _warn_missing_mesh(tile: FarmTile, crop: Node3D) -> void:
	var warning_key := "%s:%s" % [tile.seed_record, crop.scene_file_path]
	if _missing_mesh_warnings.has(warning_key):
		return
	_missing_mesh_warnings[warning_key] = true
	push_warning(
		"FarmCropVisualManager: 作物 %s 的场景中没有找到 MeshInstance3D，保留原视觉节点。"
		% crop.get_path()
	)
