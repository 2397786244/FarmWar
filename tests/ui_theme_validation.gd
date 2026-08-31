extends Control

const SHARED_THEME_PATH := "res://ui/shared_ui_theme.tres"
const NON_CHOCOLATE_UI_SCENES := [
	"res://ui/MainMenuRoot.tscn",
	"res://ui/HomeMenuPage.tscn",
	"res://ui/SinglePlayerWorldPage.tscn",
	"res://ui/CooperativeWorldPage.tscn",
	"res://ui/CooperativeLobbyPage.tscn",
	"res://ui/MultiplayerModePage.tscn",
	"res://ui/MultiplayerLobbyFlow.tscn",
	"res://ui/MultiplayerBattleRoomPage.tscn",
	"res://ui/MultiplayerLoadoutSelect.tscn",
	"res://ui/ServerBrowserPage.tscn",
	"res://ui/ingredient_extractor_page.tscn",
	"res://ui/stand_mixer_page.tscn",
	"res://ui/plating_station_page.tscn",
	"res://ui/griddle_station_page.tscn",
	"res://ui/induction_counter_page.tscn",
	"res://ui/oven_page.tscn",
	"res://ui/freezer_page.tscn",
	"res://ui/farm_smoker_page.tscn",
	"res://ui/auto_cooker_page.tscn",
	"res://ui/industrial_workbench_page.tscn",
	"res://ui/ingredient_pickup_page.tscn",
	"res://ui/ingredient_pickup_slot.tscn",
	"res://ui/plating_station_slot.tscn",
	"res://ui/item_icon.tscn",
	"res://ui/player_backpack.tscn",
	"res://ui/player_backpack_slot.tscn",
	"res://ui/player_backpack_drag_preview.tscn",
	"res://ui/player_backpack_tooltip.tscn",
	"res://ui/sprout_seed_selector.tscn",
	"res://ui/game_exit_dialog.tscn",
	"res://ui/game_settings_panel.tscn",
	"res://ui/event_task_hud.tscn",
	"res://ui/team_chat_panel.tscn",
	"res://ui/vehicle_service_page.tscn",
	"res://ui/vehicle_upgrade_page.tscn",
]

const DYNAMIC_UI_SCRIPTS := [
	"res://src/action_drone.gd",
	"res://src/auto_sales_page.gd",
	"res://src/broadcast_camera.gd",
	"res://src/cargo_car_storage_page.gd",
	"res://src/cargo_crate_storage_page.gd",
	"res://src/cargo_delivery_page.gd",
	"res://src/cooldown_ring.gd",
	"res://src/farmwar_runtime_map_editor.gd",
	"res://src/global_capture_manager.gd",
	"res://src/government_notice_page.gd",
	"res://src/livestock_chop_page.gd",
	"res://src/map_loading_screen.gd",
	"res://src/player.gd",
	"res://src/vehicle_seat_hud.gd",
	"res://src/vehicle_service_page.gd",
]

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var shared := load(SHARED_THEME_PATH) as Theme
	_check(shared != null, "shared theme resource loads")
	if shared == null:
		_finish()
		return

	_check(UITheme.SHARED_THEME == shared, "UITheme uses the shared theme resource")
	_check(shared.get_color("font_color", "Label").is_equal_approx(UITheme.COLOR_TEXT), "label text uses the shared primary color")
	_check(shared.get_color("default_color", "RichTextLabel").is_equal_approx(UITheme.COLOR_TEXT), "rich text uses the shared primary color")

	for scene_path: String in NON_CHOCOLATE_UI_SCENES:
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "%s loads" % scene_path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_check(instance is Control, "%s has a Control root" % scene_path)
		if instance is Control:
			_check((instance as Control).theme == shared, "%s inherits the shared theme" % scene_path)
		instance.free()

	for script_path: String in DYNAMIC_UI_SCRIPTS:
		var source := FileAccess.get_file_as_string(script_path)
		_check(source.contains("UITheme.apply"), "%s applies the shared theme to dynamic UI" % script_path)

	var root := Control.new()
	add_child(root)
	UITheme.apply(root)
	_check(root.theme == shared and root.has_meta("shared_ui_theme_applied"), "apply marks a themed root")

	var button := Button.new()
	root.add_child(button)
	UITheme.apply_button(button)
	_check(
		(button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(UITheme.COLOR_CONTROL),
		"button normal state uses the neutral control surface"
	)
	_check(
		(button.get_theme_stylebox("hover") as StyleBoxFlat).bg_color.is_equal_approx(UITheme.COLOR_HOVER),
		"button hover state uses the neutral hover surface"
	)

	var slot := PanelContainer.new()
	root.add_child(slot)
	UITheme.apply_slot(slot, true, false)
	_check(
		(slot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(UITheme.COLOR_SELECTED),
		"selected inventory slots use the shared selected surface"
	)

	var progress := ProgressBar.new()
	root.add_child(progress)
	UITheme.apply_progress(progress, UITheme.TONE_SUCCESS)
	_check(
		(progress.get_theme_stylebox("fill") as StyleBoxFlat).bg_color.is_equal_approx(UITheme.COLOR_SUCCESS),
		"progress bars use semantic tones only for their fill"
	)

	var chocolate_source := FileAccess.get_file_as_string("res://src/chocolate_os_desktop.gd")
	_check(not chocolate_source.contains("shared_ui_theme"), "ChocolateOS desktop is not coupled to the shared theme")
	var chocolate_scene_source := FileAccess.get_file_as_string("res://ui/chocolate_os_desktop.tscn")
	_check(not chocolate_scene_source.contains("shared_ui_theme"), "ChocolateOS scene is not coupled to the shared theme")

	root.queue_free()
	_finish()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[UIThemeValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[UIThemeValidation] FAIL: %s" % description)


func _finish() -> void:
	if failures == 0:
		print("[UIThemeValidation] PASS all checks")
	else:
		push_error("[UIThemeValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
