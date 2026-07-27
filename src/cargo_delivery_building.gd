class_name CargoDeliveryBuilding
extends StaticBody3D

signal valid_delivery_entered(
	building_id: String, team: String, entrant_kind: String, entrant: Node
)

const PLAYER_LAYER := 8
const VEHICLE_LAYER := 8192
const DELIVERY_AREA_LAYER := 512

@export var building_id := ""
@export var display_name := "交付点"
@export var building_type := "delivery"
@export var owner_team := ""
@export var accepted_delivery_categories := PackedStringArray()

@export_group("Area Appearance")
@export var line_color := Color(0.18, 1.0, 0.32, 1.0)
@export var glow_color := Color(0.55, 1.0, 0.62, 0.24)
@export var outer_glow_color := Color(0.68, 1.0, 0.72, 0.10)
@export var glow_emission := Color(0.34, 1.0, 0.42, 1.0)
@export_range(0.1, 3.0, 0.05) var outline_height := 1.0

var _cargo_area: Area3D
var _outline_root: Node3D
var _outline_base_y := 0.0
var _elapsed := 0.0


func _ready() -> void:
	_apply_building_metadata()
	_cargo_area = find_child("CargoArea", true, false) as Area3D
	if _cargo_area == null:
		push_warning("CargoDeliveryBuilding: CargoArea is missing on %s." % name)
		return
	_cargo_area.collision_layer = DELIVERY_AREA_LAYER
	_cargo_area.collision_mask = PLAYER_LAYER | VEHICLE_LAYER
	_cargo_area.monitoring = true
	_cargo_area.monitorable = true
	_cargo_area.add_to_group("task_delivery_areas")
	_cargo_area.set_meta("building_id", building_id)
	_cargo_area.set_meta("team", owner_team)
	_cargo_area.set_meta("accepted_delivery_categories", accepted_delivery_categories)
	if not _cargo_area.body_entered.is_connected(_on_cargo_area_body_entered):
		_cargo_area.body_entered.connect(_on_cargo_area_body_entered)
	_create_area_outline()
	call_deferred("_register_delivery_building")


func _process(delta: float) -> void:
	if not is_instance_valid(_outline_root):
		return
	_elapsed += delta
	_outline_root.position.y = _outline_base_y + sin(_elapsed * 1.35) * 0.035


func _apply_building_metadata() -> void:
	set_meta("building_id", building_id)
	set_meta("display_name", display_name)
	set_meta("building_type", building_type)
	set_meta("team", owner_team)
	set_meta("accepts_delivery", true)
	set_meta("accepted_delivery_categories", accepted_delivery_categories)


func _register_delivery_building() -> void:
	if is_instance_valid(MapBuildingRegistry):
		MapBuildingRegistry.register_building(self, building_id, display_name, building_type)


func _on_cargo_area_body_entered(body: Node3D) -> void:
	if GameAuthority.is_client_proxy():
		return
	var entrant := _resolve_delivery_entrant(body)
	var entrant_team := str(entrant.get("team", ""))
	if not _is_delivery_entrant_allowed(entrant):
		return
	var entrant_kind := str(entrant.get("kind", ""))
	valid_delivery_entered.emit(building_id, entrant_team, entrant_kind, body)
	if is_instance_valid(FoodOrderEmitter) and FoodOrderEmitter.has_method("notify_delivery_destination_entered"):
		FoodOrderEmitter.notify_delivery_destination_entered(
			building_id,
			entrant_team,
			entrant_kind,
			int(entrant.get("peer_id", 0)),
			str(entrant.get("vehicle_id", ""))
		)
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("request_cargo_delivery_preview"):
		GameAuthority.request_cargo_delivery_preview(
			building_id,
			display_name,
			entrant_team,
			entrant_kind,
			int(entrant.get("peer_id", 0)),
			str(entrant.get("vehicle_id", ""))
		)


func is_valid_delivery_body(body: Node) -> bool:
	return _is_delivery_entrant_allowed(_resolve_delivery_entrant(body))


func _is_delivery_entrant_allowed(entrant: Dictionary) -> bool:
	if entrant.is_empty():
		return false
	var entrant_team := str(entrant.get("team", ""))
	return not entrant_team.is_empty() \
		and (owner_team.is_empty() or owner_team == entrant_team)


func _resolve_delivery_entrant(body: Node) -> Dictionary:
	var peer_id := GameAuthority.get_authority_player_peer_id(body)
	if peer_id > 0 and GameAuthority.player_states.has(peer_id):
		return {
			"kind": "player",
			"peer_id": peer_id,
			"team": str((GameAuthority.player_states[peer_id] as Dictionary).get("team", "")),
		}
	if not body is VehicleBase:
		return {}
	var vehicle := body as VehicleBase
	var vehicle_id := vehicle.get_vehicle_id()
	if not vehicle_id.to_lower().contains("cargo_car") or vehicle.driver_peer_id <= 0:
		return {}
	if not GameAuthority.player_states.has(vehicle.driver_peer_id):
		return {}
	var driver_team := str(
		(GameAuthority.player_states[vehicle.driver_peer_id] as Dictionary).get("team", "")
	)
	if driver_team.is_empty() or vehicle.owner_team != driver_team:
		return {}
	return {
		"kind": "cargo_car",
		"peer_id": vehicle.driver_peer_id,
		"team": driver_team,
		"vehicle_id": vehicle_id,
	}


func _create_area_outline() -> void:
	var collision_shape := _cargo_area.find_child(
		"CollisionShape3D", true, false
	) as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_warning("CargoDeliveryBuilding: CargoArea on %s requires a BoxShape3D." % name)
		return
	var box := collision_shape.shape as BoxShape3D
	_outline_root = Node3D.new()
	_outline_root.name = "CargoAreaOutline"
	collision_shape.add_child(_outline_root)
	_outline_base_y = -box.size.y * 0.5 + outline_height
	_outline_root.position.y = _outline_base_y

	_add_perimeter(box.size, 0.38, 0.72, -0.025, _glow_material(outer_glow_color, 2.2))
	_add_perimeter(box.size, 0.22, 0.32, -0.012, _glow_material(glow_color, 3.5))
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = line_color
	line_material.emission_enabled = true
	line_material.emission = glow_emission
	line_material.emission_energy_multiplier = 2.2
	_add_perimeter(box.size, 0.07, 0.018, 0.0, line_material)


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = glow_emission
	material.emission_energy_multiplier = energy
	return material


func _add_perimeter(
	area_size: Vector3, width: float, height: float, y_offset: float, material: Material
) -> void:
	_add_line(Vector3(0.0, y_offset, -area_size.z * 0.5), Vector3(area_size.x, height, width), material)
	_add_line(Vector3(0.0, y_offset, area_size.z * 0.5), Vector3(area_size.x, height, width), material)
	_add_line(Vector3(-area_size.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size.z), material)
	_add_line(Vector3(area_size.x * 0.5, y_offset, 0.0), Vector3(width, height, area_size.z), material)


func _add_line(line_position: Vector3, line_size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	instance.mesh = mesh
	instance.position = line_position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_outline_root.add_child(instance)
