extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")
const VehicleSalesCatalogScript = preload("res://src/vehicle_sales_catalog.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "TeamGarageDeliveryValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self
	GlobalVar.add_item("red", "money", 100000.0)

	var ground := _add_box_body(
		self,
		"GarageValidationGround",
		Vector3(0.0, -0.5, 0.0),
		Vector3(80.0, 1.0, 80.0),
		1
	)
	_check(ground != null, "delivery validation ground is created")
	await get_tree().physics_frame

	var expected_fees := {
		"atv": [3000, 1000],
		"mini_car": [3300, 1100],
		"van": [3900, 1300],
		"farm_base_vehicle": [4500, 1500],
		"sedan": [4800, 1600],
		"sport_car": [5850, 1950],
	}
	for vehicle_id_value: Variant in expected_fees.keys():
		var vehicle_id := str(vehicle_id_value)
		var product := VehicleSalesCatalogScript.get_product(vehicle_id)
		var quote := GameAuthority.get_vehicle_garage_service_quote({
			"vehicle_id": vehicle_id,
			"scene_path": str(product.get("scene_path", "")),
		})
		var fee_pair: Array = expected_fees[vehicle_id]
		_check(
			int(quote.get("repair_fee", 0)) == int(fee_pair[0])
				and int(quote.get("delivery_fee", 0)) == int(fee_pair[1])
				and int(quote.get("total_fee", 0)) == int(fee_pair[0]) + int(fee_pair[1]),
			"%s uses the authoritative garage service quote" % vehicle_id
		)

	var first_record := _make_destroyed_record("atv", "red", "black")
	var first_garage_id := str(first_record.get("garage_vehicle_id", ""))
	_set_garage_installed_modules(first_garage_id, {"composite_armor_panel": 1})
	var first_quote := GameAuthority.get_vehicle_garage_service_quote(first_record)
	var first_balance_before := GlobalVar.check_team_item_amount("red", "money")
	var first_request := {
		"shop_category": "vehicle_garage",
		"action": "repair_delivery",
		"request_id": "garage-validation-ground-1",
		"garage_vehicle_id": first_garage_id,
	}
	var first_result: Dictionary = GameAuthority.local_shop_transaction(1, first_request)
	var first_live_id := str(first_result.get("spawned_vehicle_id", ""))
	_check(
		bool(first_result.get("ok", false))
			and str(first_result.get("phase", "")) == "completed"
			and bool(first_result.get("charged", false))
			and not bool(first_result.get("refunded", false)),
		"ground repair and delivery completes authoritatively"
	)
	_check(
		is_equal_approx(
			GlobalVar.check_team_item_amount("red", "money"),
			first_balance_before - float(first_quote.get("total_fee", 0))
		),
		"ground repair charges the configured repair plus delivery fee once"
	)
	var first_active_record := GameAuthority.get_team_garage_record(first_garage_id)
	_check(
		str(first_active_record.get("status", "")) == "active"
			and str(first_active_record.get("live_vehicle_id", "")) == first_live_id
			and not bool(first_active_record.get("delivery_pending", false)),
		"successful delivery commits the garage record as active"
	)
	var balance_after_first := GlobalVar.check_team_item_amount("red", "money")
	var cached_first_result: Dictionary = GameAuthority.local_shop_transaction(1, first_request)
	_check(
		str(cached_first_result.get("phase", "")) == "completed"
			and str(cached_first_result.get("spawned_vehicle_id", "")) == first_live_id
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), balance_after_first),
		"same repair request id is idempotent"
	)

	var first_vehicle := GameAuthority.call("_find_vehicle", first_live_id) as VehicleBase
	_check(
		first_vehicle != null
			and first_vehicle.composite_armor_panel_installed
			and is_equal_approx(first_vehicle.get_max_hp(), 2000.0),
		"garage delivery restores the composite armor state and effective HP"
	)
	if first_vehicle != null:
		first_vehicle.impact("garage_validation", first_vehicle.current_hp + 1.0, "")
	await get_tree().process_frame
	var destroyed_after_live_loss := GameAuthority.get_team_garage_record(first_garage_id)
	_check(
		str(destroyed_after_live_loss.get("status", "")) == "destroyed"
			and str(destroyed_after_live_loss.get("live_vehicle_id", "")) == ""
			and not bool(destroyed_after_live_loss.get("delivery_pending", false)),
		"destroying a delivered vehicle updates the garage record"
	)

	GameAuthority.register_or_update_player(2, {
		"display_name": "GarageValidationTeammate",
		"team": "red",
		"position": Vector3.ZERO,
	})
	var blocker := _add_box_body(
		self,
		"GarageValidationDynamicBlocker",
		Vector3(0.0, 0.75, 0.0),
		Vector3(10.0, 2.0, 10.0),
		8
	)
	await get_tree().physics_frame
	var busy_request := {
		"shop_category": "vehicle_garage",
		"action": "repair_delivery",
		"request_id": "garage-validation-airdrop-1",
		"garage_vehicle_id": first_garage_id,
	}
	var busy_balance_before := GlobalVar.check_team_item_amount("red", "money")
	var busy_result: Dictionary = GameAuthority.local_shop_transaction(1, busy_request)
	_check(
		bool(busy_result.get("ok", false))
			and str(busy_result.get("phase", "")) == "pending"
			and bool(busy_result.get("charged", false)),
		"dynamic delivery blocker enters the pending airdrop phase"
	)
	var busy_live_id := str(busy_result.get("spawned_vehicle_id", ""))
	var competing_result: Dictionary = GameAuthority.local_shop_transaction(2, {
		"shop_category": "vehicle_garage",
		"action": "repair_delivery",
		"request_id": "garage-validation-competing-1",
		"garage_vehicle_id": first_garage_id,
	})
	_check(
		str(competing_result.get("reason", "")) == "garage_vehicle_busy"
			and not bool(competing_result.get("charged", false))
			and is_equal_approx(
				GlobalVar.check_team_item_amount("red", "money"),
				busy_balance_before - float(first_quote.get("total_fee", 0))
			),
		"a teammate cannot charge or acquire a garage vehicle already being delivered"
	)
	GameAuthority.call("_on_vehicle_spawn_drop_finished", false, busy_live_id)
	var failed_busy_result: Dictionary = GameAuthority.call(
		"_get_cached_shop_transaction", 1, str(busy_request.get("request_id", ""))
	)
	_check(
		str(failed_busy_result.get("phase", "")) == "failed"
			and bool(failed_busy_result.get("refunded", false))
			and is_equal_approx(
				GlobalVar.check_team_item_amount("red", "money"), busy_balance_before
			),
		"failed airdrop repair refunds exactly once"
	)
	var failed_record := GameAuthority.get_team_garage_record(first_garage_id)
	_check(
		str(failed_record.get("status", "")) == "destroyed"
			and not bool(failed_record.get("delivery_pending", false)),
		"failed delivery leaves the garage record repairable"
	)
	if blocker != null:
		blocker.queue_free()
	await get_tree().process_frame
	var retry_result: Dictionary = GameAuthority.local_shop_transaction(2, {
		"shop_category": "vehicle_garage",
		"action": "repair_delivery",
		"request_id": "garage-validation-retry-after-failure-1",
		"garage_vehicle_id": first_garage_id,
	})
	_check(
		bool(retry_result.get("ok", false))
			and str(retry_result.get("phase", "")) == "completed",
		"another teammate can retry after the first delivery is refunded"
	)

	var backpack := load("res://ui/player_backpack.tscn").instantiate() as PlayerBackpack
	_check(backpack != null, "team garage backpack UI scene instantiates")
	if backpack != null:
		add_child(backpack)
		await get_tree().process_frame
		var tabs := backpack.get_node("BackpackWindow/Margin/VBox/InventoryTabs") as TabContainer
		_check(
			tabs != null
				and tabs.get_tab_title(0) == "玩家背包"
				and tabs.get_tab_title(1) == "载具"
				and tabs.get_tab_title(2) == "队伍物资",
			"vehicle garage is the second inventory tab"
		)
		var presentation_player := PLAYER_SCENE.instantiate() as GamePlayer
		if presentation_player != null:
			presentation_player.authority_peer_id = 1
			presentation_player.team = "red"
			add_child(presentation_player)
			await get_tree().process_frame
			backpack.bind_player(presentation_player)
			backpack.open_team_storage()
			_check(
				backpack.is_open() and tabs.current_tab == 1,
				"T team inventory entry opens the vehicle tab"
			)
			backpack.open_team_materials()
			_check(tabs.current_tab == 2, "team materials remain the third tab")
			presentation_player.queue_free()
		backpack.queue_free()

	_finish()


