extends Node3D

const CARGO_SCENE := preload("res://vehicles/cargo_car.tscn")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)

	var editor := HarvestOperationRuntimeMapEditor.new()
	editor._buildings_root = buildings

	var vehicle := CARGO_SCENE.instantiate() as VehicleBase
	_check(vehicle != null, "cargo scene loads as VehicleBase")
	if vehicle == null:
		_finish()
		return
	vehicle.name = "PromoVehicle"
	vehicle.set_meta("map_editor_uuid", "vehicle_promo_smoke")
	vehicle.set_meta("map_editor_category", "vehicle")
	buildings.add_child(vehicle)
	await get_tree().process_frame

	var characters := editor._get_promotional_vehicle_driver_character_definitions()
	_check(characters.size() == 10, "exactly ten player Carry characters are available")
	for entry_value in characters:
		var entry := entry_value as Dictionary
		_check(
			not editor._promotional_animation_name_for(
				editor._get_promotional_animation_names(
					str(entry.get("path", "")),
					HarvestOperationRuntimeMapEditor.PROMOTIONAL_VEHICLE_DRIVER_ALLOWED_ANIMATIONS
				),
				"Carry"
			).is_empty(),
			"%s exposes Carry" % str(entry.get("id", "character"))
		)

	editor._apply_promotional_vehicle_driver_state(
		"vehicle_promo_smoke",
		"farmer",
		true,
		"auxiliary_vehicle_driver_smoke"
	)
	await get_tree().process_frame
	var dummy := editor._find_promotional_vehicle_driver_dummy("vehicle_promo_smoke")
	_check(dummy != null, "driver dummy is created")
	if dummy != null:
		_check(
			str(dummy.get_meta("map_editor_spawn_kind", "")) == "promotional_vehicle_driver_dummy",
			"driver dummy uses the static vehicle spawn kind"
		)
		_check(dummy.visible, "open-cabin vehicle shows driver dummy")
		_check(vehicle.seat_occupants.is_empty(), "driver dummy does not occupy a real vehicle seat")
		var character := dummy.get_node_or_null("CharacterGLB") as Node3D
		var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D if character != null else null
		_check(
			skeleton != null and skeleton.find_child("PromotionalVehicleRightLegIK", false, false) != null,
			"right leg IK is installed"
		)
		_check(
			skeleton != null and skeleton.find_child("PromotionalVehicleLeftLegIK", false, false) != null,
			"left leg IK is installed"
		)
		var serialized_driver := editor._serialize_editor_object(dummy)
		editor._apply_promotional_vehicle_driver_state(
			"vehicle_promo_smoke",
			"farmer",
			false,
			"auxiliary_vehicle_driver_smoke"
		)
		editor._restore_object_records([serialized_driver])
		var restored_dummy := editor._find_promotional_vehicle_driver_dummy("vehicle_promo_smoke")
		_check(restored_dummy != null, "driver dummy restores from editor object data")
		_check(
			restored_dummy != null and restored_dummy.visible,
			"restored open-cabin driver dummy is visible"
		)

	editor._apply_promotional_vehicle_driver_state(
		"vehicle_promo_smoke",
		"farmer",
		false,
		"auxiliary_vehicle_driver_smoke"
	)
	_check(
		editor._find_promotional_vehicle_driver_dummy("vehicle_promo_smoke") == null,
		"driver dummy can be removed without touching the vehicle seat state"
	)
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PromotionalVehicleDriverSmoke] PASS: %s" % description)
	else:
		_failures += 1
		push_error("[PromotionalVehicleDriverSmoke] FAIL: %s" % description)


func _finish() -> void:
	print("[PromotionalVehicleDriverSmoke] %s" % ("PASS" if _failures == 0 else "FAIL count=%d" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
