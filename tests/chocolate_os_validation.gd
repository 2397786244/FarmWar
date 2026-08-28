extends Node3D

const LAPTOP_SCENE := preload("res://facilities/interior/laptop.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")
const EMBEDDED_LAB_SCENE := preload("res://computer/apps/embedded_lab/embedded_lab.tscn")

var failures: Array[String] = []
var captured_computer_events: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ChocolateOSCatalog.get_manifest("browser") != null, "browser manifest is registered")
	_check(ChocolateOSCatalog.get_manifest("farm_info") != null, "farm info manifest is registered")
	var embedded_manifest := ChocolateOSCatalog.get_manifest("embedded_lab")
	_check(embedded_manifest != null and embedded_manifest.supports_os("OS26") \
			and not embedded_manifest.supports_os("OS08"), "embedded lab is OS26-only")
	var embedded_programs := EmbeddedLabCatalog.get_all_programs()
	_check(embedded_programs.size() == 20, "embedded lab exposes four five-level tracks")
	var first_program := EmbeddedLabCatalog.get_definition("collection_program_1")
	var fifth_program := EmbeddedLabCatalog.get_definition("collection_program_5")
	_check(int(first_program.get("cost", 0)) == 10000 and is_equal_approx(float(first_program.get("duration_seconds", 0.0)), 60.0), "level I research cost and duration")
	_check(int(fifth_program.get("cost", 0)) == 50000 and is_equal_approx(float(fifth_program.get("duration_seconds", 0.0)), 240.0), "level V research cost and duration")
	_check(ChocolateOSCatalog.get_store_app_ids("OS26").has("embedded_lab") \
			and not ChocolateOSCatalog.get_store_app_ids("OS08").has("embedded_lab"), "embedded lab is filtered by OS in the app store")
	_check(ChocolateOSCatalog.get_manifest_for_program("app_weather").app_id == "weather", "program id resolves to weather")
	var defaults := ChocolateOSCatalog.get_default_installed_app_ids("OS08")
	for app_id in ["browser", "my_computer", "network", "recycle_bin", "settings", "shutdown", "farm_info", "weather"]:
		_check(defaults.has(app_id), "%s is installed by default" % app_id)

	var normalized := ChocolateOSWebRegistry.normalize_url(" HTTPS://OSAPP.STORE/apps ")
	_check(bool(normalized.get("ok", false)), "store URL normalizes")
	_check(str(normalized.get("display_url", "")) == "www.osapp.store/apps", "store alias and case normalize")
	_check(str(ChocolateOSWebRegistry.resolve("www.osapp.store").get("page_kind", "")) == "store", "store root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.osapp.store/apps/weather").get("page_kind", "")) == "store_detail", "store detail resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.supplyrelay.com").get("page_kind", "")) == "supply_relay", "official Supply Relay root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.fakesupply.com/supply").get("page_kind", "")) == "fake_supply", "fake Supply page resolves")
	_check(str(ChocolateOSWebRegistry.resolve("s.com").get("page_kind", "")) == "s_chat", "s.com root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.rangeledger.com/catalog").get("page_kind", "")) == "range_ledger" \
			and str(ChocolateOSWebRegistry.resolve("www.rangeledger.com/catalog").get("page_id", "")) == "catalog", \
			"Range Ledger firearm catalog resolves")
	_check(str(ChocolateOSWebRegistry.resolve("rangeledger.com/future-series").get("page_id", "")) == "future_series", \
			"Range Ledger Future series alias resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.rangeledger.com/safety").get("page_id", "")) == "safety", \
			"Range Ledger safety and supply page resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.sofiaonwheels.com").get("page_kind", "")) == "sofia_on_wheels" \
			and str(ChocolateOSWebRegistry.resolve("www.sofiaonwheels.com").get("page_id", "")) == "home", \
			"Sofia on Wheels root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("sofiaonwheels.com/menu").get("page_id", "")) == "menu", \
			"Sofia on Wheels menu alias resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.circuitandchai.com/os08").get("page_kind", "")) == "circuit_and_chai" \
			and str(ChocolateOSWebRegistry.resolve("www.circuitandchai.com/os08").get("page_id", "")) == "os08", \
			"Circuit & Chai OS08 page resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.circuitandchai.com").get("page_id", "")) == "os08", \
			"Circuit & Chai root aliases to OS08")
	_check(str(ChocolateOSWebRegistry.resolve("circuitandchai.com/os26").get("page_kind", "")) == "circuit_and_chai" \
			and str(ChocolateOSWebRegistry.resolve("circuitandchai.com/os26").get("page_id", "")) == "os26", \
			"Circuit & Chai OS26 alias resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.circuitandchai.com/unknown").get("page_kind", "")) == "404", \
			"Circuit & Chai unknown path resolves to 404")
	_check(str(ChocolateOSWebRegistry.resolve("www.mercerseed.com").get("page_kind", "")) == "mercer_seed" \
			and str(ChocolateOSWebRegistry.resolve("www.mercerseed.com").get("page_id", "")) == "home", \
			"Mercer Seed root resolves")
	_check(str(ChocolateOSWebRegistry.resolve("mercerseed.com/seed-guide").get("page_kind", "")) == "mercer_seed" \
			and str(ChocolateOSWebRegistry.resolve("mercerseed.com/seed-guide").get("page_id", "")) == "seed_guide", \
			"Mercer Seed guide alias resolves")
	_check(str(ChocolateOSWebRegistry.resolve("www.mercerseed.com/unknown").get("page_kind", "")) == "404", \
			"Mercer Seed unknown path resolves to 404")
	_check(str(ChocolateOSWebRegistry.resolve("bellwrench.com").get("page_kind", "")) == "bellwrench" \
			and str(ChocolateOSWebRegistry.resolve("bellwrench.com").get("page_id", "")) == "vehicles", \
			"Bellwrench root aliases to the vehicle catalog")
	for bellwrench_route: Array in [
		["/vehicles", "vehicles"],
		["/service", "service"],
		["/upgrades", "upgrades"],
		["/farm-base", "farm_base"],
	]:
		var bellwrench_result := ChocolateOSWebRegistry.resolve("www.bellwrench.com%s" % str(bellwrench_route[0]))
		_check(str(bellwrench_result.get("page_kind", "")) == "bellwrench" \
				and str(bellwrench_result.get("page_id", "")) == str(bellwrench_route[1]), \
				"Bellwrench route resolves: %s" % str(bellwrench_route[0]))
	_check(str(ChocolateOSWebRegistry.resolve("www.bellwrench.com/unknown").get("page_kind", "")) == "404", \
			"Bellwrench unknown path resolves to 404")

	var bellwrench_page := BellwrenchPage.new()
	add_child(bellwrench_page)
	bellwrench_page.setup(self, "vehicles")
	await get_tree().process_frame
	var bellwrench_vehicle_text := _collect_control_text(bellwrench_page)
	var bellwrench_vehicle_names_complete := true
	for vehicle_id: String in BellwrenchPage.VEHICLE_ORDER:
		var vehicle_data: Dictionary = BellwrenchPage.VEHICLES.get(vehicle_id, {}) as Dictionary
		if not bellwrench_vehicle_text.contains(str(vehicle_data.get("name", ""))):
			bellwrench_vehicle_names_complete = false
			break
	_check(bellwrench_vehicle_names_complete, "Bellwrench vehicle page lists all six purchasable vehicles")
	_check(not bellwrench_vehicle_text.contains("警车") \
			and not bellwrench_vehicle_text.contains("消防车") \
			and not bellwrench_vehicle_text.contains("联合收割机") \
			and not bellwrench_vehicle_text.contains("货运车"), \
			"Bellwrench vehicle page omits special vehicles")
	_check(not bellwrench_vehicle_text.contains("HP") and not bellwrench_vehicle_text.contains("座位") \
			and not bellwrench_vehicle_text.contains("载货"), \
			"Bellwrench vehicle page only exposes price and top speed")
	for bellwrench_page_id: String in ["service", "upgrades", "farm_base"]:
		bellwrench_page.setup(self, bellwrench_page_id)
		await get_tree().process_frame
		_check(bellwrench_page.custom_minimum_size.y > 700.0, \
				"Bellwrench page builds and reserves scroll space: %s" % bellwrench_page_id)
	bellwrench_page.queue_free()
	var bellwrench_common_module_ids := [
		"high_performance_motor", "composite_armor_panel", "vehicle_control_module", "battery_pack",
	]
	var bellwrench_farm_base_module_ids := [
		"vehicle_harvest_reel", "vehicle_extended_seat", "vehicle_roof_headlights", "vehicle_machine_gun",
		"vehicle_nitro_boost", "vehicle_roof_cooling_system", "vehicle_signal_augment",
	]
	var bellwrench_modules_registered := true
	for module_id: String in bellwrench_common_module_ids + bellwrench_farm_base_module_ids:
		var module_product := GlobalVar.get_shop_product(module_id)
		var module_definition := IngredientCatalog.get_definition(module_id)
		var module_models: Variant = module_definition.get("models", {})
		var module_model_path := str((module_models as Dictionary).get("whole_item", "")) \
			if module_models is Dictionary else ""
		if module_product.is_empty() or int(module_product.get("buy_price", 0)) <= 0 \
				or module_model_path.is_empty() or not FileAccess.file_exists(module_model_path):
			bellwrench_modules_registered = false
			break
	_check(bellwrench_modules_registered, "Bellwrench modules reuse registered items and models")
	var food_car_assets_complete := true
	for food_car_asset_id: String in [
		"food_truck", "burger", "fries", "taco", "soda", "ice_cream", "egg_tart", "fried_chicken_nuggets",
	]:
		if not FileAccess.file_exists("res://assets/icons/food_car/%s.png" % food_car_asset_id):
			food_car_assets_complete = false
			break
	_check(food_car_assets_complete, "Sofia on Wheels has food-car and menu reference images")
	var mercer_seed_assets_complete := true
	for crop_id: String in IngredientCatalog.get_plantable_ids():
		if not FileAccess.file_exists("res://assets/icons/mercersed/%s.png" % crop_id):
			mercer_seed_assets_complete = false
			break
	_check(mercer_seed_assets_complete, "Mercer Seed has copied harvest-drop crop images")
	var range_ledger_assets_complete := true
	for range_ledger_asset_id: String in [
		"mpx", "m4", "ar15", "shotgun", "hunting_rifle", "crossbow", "suppressed_pistol",
		"future_m4", "future_mpx", "grenade", "ammo_supply_box",
	]:
		if not FileAccess.file_exists("res://assets/icons/rangeledger/%s.png" % range_ledger_asset_id):
			range_ledger_assets_complete = false
			break
	_check(range_ledger_assets_complete, "Range Ledger has all firearm and supply reference images")
	var s_chat_posts := SChatCatalog.get_posts()
	var range_ledger_posts_are_reference_only := true
	for post: Dictionary in s_chat_posts:
		var links_value: Variant = post.get("links", [])
		var links_text := str(links_value)
		if not links_text.contains("rangeledger.com"):
			continue
		var post_text := str(post.get("text", ""))
		for forbidden_phrase: String in ["在线订购", "网上订购", "在线购买", "网购", "购买链接", "下单"]:
			if post_text.contains(forbidden_phrase):
				range_ledger_posts_are_reference_only = false
				break
		if not range_ledger_posts_are_reference_only:
			break
	_check(range_ledger_posts_are_reference_only, "Range Ledger links remain reference-only without online gun ordering")
	var s_chat_engagement_complete := s_chat_posts.size() == 146
	var s_chat_posts_are_interleaved := true
	for post_index in range(1, s_chat_posts.size()):
		if str(s_chat_posts[post_index - 1].get("npc_id", "")) \
				== str(s_chat_posts[post_index].get("npc_id", "")):
			s_chat_posts_are_interleaved = false
			break
	_check(s_chat_posts_are_interleaved, "s.chat randomizes and interleaves authors without adjacent duplicates")
	_check(SChatCatalog.get_image_paths({"image": null}).is_empty(), \
		"s.chat treats a null legacy image as no image")
	var s_chat_post_counts: Dictionary = {}
	var new_s_chat_posts_are_immediate_and_text_only := true
	var expanded_s_chat_npc_ids := [
		"npc_leah_mercer", "npc_marcus_bell", "npc_calvin_reed", "npc_evelyn_shaw",
		"npc_theo_grant", "npc_grace_chen", "npc_nolan_fraser", "npc_ren_takahashi",
		"npc_priya_nair", "npc_sofia_marin",
	]
	for post: Dictionary in s_chat_posts:
		var post_npc_id := str(post.get("npc_id", ""))
		s_chat_post_counts[post_npc_id] = int(s_chat_post_counts.get(post_npc_id, 0)) + 1
		if post_npc_id in expanded_s_chat_npc_ids and (post.get("published_at", null) != null \
				or not SChatCatalog.get_image_paths(post).is_empty()):
			new_s_chat_posts_are_immediate_and_text_only = false
		var engagement_value: Variant = post.get("engagement", null)
		if not engagement_value is Dictionary:
			s_chat_engagement_complete = false
			break
		for field: String in ["likes", "comments", "reposts"]:
			if not (engagement_value as Dictionary).has(field):
				s_chat_engagement_complete = false
				break
	_check(s_chat_engagement_complete, "s.chat posts carry static engagement counts")
	var expected_s_chat_post_counts := {
		"npc_aiko_mori": 6,
		"npc_dana_ortiz": 10,
		"npc_eddie_vale": 10,
		"npc_jordan_kim": 10,
		"npc_seo_yeon_han": 10,
	}
	for npc_id: String in expanded_s_chat_npc_ids:
		expected_s_chat_post_counts[npc_id] = 10
	_check(s_chat_post_counts == expected_s_chat_post_counts, "s.chat has the final fifteen-author post distribution")
	_check(new_s_chat_posts_are_immediate_and_text_only, "expanded s.chat posts are immediate and have no images")
	var s_chat_profiles_complete := true
	for npc_id: String in expected_s_chat_post_counts:
		var profile := SChatCatalog.get_profile(npc_id)
		var avatar_path := str(profile.get("avatar", ""))
		if str(profile.get("handle", "")) == "@unknown" or avatar_path.is_empty() \
				or not FileAccess.file_exists(avatar_path):
			s_chat_profiles_complete = false
			break
	_check(s_chat_profiles_complete and not SChatCatalog.NPC_PROFILES.has("npc_elena_kovacs"), \
		"s.chat registers the final fifteen profiles and removes Elena")
	_check(GlobalVar.is_shop_product_sellable("gun_store", "ammo_supply_box"), "gun store allows AmmoSupplyBox resale through its whitelist")
	_check(not GlobalVar.is_shop_product_sellable("gun_store", "future_m4") \
			and not GlobalVar.is_shop_product_sellable("gun_store", "future_mpx"), \
			"gun store excludes Future firearm resale through its whitelist")
	_check(GlobalVar.is_shop_product_buyable("gun_store", "m4") \
			and not GlobalVar.is_shop_product_buyable("gun_store", "future_m4") \
			and not GlobalVar.is_shop_product_buyable("gun_store", "future_mpx"), \
			"gun store purchase whitelist excludes Future firearms")
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
	if not GameAuthority.reliable_world_event_ready.is_connected(_capture_computer_event):
		GameAuthority.reliable_world_event_ready.connect(_capture_computer_event)
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	player.authority_peer_id = 1
	add_child(player)
	await get_tree().process_frame
	var plain_y := InputEventKey.new()
	plain_y.keycode = KEY_Y
	plain_y.physical_keycode = KEY_Y
	plain_y.pressed = true
	var ctrl_y := InputEventKey.new()
	ctrl_y.keycode = KEY_Y
	ctrl_y.physical_keycode = KEY_Y
	ctrl_y.ctrl_pressed = true
	ctrl_y.pressed = true
	_check(not bool(player.team_chat_panel.call("is_modified_talk_event", plain_y)), "plain Y does not open or toggle chat")
	_check(bool(player.team_chat_panel.call("is_modified_talk_event", ctrl_y)), "Ctrl+Y is the only chat toggle shortcut")

	_check(laptop.os_id == "OS08", "laptop uses OS08")
	_check(laptop.installed_app_ids.has("farm_info") and laptop.installed_app_ids.has("weather"), "laptop has default applications")
	var acquire := GameAuthority.server_computer_action(1, {
		"action": "acquire",
		"computer_id": laptop.get_computer_id(),
	})
	_check(bool(acquire.get("ok", false)), "authority acquires the computer lock")
	_check((acquire.get("computer_state", {}) as Dictionary).has("app_data"), \
		"successful acquire returns full computer app data to its requester")
	var acquire_summary_found := false
	for event: Dictionary in captured_computer_events:
		if str(event.get("type", "")) != "computer_state":
			continue
		var summary := event.get("computer_state", {}) as Dictionary
		if str(summary.get("computer_id", "")) == laptop.get_computer_id() \
				and not summary.has("app_data"):
			acquire_summary_found = true
			break
	_check(acquire_summary_found, "computer acquire broadcasts a summary without app data")
	captured_computer_events.clear()
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
	player.computer_desktop._browser_navigate("www.supplyrelay.com", "browser", true)
	await get_tree().process_frame
	var supply_session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var supply_page := supply_session.get("page", null) as VBoxContainer
	var supply_page_loaded := false
	if supply_page != null:
		for child: Node in supply_page.get_children():
			if child.has_method("apply_supply_result"):
				supply_page_loaded = true
				break
	_check(supply_page_loaded, "official Supply Relay page builds inside the browser")
	player.computer_desktop._browser_navigate("www.fakesupply.com/supply", "browser", true)
	await get_tree().process_frame
	var fake_session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var fake_page := fake_session.get("page", null) as VBoxContainer
	var fake_page_loaded := false
	if fake_page != null:
		for child: Node in fake_page.get_children():
			if child.has_method("apply_supply_result"):
				fake_page_loaded = true
				break
	_check(fake_page_loaded, "fake Supply page builds inside the browser")
	player.computer_desktop._browser_navigate("s.com", "browser", true)
	await get_tree().process_frame
	var s_chat_session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var s_chat_page := s_chat_session.get("page", null) as VBoxContainer
	var s_chat_page_loaded := false
	if s_chat_page != null:
		for child: Node in s_chat_page.get_children():
			if child is SChatPage:
				s_chat_page_loaded = true
				break
	_check(s_chat_page_loaded, "s.com page builds inside the browser")
	player.computer_desktop._browser_navigate("www.mercerseed.com/seed-guide", "browser", true)
	await get_tree().process_frame
	var mercer_session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var mercer_page := mercer_session.get("page", null) as VBoxContainer
	var mercer_page_loaded := false
	if mercer_page != null:
		for child: Node in mercer_page.get_children():
			if child is MercerSeedPage:
				mercer_page_loaded = true
				break
	_check(mercer_page_loaded, "Mercer Seed guide builds inside the browser")
	player.computer_desktop.set_browser_s_chat_like_state("browser", ["aiko_mori_rain_after"])
	await get_tree().process_frame
	var browser_data_after_like: Dictionary = laptop.app_data.get("browser", {}) as Dictionary
	var browser_payload_after_like: Dictionary = browser_data_after_like.get("payload", {}) as Dictionary
	var browser_s_chat_after_like: Dictionary = browser_payload_after_like.get("s_chat", {}) as Dictionary
	_check((browser_s_chat_after_like.get("liked_post_ids", []) as Array).has("aiko_mori_rain_after"), \
		"s.chat like is stored in the computer's Browser data")
	var like_emitted_shared_state := false
	for event: Dictionary in captured_computer_events:
		if str(event.get("type", "")) == "computer_state":
			like_emitted_shared_state = true
			break
	_check(not like_emitted_shared_state, "browser like does not broadcast a shared computer state")
	captured_computer_events.clear()
	player.computer_desktop._browser_navigate("www.osapp.store", "browser", true)
	player.computer_desktop._browser_navigate("s.com", "browser", true)
	await get_tree().process_frame
	var reopened_s_chat_session := player.computer_desktop.browser_sessions.get("browser", {}) as Dictionary
	var reopened_s_chat_page := reopened_s_chat_session.get("page", null) as VBoxContainer
	var restored_like := false
	if reopened_s_chat_page != null:
		for child: Node in reopened_s_chat_page.get_children():
			if child is SChatPage:
				restored_like = (child as SChatPage).liked_post_ids.has("aiko_mori_rain_after")
				break
	_check(restored_like, "s.chat restores likes when the same computer is reopened")
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
	var computer_state_before_lab := laptop.get_computer_state()
	var computer_app_data := computer_state_before_lab.get("app_data", {}) as Dictionary
	_check(not computer_app_data.has("embedded_lab"), "computer state does not own Embedded Lab progression")
	var first_shared_research := GameAuthority.start_team_embedded_lab_research(
		"red", "collection_program_1", 1, laptop.get_computer_id()
	)
	_check(bool(first_shared_research.get("ok", false)), "team can start shared Embedded Lab research")
	var duplicate_shared_research := GameAuthority.start_team_embedded_lab_research(
		"red", "collection_program_1", 2, "another_computer"
	)
	_check(not bool(duplicate_shared_research.get("ok", false)) \
			and str(duplicate_shared_research.get("reason", "")) == "embedded_lab_busy" \
			and not GameAuthority.get_team_embedded_lab_state("red").get("unlocked_program_ids", []).has("collection_program_1"), \
		"a duplicate simultaneous team research request is rejected without a duplicate unlock")
	GameAuthority.advance_team_embedded_labs(59.0)
	_check(not GameAuthority.get_team_embedded_lab_state("red").get("unlocked_program_ids", []).has("collection_program_1"), \
		"a program is not unlocked before its research duration completes")
	GameAuthority.advance_team_embedded_labs(1.0)
	var shared_lab_state := GameAuthority.get_team_embedded_lab_state("red")
	var shared_unlocked: Array = shared_lab_state.get("unlocked_program_ids", []) as Array
	_check(shared_unlocked.count("collection_program_1") == 1 \
			and (shared_lab_state.get("active_research", {}) as Dictionary).is_empty(), \
		"completed team research unlocks exactly once and clears the shared job")
	GameAuthority.advance_team_embedded_labs(60.0)
	_check((GameAuthority.get_team_embedded_lab_state("red").get("unlocked_program_ids", []) as Array).count("collection_program_1") == 1, \
		"repeated completion ticks remain idempotent")
	var lab_snapshot := GameAuthority.call("_build_low_frequency_snapshot") as Dictionary
	_check((lab_snapshot.get("embedded_lab_teams", {}) as Dictionary).has("red"), \
		"low-frequency snapshots contain shared Embedded Lab team state")
	var persistent_world_state := CooperativeSession.call("_capture_persistent_world_state") as Dictionary
	_check((persistent_world_state.get("embedded_lab_teams", {}) as Dictionary).has("red"), \
		"world persistence captures shared Embedded Lab team state")
	var app_drive_info := HardDriveProgramCatalog.describe("app_weather")
	_check(bool(app_drive_info.get("is_application", false)) \
			and str(app_drive_info.get("program_type", "")) == "可安装应用程序" \
			and str(app_drive_info.get("display_name", "")) == "Weather", \
		"hard drive descriptions identify installable applications")
	var firmware_drive_info := HardDriveProgramCatalog.describe("collection_program_1")
	_check(bool(firmware_drive_info.get("is_firmware", false)) \
			and str(firmware_drive_info.get("program_type", "")) == "嵌入式固件程序", \
		"hard drive descriptions identify Embedded Lab firmware")
	var embedded_lab_ui := EMBEDDED_LAB_SCENE.instantiate() as ChocolateOSEmbeddedLabApp
	add_child(embedded_lab_ui)
	await get_tree().process_frame
	embedded_lab_ui.current_state = {
		"unlocked_program_ids": ["collection_program_1"],
		"active_research": {},
	}
	embedded_lab_ui.hard_drives = [{
		"slot_index": 2,
		"drive_instance_id": "validation-application-drive",
		"program_id": "app_weather",
	}]
	embedded_lab_ui._refresh_burn_view()
	await get_tree().process_frame
	var app_drive_row := embedded_lab_ui.burn_rows.get("collection_program_1", {}) as Dictionary
	var app_drive_option := app_drive_row.get("drive_option", null) as OptionButton
	var app_drive_option_before := app_drive_option
	_check(app_drive_option != null and app_drive_option.selected == 0 \
			and app_drive_option.get_item_text(0).contains("Weather") \
			and app_drive_option.get_item_text(0).contains("可安装应用程序") \
			and not app_drive_option.get_item_text(0).contains("#"), \
		"burn rows select and identify an application-programmed drive")
	var app_drive_panel := app_drive_row.get("panel", null) as PanelContainer
	_check(app_drive_panel != null and app_drive_panel.get_parent() == embedded_lab_ui.burn_list \
			and app_drive_panel.visible, "burn row is attached to the visible burn list")
	embedded_lab_ui._refresh_burn_view()
	await get_tree().process_frame
	var app_drive_option_after := (embedded_lab_ui.burn_rows.get("collection_program_1", {}) as Dictionary).get("drive_option", null) as OptionButton
	_check(app_drive_option_before == app_drive_option_after, \
		"burn polling preserves the drive dropdown control")
	embedded_lab_ui.queue_free()
	var money_before_get := GlobalVar.check_team_item_amount("red", "money")
	var get_money_result := GameAuthority.server_team_chat(1, "[get] money 10000")
	_check(bool(get_money_result.get("ok", false)) \
			and is_equal_approx(
				GlobalVar.check_team_item_amount("red", "money"),
				money_before_get + 10000.0
			),
		"[get] money adds funds to the sender's team")
	var money_before_supply := GlobalVar.check_team_item_amount("red", "money")
	var real_supply_result := GameAuthority.server_computer_action(1, {
		"action": "supply_draw",
		"computer_id": laptop.get_computer_id(),
		"site_id": "supplyrelay",
	})
	var real_reward_id := str(real_supply_result.get("reward_item_id", ""))
	_check(bool(real_supply_result.get("ok", false)) \
			and bool(real_supply_result.get("reward_delivered", false)) \
			and not real_reward_id.is_empty() \
			and GlobalVar.check_team_item_amount("red", real_reward_id) > 0.0, \
		"official Supply Relay charges once and deposits the reward in team storage")
	_check(is_equal_approx(
		GlobalVar.check_team_item_amount("red", "money"), money_before_supply - SupplyRelayCatalog.DRAW_COST
	), "official Supply Relay deducts exactly $500")
	var storage_before_fake: Dictionary = GlobalVar.team_storage["red"].duplicate(true)
	storage_before_fake.erase("money")
	var fake_supply_result := GameAuthority.server_computer_action(1, {
		"action": "supply_draw",
		"computer_id": laptop.get_computer_id(),
		"site_id": "fakesupply",
	})
	_check(bool(fake_supply_result.get("ok", false)) \
			and not bool(fake_supply_result.get("reward_delivered", true)) \
			and bool(fake_supply_result.get("scam", false)), \
		"fake Supply page accepts payment without delivering the displayed reward")
	var storage_after_fake: Dictionary = GlobalVar.team_storage["red"].duplicate(true)
	storage_after_fake.erase("money")
	_check(storage_after_fake == storage_before_fake, \
		"fake Supply page does not write any item to team storage")

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
	var release_summary_found := false
	for event: Dictionary in captured_computer_events:
		if str(event.get("type", "")) != "computer_state":
			continue
		var summary := event.get("computer_state", {}) as Dictionary
		if int(summary.get("active_user_peer_id", -1)) == 0 and not summary.has("app_data"):
			release_summary_found = true
			break
	_check(release_summary_found, "computer release broadcasts a summary without app data")
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


func _capture_computer_event(event: Dictionary) -> void:
	if str(event.get("type", "")) in ["computer_action_result", "computer_state"]:
		captured_computer_events.append(event.duplicate(true))


func _collect_control_text(node: Node) -> String:
	var result := ""
	if node is Label:
		result += (node as Label).text + "\n"
	elif node is Button:
		result += (node as Button).text + "\n"
	for child: Node in node.get_children():
		result += _collect_control_text(child)
	return result


func _finish() -> void:
	if failures.is_empty():
		print("ChocolateOS validation passed")
		get_tree().quit(0)
	else:
		push_error("ChocolateOS validation failed: %s" % ", ".join(failures))
		get_tree().quit(1)
