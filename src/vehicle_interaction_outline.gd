extends Node3D
class_name VehicleInteractionOutline

## Renders one selected vehicle into a dedicated mask viewport, then draws a
## single screen-space edge over the main camera. The source vehicle materials
## are never changed.

const MASK_RENDER_LAYER := 1 << 29
const MASK_SHADER := preload("res://src/vehicle_interaction_mask.gdshader")
const OUTLINE_SHADER := preload("res://src/vehicle_interaction_outline.gdshader")

var _owner_player: Node
var _mask_viewport: SubViewport
var _mask_root: Node3D
var _mask_camera: Camera3D
var _outline_quad: MeshInstance3D
var _outline_material: ShaderMaterial
var _mask_material: ShaderMaterial
var _target_vehicle: VehicleBase
var _target_visual: Node3D
var _mask_visual: Node3D


func setup(owner_player: Node) -> void:
	_owner_player = owner_player
	_create_mask_viewport()
	_create_outline_quad()
	clear_target()


func _create_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "VehicleInteractionMaskViewport"
	_mask_viewport.transparent_bg = true
	_mask_viewport.handle_input_locally = false
	_mask_viewport.gui_disable_input = true
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	var main_viewport := _owner_player.get_viewport()
	_mask_viewport.world_3d = main_viewport.world_3d
	_mask_viewport.size = main_viewport.size
	add_child(_mask_viewport)

	_mask_root = Node3D.new()
	_mask_root.name = "VehicleMaskRoot"
	_mask_viewport.add_child(_mask_root)

	_mask_camera = Camera3D.new()
	_mask_camera.name = "VehicleMaskCamera"
	_mask_camera.cull_mask = MASK_RENDER_LAYER
	_mask_camera.current = true
	_mask_viewport.add_child(_mask_camera)


func _create_outline_quad() -> void:
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	_outline_quad = MeshInstance3D.new()
	_outline_quad.name = "VehicleInteractionOutlineQuad"
	_outline_quad.mesh = quad_mesh
	_outline_quad.layers = 1
	_outline_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_outline_quad.visible = false
	add_child(_outline_quad)

	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.render_priority = 127
	_outline_quad.material_override = _outline_material


func set_target(vehicle: VehicleBase) -> void:
	if vehicle == _target_vehicle and is_instance_valid(_mask_visual):
		_outline_quad.visible = true
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	clear_target()
	if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.body_visual):
		return
	_target_vehicle = vehicle
	_target_visual = vehicle.body_visual
	_mask_visual = _duplicate_visual_geometry(_target_visual)
	if not is_instance_valid(_mask_visual):
		clear_target()
		return
	_mask_visual.name = "SelectedVehicleMask"
	_mask_root.add_child(_mask_visual)
	_mask_visual.global_transform = _target_visual.global_transform
	_outline_quad.visible = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_outline_material.set_shader_parameter("mask_texture", _mask_viewport.get_texture())


func clear_target() -> void:
	_target_vehicle = null
	_target_visual = null
	if is_instance_valid(_mask_visual):
		_mask_visual.queue_free()
	_mask_visual = null
	if is_instance_valid(_outline_quad):
		_outline_quad.visible = false
	if is_instance_valid(_mask_viewport):
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func update(active_camera: Camera3D) -> void:
	if not is_instance_valid(_target_vehicle) or not is_instance_valid(_mask_visual) \
			or not is_instance_valid(active_camera):
		return
	if not is_instance_valid(_target_visual):
		clear_target()
		return
	_mask_visual.global_transform = _target_visual.global_transform
	_sync_camera(active_camera)
	_outline_quad.global_transform = active_camera.global_transform


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


func _duplicate_visual_geometry(source: Node3D) -> Node3D:
	if source is GeometryInstance3D:
		var geometry_root := source.duplicate() as GeometryInstance3D
		if geometry_root == null:
			return null
		geometry_root.layers = MASK_RENDER_LAYER
		_configure_mask_geometry(geometry_root)
		return geometry_root
	var root := Node3D.new()
	root.transform = source.transform
	_copy_visual_children(source, root)
	return root


func _copy_visual_children(source: Node, destination: Node3D) -> void:
	for child in source.get_children():
		if not child is Node3D:
			continue
		var source_node := child as Node3D
		var destination_node: Node3D
		if source_node is GeometryInstance3D:
			var destination_geometry := source_node.duplicate() as GeometryInstance3D
			if destination_geometry == null:
				continue
			destination_node = destination_geometry
			destination_geometry.layers = MASK_RENDER_LAYER
			_configure_mask_geometry(destination_node)
		else:
			destination_node = Node3D.new()
			destination_node.name = source_node.name
			destination_node.transform = source_node.transform
		destination.add_child(destination_node)
		if not source_node is GeometryInstance3D:
			_copy_visual_children(source_node, destination_node)


func _configure_mask_geometry(node: Node3D) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.visible = true
		geometry.material_override = _get_mask_material()
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children():
		if child is Node3D:
			_configure_mask_geometry(child as Node3D)


func _get_mask_material() -> ShaderMaterial:
	if is_instance_valid(_mask_material):
		return _mask_material
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = MASK_SHADER
	return _mask_material
