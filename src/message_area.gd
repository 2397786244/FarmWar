extends Node3D
class_name MessageArea

## Tutorial-only message trigger. The player receives the text while inside
## the Area3D; no E interaction is required.

const MESSAGE_AREA_LAYER := 1024
const PLAYER_LAYER := 8
const LINE_WIDTH := 0.07
const LINE_HEIGHT := 0.018
const GLOW_WIDTH := 0.22
const GLOW_HEIGHT := 0.32
const OUTER_GLOW_WIDTH := 0.38
const OUTER_GLOW_HEIGHT := 0.72
const OUTLINE_HEIGHT_ABOVE_AREA_FLOOR := 1.0
const FLOAT_AMPLITUDE := 0.035
const FLOAT_SPEED := 1.35

@export_multiline var prompt_text := "教程提示"
@export var boundary_color := Color(0.2, 1.0, 0.38, 1.0)
@export var show_boundary := true
@export var area_size := Vector3(4.0, 2.0, 4.0)

var _area: Area3D
var _outline_root: Node3D
var _outline_base_y := 0.0
var _elapsed := 0.0


func _ready() -> void:
	add_to_group("message_areas")
	_area = get_node_or_null("MessageArea") as Area3D
	if _area == null:
		push_warning("%s: MessageArea Area3D is missing." % name)
		return
	_area.collision_layer = MESSAGE_AREA_LAYER
	_area.collision_mask = PLAYER_LAYER
	_area.monitoring = true
	_area.monitorable = true
	var shape := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var box := shape.shape as BoxShape3D
		if box != null:
			box.size = area_size
	_refresh_boundary()


func _process(delta: float) -> void:
	if not is_instance_valid(_outline_root):
		return
	_elapsed += delta
	_outline_root.position.y = _outline_base_y + sin(_elapsed * FLOAT_SPEED) * FLOAT_AMPLITUDE


func is_player_inside(player: Node3D) -> bool:
	return is_instance_valid(_area) and is_instance_valid(player) and _area.overlaps_body(player)


func get_prompt_text() -> String:
	return prompt_text.strip_edges()


func refresh_visuals() -> void:
	_refresh_boundary()


func _refresh_boundary() -> void:
	if is_instance_valid(_outline_root):
		_outline_root.queue_free()
		_outline_root = null
	if not show_boundary or not is_instance_valid(_area):
		return
	var collision_shape := _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		return
	var box := collision_shape.shape as BoxShape3D
	_outline_root = Node3D.new()
	_outline_root.name = "MessageAreaOutline"
	collision_shape.add_child(_outline_root)
	_outline_base_y = -box.size.y * 0.5 + OUTLINE_HEIGHT_ABOVE_AREA_FLOOR
	_outline_root.position.y = _outline_base_y

	var outer_color := Color(boundary_color.r, boundary_color.g, boundary_color.b, 0.11)
	var glow_color := Color(boundary_color.r, boundary_color.g, boundary_color.b, 0.26)
	_add_perimeter(box.size, OUTER_GLOW_WIDTH, OUTER_GLOW_HEIGHT, -0.025, _create_glow_material(outer_color, 2.2))
	_add_perimeter(box.size, GLOW_WIDTH, GLOW_HEIGHT, -0.012, _create_glow_material(glow_color, 3.5))
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = boundary_color
	line_material.emission_enabled = true
	line_material.emission = boundary_color
	line_material.emission_energy_multiplier = 2.0
	_add_perimeter(box.size, LINE_WIDTH, LINE_HEIGHT, 0.0, line_material)


func _create_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = boundary_color
	material.emission_energy_multiplier = energy
	return material


func _add_perimeter(area_size_value: Vector3, width: float, height: float, y_offset: float, material: Material) -> void:
	_add_line(Vector3(0.0, y_offset, -area_size_value.z * 0.5), Vector3(area_size_value.x, height, width), material)
	_add_line(Vector3(0.0, y_offset, area_size_value.z * 0.5), Vector3(area_size_value.x, height, width), material)
	_add_line(Vector3(-area_size_value.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size_value.z), material)
	_add_line(Vector3(area_size_value.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size_value.z), material)


func _add_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_root.add_child(mesh_instance)
