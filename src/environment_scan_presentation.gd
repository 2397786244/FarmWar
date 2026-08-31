extends Node3D
class_name EnvironmentScanPresentation

const SCAN_RADIUS := 100.0
const WAVE_DURATION := 1.5
const OUTLINE_DURATION := 8.0
const MASK_RENDER_LAYER := 1 << 28
const MASK_SHADER := preload("res://src/vehicle_interaction_mask.gdshader")
const OUTLINE_SHADER := preload("res://src/environment_scan_outline.gdshader")
const GRID_SHADER := preload("res://src/environment_scan_grid.gdshader")

var _owner_player: GamePlayer
var _elapsed := 0.0
var _pending_targets: Array[Dictionary] = []
var _active_targets: Array[Dictionary] = []
var _mask_viewport: SubViewport
var _mask_root: Node3D
var _mask_camera: Camera3D
var _outline_quad: MeshInstance3D
var _outline_material: ShaderMaterial
var _mask_material: ShaderMaterial
var _wave_mesh: MeshInstance3D
var _wave_material: ShaderMaterial


func setup(owner_player: GamePlayer, origin: Vector3) -> void:
	_owner_player = owner_player
	top_level = true
	global_position = origin
	_create_mask_viewport()
	_create_outline_quad()
	_create_scan_wave()
	_pending_targets = collect_scan_targets(get_tree(), origin, SCAN_RADIUS)
	set_process(true)


func stop() -> void:
	set_process(false)
	if is_instance_valid(_mask_viewport):
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	queue_free()


func _process(delta: float) -> void:
	if not is_instance_valid(_owner_player) or _owner_player.is_respawning:
		stop()
		return
	_elapsed += delta
	_update_wave()
	_reveal_reached_targets()
	_update_active_targets()
	var active_camera := get_viewport().get_camera_3d()
	if not _active_targets.is_empty() and is_instance_valid(active_camera):
		_sync_camera(active_camera)
		_outline_quad.global_transform = active_camera.global_transform
		_outline_quad.visible = true
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_outline_quad.visible = false
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _elapsed >= WAVE_DURATION and _pending_targets.is_empty() and _active_targets.is_empty():
		stop()


func _create_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "EnvironmentScanMaskViewport"
	_mask_viewport.transparent_bg = true
	_mask_viewport.handle_input_locally = false
	_mask_viewport.gui_disable_input = true
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_mask_viewport.world_3d = _owner_player.get_viewport().world_3d
	_mask_viewport.size = _owner_player.get_viewport().size
	add_child(_mask_viewport)

	_mask_root = Node3D.new()
	_mask_root.name = "EnvironmentScanMaskRoot"
	_mask_viewport.add_child(_mask_root)
	_mask_camera = Camera3D.new()
	_mask_camera.name = "EnvironmentScanMaskCamera"
	_mask_camera.cull_mask = MASK_RENDER_LAYER
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)


func _create_outline_quad() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline_quad = MeshInstance3D.new()
	_outline_quad.name = "EnvironmentScanOutlineQuad"
	_outline_quad.mesh = quad
	_outline_quad.layers = 1
	_outline_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_outline_quad.visible = false
	add_child(_outline_quad)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.render_priority = 126
	_outline_material.set_shader_parameter("mask_texture", _mask_viewport.get_texture())
	_outline_material.set_shader_parameter("outline_color", Color("eb1616"))
	_outline_material.set_shader_parameter("thickness_pixels", 4.0)
	_outline_quad.material_override = _outline_material


func _create_scan_wave() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_wave_mesh = MeshInstance3D.new()
	_wave_mesh.name = "EnvironmentScanGridWave"
	_wave_mesh.mesh = sphere
	_wave_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_wave_mesh)
	_wave_material = ShaderMaterial.new()
	_wave_material.shader = GRID_SHADER
	_wave_material.render_priority = 120
	_wave_mesh.material_override = _wave_material
	_wave_mesh.scale = Vector3.ONE * 0.05


func _update_wave() -> void:
	if not is_instance_valid(_wave_mesh):
		return
	var progress := clampf(_elapsed / WAVE_DURATION, 0.0, 1.0)
	_wave_mesh.scale = Vector3.ONE * maxf(0.05, SCAN_RADIUS * ease(progress, 0.8))
	_wave_material.set_shader_parameter("fade", 1.0 - smoothstep(0.70, 1.0, progress))
	if progress >= 1.0:
		_wave_mesh.queue_free()
		_wave_mesh = null


func _reveal_reached_targets() -> void:
	for index in range(_pending_targets.size() - 1, -1, -1):
		var target_data := _pending_targets[index]
		var reveal_time := WAVE_DURATION * float(target_data.get("distance", SCAN_RADIUS)) / SCAN_RADIUS
		if _elapsed + 0.0001 < reveal_time:
			continue
		_pending_targets.remove_at(index)
		var target := target_data.get("target", null) as Node3D
		var visual := target_data.get("visual", null) as Node3D
		if not _is_target_still_valid(target) or not is_instance_valid(visual):
			continue
		var mask_visual := _duplicate_visual_geometry(visual, bool(target_data.get("force_hidden_visual", false)))
		if not is_instance_valid(mask_visual):
			continue
		mask_visual.name = "Detected_%s" % target.name
		_mask_root.add_child(mask_visual)
		mask_visual.global_transform = visual.global_transform
		target_data["mask"] = mask_visual
		target_data["expires_at"] = _elapsed + OUTLINE_DURATION
		_active_targets.append(target_data)