func _make_destroyed_record(vehicle_id: String, body_color_id: String, wheel_color_id: String) -> Dictionary:
	var product := VehicleSalesCatalogScript.get_product(vehicle_id)
	var record: Dictionary = GameAuthority.call(
		"_new_team_garage_record", "red", product, body_color_id, wheel_color_id
	)
	var garage_vehicle_id := str(record.get("garage_vehicle_id", ""))
	GameAuthority.call("_commit_team_garage_vehicle", {
		"team": "red",
		"garage_record": record,
	}, "garage_validation_seed_%d" % int(record.get("garage_sequence", 0)))
	GameAuthority.vehicle_states["garage_validation_seed_%d" % int(record.get("garage_sequence", 0))] = {
		"garage_vehicle_id": garage_vehicle_id,
	}
	GameAuthority.call(
		"_mark_team_garage_vehicle_destroyed",
		"garage_validation_seed_%d" % int(record.get("garage_sequence", 0)),
		null
	)
	return GameAuthority.get_team_garage_record(garage_vehicle_id)


func _set_garage_installed_modules(garage_vehicle_id: String, installed_modules: Dictionary) -> void:
	var records: Array = GameAuthority.team_garage_states.get("red", [])
	for index in range(records.size()):
		if not records[index] is Dictionary:
			continue
		var record := (records[index] as Dictionary).duplicate(true)
		if str(record.get("garage_vehicle_id", "")) != garage_vehicle_id:
			continue
		record["installed_modules"] = installed_modules.duplicate(true)
		records[index] = record
		GameAuthority.team_garage_states["red"] = records
		return


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[TeamGarageDeliveryValidation] PASS " + label)
	else:
		failures += 1
		push_error("[TeamGarageDeliveryValidation] FAIL " + label)


func _add_box_body(
	parent: Node,
	body_name: String,
	position: Vector3,
	size: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = position
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


func _finish() -> void:
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
