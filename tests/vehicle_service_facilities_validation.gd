extends Node3D

const MAP_FACILITY_CATALOG := preload("res://src/map_facility_catalog.gd")

const EXPECTED_FACILITIES := {
	"compact_two_post_lift": {
		"scene_path": "res://facilities/interior/vehicle_service/compact_two_post_lift.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/CompactTwoPostLift.glb",
		"label": "双柱汽车举升机",
		"interactive": false,
	},
	"repair_terminal": {
		"scene_path": "res://facilities/interior/vehicle_service/repair_terminal.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/RepairTerminal.glb",
		"label": "升级维修终端",
		"interactive": true,
	},
	"ev_charging_station": {
		"scene_path": "res://facilities/interior/vehicle_service/ev_charging_station.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/EVChargingStation.glb",
		"label": "EV充电站",
		"interactive": false,
	},
	"hvac": {
		"scene_path": "res://facilities/interior/vehicle_service/hvac.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/HVAC.glb",
		"label": "HVAC空调外机",
		"interactive": false,
	},
	"red_workbench": {
		"scene_path": "res://facilities/interior/vehicle_service/red_workbench.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/RedWorkbench.glb",
		"label": "红色工作台",
		"interactive": false,
	},
	"tire_rack": {
		"scene_path": "res://facilities/interior/vehicle_service/tire_rack.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/TireRack.glb",
		"label": "轮胎架",
		"interactive": false,
	},
	"welding_workbench": {
		"scene_path": "res://facilities/interior/vehicle_service/welding_workbench.tscn",
		"model_path": "res://assets/facilities/interior/vehicle_service/WeldingWorkbench.glb",
		"label": "焊接台",
		"interactive": false,
	},
}

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog_entries := {}
	for entry_value: Variant in MAP_FACILITY_CATALOG.get_assets("interior"):
		var entry := entry_value as Dictionary
		catalog_entries[str(entry.get("id", ""))] = entry

	for facility_id_value: Variant in EXPECTED_FACILITIES:
		var facility_id := str(facility_id_value)
		var expected := EXPECTED_FACILITIES[facility_id] as Dictionary
		var catalog_id := "interior_vehicle_service_%s" % facility_id
		var catalog_entry: Dictionary = catalog_entries.get(catalog_id, {})
		_check(not catalog_entry.is_empty(), "%s is discoverable by the interior facility catalog" % facility_id)
		if catalog_entry.is_empty():
			continue

		_check(
			str(catalog_entry.get("path", "")) == str(expected.get("scene_path", "")),
			"%s points to the expected scene" % facility_id
		)
		_check(
			str(catalog_entry.get("label", "")) == str(expected.get("label", "")),
			"%s has the expected Chinese label" % facility_id
		)
		_check(ResourceLoader.exists(str(expected.get("model_path", ""))), "%s model exists" % facility_id)

		var packed := load(str(expected.get("scene_path", ""))) as PackedScene
		var facility := packed.instantiate() as Node3D if packed != null else null
		_check(facility != null, "%s scene instantiates" % facility_id)
		if facility == null:
			continue
		_check(
			bool(facility.get_meta("interaction_enabled", false)) == bool(expected.get("interactive", false)),
			"%s interaction metadata is correct" % facility_id
		)
		_check(
			(expected.get("interactive", false) and not facility.find_children("*", "CollisionShape3D", true, false).is_empty()) \
				or (not expected.get("interactive", false) and facility.find_children("*", "CollisionShape3D", true, false).is_empty()),
			"%s collision setup matches its interaction role" % facility_id
		)
		_check(
			(expected.get("interactive", false) and facility.find_children("*", "Area3D", true, false).size() == 2) \
				or (not expected.get("interactive", false) and facility.find_children("*", "Area3D", true, false).is_empty()),
			"%s interaction area setup matches its interaction role" % facility_id
		)
		if expected.get("interactive", false):
			var player_area := facility.get_node_or_null("PlayerInteract") as Area3D
			var vehicle_area := facility.get_node_or_null("VehicleInteract") as Area3D
			_check(player_area != null and player_area.collision_layer == 512 and player_area.collision_mask == 8, "%s player area collision contract" % facility_id)
			_check(vehicle_area != null and vehicle_area.collision_layer == 512 and vehicle_area.collision_mask == (8192 | 8), "%s vehicle area detects vehicles and players" % facility_id)
			var service_camera := facility.get_node_or_null("Camera3D") as Camera3D
			_check(service_camera != null and not service_camera.current, "%s presentation camera starts inactive" % facility_id)
		facility.free()

	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[VehicleServiceFacilitiesValidation] PASS %s" % description)
	else:
		_failures += 1
		push_error("[VehicleServiceFacilitiesValidation] FAIL %s" % description)


func _finish() -> void:
	print(
		"[VehicleServiceFacilitiesValidation] %s" % (
			"PASS" if _failures == 0 else "FAIL count=%d" % _failures
		)
	)
	get_tree().quit(0 if _failures == 0 else 1)
