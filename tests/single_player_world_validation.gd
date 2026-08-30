extends Node3D

const PAGE_SCENE := preload("res://ui/SinglePlayerWorldPage.tscn")

var failures: Array[String] = []
var original_root := ""
var test_root := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	original_root = SinglePlayerWorldStorage.world_root
	test_root = "/private/tmp/food-war-singleplayer-validation-%d" % Time.get_ticks_usec()
	SinglePlayerWorldStorage.world_root = test_root
	SinglePlayerWorldStorage.active_world.clear()
	var map_definition := GameMapRegistry.get_map_by_id("coop_test")
	_check(not map_definition.is_empty(), "test map metadata exists")
	var config := {
		"display_name": "  单人测试世界  ",
		"map_id": str(map_definition.get("map_id", "coop_test")),
		"map_name": str(map_definition.get("display_name", "coop test")),
		"map_icon_path": str(map_definition.get("icon_path", "")),
		"map_scene_path": str(map_definition.get("scene_path", "")),
		"loading_images_directory": str(map_definition.get("loading_images_directory", "")),
		"map_version": str(map_definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(map_definition.get("map_hash", "")),
		"map_source": str(map_definition.get("source", "builtin")),
	}
	var selection := {
		"hero_id": "farmer",
		"primary_weapon_ids": ["rubber_revolver", "flame_gun", "freeze_gun"],
		"special_tool_ids": ["plant_protector", "fertilizer"],
	}
	_check(SinglePlayerWorldStorage.create_world(config, {}).is_empty(), "empty loadout creates no save")
	_check(SinglePlayerWorldStorage.list_worlds().is_empty(), "cancelled creation leaves save list empty")
	var created := SinglePlayerWorldStorage.create_world(config, selection)
	var world_id := str(created.get("world_id", ""))
	_check(not world_id.is_empty(), "world is created after loadout selection")
	_check(str(created.get("display_name", "")) == "单人测试世界", "world name is trimmed")
	_check(str(created.get("death_drop_mode", "")) == "save", "single-player death drops are disabled")
	var loaded := SinglePlayerWorldStorage.load_world(world_id)
	var lock := SinglePlayerWorldStorage.get_loadout_lock(loaded)
	_check(str(lock.get("hero_id", "")) == "farmer", "hero lock persists")
	_check((lock.get("primary_weapon_ids", []) as Array).size() == 3, "three primary weapons persist")
	_check((lock.get("special_tool_ids", []) as Array).size() == 2, "two class tools persist")
	loaded["player_state"] = WorldPersistence.merge_player_state(lock, {
		"position": [12.0, 3.0, -8.0],
		"current_hp": 75.0,
		"personal_ingredients": {"tomato": 4.0},
	})
	loaded["world_state"] = {"destroyed_vehicle_ids": ["test_vehicle"]}
	(loaded["loadout_lock"] as Dictionary)["hero_id"] = "cook"
	_check(SinglePlayerWorldStorage.save_world(loaded), "existing world saves atomically")
	var reloaded := SinglePlayerWorldStorage.load_world(world_id)
	var player_state := reloaded.get("player_state", {}) as Dictionary
	_check(is_equal_approx(float(player_state.get("current_hp", 0.0)), 75.0), "player HP restores from JSON")
	_check((player_state.get("position", []) as Array).size() == 3, "player position remains serializable")
	_check(str((reloaded.get("loadout_lock", {}) as Dictionary).get("hero_id", "")) == "farmer", \
		"runtime save cannot replace the first loadout lock")
	_check((reloaded.get("world_clock", {}) as Dictionary).has("elapsed_seconds"), \
		"new single-player worlds include a structured clock")
	var legacy_world := reloaded.duplicate(true)
	legacy_world.erase("world_clock")
	legacy_world["world_elapsed_seconds"] = 9999.0
	var legacy_clock := WorldPersistence.get_saved_world_clock_state(legacy_world)
	_check(is_zero_approx(float(legacy_clock.get("elapsed_seconds", -1.0))), \
		"legacy scalar elapsed time falls back to the map default")
	_check(SinglePlayerWorldStorage.list_worlds().size() == 1, "save browser lists valid worlds")
	var original_storage := GlobalVar.team_storage.duplicate(true)
	GlobalVar.team_storage["red"]["money"] = 321.0
	var shared_world_state := WorldPersistence.capture_world_state()
	GlobalVar.team_storage["red"]["money"] = 1.0
	var shared_restored := await WorldPersistence.restore_world_state(self, {
		"world_state": shared_world_state,
		"team_money": 321.0,
	})
	_check(shared_restored and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), 321.0), \
		"shared cooperative/single-player codec restores authority storage")
	GlobalVar.team_storage = original_storage

	var page := PAGE_SCENE.instantiate() as SinglePlayerWorldPage
	add_child(page)
	await get_tree().process_frame
	page.size = Vector2(1280, 720)
	await get_tree().process_frame
	var create_panel := page.find_child("CreateWorldPanel", true, false) as Control
	var saved_panel := page.find_child("SavedWorldPanel", true, false) as Control
	_check(create_panel != null and saved_panel != null, "single-player page has create and save columns")
	_check(create_panel.size.x > 350.0 and saved_panel.size.x > 400.0, "both columns remain usable at 1280x720")
	_check(page.find_child("MapScroll", true, false) is ScrollContainer, "map column scrolls independently")
	_check(page.find_child("SavedWorldScroll", true, false) is ScrollContainer, "save column scrolls independently")
	page.size = Vector2(1920, 1080)
	await get_tree().process_frame
	_check(create_panel.size.x > 700.0 and saved_panel.size.x > 800.0, \
		"both columns expand proportionally at 1920x1080")
	page.pending_world_config = config.duplicate(true)
	page.call("_open_loadout")
	await get_tree().process_frame
	_check(is_instance_valid(page.loadout_ui) and page.loadout_ui.presentation_mode == "singleplayer", \
		"new world opens neutral single-player loadout mode")
	_check(page.loadout_ui.title_label.text == "选择角色和初始道具", "single-player loadout title is concise")
	page.call("_cancel_loadout")
	page.queue_free()
	await get_tree().process_frame

	_check(SinglePlayerWorldStorage.delete_world(world_id), "target world deletes")
	_check(SinglePlayerWorldStorage.list_worlds().is_empty(), "deletion affects only the selected save")
	_cleanup()
	_finish()


func _cleanup() -> void:
	SinglePlayerWorldStorage.active_world.clear()
	SinglePlayerWorldStorage.world_root = original_root
	var absolute_test_root := ProjectSettings.globalize_path(test_root)
	if DirAccess.dir_exists_absolute(absolute_test_root):
		DirAccess.remove_absolute(absolute_test_root)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _finish() -> void:
	if failures.is_empty():
		print("Single-player world validation passed")
		get_tree().quit(0)
	else:
		push_error("Single-player world validation failed: %s" % ", ".join(failures))
		get_tree().quit(1)
