extends Node3D

const EXPECTED_DRIVER_OFFSET := Vector3(0.0, -0.9, 0.0)
const DRIVER_SCENES := [
	{"path": "res://vehicles/cargo_car.tscn", "anchor": "DriverSeatPoint"},
	{"path": "res://character/weapons/SurveyRider.tscn", "anchor": "ProspectorSeat"},
	{"path": "res://character/weapons/KitchenCar.tscn", "anchor": "DriverSeatPoint"},
	{"path": "res://vehicles/farm_base_vehicle.tscn", "anchor": "DriverSeatPoint"},
]

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for entry: Dictionary in DRIVER_SCENES:
		var packed := load(str(entry["path"])) as PackedScene
		_check(packed != null, "%s loads" % entry["path"])
		if packed == null:
			continue
		var vehicle := packed.instantiate() as VehicleBase
		_check(vehicle != null, "%s creates a VehicleBase" % entry["path"])
		if vehicle == null:
			continue
		add_child(vehicle)
		await get_tree().process_frame

		var anchor := vehicle.get_seat_anchor(0)
		_check(anchor != null, "%s resolves its driver seat anchor" % entry["path"])
		if anchor != null:
			_check(anchor.name == str(entry["anchor"]), "%s uses %s" % [entry["path"], entry["anchor"]])
			_check(anchor != vehicle.get_node_or_null("DriverSeat"), "%s does not fall back to the generic DriverSeat" % entry["path"])
			var seat_basis := anchor.global_transform.basis.orthonormalized()
			var expected_origin := anchor.global_position + seat_basis * EXPECTED_DRIVER_OFFSET
			var occupant_transform := vehicle.get_occupant_world_transform(0)
			_check(
				occupant_transform.origin.distance_to(expected_origin) < 0.001,
				"%s applies the root-to-hip plus shared seated lowering" % entry["path"]
			)

		vehicle.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[DriverSeatAlignmentValidation] PASS all checks")
	else:
		push_error("[DriverSeatAlignmentValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[DriverSeatAlignmentValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[DriverSeatAlignmentValidation] FAIL: %s" % description)
