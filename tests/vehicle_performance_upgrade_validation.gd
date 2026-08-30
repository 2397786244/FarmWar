extends Node3D

const VEHICLE_CASES := [
	{
		"label": "ATV",
		"scene": preload("res://vehicles/atv.tscn"),
		"base_forward": 8.0,
		"base_reverse": 4.5,
		"base_acceleration": 5.0,
		"motor_forward": 9.6,
		"motor_reverse": 5.4,
		"motor_acceleration": 6.0,
	},
	{
		"label": "MiniCar",
		"scene": preload("res://vehicles/mini_car.tscn"),
		"base_forward": 6.0,
		"base_reverse": 4.0,
		"base_acceleration": 4.8,
		"motor_forward": 7.2,
		"motor_reverse": 4.8,
		"motor_acceleration": 5.76,
	},
	{
		"label": "Van",
		"scene": preload("res://vehicles/van.tscn"),
		"base_forward": 6.0,
		"base_reverse": 4.2,
		"base_acceleration": 4.5,
		"motor_forward": 7.2,
		"motor_reverse": 5.04,
		"motor_acceleration": 5.4,
	},
	{
		"label": "FarmBaseVehicle",
		"scene": preload("res://vehicles/farm_base_vehicle.tscn"),
		"base_forward": 5.0,
		"base_reverse": 4.0,
		"base_acceleration": 1.5,
		"motor_forward": 6.0,
		"motor_reverse": 4.8,
		"motor_acceleration": 1.8,
	},
	{
		"label": "Sedan",
		"scene": preload("res://vehicles/sedan.tscn"),
		"base_forward": 8.0,
		"base_reverse": 5.0,
		"base_acceleration": 5.5,
		"motor_forward": 9.6,
		"motor_reverse": 6.0,
		"motor_acceleration": 6.6,
	},
	{
		"label": "SportCar",
		"scene": preload("res://vehicles/sport_car.tscn"),
		"base_forward": 10.0,
		"base_reverse": 5.0,
		"base_acceleration": 6.0,
		"motor_forward": 12.0,
		"motor_reverse": 6.0,
		"motor_acceleration": 7.2,
	},
]

