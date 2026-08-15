extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const BASE_MESH_SCENE_PATH := "res://assets/vehicles/ModularFarmBaseVehicle.glb"
const REINFORCED_MESH_SCENE_PATH := "res://assets/vehicles/ModularFarmBaseVehicle_Defend.glb"
const BODY_MESH_NAME := "FTF_Vehicle_ModularFarmBase_Black_6_5m_Static"
const WHEEL_MESH_NAME := "Wheel_FL_Mesh"
const DEFENSE_NET_MESH_NAME := "DefenseNet_CabFront"

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	vehicle.set_reinforced_variant(true)
	_check(vehicle.get_max_hp() == 4500.0, "reinforced configuration uses 1.5x FarmBaseVehicle HP")
	var preview_mesh := vehicle.find_child("Mesh", true, false) as Node3D
	_check(preview_mesh != null and preview_mesh.name == "Mesh", "reinforced preview keeps the Mesh node name")
	_check(
		preview_mesh != null
			and str(preview_mesh.get_meta("farm_base_mesh_scene_path", "")) == REINFORCED_MESH_SCENE_PATH,
		"reinforced preview uses ModularFarmBaseVehicle_Defend.glb"
	)
	_check(
		preview_mesh != null and preview_mesh.find_child(DEFENSE_NET_MESH_NAME, true, false) != null,
		"reinforced preview contains the authored DefenseNet mesh"
	)
	add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle.get_max_hp() == 4500.0, "deployed reinforced vehicle keeps 4500 HP")
	var mesh := vehicle.find_child("Mesh", true, false) as Node3D
	_check(mesh != null and mesh.name == "Mesh", "deployed reinforced vehicle keeps the Mesh node name")
	var body_mesh := vehicle.find_child(BODY_MESH_NAME, true, false) as MeshInstance3D
	var wheel_mesh := vehicle.find_child(WHEEL_MESH_NAME, true, false) as MeshInstance3D
	var defense_net_mesh := vehicle.find_child(DEFENSE_NET_MESH_NAME, true, false) as MeshInstance3D
	_check(body_mesh != null and wheel_mesh != null, "reinforced model keeps body and wheel mesh names")
	_check(defense_net_mesh != null, "reinforced model exposes the DefenseNet mesh")

	var body_paint := Color("d62828")
	var wheel_paint := Color("4db8ff")
	vehicle.set_body_color(body_paint)
	vehicle.set_wheel_color(wheel_paint)
	var body_material := body_mesh.material_override as StandardMaterial3D if body_mesh != null else null
	var wheel_material := wheel_mesh.material_override as StandardMaterial3D if wheel_mesh != null else null
	_check(
		body_material != null and body_material.albedo_color.is_equal_approx(body_paint),
		"body paint is applied to the reinforced chassis mesh"
	)
	_check(
		wheel_material != null and wheel_material.albedo_color.is_equal_approx(wheel_paint),
		"wheel paint is applied to the reinforced wheel mesh"
	)
	_check(
		defense_net_mesh != null and defense_net_mesh.material_override == null,
		"reinforced DefenseNet keeps its authored material instead of chassis paint"
	)

	var network_state := vehicle.get_network_state()
	_check(bool(network_state.get("reinforced_variant", false)), "reinforced state is included in vehicle snapshots")
	_check(is_equal_approx(float(network_state.get("max_hp", 0.0)), 4500.0), "vehicle snapshot exposes reinforced max HP")

	vehicle.set_reinforced_variant(false)
	await get_tree().process_frame
	_check(vehicle.get_max_hp() == 3000.0, "switching back restores the standard 3000 HP configuration")
	var standard_mesh := vehicle.find_child("Mesh", true, false) as Node3D
	_check(
		standard_mesh != null
			and str(standard_mesh.get_meta("farm_base_mesh_scene_path", "")) == BASE_MESH_SCENE_PATH,
		"switching back restores the standard GLB while keeping Mesh"
	)
	_check(
		vehicle.find_child(DEFENSE_NET_MESH_NAME, true, false) == null,
		"standard vehicle does not keep reinforced DefenseNet meshes"
	)
	var restored_body := vehicle.find_child(BODY_MESH_NAME, true, false) as MeshInstance3D
	var restored_wheel := vehicle.find_child(WHEEL_MESH_NAME, true, false) as MeshInstance3D
	var restored_body_material := restored_body.material_override as StandardMaterial3D if restored_body != null else null
	var restored_wheel_material := restored_wheel.material_override as StandardMaterial3D if restored_wheel != null else null
	_check(
		restored_body_material != null and restored_body_material.albedo_color.is_equal_approx(body_paint),
		"body paint survives a reinforced-to-standard model switch"
	)
	_check(
		restored_wheel_material != null and restored_wheel_material.albedo_color.is_equal_approx(wheel_paint),
		"wheel paint survives a reinforced-to-standard model switch"
	)

	if failures == 0:
		print("[FarmBaseVehicleReinforcedValidation] PASS all checks")
	else:
		push_error("[FarmBaseVehicleReinforcedValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[FarmBaseVehicleReinforcedValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[FarmBaseVehicleReinforcedValidation] FAIL: %s" % description)
