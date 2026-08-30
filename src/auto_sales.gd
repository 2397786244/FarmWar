extends Shop
class_name AutoSales

## AutoSales uses a deliberately quiet white perimeter.  It is a world-space
## affordance for the ShopArea, not a gameplay collision or a second trigger.
const OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.96)
const OUTLINE_WIDTH := 0.055
const OUTLINE_HEIGHT := 0.035
const OUTLINE_Y_OFFSET := 0.012

var _outline_root: Node3D


func _ready() -> void:
	add_to_group("vehicle_sales_shops")
	shop_category = "vehicle_sales"
	shop_display_name = "AutoSales 载具商店"
	interaction_hint = "[E] 打开载具商店"
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


func get_interaction_position() -> Vector3:
	var shop_area := find_child("ShopArea", true, false) as Area3D
	if shop_area == null:
		return global_position
	var collision_shape := shop_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
	return collision_shape.global_position if collision_shape != null else shop_area.global_position


func get_shop_list() -> Array[Dictionary]:
	return VehicleSalesCatalog.get_products()


func _create_area_outline(shop_area: Area3D) -> void:
	var collision_shape := shop_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_warning("%s: ShopArea requires a BoxShape3D for its prompt outline." % name)
		return
	var box := collision_shape.shape as BoxShape3D
	_outline_root = Node3D.new()
	_outline_root.name = "ShopAreaOutline"
	collision_shape.add_child(_outline_root)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = OUTLINE_COLOR
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.35

	_add_line(
		Vector3(0.0, OUTLINE_Y_OFFSET, -box.size.z * 0.5),
		Vector3(box.size.x, OUTLINE_HEIGHT, OUTLINE_WIDTH),
		material
	)
	_add_line(
		Vector3(0.0, OUTLINE_Y_OFFSET, box.size.z * 0.5),
		Vector3(box.size.x, OUTLINE_HEIGHT, OUTLINE_WIDTH),
		material
	)
	_add_line(
		Vector3(-box.size.x * 0.5, OUTLINE_Y_OFFSET, 0.0),
		Vector3(OUTLINE_WIDTH, OUTLINE_HEIGHT, box.size.z),
		material
	)
	_add_line(
		Vector3(box.size.x * 0.5, OUTLINE_Y_OFFSET, 0.0),
		Vector3(OUTLINE_WIDTH, OUTLINE_HEIGHT, box.size.z),
		material
	)


func _add_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_root.add_child(mesh_instance)
