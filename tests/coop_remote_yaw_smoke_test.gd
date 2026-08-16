extends Node
class_name CoopRemoteYawSmokeTest

## Host-only smoke test for the cooperative NormalDrone control path.
## The controller is embedded in coop_test.tscn. Running the wrapper scene from
## the editor marks the test as requested and automatically starts a one-host
## Steam cooperative session; the normal world/bootstrap path is still used.

const TEST_ARGUMENT := "--remote-yaw-smoke"
const DEVICE_ID := "normal_drone"
const STATUS_INTERVAL_SECONDS := 0.5
const TEST_SCENE_SUFFIX := "CoopRemoteYawSmokeTest.tscn"
const TEST_REQUEST_META := "coop_remote_yaw_smoke_requested"
const TEST_MAP_ID := "coop_test"
const TEST_MAP_SCENE := "res://worlds/coop_test/coop_test.tscn"

var _enabled := false
var _grant_requested := false
var _placement_requested := false
var _auto_host_attempted := false
var _auto_host_start_requested := false
var _last_status_time := -INF
var _player: GamePlayer
var _status_label: Label
var _canvas_layer: CanvasLayer
var _auto_host_world: Dictionary = {}
var _auto_host_selection: Dictionary = {}


func _ready() -> void:
	var current_scene := get_tree().current_scene
	var launched_from_wrapper := is_instance_valid(current_scene) \
		and current_scene.scene_file_path.ends_with(TEST_SCENE_SUFFIX)
	var requested_by_previous_scene := is_instance_valid(GlobalVar) \
		and bool(GlobalVar.get_meta(TEST_REQUEST_META, false))
	_enabled = TEST_ARGUMENT in OS.get_cmdline_args() \
		or launched_from_wrapper \
		or requested_by_previous_scene
	if not _enabled:
		set_process(false)
		return
	if launched_from_wrapper and is_instance_valid(GlobalVar):
		# CooperativeSession 会在启动房主后切换到 coop_test.tscn；用
		# autoload 元数据把“测试请求”跨过这次场景切换传给地图内的
		# 同一个控制器，而不改变普通 coop_test 的启动行为。
		GlobalVar.set_meta(TEST_REQUEST_META, true)
	print("[CoopRemoteYawSmoke] enabled; host-only NormalDrone yaw/pitch smoke test")
	_create_status_panel()


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if not CooperativeSession.is_active():
		_ensure_test_host_session()
		return
	if not CooperativeSession.is_host():
		_set_status("当前合作会话不是房主；此冒烟测试只接受 Host 端。")
		return
	if not CooperativeSession.is_active() or not CooperativeSession.authority_ready:
		_set_status("房主会话已建立，正在加载 coop_test 和初始化权威…")
		return
	_player = _find_local_player()
	if not is_instance_valid(_player):
		_set_status("等待本地房主玩家…")
		return
	if not _grant_requested:
		_grant_requested = true
		# Use the existing host debug-grant path so the authoritative backpack
		# state and the listen-server's local player slots are updated together.
		GameAuthority.local_team_chat(
			_player.authority_peer_id,
			"[get] %s 1" % DEVICE_ID,
			"team"
		)
		_set_status("已通过权威背包链路加入 NormalDrone，准备放置…")
		return
	if not _placement_requested and not _player.remote_is_active:
		var slot := _find_tool_slot(_player, DEVICE_ID)
		if slot >= 0:
			_player.call("_select_tool", slot, true)
			_player.call("_use_current_tool")
			_placement_requested = true
			_set_status("已通过正常放置链路放置 NormalDrone；移动鼠标测试 yaw / pitch。")
		else:
			_set_status("等待 NormalDrone 同步到房主玩家背包…")
		return
	if not _player.remote_is_active:
		_set_status("NormalDrone 已放置，等待进入遥控画面…")
		return
	_update_status()


