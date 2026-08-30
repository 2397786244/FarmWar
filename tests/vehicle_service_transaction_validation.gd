extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const MINI_VEHICLE_SCENE := preload("res://vehicles/mini_car.tscn")
const CARGO_VEHICLE_SCENE := preload("res://vehicles/cargo_car.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")
const TERMINAL_SCENE := preload("res://facilities/interior/vehicle_service/repair_terminal.tscn")

var failures := 0
var _service_events: Array[Dictionary] = []
var _interaction_player: GamePlayer


func _ready() -> void:
	GameAuthority.reliable_world_event_ready.connect(_on_authority_event)
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "VehicleServiceValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self
	GlobalVar.add_item("red", "money", 100000.0)

	var ground := _add_box_body(
		"VehicleServiceValidationGround",
		Vector3(0.0, -0.5, 0.0),
		Vector3(80.0, 1.0, 80.0),
		1
	)
	_check(ground != null, "service validation ground is available")

	var terminal := TERMINAL_SCENE.instantiate() as VehicleServiceTerminal
	_check(terminal != null, "repair terminal scene instantiates")
	if terminal == null:
		_finish()
		return
	terminal.name = "VehicleServiceValidationTerminal"
	# Match the editor placement contract: facilities sit at terrain + 0.52 m,
	# while vehicle roots sit near terrain + 0.5 m. This makes Area3D overlap
	# assertions exercise the real bay geometry instead of a hand-forced lock.
	terminal.position.y = 0.52
	add_child(terminal)

	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene instantiates for service")
	if vehicle == null:
		_finish()
		return
	vehicle.name = "VehicleServiceValidationFarm"
	vehicle.network_id = "vehicle_service_validation_farm"
	vehicle.owner_team = "red"
	vehicle.position = Vector3(0.0, 0.55, 2.0)
	add_child(vehicle)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(terminal.collision_layer == 128 and terminal.collision_mask == 0, "terminal collision contract")
	var player_area := terminal.get_node_or_null("PlayerInteract") as Area3D
	var vehicle_area := terminal.get_node_or_null("VehicleInteract") as Area3D
	_check(player_area != null and player_area.collision_layer == 512 and player_area.collision_mask == 8, "player interaction collision contract")
	_check(vehicle_area != null and vehicle_area.collision_layer == 512 and vehicle_area.collision_mask == (8192 | 8), "vehicle interaction detects vehicles and players")

	terminal.call("_on_vehicle_body_entered", vehicle)
	_check(terminal.active_vehicle_id == vehicle.get_vehicle_id(), "first vehicle acquires the vehicle-area lock")

	_interaction_player = PLAYER_SCENE.instantiate() as GamePlayer
	_check(_interaction_player != null, "player scene instantiates for terminal interaction")
	if _interaction_player != null:
		_interaction_player.authority_peer_id = 99
		_interaction_player.team = "red"
		add_child(_interaction_player)
		await get_tree().process_frame
		_interaction_player.set_process(false)
		_interaction_player.set_physics_process(false)
		_interaction_player.set_process_input(false)
		_interaction_player.collision_layer = GamePlayer.PLAYER_COLLISION_LAYER
		_interaction_player.collision_mask = GamePlayer.PLAYER_COLLISION_MASK
		var vehicle_area_shape := vehicle_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var player_area_shape := player_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		_check(vehicle_area_shape != null and player_area_shape != null, "terminal interaction shapes are available")
		if vehicle_area_shape != null and player_area_shape != null:
			_interaction_player.global_position = vehicle_area_shape.global_position + Vector3(0.0, 0.1, 0.0)
			for _frame in range(3):
				await get_tree().physics_frame
			var vehicle_area_target := _interaction_player._get_best_interaction_target()
			_check(
				str(vehicle_area_target.get("kind", "")) != "vehicle_service_vehicle_area"
					and str(vehicle_area_target.get("hint", "")) != "把载具开到这个区域中",
				"player entering an occupied VehicleInteract does not receive the delivery prompt"
			)
			_interaction_player.global_position = player_area_shape.global_position + Vector3(0.0, 0.1, 0.0)
			for _frame in range(3):
				await get_tree().physics_frame
			var player_area_target := _interaction_player._get_best_interaction_target()
			_check(
				str(player_area_target.get("kind", "")) == "vehicle_service_terminal"
					and str(player_area_target.get("hint", "")) == "按「E」打开升级和维修终端",
				"player entering PlayerInteract receives the terminal E prompt"
			)

		var service_page := _interaction_player.get_node_or_null("SubViewport/VehicleServicePage") as VehicleServicePage
		_check(service_page != null, "vehicle service page is available for color selection")
		if service_page != null:
			service_page.set("terminal", terminal)
			service_page.set("player", _interaction_player)
			service_page.set("vehicle", vehicle)
			service_page.set("vehicle_id", vehicle.get_vehicle_id())
			service_page.set("terminal_id", terminal.get_terminal_id())
			service_page.call("_update_ui", true)
			var body_option := service_page.get("_body_option") as OptionButton
			var wheel_option := service_page.get("_wheel_option") as OptionButton
			_check(body_option != null and wheel_option != null, "vehicle color selectors are available")
			if body_option != null and wheel_option != null:
				var body_index := _color_option_index(body_option, "dark_gray")
				var wheel_index := _color_option_index(wheel_option, "silver_gray")
				_check(body_index >= 0 and wheel_index >= 0, "vehicle color selectors contain catalog colors")
				if body_index >= 0 and wheel_index >= 0:
					service_page.call("_on_color_option_selected", body_index, "body")
					service_page.call("_on_color_option_selected", wheel_index, "wheel")
					service_page.call("_update_ui", false)
					_check(body_option.selected == body_index, "body color selection survives a periodic UI refresh")
					_check(wheel_option.selected == wheel_index, "wheel color selection survives a periodic UI refresh")

			var terminal_camera := terminal.get_service_camera()
			var player_camera := _interaction_player.camera as Camera3D
			_check(terminal_camera != null and not terminal_camera.current, "repair terminal camera is inactive before acquiring the user lock")
			_interaction_player.authority_peer_id = GameAuthority.LOCAL_PLAYER_ID
			if player_camera != null:
				player_camera.make_current()
			service_page.open_for(terminal, _interaction_player)
			await get_tree().process_frame
			_check(service_page.is_open() and terminal.active_user_peer_id == GameAuthority.LOCAL_PLAYER_ID, "opening the service page acquires the authoritative user lock")
			var position_before_stale_service_state := vehicle.global_position
			service_page.apply_vehicle_state({
				"vehicle_id": vehicle.get_vehicle_id(),
				"position": Vector3(-80.0, 0.5, -35.0),
				"yaw": PI,
			})
			_check(
				vehicle.global_position == position_before_stale_service_state,
				"local service UI cannot replay a stale team-spawn transform onto the authority vehicle"
			)
			_check(terminal_camera != null and terminal_camera.current and _interaction_player.is_vehicle_service_view_active(), "successful acquire switches to the repair terminal camera")
			_interaction_player.call("_ensure_local_camera_ownership")
			_check(terminal_camera != null and terminal_camera.current, "ordinary player camera recovery does not steal the service view")
			terminal.active_user_last_activity_msec = Time.get_ticks_msec() - 12000
			var heartbeat_activity_before := terminal.active_user_last_activity_msec
			service_page.set("_pending_request", {"action": "repair_hp"})
			service_page.set("_heartbeat_elapsed", VehicleServicePage.HEARTBEAT_INTERVAL_SECONDS)
			service_page.call("_process", 0.0)
			_check(
				terminal.active_user_last_activity_msec > heartbeat_activity_before and service_page.is_open(),
				"service heartbeat continues while a mutation request is pending"
			)
			service_page.call("_clear_pending_request")
			var service_window := service_page.get("_window") as PanelContainer
			var viewport_size := get_viewport().get_visible_rect().size
			_check(
				service_window != null and service_window.position.x >= 23.0 and service_window.size.x <= 681.0,
				"vehicle service UI uses the responsive left-side panel (position=%s size=%s minimum=%s)" % [
					service_window.position if service_window != null else Vector2.ZERO,
					service_window.size if service_window != null else Vector2.ZERO,
					service_window.get_combined_minimum_size() if service_window != null else Vector2.ZERO,
				]
			)
			var service_tabs := service_page.get("_service_tabs") as TabContainer
			var upgrade_scroll := service_page.get("_upgrade_scroll") as ScrollContainer
			var upgrade_list := service_page.get("_upgrade_list") as VBoxContainer
			if service_tabs != null:
				service_tabs.current_tab = 1
				await get_tree().process_frame
				await get_tree().process_frame
			_check(
				service_window != null and service_tabs != null
					and service_tabs.size.x >= service_window.size.x - 80.0,
				"upgrade tab fills the service panel width (panel=%s tabs=%s)" % [
					service_window.size if service_window != null else Vector2.ZERO,
					service_tabs.size if service_tabs != null else Vector2.ZERO,
				]
			)
			_check(
				service_tabs != null and upgrade_scroll != null and upgrade_list != null
					and upgrade_scroll.size.x >= service_tabs.size.x - 40.0
					and upgrade_list.size.x >= upgrade_scroll.size.x - 24.0,
				"upgrade scrolling content remains readable at full width (tabs=%s scroll=%s list=%s)" % [
					service_tabs.size if service_tabs != null else Vector2.ZERO,
					upgrade_scroll.size if upgrade_scroll != null else Vector2.ZERO,
					upgrade_list.size if upgrade_list != null else Vector2.ZERO,
				]
			)
			var motor_row_visible := false
			var farm_composite_row_visible := false
			if upgrade_list != null:
				for row: Node in upgrade_list.get_children():
					var row_label := row.get_child(0) as Label if row.get_child_count() > 0 else null
					if row_label != null and row_label.text.contains("高性能电机"):
						motor_row_visible = true
					if row_label != null and row_label.text.contains("复合装甲板"):
						farm_composite_row_visible = true
			_check(motor_row_visible, "FarmBaseVehicle upgrade tab renders the high-performance motor")
			_check(not farm_composite_row_visible, "FarmBaseVehicle upgrade tab hides composite armor")
			if service_tabs != null:
				service_tabs.current_tab = 0
				await get_tree().process_frame
			_check(_camera_frames_vehicle_on_right(terminal, terminal_camera, vehicle, viewport_size), "FarmBaseVehicle is fully framed on the right side")

			for framing_definition: Dictionary in [
				{"scene": MINI_VEHICLE_SCENE, "label": "small vehicle"},
				{"scene": CARGO_VEHICLE_SCENE, "label": "regular vehicle"},
			]:
				var framing_vehicle := (framing_definition.get("scene") as PackedScene).instantiate() as VehicleBase
				framing_vehicle.network_id = "vehicle_service_frame_%s" % str(framing_definition.get("label", "vehicle")).replace(" ", "_")
				framing_vehicle.owner_team = "red"
				framing_vehicle.position = vehicle.position
				add_child(framing_vehicle)
				await get_tree().process_frame
				terminal.refresh_service_camera(framing_vehicle, viewport_size)
				_check(
					_camera_frames_vehicle_on_right(terminal, terminal_camera, framing_vehicle, viewport_size),
					"%s is fully framed on the right side" % str(framing_definition.get("label", "vehicle"))
				)
				framing_vehicle.queue_free()
				await get_tree().process_frame
			terminal.refresh_service_camera(vehicle, viewport_size)
			vehicle.current_hp = vehicle.get_max_hp() * 0.5
			service_page.call("_request_action", "repair_hp", {})
			_check(find_child("VehicleServiceEffect", true, false) != null, "successful service action creates the local presentation effect")
			service_page.close()
			_check(not terminal_camera.current and player_camera != null and player_camera.current, "closing the service page disables the terminal camera and restores the player camera")
			_check(terminal.active_user_peer_id == 0, "closing the service page releases the user lock")

			service_page.open_for(terminal, _interaction_player)
			await get_tree().process_frame
			_check(terminal.active_user_peer_id == GameAuthority.LOCAL_PLAYER_ID and terminal_camera.current, "service view can be reacquired before player death")
			_interaction_player.apply_respawn_state(10.0)
			_check(not service_page.is_open() and not terminal_camera.current, "player death closes the service view and disables its camera")
			_check(terminal.active_user_peer_id == 0, "player death releases the repair terminal user lock")
			_check(is_instance_valid(_interaction_player.death_camera) and _interaction_player.death_camera.current, "death camera takes priority over the repair terminal camera")
			_interaction_player.apply_respawn_state(0.0, player_area_shape.global_position + Vector3(0.0, 0.1, 0.0))
			await get_tree().process_frame

			service_page.open_for(terminal, _interaction_player)
			await get_tree().process_frame
			_check(terminal.active_user_peer_id == GameAuthority.LOCAL_PLAYER_ID and terminal_camera.current, "service view can be reacquired before vehicle destruction")
			terminal.on_vehicle_destroyed(vehicle.get_vehicle_id())
			service_page.apply_terminal_state(terminal.get_network_state())
			_check(not service_page.is_open() and not terminal_camera.current, "vehicle destruction closes the service view and disables its camera")
			_check(terminal.active_vehicle_id.is_empty() and terminal.active_user_peer_id == 0, "vehicle destruction releases both repair terminal locks")
			_check(player_camera != null and player_camera.current, "player camera is restored after the service vehicle is destroyed")
			terminal.call("_on_vehicle_body_entered", vehicle)
			_check(terminal.active_vehicle_id == vehicle.get_vehicle_id(), "service vehicle can be detected again after camera lifecycle validation")
			# The remaining transaction tests intentionally drive peer 1 directly
			# without syncing from this presentation-only player instance.
			_interaction_player.authority_peer_id = 99

	GameAuthority.register_or_update_player(2, {
		"display_name": "VehicleServiceValidationTeammate",
		"team": "red",
		"position": Vector3.ZERO,
	})
	var transaction_context := {
		"shop_category": "vehicle_service",
		"terminal_id": terminal.get_terminal_id(),
		"terminal_path": str(terminal.get_path()),
		"vehicle_id": vehicle.get_vehicle_id(),
	}

	var acquire_one := transaction_context.duplicate(true)
	acquire_one["action"] = "acquire"
	acquire_one["request_id"] = "service-validation-acquire-1"
	var acquire_result: Dictionary = GameAuthority.local_shop_transaction(1, acquire_one)
	_check(bool(acquire_result.get("ok", false)) and terminal.active_user_peer_id == 1, "first player acquires the player-operation lock")
	var acquire_vehicle_state: Dictionary = acquire_result.get("vehicle_state", {})
	_check(
		not acquire_vehicle_state.has("position")
			and not acquire_vehicle_state.has("yaw")
			and not acquire_vehicle_state.has("speed")
			and not acquire_vehicle_state.has("steering"),
		"vehicle-service responses never carry movement state"
	)

	var acquire_two := transaction_context.duplicate(true)
	acquire_two["action"] = "acquire"
	acquire_two["request_id"] = "service-validation-acquire-2"
	var busy_result: Dictionary = GameAuthority.local_shop_transaction(2, acquire_two)
	_check(str(busy_result.get("reason", "")) == "service_in_use", "second player cannot take an active operation lock")

	vehicle.current_hp = vehicle.get_max_hp() * 0.5
	var quote := GameAuthority.get_vehicle_service_quote(vehicle, 1)
	var expected_repair_fee := ceili(float(quote.get("repair_base_fee", 0)) * 0.5)
	var repair_balance := GlobalVar.check_team_item_amount("red", "money")
	var repair_request := transaction_context.duplicate(true)
	repair_request["action"] = "repair_hp"
	repair_request["request_id"] = "service-validation-repair-1"
	var repair_result: Dictionary = GameAuthority.local_shop_transaction(1, repair_request)
	_check(bool(repair_result.get("ok", false)) and vehicle.current_hp >= vehicle.get_max_hp() - 0.001, "HP repair restores the vehicle to full health")
	_check(int(repair_result.get("service_fee", -1)) == expected_repair_fee, "HP repair uses the missing-health ratio")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), repair_balance - expected_repair_fee), "HP repair charges only the server-calculated fee")

	var color_balance := GlobalVar.check_team_item_amount("red", "money")
	var body_color_request := transaction_context.duplicate(true)
	body_color_request["action"] = "change_color"
	body_color_request["request_id"] = "service-validation-body-color-1"
	body_color_request["color_slot"] = "body"
	body_color_request["color_id"] = "dark_gray"
	var body_color_result: Dictionary = GameAuthority.local_shop_transaction(1, body_color_request)
	_check(bool(body_color_result.get("ok", false)) and vehicle.get_body_color_id() == "dark_gray", "dark-gray body color is applied through the service")

	var wheel_color_request := transaction_context.duplicate(true)
	wheel_color_request["action"] = "change_color"
	wheel_color_request["request_id"] = "service-validation-wheel-color-1"
	wheel_color_request["color_slot"] = "wheel"
	wheel_color_request["color_id"] = "silver_gray"
	var wheel_color_result: Dictionary = GameAuthority.local_shop_transaction(1, wheel_color_request)
	_check(bool(wheel_color_result.get("ok", false)) and vehicle.get_wheel_color_id() == "silver_gray", "silver-gray wheel color is applied through the service")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), color_balance - 1000.0), "each changed color slot costs 500")

	var player_state: Dictionary = GameAuthority.player_states[1]
	GameAuthority.call("_server_add_personal_ingredient", player_state, "vehicle_harvest_reel", 1.0, false)
	GameAuthority.player_states[1] = player_state
	var module_balance := GlobalVar.check_team_item_amount("red", "money")
	var module_request := transaction_context.duplicate(true)
	module_request["action"] = "install_module"
	module_request["request_id"] = "service-validation-module-1"
	module_request["module_id"] = "vehicle_harvest_reel"
	var module_result: Dictionary = GameAuthority.local_shop_transaction(1, module_request)
	_check(bool(module_result.get("ok", false)) and vehicle.harvest_reel_installed, "FarmBaseVehicle installs an allowed runtime module")
	_check(float((GameAuthority.player_states[1].get("personal_ingredients", {}) as Dictionary).get("vehicle_harvest_reel|whole", 0.0)) < 0.001, "module installation consumes one backpack module item")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), module_balance - 500.0), "module installation charges 500 team funds")
	var balance_after_module := GlobalVar.check_team_item_amount("red", "money")
	var duplicate_module_result: Dictionary = GameAuthority.local_shop_transaction(1, module_request)
	_check(str(duplicate_module_result.get("request_id", "")) == "service-validation-module-1" and bool(duplicate_module_result.get("ok", false)) and int(duplicate_module_result.get("installed_count", 0)) == 1, "a repeated module request is returned from the original idempotent transaction")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), balance_after_module), "repeated module request does not charge again")

	var motor_player_state: Dictionary = GameAuthority.player_states[1]
	GameAuthority.call("_server_add_personal_ingredient", motor_player_state, "high_performance_motor", 1.0, false)
	GameAuthority.player_states[1] = motor_player_state
	var motor_balance := GlobalVar.check_team_item_amount("red", "money")
	var motor_install_request := transaction_context.duplicate(true)
	motor_install_request["action"] = "install_module"
	motor_install_request["request_id"] = "service-validation-motor-1"
	motor_install_request["module_id"] = "high_performance_motor"
	var motor_install_result: Dictionary = GameAuthority.local_shop_transaction(1, motor_install_request)
	_check(
		bool(motor_install_result.get("ok", false))
			and vehicle.high_performance_motor_installed
			and is_equal_approx(vehicle.get_max_forward_speed(), 6.0)
			and is_equal_approx(vehicle.get_max_reverse_speed(), 4.8)
			and is_equal_approx(vehicle.get_acceleration(), 1.8),
		"FarmBaseVehicle installs the high-performance motor and applies the 20 percent performance bonus"
	)
	_check(
		float((GameAuthority.player_states[1].get("personal_ingredients", {}) as Dictionary).get("high_performance_motor|whole", 0.0)) < 0.001,
		"high-performance motor installation consumes one backpack motor"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), motor_balance - 500.0),
		"high-performance motor installation charges 500 team funds"
	)
	var motor_balance_after_install := GlobalVar.check_team_item_amount("red", "money")
	var duplicate_motor_result: Dictionary = GameAuthority.local_shop_transaction(1, motor_install_request)
	_check(
		str(duplicate_motor_result.get("request_id", "")) == "service-validation-motor-1"
			and bool(duplicate_motor_result.get("ok", false))
			and int(duplicate_motor_result.get("installed_count", 0)) == 1,
		"a repeated motor request is returned idempotently"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), motor_balance_after_install),
		"repeated motor request does not charge again"
	)
	var motor_uninstall_request := transaction_context.duplicate(true)
	motor_uninstall_request["action"] = "uninstall_module"
	motor_uninstall_request["request_id"] = "service-validation-motor-uninstall-1"
	motor_uninstall_request["module_id"] = "high_performance_motor"
	var motor_uninstall_result: Dictionary = GameAuthority.local_shop_transaction(1, motor_uninstall_request)
	_check(
		bool(motor_uninstall_result.get("ok", false)) and not vehicle.high_performance_motor_installed
			and int(motor_uninstall_result.get("uninstalled_count", 0)) == 1,
		"uninstalling the high-performance motor removes its performance state"
	)
	_check(
		is_equal_approx(
			float((GameAuthority.player_states[1].get("personal_ingredients", {}) as Dictionary).get("high_performance_motor|whole", 0.0)),
			1.0
		),
		"uninstalling the high-performance motor returns one backpack motor"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), motor_balance_after_install),
		"uninstalling the high-performance motor does not charge team funds"
	)

	var mini_quote_vehicle := MINI_VEHICLE_SCENE.instantiate() as VehicleBase
	mini_quote_vehicle.name = "VehicleServiceQuoteMiniCar"
	mini_quote_vehicle.network_id = "vehicle_service_quote_mini"
	mini_quote_vehicle.owner_team = "red"
	mini_quote_vehicle.position = Vector3(30.0, 0.55, 30.0)
	add_child(mini_quote_vehicle)
	await get_tree().process_frame
	var mini_quote := GameAuthority.get_vehicle_service_quote(mini_quote_vehicle, 1)
	var mini_modules: Array = mini_quote.get("modules", []) as Array
	var mini_has_motor := false
	var mini_has_composite_armor := false
	for module_value: Variant in mini_modules:
		if not module_value is Dictionary:
			continue
		var module_id := str((module_value as Dictionary).get("module_id", ""))
		mini_has_motor = mini_has_motor or module_id == "high_performance_motor"
		mini_has_composite_armor = mini_has_composite_armor or module_id == "composite_armor_panel"
	_check(
		mini_modules.size() == 2 and mini_has_motor and mini_has_composite_armor,
		"ordinary vehicle quote exposes the motor and composite armor upgrades"
	)
	var mini_service_terminal := TERMINAL_SCENE.instantiate() as VehicleServiceTerminal
	_check(mini_service_terminal != null, "second repair terminal instantiates for composite armor transaction")
	if mini_service_terminal != null:
		mini_service_terminal.name = "VehicleServiceCompositeTerminal"
		mini_service_terminal.position = Vector3(30.0, 0.52, 30.0)
		add_child(mini_service_terminal)
		await get_tree().process_frame
		mini_service_terminal.call("_on_vehicle_body_entered", mini_quote_vehicle)
		var player_one_state_for_mini: Dictionary = GameAuthority.player_states[1]
		var original_player_one_position: Variant = player_one_state_for_mini.get("position", Vector3.ZERO)
		player_one_state_for_mini["position"] = mini_service_terminal.get_interaction_position()
		GameAuthority.player_states[1] = player_one_state_for_mini
		var composite_player_state: Dictionary = GameAuthority.player_states[1]
		GameAuthority.call("_server_add_personal_ingredient", composite_player_state, "composite_armor_panel", 1.0, false)
		GameAuthority.player_states[1] = composite_player_state
		var composite_base_hp := mini_quote_vehicle.get_max_hp()
		mini_quote_vehicle.current_hp = composite_base_hp * 0.5
		var composite_context := {
			"shop_category": "vehicle_service",
			"terminal_id": mini_service_terminal.get_terminal_id(),
			"terminal_path": str(mini_service_terminal.get_path()),
			"vehicle_id": mini_quote_vehicle.get_vehicle_id(),
		}
		var composite_acquire_request := composite_context.duplicate(true)
		composite_acquire_request["action"] = "acquire"
		composite_acquire_request["request_id"] = "service-validation-composite-acquire-1"
		var composite_acquire_result: Dictionary = GameAuthority.local_shop_transaction(1, composite_acquire_request)
		_check(bool(composite_acquire_result.get("ok", false)), "ordinary vehicle accepts the composite armor service lock")
		var composite_money_before := GlobalVar.check_team_item_amount("red", "money")
		var composite_install_request := composite_context.duplicate(true)
		composite_install_request["action"] = "install_module"
		composite_install_request["request_id"] = "service-validation-composite-install-1"
		composite_install_request["module_id"] = "composite_armor_panel"
		var composite_install_result: Dictionary = GameAuthority.local_shop_transaction(1, composite_install_request)
		_check(
			bool(composite_install_result.get("ok", false))
				and mini_quote_vehicle.composite_armor_panel_installed
				and is_equal_approx(mini_quote_vehicle.get_max_hp(), composite_base_hp + 1500.0)
				and is_equal_approx(mini_quote_vehicle.current_hp, composite_base_hp * 0.5 + 1500.0)
				and is_equal_approx(float((composite_install_result.get("quote", {}) as Dictionary).get("max_hp", 0.0)), composite_base_hp + 1500.0),
			"composite armor installation increases ordinary vehicle max and current HP"
		)
		_check(
			is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), composite_money_before - 500.0)
				and float((GameAuthority.player_states[1].get("personal_ingredients", {}) as Dictionary).get("composite_armor_panel|whole", 0.0)) < 0.001,
			"composite armor installation consumes one panel and 500 team funds"
		)
		var composite_money_after_install := GlobalVar.check_team_item_amount("red", "money")
		var duplicate_composite_result: Dictionary = GameAuthority.local_shop_transaction(1, composite_install_request)
		_check(
			bool(duplicate_composite_result.get("ok", false))
				and int(duplicate_composite_result.get("installed_count", 0)) == 1
				and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), composite_money_after_install),
			"repeated composite armor installation is idempotent"
		)
		mini_quote_vehicle.current_hp = mini_quote_vehicle.get_max_hp() * 0.5
		var repaired_hp := mini_quote_vehicle.repair(99999.0)
		_check(
			is_equal_approx(repaired_hp, mini_quote_vehicle.get_max_hp() * 0.5)
				and is_equal_approx(mini_quote_vehicle.current_hp, composite_base_hp + 1500.0),
			"vehicle repair uses the composite armor effective maximum HP"
		)
		var composite_uninstall_request := composite_context.duplicate(true)
		composite_uninstall_request["action"] = "uninstall_module"
		composite_uninstall_request["request_id"] = "service-validation-composite-uninstall-1"
		composite_uninstall_request["module_id"] = "composite_armor_panel"
		var composite_uninstall_result: Dictionary = GameAuthority.local_shop_transaction(1, composite_uninstall_request)
		_check(
			bool(composite_uninstall_result.get("ok", false))
				and not mini_quote_vehicle.composite_armor_panel_installed
				and is_equal_approx(mini_quote_vehicle.get_max_hp(), composite_base_hp)
				and is_equal_approx(mini_quote_vehicle.current_hp, composite_base_hp),
			"composite armor removal clamps current HP to the base maximum"
		)
		_check(
			is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), composite_money_after_install)
			and is_equal_approx(
				float((GameAuthority.player_states[1].get("personal_ingredients", {}) as Dictionary).get("composite_armor_panel|whole", 0.0)),
				1.0
			),
			"composite armor removal returns one panel without charging funds"
		)
		mini_service_terminal.release_user(1)
		player_one_state_for_mini["position"] = original_player_one_position
		GameAuthority.player_states[1] = player_one_state_for_mini
		mini_service_terminal.queue_free()
		await get_tree().process_frame
	mini_quote_vehicle.queue_free()
	var cargo_quote_vehicle := CARGO_VEHICLE_SCENE.instantiate() as VehicleBase
	cargo_quote_vehicle.name = "VehicleServiceQuoteCargoCar"
	cargo_quote_vehicle.network_id = "vehicle_service_quote_cargo"
	cargo_quote_vehicle.owner_team = "red"
	cargo_quote_vehicle.position = Vector3(35.0, 0.55, 35.0)
	add_child(cargo_quote_vehicle)
	await get_tree().process_frame
	var cargo_quote := GameAuthority.get_vehicle_service_quote(cargo_quote_vehicle, 1)
	_check((cargo_quote.get("modules", []) as Array).is_empty(), "special-purpose CargoCar quote hides common upgrades")
	cargo_quote_vehicle.queue_free()

	var release_request := transaction_context.duplicate(true)
	release_request["action"] = "release"
	release_request["request_id"] = "service-validation-release-1"
	var release_result: Dictionary = GameAuthority.local_shop_transaction(1, release_request)
	_check(bool(release_result.get("ok", false)) and terminal.active_user_peer_id == 0, "the current player can release the operation lock")
	var reacquire_request := transaction_context.duplicate(true)
	reacquire_request["action"] = "acquire"
	reacquire_request["request_id"] = "service-validation-acquire-3"
	var reacquire_result: Dictionary = GameAuthority.local_shop_transaction(2, reacquire_request)
	_check(bool(reacquire_result.get("ok", false)) and terminal.active_user_peer_id == 2, "another player can take over after release")

	var module_collision_body := StaticBody3D.new()
	module_collision_body.name = "ValidationVehicleModuleBody"
	vehicle.add_child(module_collision_body)
	terminal.call("_on_vehicle_body_exited", module_collision_body)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		terminal.active_vehicle_id == vehicle.get_vehicle_id() and terminal.active_user_peer_id == 2,
		"one FarmBaseVehicle module body exiting does not release an overlapping vehicle"
	)
	module_collision_body.queue_free()

	var service_event_count_before_exit := _service_events.size()
	var vehicle_hp_before_exit := vehicle.current_hp
	vehicle.collision_layer = 0
	vehicle.global_position = Vector3(20.0, 0.55, 20.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	terminal.call("_on_vehicle_body_exited", vehicle)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		terminal.active_vehicle_id == vehicle.get_vehicle_id(),
		"a transient overlap miss does not immediately release the vehicle lock"
	)
	terminal.set(
		"_vehicle_overlap_missing_since_msec",
		Time.get_ticks_msec() - VehicleServiceTerminal.VEHICLE_EXIT_GRACE_MSEC - 1
	)
	terminal.authority_tick(0.0)
	_check(terminal.active_vehicle_id.is_empty() and not vehicle.is_queued_for_deletion(), "normal vehicle exit releases the lock without destroying the vehicle")
	_check(
		vehicle.global_position == Vector3(20.0, 0.55, 20.0)
			and is_equal_approx(vehicle.current_hp, vehicle_hp_before_exit),
		"vehicle lock release does not move or damage the vehicle"
	)
	_check(_service_events.size() > service_event_count_before_exit, "terminal lock changes emit a reliable service-state event")

	var timeout_vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	timeout_vehicle.name = "VehicleServiceTimeoutSurvivor"
	timeout_vehicle.network_id = "vehicle_service_timeout_survivor"
	timeout_vehicle.owner_team = "red"
	timeout_vehicle.position = Vector3(0.0, 0.55, 2.0)
	add_child(timeout_vehicle)
	await get_tree().physics_frame
	await get_tree().physics_frame
	terminal.call("_on_vehicle_body_entered", timeout_vehicle)
	terminal.try_acquire_user(1)
	var timeout_vehicle_position_before := timeout_vehicle.global_position
	var timeout_vehicle_hp_before := timeout_vehicle.current_hp
	var destroy_event_count_before_timeout := _vehicle_destroyed_event_count()
	terminal.active_user_last_activity_msec = Time.get_ticks_msec() - VehicleServiceTerminal.PLAYER_LOCK_TIMEOUT_MSEC - 1000
	terminal.authority_tick(0.0)
	_check(
		terminal.active_user_peer_id == 0 and terminal.active_vehicle_id == timeout_vehicle.get_vehicle_id(),
		"local player-lock timeout releases only the user while preserving bay occupancy"
	)
	_check(not timeout_vehicle.is_queued_for_deletion(), "local player-lock timeout never destroys the parked vehicle")
	_check(
		timeout_vehicle.global_position == timeout_vehicle_position_before
			and is_equal_approx(timeout_vehicle.current_hp, timeout_vehicle_hp_before),
		"local player-lock timeout does not move or damage the parked vehicle"
	)
	_check(
		_vehicle_destroyed_event_count() == destroy_event_count_before_timeout
			and not GameAuthority.is_persistently_destroyed_vehicle(timeout_vehicle.get_vehicle_id()),
		"local player-lock timeout emits no destroy event or persistent destroyed marker"
	)

	# Dedicated/listen servers execute the same authority_tick path. Verify that
	# multiplayer authority also expires only the remote player's UI lease.
	GameAuthority.start_server_mode()
	GameAuthority.set_physics_process(false)
	GameAuthority.register_or_update_player(41, {
		"display_name": "VehicleServiceRemoteValidation",
		"team": "red",
		"position": terminal.get_interaction_position(),
	})
	terminal.call("_on_vehicle_body_entered", timeout_vehicle)
	_check(terminal.try_acquire_user(41), "server authority grants the remote player-operation lock")
	var server_destroy_event_count_before_timeout := _vehicle_destroyed_event_count()
	terminal.active_user_last_activity_msec = Time.get_ticks_msec() - VehicleServiceTerminal.PLAYER_LOCK_TIMEOUT_MSEC - 1000
	terminal.authority_tick(0.0)
	_check(
		terminal.active_user_peer_id == 0 and terminal.active_vehicle_id == timeout_vehicle.get_vehicle_id(),
		"server player-lock timeout preserves the physically overlapping vehicle"
	)
	_check(
		not timeout_vehicle.is_queued_for_deletion()
			and _vehicle_destroyed_event_count() == server_destroy_event_count_before_timeout,
		"server player-lock timeout never destroys or broadcasts destruction"
	)
	timeout_vehicle.collision_layer = 0
	timeout_vehicle.global_position = Vector3(20.0, 0.55, 20.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	terminal.authority_tick(0.0)
	terminal.set(
		"_vehicle_overlap_missing_since_msec",
		Time.get_ticks_msec() - VehicleServiceTerminal.VEHICLE_EXIT_GRACE_MSEC - 1
	)
	terminal.authority_tick(0.0)
	_check(
		terminal.active_vehicle_id.is_empty() and terminal.active_user_peer_id == 0
			and not timeout_vehicle.is_queued_for_deletion(),
		"server authority releases both locks after a real bay exit without destroying the vehicle"
	)

	_finish()


func _vehicle_destroyed_event_count() -> int:
	var count := 0
	for event: Dictionary in _service_events:
		if str(event.get("type", "")) == "vehicle_destroyed":
			count += 1
	return count


func _color_option_index(option: OptionButton, color_id: String) -> int:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == color_id:
			return index
	return -1


func _camera_frames_vehicle_on_right(
	terminal: VehicleServiceTerminal,
	camera_value: Camera3D,
	vehicle: VehicleBase,
	viewport_size: Vector2
) -> bool:
	if camera_value == null or viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return false
	var bounds := terminal.call("_service_vehicle_world_bounds", vehicle) as AABB
	if bounds.size.length_squared() <= 0.001:
		return false
	var center_screen := camera_value.unproject_position(bounds.position + bounds.size * 0.5)
	var center_ratio := center_screen.x / viewport_size.x
	if center_ratio < 0.62 or center_ratio > 0.80:
		return false
	for x: float in [bounds.position.x, bounds.end.x]:
		for y: float in [bounds.position.y, bounds.end.y]:
			for z: float in [bounds.position.z, bounds.end.z]:
				var corner := Vector3(x, y, z)
				if camera_value.is_position_behind(corner):
					return false
				var screen_point := camera_value.unproject_position(corner)
				if screen_point.x < viewport_size.x * 0.40 or screen_point.x > viewport_size.x * 0.98 \
						or screen_point.y < viewport_size.y * 0.04 or screen_point.y > viewport_size.y * 0.96:
					return false
	return true


func _on_authority_event(event: Dictionary) -> void:
	if str(event.get("type", "")) in ["vehicle_service_state", "vehicle_destroyed"]:
		_service_events.append(event.duplicate(true))


func _add_box_body(body_name: String, position: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = position
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	return body


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[VehicleServiceTransactionValidation] PASS " + label)
	else:
		failures += 1
		push_error("[VehicleServiceTransactionValidation] FAIL " + label)


func _finish() -> void:
	if GameAuthority.reliable_world_event_ready.is_connected(_on_authority_event):
		GameAuthority.reliable_world_event_ready.disconnect(_on_authority_event)
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