const SPECIAL_VEHICLE_SCENES := [
	{"label": "CargoCar", "scene": preload("res://vehicles/cargo_car.tscn")},
	{"label": "CombineCar", "scene": preload("res://vehicles/combine_car.tscn")},
	{"label": "PoliceCar", "scene": preload("res://vehicles/police_car.tscn")},
	{"label": "FirePickup", "scene": preload("res://vehicles/fire_pickup.tscn")},
]

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for case_value: Dictionary in VEHICLE_CASES:
		var label := str(case_value["label"])
		var scene := case_value["scene"] as PackedScene
		var vehicle := scene.instantiate() as VehicleBase
		_check(vehicle != null, "%s scene instantiates" % label)
		if vehicle == null:
			continue
		vehicle.name = "PerformanceValidation_%s" % label
		vehicle.network_id = "performance_validation_%s" % label.to_lower()
		vehicle.owner_team = "red"
		add_child(vehicle)
		await get_tree().process_frame
		_check(vehicle.supports_common_service_upgrades(), "%s enables common service upgrades" % label)
		_check(not vehicle.high_performance_motor_installed, "%s starts without the motor" % label)
		_check(is_equal_approx(vehicle.get_max_forward_speed(), float(case_value["base_forward"])), "%s base forward speed" % label)
		_check(is_equal_approx(vehicle.get_max_reverse_speed(), float(case_value["base_reverse"])), "%s base reverse speed" % label)
		_check(is_equal_approx(vehicle.get_acceleration(), float(case_value["base_acceleration"])), "%s base acceleration" % label)
		vehicle.set_high_performance_motor_installed(true)
		_check(vehicle.high_performance_motor_installed, "%s installs the motor once" % label)
		_check(is_equal_approx(vehicle.get_max_forward_speed(), float(case_value["motor_forward"])), "%s motor forward speed is 20 percent higher" % label)
		_check(is_equal_approx(vehicle.get_max_reverse_speed(), float(case_value["motor_reverse"])), "%s motor reverse speed is 20 percent higher" % label)
		_check(is_equal_approx(vehicle.get_acceleration(), float(case_value["motor_acceleration"])), "%s motor acceleration is 20 percent higher" % label)
		vehicle.set_high_performance_motor_installed(true)
		_check(is_equal_approx(vehicle.get_max_forward_speed(), float(case_value["motor_forward"])), "%s motor bonus does not stack" % label)
		var snapshot := vehicle.get_network_state()
		_check(bool(snapshot.get("high_performance_motor_installed", false)), "%s snapshot contains motor state" % label)
		vehicle.set_high_performance_motor_installed(false)
		vehicle.apply_network_state(snapshot)
		_check(vehicle.high_performance_motor_installed, "%s restores motor state from snapshot" % label)
		var base_max_hp := vehicle.get_max_hp()
		var composite_supported := vehicle.supports_vehicle_service_module("composite_armor_panel")
		_check(
			composite_supported == (not (vehicle is FarmBaseVehicle)),
			"%s has the expected composite armor compatibility" % label
		)
		if composite_supported:
			vehicle.current_hp = base_max_hp * 0.5
			vehicle.set_composite_armor_panel_installed(true)
			_check(
				vehicle.composite_armor_panel_installed
					and is_equal_approx(vehicle.get_max_hp(), base_max_hp + 1500.0)
					and is_equal_approx(vehicle.current_hp, base_max_hp * 0.5 + 1500.0),
				"%s composite armor increases max and current HP by 1500" % label
			)
			vehicle.set_composite_armor_panel_installed(true)
			_check(
				is_equal_approx(vehicle.get_max_hp(), base_max_hp + 1500.0)
					and is_equal_approx(vehicle.current_hp, base_max_hp * 0.5 + 1500.0),
				"%s composite armor bonus does not stack" % label
			)
			var composite_snapshot := vehicle.get_network_state()
			_check(
				bool(composite_snapshot.get("composite_armor_panel_installed", false))
					and is_equal_approx(float(composite_snapshot.get("max_hp", 0.0)), base_max_hp + 1500.0),
				"%s snapshot contains composite armor state and effective HP" % label
			)
			vehicle.set_composite_armor_panel_installed(false)
			_check(
				not vehicle.composite_armor_panel_installed
					and is_equal_approx(vehicle.get_max_hp(), base_max_hp)
					and is_equal_approx(vehicle.current_hp, base_max_hp),
				"%s composite armor removal clamps current HP to the new maximum" % label
			)
			vehicle.apply_network_state({"hp": base_max_hp})
			_check(
				not vehicle.composite_armor_panel_installed
					and is_equal_approx(vehicle.get_max_hp(), base_max_hp),
				"%s legacy snapshots without composite armor default to uninstalled" % label
			)
			vehicle.apply_network_state(composite_snapshot)
			_check(
				vehicle.composite_armor_panel_installed
					and is_equal_approx(vehicle.get_max_hp(), base_max_hp + 1500.0)
					and is_equal_approx(vehicle.current_hp, base_max_hp * 0.5 + 1500.0),
				"%s restores composite armor and HP from a snapshot without double-adding" % label
			)
		else:
			vehicle.set_composite_armor_panel_installed(true)
			_check(
				not vehicle.composite_armor_panel_installed
					and is_equal_approx(vehicle.get_max_hp(), base_max_hp),
				"%s rejects composite armor" % label
			)
		if vehicle is FarmBaseVehicle:
			var farm_vehicle := vehicle as FarmBaseVehicle
			farm_vehicle.set_nitro_boost_installed(true)
			_check(is_equal_approx(farm_vehicle.get_max_forward_speed(), 9.6), "FarmBaseVehicle Nitro and motor stack on forward speed")
			_check(is_equal_approx(farm_vehicle.get_max_reverse_speed(), 9.6), "FarmBaseVehicle Nitro and motor stack on reverse speed")
			_check(is_equal_approx(farm_vehicle.get_acceleration(), 1.8), "FarmBaseVehicle Nitro preserves motor acceleration bonus")
			farm_vehicle.set_nitro_boost_installed(false)
		vehicle.queue_free()
		await get_tree().process_frame

	for special_value: Dictionary in SPECIAL_VEHICLE_SCENES:
		var label := str(special_value["label"])
		var vehicle := (special_value["scene"] as PackedScene).instantiate() as VehicleBase
		_check(vehicle != null, "%s scene instantiates" % label)
		if vehicle == null:
			continue
		vehicle.name = "PerformanceValidation_%s" % label
		vehicle.network_id = "performance_validation_%s" % label.to_lower()
		add_child(vehicle)
		await get_tree().process_frame
		_check(not vehicle.supports_common_service_upgrades(), "%s keeps common upgrades disabled" % label)
		_check(not vehicle.supports_vehicle_service_module("composite_armor_panel"), "%s rejects composite armor" % label)
		vehicle.set_high_performance_motor_installed(true)
		_check(not vehicle.high_performance_motor_installed, "%s rejects the common motor" % label)
		vehicle.queue_free()
		await get_tree().process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[VehiclePerformanceUpgradeValidation] PASS: " + description)
	else:
		failures += 1
		push_error("[VehiclePerformanceUpgradeValidation] FAIL: " + description)


func _finish() -> void:
	if failures == 0:
		print("[VehiclePerformanceUpgradeValidation] PASS all checks")
	else:
		push_error("[VehiclePerformanceUpgradeValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