func _ensure_test_host_session() -> void:
	if _auto_host_attempted:
		if not SteamService.initialization_finished:
			_set_status("正在等待 Steam 初始化，以创建测试房主…")
		elif not SteamService.initialized:
			_set_status("Steam 初始化失败，无法自动创建合作房主；请启动 Steam 后重试。")
		return
	if not SteamService.initialization_finished:
		_set_status("正在等待 Steam 初始化，以创建测试房主…")
		return
	_auto_host_attempted = true
	if not SteamService.initialized:
		_set_status("Steam 初始化失败，无法自动创建合作房主；请启动 Steam 后重试。")
		return
	var map_definition := GameMapRegistry.get_map_by_id(TEST_MAP_ID)
	if map_definition.is_empty():
		_set_status("找不到 coop_test 内置地图，测试无法启动。")
		return
	_auto_host_world = CooperativeWorldStorage.create_world({
		"display_name": "Remote Yaw Smoke Test",
		"map_id": TEST_MAP_ID,
		"map_name": str(map_definition.get("display_name", "coop test")),
		"map_icon_path": str(map_definition.get("icon_path", "")),
		"map_scene_path": TEST_MAP_SCENE,
		"map_version": str(map_definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(map_definition.get("map_hash", "")),
		"map_source": str(map_definition.get("source", "builtin")),
		"max_players": 1,
		"host_steam_id": SteamService.steam_id,
		"host_display_name": SteamService.persona_name,
	})
	if _auto_host_world.is_empty():
		_set_status("无法创建测试世界存档。")
		return
	_auto_host_selection = {
		"steam_id": SteamService.steam_id,
		"display_name": SteamService.persona_name,
		"hero_id": "farmer",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
		"ready": true,
	}
	if not SteamService.cooperative_lobby_created.is_connected(_on_test_lobby_created):
		SteamService.cooperative_lobby_created.connect(_on_test_lobby_created)
	if not SteamService.create_cooperative_lobby(_auto_host_world):
		_set_status("Steam Lobby 创建失败，测试无法启动。")
		return
	_set_status("正在自动创建 Steam 合作房主 Lobby…")


func _on_test_lobby_created(_lobby_id: int, _lobby_data: Dictionary) -> void:
	if not _enabled or _auto_host_start_requested or _auto_host_world.is_empty():
		return
	_auto_host_start_requested = true
	if CooperativeSession.start_host(_auto_host_world, _auto_host_selection):
		_set_status("房主 Lobby 已建立，正在加载 coop_test…")
	else:
		_set_status("合作房主启动失败，请查看 Godot 输出日志。")


func _find_local_player() -> GamePlayer:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			return node as GamePlayer
	return null


func _find_tool_slot(player: GamePlayer, tool_id: String) -> int:
	for index in range(player.tool_definitions.size()):
		if str(player.tool_definitions[index].get("id", "")) == tool_id:
			return index
	return -1


func _update_status() -> void:
	var device := _player.remote_tool_node if is_instance_valid(_player) else null
	if not is_instance_valid(device):
		_set_status("遥控状态已打开，但本地设备实例不可用。")
		return
	var camera_pivot := device.find_child("CameraPivot", true, false) as Node3D
	var device_id := _player.call("_remote_device_id", device) as String
	var state: Dictionary = GameAuthority.remote_device_states.get(device_id, {})
	var local_yaw := device.rotation.y
	var authority_yaw := float(state.get("yaw", local_yaw))
	var pitch := camera_pivot.rotation.x if camera_pivot != null else 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_status_time >= STATUS_INTERVAL_SECONDS:
		_last_status_time = now
		print(
			"[CoopRemoteYawSmoke] device=%s local_yaw=%.4f authority_yaw=%.4f "
			+ "pitch=%.4f input=%s process=%s physics=%s camera=%s seq=%d"
			% [
				device_id,
				local_yaw,
				authority_yaw,
				pitch,
				device.is_processing_input(),
				device.is_processing(),
				device.is_physics_processing(),
				_player.remote_control_camera != null and _player.remote_control_camera.current,
				int(state.get("last_input_seq", 0)),
			]
		)
	_set_status(
		"Coop Host NormalDrone 冒烟测试\n"
		+ "鼠标左右：机体 yaw；鼠标上下：CameraPivot pitch\n"
		+ "本地 yaw：%.3f\n权威 yaw：%.3f\npitch：%.3f\n"
		+ "设备输入：%s   process：%s   physics：%s\n"
		+ "相机 current：%s   输入序号：%d\n"
		+ "预期：左右移动时本地 yaw 和权威 yaw 同步变化；上下移动时 pitch 变化。"
		% [
			local_yaw,
			authority_yaw,
			pitch,
			device.is_processing_input(),
			device.is_processing(),
			device.is_physics_processing(),
			_player.remote_control_camera != null and _player.remote_control_camera.current,
			int(state.get("last_input_seq", 0)),
		]
	)


func _create_status_panel() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 250
	add_child(_canvas_layer)
	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 24.0)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#F4E7A1"))
	_status_label.add_theme_color_override("font_shadow_color", Color("#111111"))
	_status_label.add_theme_constant_override("shadow_offset_x", 2)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	_canvas_layer.add_child(_status_label)


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
