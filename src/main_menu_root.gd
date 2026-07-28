extends Control
class_name MainMenuRoot

const HOME_SCENE := preload("res://ui/HomeMenuPage.tscn")
const SERVER_BROWSER_SCENE := preload("res://ui/ServerBrowserPage.tscn")
const LOBBY_SCENE := preload("res://ui/MultiplayerLobbyFlow.tscn")
const BATTLE_ROOM_SCENE := preload("res://ui/MultiplayerBattleRoomPage.tscn")
const LOCAL_WORLD_SCENE := preload("res://worlds/creston_town.tscn")

var page_host: Control
var current_page: Control


func _ready() -> void:
	print("[MenuFlow] MainMenuRoot ready")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()
	_connect_multiplayer_network_signals()
	if GlobalVar.open_server_browser_on_main_menu:
		GlobalVar.open_server_browser_on_main_menu = false
		_show_server_browser()
	else:
		_show_home()
	#Input.MOUSE_MODE_CAPTURED

func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_host = Control.new()
	page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page_host)


func _set_page(scene: PackedScene) -> Control:
	print("[MenuFlow] Switching page to: %s" % scene.resource_path)
	if current_page != null and is_instance_valid(current_page):
		current_page.queue_free()
	current_page = scene.instantiate() as Control
	current_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_host.add_child(current_page)
	return current_page


func _show_home() -> void:
	print("[MenuFlow] Opening home page")
	var page := _set_page(HOME_SCENE)
	page.singleplayer_requested.connect(_on_singleplayer_requested)
	page.multiplayer_requested.connect(_show_server_browser)
	page.quit_requested.connect(func(): get_tree().quit())


func _show_server_browser() -> void:
	print("[MenuFlow] Multiplayer requested; opening server browser")
	var page := _set_page(SERVER_BROWSER_SCENE)
	page.back_requested.connect(_show_home)
	page.join_server_requested.connect(_show_multiplayer_lobby)


func _show_multiplayer_lobby(address := "", port := 0) -> void:
	print("[MenuFlow] Opening multiplayer lobby for %s:%d" % [str(address), int(port)])
	var page := _set_page(LOBBY_SCENE)
	page.back_requested.connect(_show_server_browser)
	page.loadout_ready_submitted.connect(_show_multiplayer_battle_room.bind(false))
	if not str(address).is_empty() and int(port) > 0:
		page.call_deferred("connect_to_server", str(address), int(port))


func _show_multiplayer_battle_room(selection: Dictionary, auto_load_map := false) -> void:
	var page := _set_page(BATTLE_ROOM_SCENE)
	page.setup_from_selection(selection, auto_load_map)


func _on_singleplayer_requested() -> void:
	var selection := {
		"peer_id": GameAuthority.LOCAL_PLAYER_ID,
		"display_name": "LocalPlayer",
		"team": "red",
		"hero_id": "cook",
		"primary_weapon_ids": ["sprout_blaster", "brick", "freeze_gun"],
		"special_tool_ids": ["small_mouse", "wand"],
		"ready": true,
	}
	GameAuthority.start_local_mode(selection)
	GlobalVar.pending_player_selection = selection
	MapLoading.begin_loading(
		"Creston Town",
		"res://assets/loading/creston_town",
		"res://data/loading_tips.json"
	)
	await get_tree().process_frame
	get_tree().change_scene_to_packed(LOCAL_WORLD_SCENE)


func _connect_multiplayer_network_signals() -> void:
	if not MultiplayerNetwork.lobby_players_public_info_received.is_connected(
		_on_lobby_players_public_info_received
	):
		MultiplayerNetwork.lobby_players_public_info_received.connect(
			_on_lobby_players_public_info_received
		)
	if not MultiplayerNetwork.match_started_received.is_connected(
		_on_match_started_received
	):
		MultiplayerNetwork.match_started_received.connect(_on_match_started_received)


func _on_lobby_players_public_info_received(players: Array) -> void:
	if current_page != null and current_page.has_method("set_players"):
		current_page.call("set_players", players)


func _on_match_started_received(info: Dictionary) -> void:
	if current_page != null and current_page.has_method("apply_match_start_info"):
		current_page.call("apply_match_start_info", info)
	if current_page != null and current_page.has_method("load_multiplayer_map"):
		current_page.call("load_multiplayer_map")
