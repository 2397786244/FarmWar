extends Node3D

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var neutral_packed := load("res://vehicles/cargo_car.tscn") as PackedScene
	_check(neutral_packed != null, "neutral CargoCar scene loads")
	if neutral_packed != null:
		var neutral_vehicle := neutral_packed.instantiate() as VehicleBase
		add_child(neutral_vehicle)
		await get_tree().process_frame
		_check(neutral_vehicle.supports_cargo(), "neutral CargoCar enables cargo support")
		var neutral_areas := neutral_vehicle.find_children("*", "CargoCarInteractionArea", true, false)
		_check(neutral_areas.size() == 5, "neutral CargoCar creates two driver and three cargo areas")
		var neutral_rear := neutral_vehicle.find_child("CargoAreaRear", true, false) as CargoCarInteractionArea
		_check(neutral_rear != null, "neutral CargoCar creates a recursive rear cargo area")
		if neutral_rear != null:
			_check(neutral_vehicle.is_cargo_storage_interaction_available_to(neutral_rear.global_position),
				"recursive cargo range check accepts the rear cargo area")
		neutral_vehicle.queue_free()

	var team_packed := load("res://vehicles/red_cargo_car.tscn") as PackedScene
	_check(team_packed != null, "team CargoCar scene loads")
	if team_packed != null:
		var team_vehicle := team_packed.instantiate() as VehicleBase
		add_child(team_vehicle)
		await get_tree().process_frame
		var team_rear := team_vehicle.find_child("CargoAreaRear", true, false) as CargoCarInteractionArea
		_check(team_rear != null, "team CargoCar creates a recursive rear cargo area")
		if team_rear != null:
			_check(team_vehicle.is_cargo_storage_interaction_available_to(team_rear.global_position),
				"team CargoCar recursive range check accepts the rear cargo area")
		team_vehicle.queue_free()

	if failures.is_empty():
		print("[CargoCarInteractionValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[CargoCarInteractionValidation] " + failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
