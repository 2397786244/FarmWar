extends Shop
class_name FoodCarShop

const OUTLINE_COLOR := Color(1.0, 0.74, 0.18, 1.0)
const OUTLINE_EMISSION := Color(1.0, 0.38, 0.04, 1.0)
const GLOW_COLOR := Color(1.0, 0.82, 0.24, 0.26)
const OUTER_GLOW_COLOR := Color(1.0, 0.76, 0.16, 0.11)
const GLOW_EMISSION := Color(1.0, 0.58, 0.06, 1.0)
const LINE_WIDTH := 0.07
const LINE_HEIGHT := 0.018
const GLOW_WIDTH := 0.22
const GLOW_HEIGHT := 0.32
const OUTER_GLOW_WIDTH := 0.38
const OUTER_GLOW_HEIGHT := 0.72
const OUTLINE_HEIGHT_ABOVE_AREA_FLOOR := 1.0
const FLOAT_AMPLITUDE := 0.035
const FLOAT_SPEED := 1.35

var _outline_root: Node3D
var _outline_base_y := 0.0
var _elapsed := 0.0


func _ready() -> void:
	var shop_area := find_child("ShopArea", true, false) as Area3D
	if shop_area == null:
		push_warning("%s: ShopArea is missing." % name)
		return
	shop_area.collision_layer = 512
	shop_area.collision_mask = 8
	shop_area.monitoring = true
	shop_area.monitorable = true
	shop_area.add_to_group("shop_interaction_areas")
	_create_area_outline(shop_area)

func _process(delta: float) -> void:
	if not is_instance_valid(_outline_root):
		return
	_elapsed += delta
	_outline_root.position.y = _outline_base_y + sin(_elapsed * FLOAT_SPEED) * FLOAT_AMPLITUDE


func _create_area_outline(shop_area: Area3D) -> void:
	var collision_shape := shop_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_warning("%s: ShopArea requires a BoxShape3D for its prompt outline." % name)
		return
	var box := collision_shape.shape as BoxShape3D
	_outline_root = Node3D.new()
	_outline_root.name = "ShopAreaOutline"
	collision_shape.add_child(_outline_root)
	_outline_base_y = -box.size.y * 0.5 + OUTLINE_HEIGHT_ABOVE_AREA_FLOOR
	_outline_root.position.y = _outline_base_y

	var outer_glow_material := _create_glow_material(OUTER_GLOW_COLOR, 2.2)
	_add_perimeter(box.size, OUTER_GLOW_WIDTH, OUTER_GLOW_HEIGHT, -0.025, outer_glow_material)
	var glow_material := _create_glow_material(GLOW_COLOR, 3.5)
	_add_perimeter(box.size, GLOW_WIDTH, GLOW_HEIGHT, -0.012, glow_material)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = OUTLINE_COLOR
	material.emission_enabled = true
	material.emission = OUTLINE_EMISSION
	material.emission_energy_multiplier = 2.0
	_add_perimeter(box.size, LINE_WIDTH, LINE_HEIGHT, 0.0, material)


func _create_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = GLOW_EMISSION
	material.emission_energy_multiplier = energy
	return material


func _add_perimeter(
	area_size: Vector3,
	width: float,
	height: float,
	y_offset: float,
	material: Material
) -> void:
	_add_line(Vector3(0.0, y_offset, -area_size.z * 0.5), Vector3(area_size.x, height, width), material)
	_add_line(Vector3(0.0, y_offset, area_size.z * 0.5), Vector3(area_size.x, height, width), material)
	_add_line(Vector3(-area_size.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size.z), material)
	_add_line(Vector3(area_size.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size.z), material)


func _add_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_root.add_child(mesh_instance)