func _update_active_targets() -> void:
	for index in range(_active_targets.size() - 1, -1, -1):
		var target_data := _active_targets[index]
		var target := target_data.get("target", null) as Node3D
		var visual := target_data.get("visual", null) as Node3D
		var mask := target_data.get("mask", null) as Node3D
		if _elapsed >= float(target_data.get("expires_at", 0.0)) \
				or not _is_target_still_valid(target) or not is_instance_valid(visual) \
				or not is_instance_valid(mask):
			if is_instance_valid(mask):
				mask.queue_free()
			_active_targets.remove_at(index)
			continue
		mask.global_transform = visual.global_transform


func _sync_camera(source: Camera3D) -> void:
	var main_viewport := _owner_player.get_viewport()
	if _mask_viewport.size != main_viewport.size:
		_mask_viewport.size = main_viewport.size
	_mask_camera.global_transform = source.global_transform
	_mask_camera.projection = source.projection
	_mask_camera.fov = source.fov
	_mask_camera.size = source.size
	_mask_camera.near = source.near
	_mask_camera.far = source.far
	_mask_camera.frustum_offset = source.frustum_offset
	_mask_camera.h_offset = source.h_offset
	_mask_camera.v_offset = source.v_offset
	_mask_camera.keep_aspect = source.keep_aspect
	_mask_camera.current = true


func _duplicate_visual_geometry(source: Node3D, force_hidden_visual: bool) -> Node3D:
	if source is MeshInstance3D:
		var geometry_root := source.duplicate() as MeshInstance3D
		if geometry_root == null:
			return null
		_configure_mask_geometry(geometry_root)
		return geometry_root
	var root := Node3D.new()
	_copy_visual_children(source, root, force_hidden_visual)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


func _copy_visual_children(source: Node, destination: Node3D, force_hidden_visual: bool) -> void:
	for child in source.get_children():
		if not child is Node3D:
			continue
		var source_node := child as Node3D
		if not force_hidden_visual and not source_node.visible:
			continue
		var destination_node: Node3D
		if source_node is MeshInstance3D:
			var destination_geometry := source_node.duplicate() as MeshInstance3D
			if destination_geometry == null:
				continue
			destination_node = destination_geometry
			_configure_mask_geometry(destination_geometry)
		else:
			destination_node = Node3D.new()
			destination_node.name = source_node.name
			destination_node.transform = source_node.transform
		destination.add_child(destination_node)
		if not source_node is MeshInstance3D:
			_copy_visual_children(source_node, destination_node, force_hidden_visual)
			if destination_node.get_child_count() == 0:
				destination.remove_child(destination_node)
				destination_node.free()


func _configure_mask_geometry(geometry: MeshInstance3D) -> void:
	geometry.layers = MASK_RENDER_LAYER
	geometry.visible = true
	geometry.material_override = _get_mask_material()
	geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _get_mask_material() -> ShaderMaterial:
	if is_instance_valid(_mask_material):
		return _mask_material
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = MASK_SHADER
	return _mask_material


func _is_target_still_valid(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():
		return false
	if target is VehicleBase:
		var vehicle := target as VehicleBase
		return vehicle.vehicle_deployed and vehicle.current_hp > 0.0 and vehicle.get_driver_seat_index() >= 0
	if target is HarvestOre:
		return not (target as HarvestOre).destroyed
	if target is GiantPlants:
		return not (target as GiantPlants).destroyed
	return target is PickupItem


static func collect_scan_targets(scene_tree: SceneTree, origin: Vector3, radius := SCAN_RADIUS) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if scene_tree == null:
		return results
	var seen: Dictionary = {}
	for group_name in [&"harvest_ores", &"harvest_mushrooms", &"dropped_pickup_items", &"rare_resources", &"vehicle_bases"]:
		for candidate in scene_tree.get_nodes_in_group(group_name):
			if not candidate is Node3D or not is_instance_valid(candidate):
				continue
			var target := candidate as Node3D
			var instance_id := target.get_instance_id()
			if seen.has(instance_id) or target.is_queued_for_deletion():
				continue
			var visual := _scan_visual_for_target(target)
			if not is_instance_valid(visual) or not _scan_target_is_alive(target):
				continue
			var distance := origin.distance_to(target.global_position)
			if distance > radius:
				continue
			seen[instance_id] = true
			results.append({
				"target": target,
				"visual": visual,
				"distance": distance,
				"force_hidden_visual": target is HarvestOre,
			})
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("distance", 0.0)) < float(right.get("distance", 0.0))
	)
	return results


static func _scan_target_is_alive(target: Node3D) -> bool:
	if target is VehicleBase:
		var vehicle := target as VehicleBase
		return vehicle.vehicle_deployed and vehicle.current_hp > 0.0 and vehicle.get_driver_seat_index() >= 0
	if target is HarvestOre:
		return not (target as HarvestOre).destroyed
	if target is GiantPlants:
		return not (target as GiantPlants).destroyed
	return target is PickupItem


static func _scan_visual_for_target(target: Node3D) -> Node3D:
	if target is VehicleBase:
		# Start at the vehicle root so FarmBase attachments and other installed
		# modules join the same union mask as the chassis.
		return target
	if target is PickupItem:
		return (target as PickupItem).model_pivot
	if target is HarvestOre:
		return (target as HarvestOre).mesh_root
	if target is GiantPlants:
		return target.get_node_or_null("Mesh") as Node3D
	return null
