extends Node

signal initialization_completed(success: bool, message: String)
signal cooperative_lobby_created(lobby_id: int, lobby_data: Dictionary)
signal cooperative_lobby_joined(lobby_id: int, lobby_data: Dictionary)
signal cooperative_lobby_error(message: String)
signal cooperative_lobby_closed(reason: String)
signal cooperative_lobby_members_changed
signal invite_feedback(message: String)

const COOPERATIVE_MODE_TAG := "farmwar_pve_coop"
const LOBBY_SCHEMA_VERSION := "1"

var initialized := false
var initialization_finished := false
var initialization_message := "正在初始化 Steam..."
var steam_id := 0
var persona_name := ""
var cooperative_lobby_id := 0
var cooperative_lobby_host_steam_id := 0
var _pending_world: Dictionary = {}
var _avatar_texture_cache: Dictionary = {}


func _ready() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_lobby_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_kicked.connect(_on_lobby_kicked)
	call_deferred("_initialize_steam")


func _process(_delta: float) -> void:
	if initialized:
		Steam.run_callbacks()


func create_cooperative_lobby(world: Dictionary) -> bool:
	if not initialized:
		cooperative_lobby_error.emit("Steam 尚未初始化，无法创建合作房间。")
		return false
	if world.is_empty():
		cooperative_lobby_error.emit("合作世界数据无效。")
		return false
	_pending_world = world.duplicate(true)
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, clampi(int(world.get("max_players", 4)), 1, 4))
	return true


func join_cooperative_lobby(lobby_id: int) -> bool:
	if not initialized or lobby_id <= 0:
		return false
	Steam.joinLobby(lobby_id)
	return true


func leave_cooperative_lobby() -> void:
	if is_current_lobby_host():
		_close_cooperative_lobby("房主已离开合作世界，Lobby 已关闭。")
		return
	if initialized and cooperative_lobby_id > 0:
		Steam.leaveLobby(cooperative_lobby_id)
	cooperative_lobby_id = 0
	cooperative_lobby_host_steam_id = 0
	_pending_world.clear()


func invite_friends() -> bool:
	if not initialized:
		invite_feedback.emit("Steam 尚未初始化：请启动 Steam 客户端并重新打开游戏。")
		return false
	if cooperative_lobby_id <= 0:
		invite_feedback.emit("尚未建立 Steam Lobby，无法邀请好友。")
		return false
	Steam.activateGameOverlayInviteDialog(cooperative_lobby_id)
	if OS.has_feature("editor"):
		invite_feedback.emit("已请求 Steam 邀请窗口；Godot 编辑器内不会显示 Overlay，请使用导出的测试包邀请好友。")
	else:
		invite_feedback.emit("已打开 Steam 好友邀请窗口。若窗口未出现，请确认 Steam Overlay 已在 Steam 设置中启用。")
	return true


func get_current_lobby_data() -> Dictionary:
	if cooperative_lobby_id <= 0:
		return _pending_world.duplicate(true)
	return {
		"world_id": Steam.getLobbyData(cooperative_lobby_id, "world_id"),
		"display_name": Steam.getLobbyData(cooperative_lobby_id, "world_name"),
		"map_id": Steam.getLobbyData(cooperative_lobby_id, "map_id"),
		"map_name": Steam.getLobbyData(cooperative_lobby_id, "map_name"),
		"map_icon_path": Steam.getLobbyData(cooperative_lobby_id, "map_icon_path"),
		"map_scene_path": Steam.getLobbyData(cooperative_lobby_id, "map_scene_path"),
		"max_players": int(Steam.getLobbyData(cooperative_lobby_id, "max_players")),
		"death_drop_mode": Steam.getLobbyData(cooperative_lobby_id, "death_drop_mode"),
		"host_steam_id": int(Steam.getLobbyData(cooperative_lobby_id, "host_steam_id")),
		"session_state": Steam.getLobbyData(cooperative_lobby_id, "session_state"),
	}


func is_cooperative_world_running() -> bool:
	return cooperative_lobby_id > 0 \
		and Steam.getLobbyData(cooperative_lobby_id, "session_state") == "running"


func set_cooperative_world_running() -> void:
	if not is_current_lobby_host():
		return
	Steam.setLobbyData(cooperative_lobby_id, "session_state", "running")
	cooperative_lobby_members_changed.emit()


func get_cooperative_lobby_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	if not initialized or cooperative_lobby_id <= 0:
		return members
	var owner_id := Steam.getLobbyOwner(cooperative_lobby_id)
	var member_count := Steam.getNumLobbyMembers(cooperative_lobby_id)
	for index in range(member_count):
		var member_id := Steam.getLobbyMemberByIndex(cooperative_lobby_id, index)
		if member_id <= 0:
			continue
		var display_name := persona_name if member_id == steam_id else Steam.getFriendPersonaName(member_id)
		if display_name.is_empty():
			display_name = "Steam 用户 %d" % member_id
		members.append({
			"steam_id": member_id,
			"display_name": display_name,
			"is_host": member_id == owner_id,
			"avatar": _get_avatar_texture(member_id),
		})
	return members


func _get_avatar_texture(member_id: int) -> Texture2D:
	var cached: Variant = _avatar_texture_cache.get(member_id, null)
	if cached is Texture2D:
		return cached as Texture2D
	var image_handle := Steam.getMediumFriendAvatar(member_id)
	if image_handle <= 0:
		return null
	var image_size: Dictionary = Steam.getImageSize(image_handle)
	if not bool(image_size.get("success", false)):
		return null
	var width := int(image_size.get("width", 0))
	var height := int(image_size.get("height", 0))
	if width <= 0 or height <= 0:
		return null
	var image_rgba: Dictionary = Steam.getImageRGBA(image_handle)
	if not bool(image_rgba.get("success", false)):
		return null
	var rgba := _packed_byte_array(image_rgba.get("buffer", []))
	if rgba.is_empty():
		return null
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	_avatar_texture_cache[member_id] = texture
	return texture


