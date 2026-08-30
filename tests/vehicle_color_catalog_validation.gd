extends Node3D

const VehicleColorCatalogScript = preload("res://src/vehicle_color_catalog.gd")
const EDITOR_SCRIPT = preload("res://src/farmwar_runtime_map_editor.gd")

const COLORABLE_VEHICLES := [
	{"id": "atv", "path": "res://vehicles/atv.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "mini_car", "path": "res://vehicles/mini_car.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "van", "path": "res://vehicles/van.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "sedan", "path": "res://vehicles/sedan.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "sport_car", "path": "res://vehicles/sport_car.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "police_car", "path": "res://vehicles/police_car.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "fire_pickup", "path": "res://vehicles/fire_pickup.tscn", "body": "BodyPaint_Mesh", "wheel": "Wheel_FL_Hub"},
	{"id": "farm_base_vehicle", "path": "res://vehicles/farm_base_vehicle.tscn", "body": "FTF_Vehicle_ModularFarmBase_Black_6_5m_Static", "wheel": "Wheel_FL_Mesh"},
]

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := VehicleColorCatalogScript.get_options()
	_check(options.size() == 11, "shared color catalog contains eleven options")
	_check(VehicleColorCatalogScript.get_label("dark_gray") == "深灰色", "dark gray has a stable label")
	_check(VehicleColorCatalogScript.get_label("silver_gray") == "银灰色", "silver gray has a stable label")
	_check(VehicleColorCatalogScript.has_color("dark_gray"), "dark gray is accepted by the catalog")
	_check(VehicleColorCatalogScript.has_color("silver_gray"), "silver gray is accepted by the catalog")

	var dark_gray := VehicleColorCatalogScript.get_color("dark_gray")
	var silver_gray := VehicleColorCatalogScript.get_color("silver_gray")
	for entry_value: Variant in COLORABLE_VEHICLES:
		var entry := entry_value as Dictionary
		var packed := load(str(entry.get("path", ""))) as PackedScene
		var vehicle := packed.instantiate() as VehicleBase if packed != null else null
		_check(vehicle != null, "%s scene instantiates" % str(entry.get("id", "vehicle")))
		if vehicle == null:
			continue
		_check(vehicle.supports_custom_colors(), "%s exposes body and wheel paint targets" % str(entry.get("id", "vehicle")))
		vehicle.set_body_color(dark_gray)
		vehicle.set_wheel_color(silver_gray)
		var body := vehicle.find_child(str(entry.get("body", "")), true, false) as MeshInstance3D
		var wheel := vehicle.find_child(str(entry.get("wheel", "")), true, false) as MeshInstance3D
		var body_material := body.material_override as StandardMaterial3D if body != null else null
		var wheel_material := wheel.material_override as StandardMaterial3D if wheel != null else null
		_check(
			body_material != null and body_material.albedo_color.is_equal_approx(dark_gray),
			"%s applies dark gray to the body" % str(entry.get("id", "vehicle"))
		)
		_check(
			wheel_material != null and wheel_material.albedo_color.is_equal_approx(silver_gray),
			"%s applies silver gray to a wheel hub" % str(entry.get("id", "vehicle"))
		)
		vehicle.free()

	var editor := EDITOR_SCRIPT.new()
	editor._tool_mode = 8 # ToolMode.VEHICLE
	for entry_value: Variant in COLORABLE_VEHICLES:
		var entry := entry_value as Dictionary
		editor._selected_building_asset = {
			"path": str(entry.get("path", "")),
			"placement_category": "vehicle",
		}
		_check(
			bool(editor._selected_vehicle_supports_custom_colors()),
			"map editor exposes color controls for %s" % str(entry.get("id", "vehicle"))
		)
	editor._selected_building_asset = {"path": "res://vehicles/combine_car.tscn", "placement_category": "vehicle"}
	_check(
		not bool(editor._selected_vehicle_supports_custom_colors()),
		"map editor hides paint controls for a vehicle without paint targets"
	)
	editor.free()
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[VehicleColorCatalogValidation] PASS %s" % description)
	else:
		_failures += 1
		push_error("[VehicleColorCatalogValidation] FAIL %s" % description)


func _finish() -> void:
	print("[VehicleColorCatalogValidation] %s" % ("PASS" if _failures == 0 else "FAIL count=%d" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
