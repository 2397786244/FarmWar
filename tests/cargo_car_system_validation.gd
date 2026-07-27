extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "CargoCarValidationRoot"
	get_root().add_child(root)
	var packed := load("res://vehicles/red_cargo_car.tscn") as PackedScene
	_check(packed != null, "red CargoCar scene loads")
	var vehicle: Node = packed.instantiate()
	root.add_child(vehicle)
	await process_frame
	_check(vehicle.get_available_cargo_slot_count() == 12, "full-health CargoCar exposes 12 slots")
	var crate_a := _crate("test_a", "dish", "garden_salad", 50.0, "serving", 10.0)
	var crate_b := _crate("test_b", "dish", "garden_salad", 100.0, "serving", 20.0)
	var crate_c := _crate("test_c", "ingredient", "wheat", 1.0, "kg", 1.0)
	_check(vehicle.try_load_cargo_crate(crate_a, 0) == 0, "loads first partial crate")
	_check(vehicle.try_load_cargo_crate(crate_b, 1) == 1, "loads second partial crate")
	_check(vehicle.try_load_cargo_crate(crate_c, 2) == 2, "loads one-kilogram crate")
	_check(vehicle.get_cargo_crate_count() == 3, "crate count is independent from fill amount")
	_check(is_equal_approx(vehicle.get_cargo_weight_kg(), 31.0), "actual crate weights are summed")
	vehicle.impact("test", 500.0, "blue")
	_check(vehicle.get_available_cargo_slot_count() == 11, "one twelfth HP loss disables one slot")
	_check(vehicle.get_cargo_crate_count() == 2, "one existing crate is destroyed at the HP threshold")
	vehicle.current_hp = vehicle.vehicle_config.max_hp
	_check(vehicle.get_available_cargo_slot_count() == 12, "repair reopens the damaged slot")

	var event_board: Node = root.get_node("/root/EventBoard")
	var emitter: Node = root.get_node("/root/FoodOrderEmitter")
	event_board.reset()
	event_board.add_team_task("red", {
		"task_type": "delivery_order",
		"title": "部分装箱交付测试",
		"delivery_location_id": "test_delivery",
		"delivery_items": [{"dish_id": "garden_salad", "display_name": "田园沙拉", "quantity": 120}],
		"rewards": {"money": 100},
		"active": true,
	})
	var delivery_crates: Array[Dictionary] = [crate_a, crate_b]
	var preview: Dictionary = emitter.build_cargo_delivery_preview(
		"test_delivery", "测试交付点", "red", "cargo_car", 1, "test_vehicle",
		delivery_crates
	)
	_check(int(preview.get("crate_count", 0)) == 2, "delivery can draw content from multiple crates")
	_check(is_equal_approx(float((preview.get("delivered_now", {}) as Dictionary).get("garden_salad", 0.0)), 120.0), "delivery consumes the requested serving amount, not whole crates")
	var authority: Node = root.get_node("/root/GameAuthority")
	authority._apply_cargo_consumption(delivery_crates, preview.get("consumption", []) as Array)
	_check(not delivery_crates[0].is_empty() \
		and (delivery_crates[0].get("stored_item", {}) as Dictionary).is_empty(),
		"fully consumed cargo leaves a reusable empty crate")
	_check(is_equal_approx(float(delivery_crates[0].get("total_weight_kg", 0.0)), 2.0),
		"empty medium crate retains its two-kilogram tare weight")
	_check(is_equal_approx(float(delivery_crates[1].get("content_quantity", 0.0)), 30.0), "partially consumed crate keeps its remaining servings")
	_check(is_equal_approx(float(delivery_crates[1].get("content_weight_kg", 0.0)), 6.0), "partial crate content weight follows its remaining servings")
	_check(is_equal_approx(float(delivery_crates[1].get("total_weight_kg", 0.0)), 8.0), "partial crate total includes its tare weight")

	event_board.reset()
	event_board.add_team_task("red", {
		"task_type": "delivery_order", "title": "矿石交付测试",
		"delivery_location_id": "test_delivery",
		"delivery_items": [{"material_id": "iron", "display_name": "铁矿", "quantity": 6, "unit": "count"}],
		"rewards": {"money": 100}, "active": true,
	})
	var ore_crate := CargoCrateData.create_empty("large", "ore_crate")
	ore_crate["stored_item"] = {"kind": "ingredient", "ingredient_id": "iron", "weight_kg": 10.0}
	ore_crate = CargoCrateData.refresh_totals(ore_crate)
	var ore_crates: Array[Dictionary] = [ore_crate]
	var ore_preview: Dictionary = emitter.build_cargo_delivery_preview(
		"test_delivery", "测试交付点", "red", "cargo_car", 1, "test_vehicle", ore_crates
	)
	_check(is_equal_approx(float((ore_preview.get("delivered_now", {}) as Dictionary).get("iron", 0.0)), 6.0),
		"CargoArea settles material tasks by the count stored inside the crate")
	authority._apply_cargo_consumption(ore_crates, ore_preview.get("consumption", []) as Array)
	_check(int(ore_crates[0].get("content_quantity", 0)) == 4, "CargoArea leaves unconsumed material in the crate")
	_check(is_equal_approx(float(ore_crates[0].get("content_weight_kg", 0.0)), 4.0),
		"CargoArea updates remaining material weight after settlement")

	var empty_small := CargoCrateData.create_empty("small", "empty_small")
	var empty_medium := CargoCrateData.create_empty("medium", "empty_medium")
	var empty_large := CargoCrateData.create_empty("large", "empty_large")
	_check(is_equal_approx(float(empty_small.get("total_weight_kg", 0.0)), 1.0), "small empty crate weighs one kilogram")
	_check(is_equal_approx(float(empty_medium.get("total_weight_kg", 0.0)), 2.0), "medium empty crate weighs two kilograms")
	_check(is_equal_approx(float(empty_large.get("total_weight_kg", 0.0)), 4.0), "large empty crate weighs four kilograms")
	_check(str(empty_small.get("crate_instance_id", "")) != str(empty_medium.get("crate_instance_id", "")), "cargo crates remain unique non-stackable items")

	vehicle.queue_free()
	root.queue_free()
	if failures.is_empty():
		print("[CargoCarValidation] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[CargoCarValidation] " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _crate(id: String, content_kind: String, content_id: String, quantity: float, unit: String, weight: float) -> Dictionary:
	return {
		"kind": "cargo_crate", "crate_instance_id": id,
		"content_kind": content_kind, "content_id": content_id,
		"content_quantity": quantity, "content_unit": unit,
		"total_weight_kg": weight, "display_name": "测试货运箱",
	}
