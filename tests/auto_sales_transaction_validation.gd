extends Node3D

const VehicleSalesCatalogScript = preload("res://src/vehicle_sales_catalog.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "AutoSalesTransactionValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self

	var shop := AutoSales.new()
	shop.name = "AutoSalesValidationShop"
	add_child(shop)
	await get_tree().process_frame

	GlobalVar.add_item("red", "money", 50000.0)
	var request := {
		"action": "vehicle_purchase",
		"shop_category": "vehicle_sales",
		"request_id": "autosales-validation-no-spawn-1",
		"vehicle_id": "atv",
		"body_color_id": "red",
		"wheel_color_id": "black",
		"shop_path": str(shop.get_path()),
		"shop_position": shop.get_interaction_position(),
	}
	var balance_before := GlobalVar.check_team_item_amount("red", "money")
	var no_spawn_result := GameAuthority.local_shop_transaction(1, request)
	_check(
		str(no_spawn_result.get("reason", "")) == "no_team_spawn_point"
			and not bool(no_spawn_result.get("charged", false)),
		"invalid team spawn returns before charging"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), balance_before),
		"pre-charge placement failure preserves the team balance"
	)
	var retry_result := GameAuthority.local_shop_transaction(1, request)
	_check(
		str(retry_result.get("request_id", "")) == str(no_spawn_result.get("request_id", ""))
			and str(retry_result.get("reason", "")) == str(no_spawn_result.get("reason", "")),
		"same request id returns the cached validation result"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), balance_before),
		"cached retry does not charge a second time"
	)

	var ground := _add_box_body(
		self,
		"AutoSalesValidationGround",
		Vector3(4.0, -0.5, 0.0),
		Vector3(40.0, 1.0, 40.0),
		1
	)
	var spawn_point := TeamSpawnPoint.new()
	spawn_point.name = "AutoSalesValidationRedSpawn"
	spawn_point.team = "red"
	spawn_point.spawn_point_id = "autosales_validation_red"
	spawn_point.spawn_radius = 0.5
	spawn_point.position = Vector3(4.0, 0.0, 0.0)
	add_child(spawn_point)
	_check(ground != null, "validating ground is created")
	await get_tree().physics_frame

	var ground_request := request.duplicate(true)
	ground_request["request_id"] = "autosales-validation-ground-1"
	var ground_balance_before := GlobalVar.check_team_item_amount("red", "money")
	var ground_result: Dictionary = GameAuthority.local_shop_transaction(1, ground_request)
	_check(
		bool(ground_result.get("ok", false))
			and str(ground_result.get("phase", "")) == "completed"
			and bool(ground_result.get("charged", false))
			and not bool(ground_result.get("refunded", false)),
		"valid ground purchase completes after the authoritative charge"
	)
	_check(
		GlobalVar.check_team_item_amount("red", "money") < ground_balance_before,
		"successful ground purchase charges the team once"
	)
	var ground_vehicle_id := str(ground_result.get("spawned_vehicle_id", ""))
	var ground_garage_id := str(ground_result.get("garage_vehicle_id", ""))
	var ground_vehicle := GameAuthority.call("_find_vehicle", ground_vehicle_id) as VehicleBase
	var ground_record := GameAuthority.get_team_garage_record(ground_garage_id)
	_check(ground_vehicle != null, "successful ground purchase creates a vehicle node")
	_check(
		str(ground_record.get("status", "")) == "active"
			and str(ground_record.get("live_vehicle_id", "")) == ground_vehicle_id,
		"successful ground purchase creates one active garage record"
	)
	var ground_retry_balance := GlobalVar.check_team_item_amount("red", "money")
	var ground_retry_result: Dictionary = GameAuthority.local_shop_transaction(1, ground_request)
	_check(
		str(ground_retry_result.get("phase", "")) == "completed"
			and str(ground_retry_result.get("spawned_vehicle_id", "")) == ground_vehicle_id
			and is_equal_approx(
				GlobalVar.check_team_item_amount("red", "money"), ground_retry_balance
			),
		"same successful request id does not charge or spawn a second vehicle"
	)
	if ground_vehicle != null:
		ground_vehicle.queue_free()
	GameAuthority.vehicle_states.erase(ground_vehicle_id)
	await get_tree().process_frame

	# A dynamic character-layer blocker forces the existing placement resolver to
	# choose the airdrop path.  Finalization is driven through the same callback
	# used by VehicleBase so both success and failure are covered here.
	var dynamic_blocker := _add_box_body(
		self,
		"AutoSalesValidationDynamicBlocker",
		Vector3(4.0, 0.75, 0.0),
		Vector3(10.0, 2.0, 10.0),
		8
	)
	GlobalVar.add_item("red", "money", 50000.0)
	await get_tree().physics_frame
	var drop_success_request := request.duplicate(true)
	drop_success_request["request_id"] = "autosales-validation-airdrop-success-1"
	var drop_success_result: Dictionary = GameAuthority.local_shop_transaction(1, drop_success_request)
	_check(
		str(drop_success_result.get("phase", "")) == "pending"
			and bool(drop_success_result.get("charged", false)),
		"airdrop purchase stays pending after charging"
	)
	var drop_success_id := str(drop_success_result.get("spawned_vehicle_id", ""))
	GameAuthority.call("_on_vehicle_spawn_drop_finished", true, drop_success_id)
	var drop_success_final: Dictionary = GameAuthority.call(
		"_get_cached_shop_transaction", 1, str(drop_success_request.get("request_id", ""))
	)
	_check(
		bool(drop_success_final.get("ok", false))
			and str(drop_success_final.get("phase", "")) == "completed"
			and not bool(drop_success_final.get("refunded", false)),
		"successful airdrop completes exactly once"
	)
	var drop_success_record := GameAuthority.get_team_garage_record(
		str(drop_success_final.get("garage_vehicle_id", ""))
	)
	_check(
		str(drop_success_record.get("status", "")) == "active"
			and str(drop_success_record.get("live_vehicle_id", "")) == drop_success_id,
		"successful airdrop creates an active garage record"
	)
	var drop_success_vehicle := GameAuthority.call("_find_vehicle", drop_success_id) as VehicleBase
	if drop_success_vehicle != null:
		drop_success_vehicle.queue_free()
	GameAuthority.vehicle_states.erase(drop_success_id)
	await get_tree().process_frame

	var drop_failure_request := request.duplicate(true)
	drop_failure_request["request_id"] = "autosales-validation-airdrop-failure-1"
	var drop_failure_balance_before := GlobalVar.check_team_item_amount("red", "money")
	var drop_failure_result: Dictionary = GameAuthority.local_shop_transaction(1, drop_failure_request)
	_check(
		str(drop_failure_result.get("phase", "")) == "pending"
			and bool(drop_failure_result.get("charged", false)),
		"failed airdrop starts as a charged pending transaction"
	)
	var drop_failure_id := str(drop_failure_result.get("spawned_vehicle_id", ""))
	var drop_failure_garage_id := str(drop_failure_result.get("garage_vehicle_id", ""))
	var drop_failure_vehicle := GameAuthority.call("_find_vehicle", drop_failure_id) as VehicleBase
	if drop_failure_vehicle != null:
		drop_failure_vehicle.queue_free()
	await get_tree().process_frame
	_check(
		GameAuthority.vehicle_states.has(drop_failure_id),
		"missing airdrop node retains authoritative purchase metadata"
	)
	GameAuthority.call("_on_vehicle_spawn_drop_finished", false, drop_failure_id)
	var drop_failure_final: Dictionary = GameAuthority.call(
		"_get_cached_shop_transaction", 1, str(drop_failure_request.get("request_id", ""))
	)
	_check(
		str(drop_failure_final.get("phase", "")) == "failed"
			and bool(drop_failure_final.get("charged", false))
			and bool(drop_failure_final.get("refunded", false)),
		"failed airdrop returns a final refunded result"
	)
	_check(
		is_equal_approx(
			GlobalVar.check_team_item_amount("red", "money"),
			drop_failure_balance_before
		),
		"failed airdrop refunds the charge exactly once"
	)
	_check(
		GameAuthority.get_team_garage_record(drop_failure_garage_id).is_empty()
			and not GameAuthority.vehicle_states.has(drop_failure_id),
		"failed airdrop leaves no active garage record or vehicle state"
	)
	# Calling the callback again must not issue another refund or result mutation.
	GameAuthority.call("_on_vehicle_spawn_drop_finished", false, drop_failure_id)
	_check(
		is_equal_approx(
			GlobalVar.check_team_item_amount("red", "money"),
			drop_failure_balance_before
		),
		"repeated failed-drop callback cannot refund twice"
	)
	if dynamic_blocker != null:
		dynamic_blocker.queue_free()
	await get_tree().process_frame

	var refund_before := GlobalVar.check_team_item_amount("red", "money")
	var refund_metadata := {"team": "red", "price": 321, "refunded": false}
	var first_refund: Dictionary = GameAuthority.call("_refund_vehicle_purchase", refund_metadata)
	var second_refund: Dictionary = GameAuthority.call("_refund_vehicle_purchase", refund_metadata)
	_check(bool(first_refund.get("refunded", false)), "charged purchase can be refunded")
	_check(bool(second_refund.get("refunded", false)), "second refund call is idempotently acknowledged")
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), refund_before + 321.0),
		"refund amount is credited exactly once"
	)

	var product := VehicleSalesCatalogScript.get_product("atv")
	var garage_record: Dictionary = GameAuthority.call(
		"_new_team_garage_record", "red", product, "red", "black"
	)
	var garage_id := str(garage_record.get("garage_vehicle_id", ""))
	var garage_metadata := {
		"team": "red",
		"garage_record": garage_record,
	}
	var committed_id := str(GameAuthority.call(
		"_commit_team_garage_vehicle", garage_metadata, "validation_vehicle"
	))
	_check(committed_id == garage_id and garage_id.begins_with("garage_red_atv_red_black_"), "garage id encodes team, vehicle and colors")
	var active_record := GameAuthority.get_team_garage_record(garage_id)
	_check(
		str(active_record.get("status", "")) == "active"
			and str(active_record.get("live_vehicle_id", "")) == "validation_vehicle"
			and str(active_record.get("body_color_id", "")) == "red"
			and str(active_record.get("wheel_color_id", "")) == "black",
		"active garage record keeps stable customization ids"
	)
	var saved_garages := GameAuthority.get_persistent_team_garage_states()
	GameAuthority.apply_persistent_team_garage_states(saved_garages)
	var restored_record := GameAuthority.get_team_garage_record(garage_id)
	_check(
		str(restored_record.get("body_color_id", "")) == "red"
			and str(restored_record.get("wheel_color_id", "")) == "black",
		"garage colors survive authority state restore"
	)
	GameAuthority.vehicle_states["validation_vehicle"] = {"garage_vehicle_id": garage_id}
	var marked_destroyed := bool(GameAuthority.call(
		"_mark_team_garage_vehicle_destroyed", "validation_vehicle", null
	))
	var marked_again := bool(GameAuthority.call(
		"_mark_team_garage_vehicle_destroyed", "validation_vehicle", null
	))
	var destroyed_record := GameAuthority.get_team_garage_record(garage_id)
	_check(marked_destroyed and not marked_again, "destroyed garage records are marked only once")
	_check(
		str(destroyed_record.get("status", "")) == "destroyed"
			and str(destroyed_record.get("live_vehicle_id", "")) == "",
		"destroyed garage record remains stored without automatic respawn"
	)

	var page := AutoSalesPage.new()
	page.name = "AutoSalesPageValidation"
	add_child(page)
	await get_tree().process_frame
	page.set("selected_vehicle_id", "atv")
	page.call("_refresh_selection")
	page.set("purchase_pending", true)
	page.set("_active_purchase_request_id", "autosales-ui-validation-1")
	page.set("_active_purchase_request", {"request_id": "autosales-ui-validation-1", "vehicle_id": "atv"})
	page.call("_process", 8.1)
	var purchase_button := page.get("_purchase_button") as Button
	_check(not page.purchase_pending and bool(page.get("_purchase_timed_out")), "UI request timeout exits pending state")
	_check(purchase_button != null and not purchase_button.disabled, "UI purchase button recovers after timeout")
	page.set("purchase_pending", true)
	page.set("_purchase_timed_out", false)
	page.call("apply_transaction_result", {
		"ok": true,
		"phase": "completed",
		"shop_category": "vehicle_sales",
		"request_id": "autosales-ui-validation-old",
	})
	_check(page.purchase_pending, "late result for another request is ignored")
	page.call("apply_transaction_result", {
		"ok": false,
		"phase": "failed",
		"reason": "request_not_sent",
		"shop_category": "vehicle_sales",
		"request_id": "autosales-ui-validation-1",
	})
	_check(not page.purchase_pending, "matching final result closes the UI request")

	var safe_color: Variant = CooperativeWorldStorage.call("_json_safe", Color("112233"))
	_check(safe_color is Array and (safe_color as Array).size() == 4, "persistent vehicle colors have JSON-safe encoding")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[AutoSalesTransactionValidation] PASS " + label)
	else:
		failures += 1
		push_error("[AutoSalesTransactionValidation] FAIL " + label)


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