func _packed_byte_array(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value as PackedByteArray
	var result := PackedByteArray()
	if value is Array:
		for item: Variant in value:
			result.append(clampi(int(item), 0, 255))
	return result


func is_current_lobby_host() -> bool:
	return initialized and cooperative_lobby_id > 0 and Steam.getLobbyOwner(cooperative_lobby_id) == steam_id


func _initialize_steam() -> void:
	initialized = Steam.steamInit()
	initialization_finished = true
	if not initialized:
		initialization_message = "Steam 初始化失败：请启动 Steam 客户端并确认 steam_appid.txt。"
		initialization_completed.emit(false, initialization_message)
		return
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	initialization_message = "Steam 已登录：%s" % persona_name
	initialization_completed.emit(true, initialization_message)
	_check_connect_lobby_argument()


func _check_connect_lobby_argument() -> void:
	var arguments := OS.get_cmdline_args()
	for index in range(arguments.size() - 1):
		if str(arguments[index]) == "+connect_lobby":
			join_cooperative_lobby(int(arguments[index + 1]))
			return


func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.Result.RESULT_OK:
		cooperative_lobby_error.emit("创建 Steam 合作房间失败：%s" % result)
		return
	cooperative_lobby_id = lobby_id
	cooperative_lobby_host_steam_id = steam_id
	Steam.setLobbyData(lobby_id, "game_mode", COOPERATIVE_MODE_TAG)
	Steam.setLobbyData(lobby_id, "schema", LOBBY_SCHEMA_VERSION)
	Steam.setLobbyData(lobby_id, "world_id", str(_pending_world.get("world_id", "")))
	Steam.setLobbyData(lobby_id, "world_name", str(_pending_world.get("display_name", "合作农场")))
	Steam.setLobbyData(lobby_id, "map_id", str(_pending_world.get("map_id", "")))
	Steam.setLobbyData(lobby_id, "map_name", str(_pending_world.get("map_name", "")))
	Steam.setLobbyData(lobby_id, "map_icon_path", str(_pending_world.get("map_icon_path", "")))
	Steam.setLobbyData(lobby_id, "map_scene_path", str(_pending_world.get("map_scene_path", "")))
	Steam.setLobbyData(lobby_id, "max_players", str(_pending_world.get("max_players", 4)))
	Steam.setLobbyData(lobby_id, "death_drop_mode", str(_pending_world.get("death_drop_mode", "save")))
	Steam.setLobbyData(lobby_id, "host_steam_id", str(steam_id))
	Steam.setLobbyData(lobby_id, "session_state", "open")
	Steam.setLobbyJoinable(lobby_id, true)
	cooperative_lobby_members_changed.emit()
	cooperative_lobby_created.emit(lobby_id, _pending_world.duplicate(true))


func _on_lobby_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_cooperative_lobby(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: int, response: int) -> void:
	if response != Steam.ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		cooperative_lobby_error.emit("加入 Steam 合作房间失败，响应码：%d" % response)
		return
	if Steam.getLobbyData(lobby_id, "game_mode") != COOPERATIVE_MODE_TAG:
		cooperative_lobby_error.emit("该 Steam Lobby 不是 FarmWar 联机合作世界。")
		Steam.leaveLobby(lobby_id)
		return
	cooperative_lobby_id = lobby_id
	cooperative_lobby_host_steam_id = int(Steam.getLobbyData(lobby_id, "host_steam_id"))
	cooperative_lobby_joined.emit(lobby_id, get_current_lobby_data())
	cooperative_lobby_members_changed.emit()


func _on_lobby_chat_update(lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	_verify_cooperative_lobby_host(lobby_id)
	if lobby_id == cooperative_lobby_id:
		cooperative_lobby_members_changed.emit()


func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int) -> void:
	if success != 0:
		_verify_cooperative_lobby_host(lobby_id)


func _on_lobby_kicked(lobby_id: int, _admin_id: int, _due_to_disconnect: int) -> void:
	if lobby_id == cooperative_lobby_id:
		_close_cooperative_lobby("你已离开合作 Lobby。")


func _verify_cooperative_lobby_host(lobby_id: int) -> void:
	if lobby_id != cooperative_lobby_id or lobby_id <= 0:
		return
	if Steam.getLobbyData(lobby_id, "session_state") == "closed":
		_close_cooperative_lobby("房主已关闭合作世界。")
		return
	if cooperative_lobby_host_steam_id <= 0:
		cooperative_lobby_host_steam_id = int(Steam.getLobbyData(lobby_id, "host_steam_id"))
	if cooperative_lobby_host_steam_id > 0 and Steam.getLobbyOwner(lobby_id) != cooperative_lobby_host_steam_id:
		_close_cooperative_lobby("房主已离开合作 Lobby，世界已关闭。")


func _close_cooperative_lobby(reason: String) -> void:
	var closing_lobby_id := cooperative_lobby_id
	if initialized and closing_lobby_id > 0 and Steam.getLobbyOwner(closing_lobby_id) == steam_id:
		Steam.setLobbyJoinable(closing_lobby_id, false)
		Steam.setLobbyData(closing_lobby_id, "session_state", "closed")
	if initialized and closing_lobby_id > 0:
		Steam.leaveLobby(closing_lobby_id)
	cooperative_lobby_id = 0
	cooperative_lobby_host_steam_id = 0
	_pending_world.clear()
	_avatar_texture_cache.clear()
	cooperative_lobby_closed.emit(reason)
