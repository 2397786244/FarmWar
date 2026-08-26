extends Node3D

const LAPTOP_SCENE := preload("res://facilities/interior/laptop.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ChocolateOSCatalog.get_manifest("browser") != null, "browser manifest is registered")
	_check(ChocolateOSCatalog.get_manifest("farm_info") != null, "farm info manifest is registered")
	_check(ChocolateOSCatalog.get_manifest_for_program("app_weather").app_id == "weather", "program id resolves to weather")
	var defaults := ChocolateOSCatalog.get_default_installed_app_ids("OS08")
	for app_id in ["browser", "my_computer", "network", "recycle_bin", "settings", "shutdown", "farm_info", "weather"]:
		_check(defaults.has(app_id), "%s is installed by default" % app_id)

	var normalized := ChocolateOSWebRegistry.normalize_url(" HTTPS://OSAPP.STORE/apps ")
	_check(bool(normalized.get("ok", false)), "store URL normalizes")
	_check(str(normalized.get("display_url", "")) == "www.osapp.store/apps", "store alias and case normalize")
	_check(str(ChocolateOSWebRegistry.resolve("www.osapp.store").get("page_kind", "")) == "store", "store root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.osapp.store/apps/weather").get("page_kind", "")) == "store_detail", "store detail resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.unknown.example").get("page_kind", "")) == "404", "unknown domain resolves to 404")
	_check(str(ChocolateOSWebRegistry.resolve("not an address").get("page_kind", "")) == "invalid", "invalid text is rejected")

	GlobalVar.gameworld = self
	GameAuthority.start_local_mode({
		"display_name": "ChocolateOSValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	var laptop := LAPTOP_SCENE.instantiate() as ComputerTerminal
	add_child(laptop)
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	player.authority_peer_id = 1
	add_child(player)
	await get_tree().process_frame

	_check(laptop.os_id == "OS08", "laptop uses OS08")
	_check(laptop.installed_app_ids.has("farm_info") and laptop.installed_app_ids.has("weather"), "laptop has default applications")
	var acquire := GameAuthority.server_computer_action(1, {
		"action": "acquire",
		"computer_id": laptop.get_computer_id(),
	})
	_check(bool(acquire.get("ok", false)), "authority acquires the computer lock")
	_check(laptop.active_user_peer_id == 1 and laptop.powered_on, "acquire powers on and owns the computer")
	_check(not laptop.try_acquire_user(2), "a second user cannot acquire an occupied computer")
	await get_tree().process_frame
	_check(is_instance_valid(player.computer_desktop) and player.computer_desktop.is_open(), "acquire opens the shared desktop")
	_check(player.interact_hint.visible and player.interact_hint.text == "按 ESC退出电脑", "computer exit instruction uses the yellow interaction prompt")
	_check(player.computer_desktop.window_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "empty window layer does not block desktop icon input")
	_check(player.computer_desktop.icon_controls.size() == laptop.installed_app_ids.size(), "desktop renders every installed application")
	var weather_manifest := ChocolateOSCatalog.get_manifest("weather")
	_check(weather_manifest != null and weather_manifest.entry_scene != null, "weather app has a dedicated entry scene")
	var farm_info_manifest := ChocolateOSCatalog.get_manifest("farm_info")
	var recycle_bin_manifest := ChocolateOSCatalog.get_manifest("recycle_bin")
	_check(farm_info_manifest != null and farm_info_manifest.entry_scene != null, "farm info app has a dedicated entry scene")
	_check(recycle_bin_manifest != null and recycle_bin_manifest.entry_scene != null, "recycle bin app has a dedicated entry scene")
	var first_dock_button := player.computer_desktop.dock.get_child(0) as Button
	_check(first_dock_button != null and first_dock_button.tooltip_text == "Shutdown", "shutdown is the leftmost taskbar shortcut")
	var browser_icon := player.computer_desktop.icon_controls.get("browser", null) as Button
	_check(browser_icon != null, "browser desktop icon has a button activation signal")
	if browser_icon != null:
		browser_icon.emit_signal("pressed")
		await get_tree().process_frame
		browser_icon.emit_signal("pressed")
		await get_tree().process_frame
	_check(player.computer_desktop.app_windows.has("browser"), "desktop icon opens after two clicks")
	var rendered_size := ChocolateOSDesktop.LOGICAL_SIZE * player.computer_desktop.shell.scale
	var viewport_size := player.computer_desktop.get_viewport_rect().size
	_check(rendered_size.x <= viewport_size.x * 0.801 and rendered_size.y <= viewport_size.y * 0.801, "desktop stays inside the responsive 80 percent bounds")
	# Exercise the authority cache with owned/unowned and planted/unplanted
	# tiles. These test tiles have no crop visuals because the statistic only
	# consumes the authoritative owner/seed fields.
	var red_empty_tile := FarmTile.new()
	red_empty_tile.land_owner = "red"
	add_child(red_empty_tile)
	var red_planted_tile := FarmTile.new()
	red_planted_tile.land_owner = "red"
	red_planted_tile.seed_record = "wheat"
	add_child(red_planted_tile)
	var blue_planted_tile := FarmTile.new()
	blue_planted_tile.land_owner = "blue"
	blue_planted_tile.seed_record = "wheat"
	add_child(blue_planted_tile)
	await get_tree().process_frame
	GameAuthority.rebuild_farm_statistics()
	var farm_context := ChocolateOSAppContext.new(player.computer_desktop, "farm_info")
	var farm_state := farm_context.query("farm.read")
	_check(bool(farm_state.get("ok", false)), "declared app service permission is available")
	_check(farm_state.has("owned_farm_tiles") and farm_state.has("planted_farm_tiles") \
			and farm_state.has("inventory_entries"), "farm.read returns the cached farm and inventory summary")
	_check(int(farm_state.get("owned_farm_tiles", 0)) == 2 \
			and int(farm_state.get("planted_farm_tiles", 0)) == 1, "farm.read counts only the current team's owned and planted tiles")
	red_empty_tile.land_owner = "blue"
	GameAuthority.report_farm_tile_delta(red_empty_tile, red_empty_tile.get_farm_tile_delta("owner"))
	red_planted_tile.seed_record = ""
	GameAuthority.report_farm_tile_delta(red_planted_tile, red_planted_tile.get_farm_tile_delta("harvest"))
	farm_state = farm_context.query("farm.read")
	_check(int(farm_state.get("owned_farm_tiles", 0)) == 1 \
			and int(farm_state.get("planted_farm_tiles", 0)) == 0, "FarmTile deltas update the cached counts without a second full scan")
	var shared_inventory_state := GlobalVar.get_team_storage_display_state("red")
	_check(shared_inventory_state.has("entries") and shared_inventory_state.has("total_weight_kg"), "team inventory display data uses the shared GlobalVar interface")
	var public_inventory := GlobalVar.get_public_inventory_state()
	_check((public_inventory.get("inventory_revisions", {}) as Dictionary).has("red"), "inventory snapshots include authoritative revisions")
	_check(not bool(farm_context.query("weather.read").get("ok", false)), "undeclared app service permission is denied")

	var uninstall := GameAuthority.server_computer_action(1, {
		"action": "uninstall_app",
		"computer_id": laptop.get_computer_id(),
		"app_id": "weather",
	})
	_check(bool(uninstall.get("ok", false)) and not laptop.installed_app_ids.has("weather"), "removable application uninstalls")
	_check(not laptop.app_data.has("weather"), "uninstall removes application data")
	var reinstall := GameAuthority.server_computer_action(1, {
		"action": "install_app",
		"computer_id": laptop.get_computer_id(),
		"program_id": "app_weather",
		"source": "app_store",
	})
	_check(bool(reinstall.get("ok", false)) and laptop.installed_app_ids.has("weather"), "store program installs again")

	var browser_cell := ChocolateOSCatalog._as_grid_cell(laptop.desktop_layout.get("browser", [0, 0]))
	var farm_cell := ChocolateOSCatalog._as_grid_cell(laptop.desktop_layout.get("farm_info", [0, 0]))
	var move := GameAuthority.server_computer_action(1, {
		"action": "move_app",
		"computer_id": laptop.get_computer_id(),
		"app_id": "browser",
		"cell": [farm_cell.x, farm_cell.y],
	})
	_check(bool(move.get("ok", false)), "desktop icon move is accepted")
	_check(ChocolateOSCatalog._as_grid_cell(laptop.desktop_layout["browser"]) == farm_cell, "moved icon reaches requested cell")
	_check(ChocolateOSCatalog._as_grid_cell(laptop.desktop_layout["farm_info"]) == browser_cell, "occupied cells swap")

	player.computer_desktop._open_app("browser")
	await get_tree().process_frame
	_check(player.computer_desktop.app_windows.has("browser"), "browser opens in the window manager")
	_check(player.computer_desktop.browser_sessions.has("browser"), "browser owns local navigation state")
	player.computer_desktop._open_app("weather")
	await get_tree().process_frame
	_check(player.computer_desktop.app_windows.has("weather"), "weather app opens in the window manager")
	_check(player.computer_desktop.app_instances.get("weather", null) is ChocolateOSAppBase, "weather app uses the shared app lifecycle")
	player.computer_desktop._open_app("farm_info")
	await get_tree().process_frame
	_check(player.computer_desktop.app_windows.has("farm_info"), "farm info opens in the window manager")
	_check(player.computer_desktop.app_instances.get("farm_info", null) is ChocolateOSAppBase, "farm info uses the shared app lifecycle")
	player.computer_desktop._open_app("recycle_bin")
	await get_tree().process_frame
	_check(player.computer_desktop.app_windows.has("recycle_bin"), "recycle bin opens in the window manager")
	_check(player.computer_desktop.app_instances.get("recycle_bin", null) is ChocolateOSAppBase, "recycle bin uses the dedicated app lifecycle")
	player.computer_desktop._browser_navigate("www.missing.domain", "browser", true)
	var session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var title := session.get("title", null) as Label
	_check(title != null and title.text.begins_with("404"), "browser displays a 404 page")
	var snapshot := GameAuthority.call("_build_low_frequency_snapshot") as Dictionary
	_check(snapshot.get("computers", []) is Array and not (snapshot.get("computers", []) as Array).is_empty(), "low-frequency snapshot contains computer summaries")
	var persistent_entries := CooperativeSession.call("_capture_persistent_station_states") as Array
	var computer_saved := false
	for entry_value: Variant in persistent_entries:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("group", "")) == "computer_terminals":
			computer_saved = true
			break
	_check(computer_saved, "world persistence captures computer state")

	var shutdown_button := player.computer_desktop.dock.get_child(0) as Button
	_check(shutdown_button != null and shutdown_button.tooltip_text == "Shutdown", "shutdown button is available for signal regression")
	if shutdown_button != null:
		# Emit the same signal path used by a real taskbar click. Shutdown is now
		# a visual-only black screen and must keep the computer lock alive.
		shutdown_button.emit_signal("pressed")
	await get_tree().process_frame
	_check(not player.computer_desktop.dock_refresh_queued, "dock refresh completes after shutdown signal unwinds")
	_check(player.computer_desktop.is_open() and player.computer_desktop.shutting_down \
			and player.computer_desktop.shutdown_overlay.visible, "shutdown only blacks out the desktop")
	_check(player.computer_desktop.shutdown_label.text == "已关机", "shutdown screen displays the powered-off message")
	_check(laptop.active_user_peer_id == 1, "visual shutdown keeps the computer lock")
	# ESC uses the same close path as the real player input handler.
	player.computer_desktop.close()
	await get_tree().process_frame
	_check(laptop.active_user_peer_id == 0, "closing the desktop releases its lock")
	red_empty_tile.queue_free()
	red_planted_tile.queue_free()
	blue_planted_tile.queue_free()
	GameAuthority.stop_authority()
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	if failures.is_empty():
		print("ChocolateOS validation passed")
		get_tree().quit(0)
	else:
		push_error("ChocolateOS validation failed: %s" % ", ".join(failures))
		get_tree().quit(1)
