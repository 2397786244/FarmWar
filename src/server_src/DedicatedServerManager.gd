##
extends Node
class_name DedicatedServerManager

## 服务器进程需要从目录下面读取server_config.json作为开服的配置文件
signal server_started(port: int, max_clients: int)
signal server_failed(reason: String)
signal server_stopped()

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)

signal server_public_info_changed(info: Dictionary)
signal lobby_players_public_info_changed(players_info: Array)

signal match_started(info: Dictionary)


const DEFAULT_PORT := 2002
const DEFAULT_QUERY_PORT := 2003
const DEFAULT_MAX_CLIENTS := 10 # 最大 5v5

const DEFAULT_SERVER_NAME := "Farm Battle Server"
const DEFAULT_MAP_ID := "creston_town"
const DEFAULT_MAP_NAME := "Creston Town"
const DEFAULT_GAME_MODE := "5v5_Battle"
const DEFAULT_METRICS_LOG_INTERVAL_SECONDS := 10.0
const DEFAULT_MATCH_DURATION_MINUTES := 48.0
const DEFAULT_DEATH_DROP_MODE := "save"
const VALID_DEATH_DROP_MODES := ["all", "random", "save"]
const SERVER_WORLD_SCENE_PATH := "res://worlds/creston_town.tscn"

const PUBLIC_STATE_WAITING_PLAYERS := "WAITING_PLAYERS"
const PUBLIC_STATE_IN_GAME := "IN_GAME"

const TEAM_RED := "red"
const TEAM_BLUE := "blue"
const TEAM_MAX_PLAYERS := 5

const VALID_HERO_IDS := [
	"farmer",
	"cook",
	"guard",
	"apothecary",
	"assistant",
	"engineer",
	"mage",
	"prospector",
	"rider",
	"trickster",
]

const VALID_PRIMARY_WEAPON_IDS := [
	"rubber_revolver",
	"flame_gun",
	"freeze_gun",
	"nail_gun",
	"shotgun",
	"hunting_rifle",
	"eater",
	"sprout_blaster",
	"wreck",
]

const VALID_SPECIAL_TOOL_IDS_BY_HERO := {
	"farmer": ["plant_protector", "fertilizer", "farm_runner"],
	"cook": ["spicy_blaster", "field_kitchen", "auto_cooker"],
	"guard": ["anti_air", "shield_door", "auto_shooter", "area_protector"],
	"apothecary": ["medicine_pistol", "medicine_cannon", "tranquilizer_pistol"],
	"assistant": ["normal_drone", "wheat_sentry", "cargo_shield"],
	"engineer": ["signal_jam", "tech_drone", "small_mouse"],
	"mage": ["wand", "bug_cannon", "rift_book"],
	"prospector": ["signal_augment", "prospect_scanner", "survey_rider"],
	"rider": ["repair_welder", "vehicle_shield_shooter", "boom_buggy"],
	"trickster": ["big_mouth", "trap", "fake_player"],
}


enum MatchState {
	WAITING_PLAYERS,
	IN_GAME
}


var peer: ENetMultiplayerPeer

var port := DEFAULT_PORT
var query_port := DEFAULT_QUERY_PORT
var max_clients := DEFAULT_MAX_CLIENTS

var server_name := DEFAULT_SERVER_NAME
var current_map_id := DEFAULT_MAP_ID
var current_map_name := DEFAULT_MAP_NAME
var game_mode := DEFAULT_GAME_MODE
var metrics_log_enabled := true
var metrics_log_interval_seconds := DEFAULT_METRICS_LOG_INTERVAL_SECONDS
var public_info_log_enabled := false
var match_duration_minutes := DEFAULT_MATCH_DURATION_MINUTES
var death_drop_mode := DEFAULT_DEATH_DROP_MODE
var public_info_broadcast_accumulator := 0.0

var match_state := MatchState.WAITING_PLAYERS
var match_started_unix_time := 0
var match_end_unix_time := 0
var server_world: Node3D

# peer_id -> player_info
var players := {}
var team_rng := RandomNumberGenerator.new()


# ============================================================
# 一、生命周期
# ============================================================

func _ready() -> void:
	add_to_group("dedicated_server_manager")
	team_rng.randomize()
	# 1. 先读取 JSON 配置。
	_load_server_config()
	#
	## 2. 命令行参数优先级高于 JSON 配置。
	#port = _get_arg_int("--port", port)
	#query_port = _get_arg_int("--query-port", query_port)
	#max_clients = _get_arg_int("--max-clients", max_clients)
	#server_name = _get_arg_string("--server-name", server_name)
	#current_map_id = _get_arg_string("--map-id", current_map_id)
	#current_map_name = _get_arg_string("--map-name", current_map_name)
	#game_mode = _get_arg_string("--game-mode", game_mode)

	# 3. 启动 ENet 专用服务器。
	_configure_status_query_server()
	GameAuthority.enable_metrics_periodic_log(metrics_log_enabled, metrics_log_interval_seconds)
	start_server(port, max_clients)


func _process(delta: float) -> void:
	if match_state != MatchState.IN_GAME:
		return
	public_info_broadcast_accumulator += delta
	if public_info_broadcast_accumulator >= 1.0:
		public_info_broadcast_accumulator = 0.0
		_emit_and_broadcast_server_public_info()
	if get_match_remaining_seconds() <= 0:
		_finish_match_due_to_time_limit()


# ============================================================
# 二、配置读取
# ============================================================

# 作用：
# 从 server_config.json 读取服务器基础配置。
#
# 支持读取：
# - server_name
# - map_id
# - map_name
# - game_mode
# - port
	# - query_port
	# - max_clients
# - match_duration_minutes
# - death_drop_mode: all / random / save
func _load_server_config() -> void:
	var config_path := _get_server_config_path()

	if config_path.is_empty():
		print("没有找到 server_config.json，使用默认服务器配置。")
		return

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		print("无法打开服务器配置文件：", config_path)
		print("使用默认服务器配置。")
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)

	if err != OK:
		print("服务器配置 JSON 解析失败：", json.get_error_message())
		print("错误行：", json.get_error_line())
		print("使用默认服务器配置。")
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		print("服务器配置文件根节点不是 Dictionary，使用默认服务器配置。")
		return

	_apply_config_dictionary(data)

	print("服务器配置加载完成：", config_path)


# 作用：
# 寻找 server_config.json 的位置。
#
# 优先级：
# 1. 命令行 --config 指定的路径
# 2. 可执行文件同目录下的 server_config.json
# 3. 项目内部 res://server/server_config.json
func _get_server_config_path() -> String:
	var arg_config_path := _get_arg_string("--config", "")
	if not arg_config_path.is_empty():
		if FileAccess.file_exists(arg_config_path):
			return arg_config_path

		print("命令行指定的配置文件不存在：", arg_config_path)

	var executable_path := OS.get_executable_path()
	if not executable_path.is_empty():
		var executable_dir := executable_path.get_base_dir()
		var external_config_path := executable_dir.path_join("server_config.json")

		if FileAccess.file_exists(external_config_path):
			return external_config_path

	var res_config_path := "res://server/server_config.json"
	if FileAccess.file_exists(res_config_path):
		return res_config_path

	return ""


# 作用：
# 把 JSON Dictionary 应用到服务器变量上。
func _apply_config_dictionary(data: Dictionary) -> void:
	server_name = str(data.get("server_name", server_name))
	current_map_id = str(data.get("map_id", current_map_id))
	current_map_name = str(data.get("map_name", current_map_name))
	game_mode = str(data.get("game_mode", game_mode))

	port = int(data.get("port", port))
	query_port = int(data.get("query_port", query_port))
	max_clients = int(data.get("max_clients", max_clients))
	metrics_log_enabled = bool(data.get("metrics_log_enabled", metrics_log_enabled))
	metrics_log_interval_seconds = float(data.get("metrics_log_interval_seconds", metrics_log_interval_seconds))
	public_info_log_enabled = bool(data.get("public_info_log_enabled", public_info_log_enabled))
	match_duration_minutes = maxf(1.0, float(data.get("match_duration_minutes", match_duration_minutes)))
	var configured_death_drop_mode := str(data.get("death_drop_mode", death_drop_mode)).strip_edges().to_lower()
	if VALID_DEATH_DROP_MODES.has(configured_death_drop_mode):
		death_drop_mode = configured_death_drop_mode
	else:
		push_warning("无效的 death_drop_mode：%s，改用 %s。" % [configured_death_drop_mode, DEFAULT_DEATH_DROP_MODE])
		death_drop_mode = DEFAULT_DEATH_DROP_MODE


func get_death_drop_mode() -> String:
	return death_drop_mode


func _configure_status_query_server() -> void:
	var query_server := get_node_or_null("StatusQueryServer") as StatusQueryServer
	if query_server == null:
		return
	query_server.query_port = query_port
	query_server.server_manager = self
	query_server.start_query_server()


# 作用：
# 从命令行读取 int 参数。
#
# 例子：
# --port 2002
# --query-port 2003
# --max-clients 10
func _get_arg_int(name: String, default_value: int) -> int:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)

	if index == -1:
		return default_value

	if index + 1 >= args.size():
		return default_value

	return int(args[index + 1])


# 作用：
# 从命令行读取 String 参数。
#
# 例子：
# --config /home/ubuntu/farm_server/server_config.json
# --server-name "Farm Server 01"
func _get_arg_string(name: String, default_value: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)

	if index == -1:
		return default_value

	if index + 1 >= args.size():
		return default_value

	return str(args[index + 1])


# ============================================================
# 三、ENet 服务器启动 / 关闭
# ============================================================

# 作用：
# 创建 ENet 服务端，并开始监听 UDP 端口。
func start_server(server_port: int, server_max_clients: int) -> bool:
	if server_port <= 0 or server_port > 65535:
		server_failed.emit("服务器端口必须在 1 到 65535 之间。")
		return false

	if server_max_clients <= 0:
		server_failed.emit("最大客户端数量必须大于 0。")
		return false

	# 如果之前已经有 peer，先清理。
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	peer = ENetMultiplayerPeer.new()

	var err := peer.create_server(server_port, server_max_clients)
	if err != OK:
		peer = null
		multiplayer.multiplayer_peer = null
		server_failed.emit("创建 ENet 服务端失败，错误码：%d。" % err)
		return false

	multiplayer.multiplayer_peer = peer

	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	match_state = MatchState.WAITING_PLAYERS
	match_started_unix_time = 0
	match_end_unix_time = 0
	public_info_broadcast_accumulator = 0.0
	players.clear()
	GameAuthority.start_server_mode(self)
	_connect_game_authority_signals()

	print("====================================")
	print("ENet 专用服务器启动成功。")
	print("服务器名：", server_name)
	print("监听 UDP 端口：", server_port)
	print("最大客户端数量：", server_max_clients)
	print("地图：%s (%s)" % [current_map_name, current_map_id])
	print("游戏模式：", game_mode)
	print("死亡掉落模式：", death_drop_mode)
	print("公开状态：", get_public_state_text())
	print("====================================")

	server_started.emit(server_port, server_max_clients)
	_emit_and_broadcast_server_public_info()

	return true


# 作用：
# 关闭 ENet 服务端。
func stop_server() -> void:
	var query_server := get_node_or_null("StatusQueryServer") as StatusQueryServer
	if query_server != null:
		query_server.stop_query_server()

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()

	multiplayer.multiplayer_peer = null
	peer = null

	players.clear()
	match_state = MatchState.WAITING_PLAYERS
	match_started_unix_time = 0
	match_end_unix_time = 0
	public_info_broadcast_accumulator = 0.0
	if is_instance_valid(server_world):
		server_world.queue_free()
	server_world = null
	GlobalVar.gameworld = null
	GameAuthority.stop_authority()

	print("ENet 专用服务器已关闭。")

	server_stopped.emit()


# ============================================================
# 四、玩家连接管理
# ============================================================

# 作用：
# 客户端连接进服务器时自动触发。
func _on_peer_connected(peer_id: int) -> void:
	print("客户端连接：", peer_id)

	if not can_accept_new_player():
		print("服务器当前不接受新玩家，断开 peer_id：", peer_id)

		if peer != null:
			peer.disconnect_peer(peer_id)

		return

	var player_info := _create_empty_player_info(peer_id)
	player_info["assigned_team"] = _assign_balanced_team_for_peer(peer_id)
	players[peer_id] = player_info

	client_connected.emit(peer_id)

	print("当前玩家数量：%d / %d" % [players.size(), max_clients])

	# 给新玩家单独发送一次当前服务器公开信息。
	_send_server_public_info_to_peer(peer_id)

	# 给所有玩家广播服务器公开信息和大厅玩家列表。
	_emit_and_broadcast_server_public_info()
	_broadcast_lobby_players_public_info()


# 作用：
# 客户端断开连接时自动触发。
func _on_peer_disconnected(peer_id: int) -> void:
	print("客户端断开：", peer_id)

	if players.has(peer_id):
		players.erase(peer_id)
		GameAuthority.unregister_player(peer_id)

	client_disconnected.emit(peer_id)

	print("当前玩家数量：%d / %d" % [players.size(), max_clients])

	if match_state == MatchState.IN_GAME and players.is_empty():
		_reset_match_to_waiting_players()

	_emit_and_broadcast_server_public_info()
	_broadcast_lobby_players_public_info()


# 作用：
# 判断服务器现在是否允许新玩家加入。
func can_accept_new_player() -> bool:
	if match_state != MatchState.WAITING_PLAYERS:
		return false

	if players.size() >= max_clients:
		return false

	return true


# 作用：
# 创建一个刚连接进来的玩家默认数据。
#
# 字段说明：
# - hero_id：前端选人界面产生的职业角色 id，例如 farmer/cook/assistant。
# - primary_weapon_ids：前端主武器页选择的 3 个通用主武器。
# - special_tool_ids：前端职业专属页选择的 2 个专属武器/道具。
# - assigned_team：服务器在连接时预分配的队伍，不直接公开给客户端。
# - raw_loadout：保留客户端原始选择字典，方便调试；正式逻辑只信任服务器验证后的字段。
func _create_empty_player_info(peer_id: int) -> Dictionary:
	return {
		"peer_id": peer_id,
		"display_name": "Player_%d" % peer_id,
		"team": "",
		"assigned_team": "",
		"hero_id": "",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
		"ready": false,
		"connected": true,
		"raw_loadout": {}
	}


# ============================================================
# 五、玩家提交角色 / 道具 / 队伍信息
# ============================================================

# 作用：
# 客户端选择好角色、道具后，通过 RPC 发给服务器。
# 队伍不再相信客户端提交值，由服务器按人数平衡规则分配。
#
# 客户端调用示例：
#
# var setup := {
#     "display_name": "PlayerName",
#     "hero_id": "farmer",
#     "primary_weapon_ids": ["rubber_revolver", "flame_gun", "nail_gun"],
#     "special_tool_ids": ["plant_protector", "farm_runner"],
#     "ready": true
# }
#
# DedicatedServerManager.request_submit_player_setup.rpc_id(1, setup)
@rpc("any_peer", "reliable")
func request_submit_player_setup(setup_data: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if not players.has(sender_id):
		print("收到未知玩家的 setup 数据：", sender_id)
		return

	if match_state != MatchState.WAITING_PLAYERS:
		print("比赛已经开始，拒绝修改玩家配置：", sender_id)
		return

	var parsed_data := parse_player_setup_dictionary(setup_data)

	if parsed_data.is_empty():
		print("玩家配置解析失败：", sender_id)
		print("原始数据：", setup_data)
		_send_player_setup_rejected(sender_id, "角色或装备配置不合法。")
		return

	var assigned_team := str(players[sender_id].get("assigned_team", ""))
	if assigned_team.is_empty():
		assigned_team = _assign_balanced_team_for_peer(sender_id)
		players[sender_id]["assigned_team"] = assigned_team
	if assigned_team.is_empty():
		print("队伍分配失败，服务器队伍已满：", sender_id)
		_send_player_setup_rejected(sender_id, "服务器队伍已满。")
		return

	parsed_data["team"] = assigned_team
	_apply_player_setup(sender_id, parsed_data)

	print("玩家 %d 提交配置：" % sender_id)
	print(players[sender_id])

	_send_player_setup_confirmed(sender_id)
	_emit_and_broadcast_server_public_info()
	_broadcast_lobby_players_public_info()

	_try_start_match()


# 作用：
# 解析客户端发来的 Dictionary。
#
# 你后面可以替换这个函数。
# 这里现在只是一个临时可用版本。
#
# 这个函数按前端 MultiplayerLoadoutSelect.get_selection() 产生的 Dictionary 验证：
# {
#   "hero_id": "farmer",
#   "primary_weapon_ids": ["rubber_revolver", "flame_gun", "nail_gun"],
#   "special_tool_ids": ["plant_protector", "farm_runner"],
#   "ready": true
# }
#
# 服务端只接受验证后的字段；客户端传来的 team/ready/raw_loadout 等不作为权威依据。
func parse_player_setup_dictionary(setup_data: Dictionary) -> Dictionary:
	var result := {}

	var display_name := str(setup_data.get("display_name", ""))
	var hero_id := str(setup_data.get("hero_id", setup_data.get("character_id", "")))

	display_name = display_name.strip_edges()
	hero_id = _normalize_hero_id(hero_id.strip_edges())

	if display_name.is_empty():
		display_name = "Player_%d" % multiplayer.get_remote_sender_id()
	display_name = display_name.substr(0, 24)

	if not VALID_HERO_IDS.has(hero_id):
		return {}

	var primary_weapon_ids := _parse_unique_string_array(
		setup_data.get("primary_weapon_ids", []),
		3
	)
	if primary_weapon_ids.size() != 3:
		return {}

	for weapon_id: String in primary_weapon_ids:
		if not VALID_PRIMARY_WEAPON_IDS.has(weapon_id):
			return {}

	var special_tool_ids := _parse_unique_string_array(
		setup_data.get("special_tool_ids", []),
		2
	)
	if special_tool_ids.size() != 2:
		return {}

	var allowed_special_ids: Array = VALID_SPECIAL_TOOL_IDS_BY_HERO.get(hero_id, [])
	for tool_id: String in special_tool_ids:
		if not allowed_special_ids.has(tool_id):
			return {}

	if not bool(setup_data.get("ready", true)):
		return {}

	result["display_name"] = display_name
	result["hero_id"] = hero_id
	result["primary_weapon_ids"] = primary_weapon_ids
	result["special_tool_ids"] = special_tool_ids
	result["ready"] = true
	result["raw_loadout"] = setup_data.duplicate(true)

	return result


func _parse_unique_string_array(value: Variant, expected_size: int) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		var item_id := str(item).strip_edges()
		if item_id.is_empty() or result.has(item_id):
			continue
		result.append(item_id)
		if result.size() > expected_size:
			return []
	return result


func _normalize_hero_id(hero_id: String) -> String:
	return hero_id


func _assign_balanced_team_for_peer(submitting_peer_id: int) -> String:
	var blue_count := 0
	var red_count := 0

	for peer_id in players.keys():
		if int(peer_id) == submitting_peer_id:
			continue
		var p: Dictionary = players[peer_id]
		var counted_team := str(p.get("assigned_team", p.get("team", "")))
		if counted_team.is_empty():
			counted_team = str(p.get("team", ""))
		match counted_team:
			TEAM_BLUE:
				blue_count += 1
			TEAM_RED:
				red_count += 1

	if blue_count >= TEAM_MAX_PLAYERS and red_count >= TEAM_MAX_PLAYERS:
		return ""
	if blue_count >= TEAM_MAX_PLAYERS:
		return TEAM_RED
	if red_count >= TEAM_MAX_PLAYERS:
		return TEAM_BLUE
	if blue_count < red_count:
		return TEAM_BLUE
	if red_count < blue_count:
		return TEAM_RED
	return TEAM_BLUE if team_rng.randi_range(0, 1) == 0 else TEAM_RED


# 作用：
# 把已经解析并验证后的玩家配置写入 players 字典。
func _apply_player_setup(peer_id: int, parsed_data: Dictionary) -> void:
	if not players.has(peer_id):
		return

	var p: Dictionary = players[peer_id]

	p["display_name"] = parsed_data.get("display_name", p.get("display_name", "Player_%d" % peer_id))
	p["team"] = parsed_data.get("team", p.get("team", ""))
	p["hero_id"] = parsed_data.get("hero_id", p.get("hero_id", ""))
	p["primary_weapon_ids"] = parsed_data.get(
		"primary_weapon_ids",
		p.get("primary_weapon_ids", [])
	)
	p["special_tool_ids"] = parsed_data.get(
		"special_tool_ids",
		p.get("special_tool_ids", [])
	)
	p["ready"] = bool(parsed_data.get("ready", true))
	p["raw_loadout"] = parsed_data.get("raw_loadout", parsed_data)

	players[peer_id] = p
	GameAuthority.register_or_update_player(peer_id, _make_authoritative_selection_for_peer(peer_id))


# 作用：
# 判断单个玩家是否完成了开局前配置。
func _is_player_setup_complete(peer_id: int) -> bool:
	if not players.has(peer_id):
		return false

	var p: Dictionary = players[peer_id]

	if str(p.get("team", "")).is_empty():
		return false

	if str(p.get("hero_id", "")).is_empty():
		return false

	var primary_ids: Array = p.get("primary_weapon_ids", [])
	if primary_ids.size() != 3:
		return false

	var special_ids: Array = p.get("special_tool_ids", [])
	if special_ids.size() != 2:
		return false

	if not bool(p.get("ready", false)):
		return false

	return true


# 作用：
# 判断所有玩家是否都完成了角色 / 道具 / 队伍选择。
func _all_players_have_completed_setup() -> bool:
	for peer_id in players.keys():
		if not _is_player_setup_complete(peer_id):
			return false

	return true


# ============================================================
# 六、战局公开信息
# ============================================================

# 作用：
# 生成一份给客户端 UI 显示的服务器公开信息。
#
# 玩家界面主要看：
# - WAITING_PLAYERS
# - IN_GAME
#
# 等待阶段也显示地图名，方便客户端战局准备页顶部展示将要进入的地图。
func get_server_public_info() -> Dictionary:
	var info := {
		"server_name": server_name,
		"state": get_public_state_text(),
		"map_id": current_map_id,
		"map_name": current_map_name,
		"game_mode": game_mode,
		"current_players": players.size(),
		"max_players": max_clients,
		"red_players": get_team_count(TEAM_RED),
		"blue_players": get_team_count(TEAM_BLUE),
		"scores": GlobalVar.get_team_scores(),
		"can_join": can_accept_new_player(),
		"elapsed_time": get_match_elapsed_seconds(),
		"remaining_time_seconds": get_match_remaining_seconds(),
		"match_duration_seconds": get_match_duration_seconds(),
		"match_duration_minutes": match_duration_minutes,
		"death_drop_mode": death_drop_mode,
	}
	info["metrics"] = GameAuthority.get_server_metrics_public_info()
	return info


func get_connected_peer_count() -> int:
	return players.size()


func _reset_match_to_waiting_players() -> void:
	print("战局内所有玩家已退出，重置为 WAITING_PLAYERS。")
	match_state = MatchState.WAITING_PLAYERS
	match_started_unix_time = 0
	match_end_unix_time = 0
	public_info_broadcast_accumulator = 0.0
	if is_instance_valid(server_world):
		server_world.queue_free()
	server_world = null
	GlobalVar.gameworld = null
	GlobalVar.reset_team_storage()
	GameAuthority.start_server_mode(self)


# 作用：
# 返回给玩家看的公开状态。
func get_public_state_text() -> String:
	if match_state == MatchState.IN_GAME:
		return PUBLIC_STATE_IN_GAME

	return PUBLIC_STATE_WAITING_PLAYERS


# 作用：
# 统计某个队伍的人数。
func get_team_count(team_name: String) -> int:
	var count := 0

	for peer_id in players.keys():
		var p: Dictionary = players[peer_id]
		if str(p.get("team", "")) == team_name:
			count += 1

	return count


# 作用：
# 如果比赛已经开始，返回已经进行的秒数。
func get_match_elapsed_seconds() -> int:
	if match_state != MatchState.IN_GAME:
		return 0

	if match_started_unix_time <= 0:
		return 0

	return int(Time.get_unix_time_from_system()) - match_started_unix_time


func get_match_duration_seconds() -> int:
	return maxi(60, int(round(match_duration_minutes * 60.0)))


func get_match_remaining_seconds() -> int:
	if match_state != MatchState.IN_GAME:
		return get_match_duration_seconds()
	if match_end_unix_time <= 0:
		return get_match_duration_seconds()
	return maxi(0, match_end_unix_time - int(Time.get_unix_time_from_system()))


# 作用：
# 生成大厅玩家公开信息。
#
# 这个信息可以给客户端 UI 显示红蓝队列表。
func get_lobby_players_public_info() -> Array:
	var result := []

	for peer_id in players.keys():
		var p: Dictionary = players[peer_id]

		result.append({
			"peer_id": peer_id,
			"display_name": p.get("display_name", "Player_%d" % peer_id),
			"team": p.get("team", ""),
			"hero_id": p.get("hero_id", ""),
			"character_id": p.get("hero_id", ""), # 兼容旧客户端字段名。
			"primary_weapon_ids": p.get("primary_weapon_ids", []),
			"special_tool_ids": p.get("special_tool_ids", []),
			"ready": bool(p.get("ready", false)),
			"connected": bool(p.get("connected", true))
		})

	return result


# ============================================================
# 七、广播给客户端
# ============================================================

# 作用：
# 在服务器内部发信号，同时通过 RPC 广播服务器公开信息。
func _emit_and_broadcast_server_public_info() -> void:
	var info := get_server_public_info()

	server_public_info_changed.emit(info)

	if public_info_log_enabled:
		print("公开战局信息：", info)

	if multiplayer.multiplayer_peer != null:
		receive_server_public_info.rpc(info)


# 作用：
# 只给某一个玩家发送服务器公开信息。
func _send_server_public_info_to_peer(peer_id: int) -> void:
	var info := get_server_public_info()

	if multiplayer.multiplayer_peer != null and _is_peer_connected(peer_id):
		receive_server_public_info.rpc_id(peer_id, info)


# 作用：
# 广播大厅玩家列表。
func _broadcast_lobby_players_public_info() -> void:
	var lobby_players := get_lobby_players_public_info()

	lobby_players_public_info_changed.emit(lobby_players)

	if multiplayer.multiplayer_peer != null:
		# lobby_players 包含战局中所有玩家的公开可显示信息：
		# peer_id、display_name、team、hero_id、已选择装备摘要、ready、connected。
		# 客户端战局准备页用它刷新红蓝队 5 个格子。
		receive_lobby_players_public_info.rpc(lobby_players)


func _connect_game_authority_signals() -> void:
	if not GameAuthority.world_snapshot_ready.is_connected(_on_world_snapshot_ready):
		GameAuthority.world_snapshot_ready.connect(_on_world_snapshot_ready)
	if not GameAuthority.reliable_world_event_ready.is_connected(_on_reliable_world_event_ready):
		GameAuthority.reliable_world_event_ready.connect(_on_reliable_world_event_ready)
	if not GameAuthority.visual_world_event_ready.is_connected(_on_visual_world_event_ready):
		GameAuthority.visual_world_event_ready.connect(_on_visual_world_event_ready)
	if not GameAuthority.inventory_state_ready.is_connected(_on_inventory_state_ready):
		GameAuthority.inventory_state_ready.connect(_on_inventory_state_ready)
	if not GameAuthority.player_correction_ready.is_connected(_on_player_correction_ready):
		GameAuthority.player_correction_ready.connect(_on_player_correction_ready)
	if not GameAuthority.team_chat_message_ready.is_connected(_on_team_chat_message_ready):
		GameAuthority.team_chat_message_ready.connect(_on_team_chat_message_ready)


func _on_world_snapshot_ready(snapshot: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or match_state != MatchState.IN_GAME:
		return
	for peer_id_value in players.keys():
		var peer_id := int(peer_id_value)
		if not _is_peer_connected(peer_id):
			continue
		var tailored_snapshot := snapshot.duplicate(true)
		var team := str(players[peer_id].get("team", ""))
		tailored_snapshot["event_board"] = EventBoard.get_state_for_team(team)
		receive_world_snapshot.rpc_id(peer_id, tailored_snapshot)


func _on_reliable_world_event_ready(event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var event_type := str(event.get("type", ""))
	if event_type == "hit_confirmed":
		var attacker_peer_id := int(event.get("attacker_peer_id", 0))
		if attacker_peer_id > 0 and _is_peer_connected(attacker_peer_id):
			receive_hit_confirmation.rpc_id(attacker_peer_id, event)
		return
	if event_type == "weapon_ammo_state":
		var owner_peer_id := int(event.get("peer_id", 0))
		if owner_peer_id > 0 and _is_peer_connected(owner_peer_id):
			receive_reliable_world_event.rpc_id(owner_peer_id, event)
		return
	if event_type in ["cargo_car_action_result", "cargo_delivery_preview", "cargo_delivery_result"]:
		var cargo_peer_id := int(event.get("peer_id", 0))
		if cargo_peer_id <= 0:
			var cargo_data: Variant = event.get("data", {})
			if cargo_data is Dictionary:
				cargo_peer_id = int((cargo_data as Dictionary).get("peer_id", 0))
		if cargo_peer_id > 0 and _is_peer_connected(cargo_peer_id):
			receive_reliable_world_event.rpc_id(cargo_peer_id, event)
		return
	if event_type == "action_reward":
		var rewarded_peer_id := int(event.get("peer_id", 0))
		if rewarded_peer_id > 0 and _is_peer_connected(rewarded_peer_id):
			receive_reliable_world_event.rpc_id(rewarded_peer_id, event)
		return
	if event_type == "team_money_changed":
		var target_team := str(event.get("team", ""))
		for peer_id_value in players.keys():
			var peer_id := int(peer_id_value)
			if _is_peer_connected(peer_id) \
					and str(players[peer_id].get("team", "")) == target_team:
				receive_reliable_world_event.rpc_id(peer_id, event)
		return
	if event_type == "remote_device_damaged":
		var controller_peer_id := int(event.get("controller_peer_id", 0))
		if controller_peer_id > 0 and _is_peer_connected(controller_peer_id):
			receive_reliable_world_event.rpc_id(controller_peer_id, event)
		return
	if event_type == "vehicle_damaged":
		var occupants_value: Variant = event.get("occupant_peer_ids", [])
		if occupants_value is Array:
			for peer_id_value: Variant in occupants_value:
				var peer_id := int(peer_id_value)
				if peer_id > 0 and _is_peer_connected(peer_id):
					receive_reliable_world_event.rpc_id(peer_id, event)
		return
	if event_type in ["low_frequency_snapshot", "farm_reconcile_chunk"]:
		receive_bulk_world_event.rpc(event)
		return
	if event_type == "event_board_state":
		for peer_id_value in players.keys():
			var peer_id := int(peer_id_value)
			if not _is_peer_connected(peer_id):
				continue
			var team := str(players[peer_id].get("team", ""))
			receive_reliable_world_event.rpc_id(peer_id, {
				"type": "event_board_state",
				"data": EventBoard.get_state_for_team(team),
				"tick": int(event.get("tick", GameAuthority.server_tick)),
			})
		return
	receive_reliable_world_event.rpc(event)


func _on_visual_world_event_ready(event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or match_state != MatchState.IN_GAME:
		return
	receive_visual_world_event.rpc(event)


func _on_inventory_state_ready(state: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	receive_inventory_state.rpc(state)


func _on_player_correction_ready(peer_id: int, correction: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or match_state != MatchState.IN_GAME:
		return
	if not players.has(peer_id) or not bool(players[peer_id].get("connected", false)):
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	if players.has(peer_id) and players[peer_id].has("last_client_time_msec"):
		correction["client_time_msec"] = int(players[peer_id].get("last_client_time_msec", 0))
	receive_player_correction.rpc_id(peer_id, correction)


func _on_team_chat_message_ready(message: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or match_state != MatchState.IN_GAME:
		return
	var recipient_peer_id := int(message.get("recipient_peer_id", 0))
	if recipient_peer_id > 0:
		if _is_peer_connected(recipient_peer_id):
			receive_team_chat_message.rpc_id(recipient_peer_id, message)
		return
	if str(message.get("scope", "team")) == "all":
		for peer_id_value in players.keys():
			var peer_id := int(peer_id_value)
			if _is_peer_connected(peer_id):
				receive_team_chat_message.rpc_id(peer_id, message)
		return
	var team := str(message.get("team", ""))
	if team.is_empty():
		return
	for peer_id_value in players.keys():
		var peer_id := int(peer_id_value)
		if not _is_peer_connected(peer_id):
			continue
		if str(players[peer_id].get("team", "")) == team:
			receive_team_chat_message.rpc_id(peer_id, message)


func _send_player_setup_confirmed(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var selection := _make_authoritative_selection_for_peer(peer_id)
	if multiplayer.multiplayer_peer != null and _is_peer_connected(peer_id):
		receive_player_setup_confirmed.rpc_id(peer_id, selection)


func _send_player_setup_rejected(peer_id: int, reason: String) -> void:
	if multiplayer.multiplayer_peer != null and _is_peer_connected(peer_id):
		receive_player_setup_rejected.rpc_id(peer_id, reason)


func _is_peer_connected(peer_id: int) -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().has(peer_id)


func _make_authoritative_selection_for_peer(peer_id: int) -> Dictionary:
	var p: Dictionary = players.get(peer_id, {})
	return {
		"peer_id": peer_id,
		"display_name": p.get("display_name", "Player_%d" % peer_id),
		"team": p.get("team", ""),
		"hero_id": p.get("hero_id", ""),
		"character_id": p.get("hero_id", ""),
		"primary_weapon_ids": p.get("primary_weapon_ids", []),
		"special_tool_ids": p.get("special_tool_ids", []),
		"ready": bool(p.get("ready", false)),
	}


# 作用：
# 客户端接收服务器公开信息。
#
# 注意：
# 这个 RPC 函数要想在客户端收到，客户端也必须有相同路径的节点和同名函数。
# 后面更推荐把这些 RPC 接收函数拆到 NetworkRpc.gd。
# 客户端已由 ClientServerRpcEndpoint.receive_server_public_info 接收，
# 再通过 MultiplayerNetwork.server_public_info_received 转发给 UI。
#
# 这个信息主要用于“已经连接进服务器后的大厅/战局 UI”。
# 如果要做“未加入前的服务器浏览器”，通常还需要 HTTP/UDP Master Server 或局域网广播；
# ENet 客户端只有连接后才能收到这个 RPC。
@rpc("authority", "reliable")
func receive_server_public_info(info: Dictionary) -> void:
	# 服务端这里不需要处理。
	# 客户端可以在这里刷新服务器状态 UI。
	pass


# 作用：
# 客户端接收大厅玩家列表。
@rpc("authority", "reliable")
func receive_lobby_players_public_info(lobby_players: Array) -> void:
	# 服务端这里不需要处理。
	# 客户端可以在这里刷新红蓝队玩家列表 UI。
	pass


# 作用：
# 客户端接收自己被服务器权威确认后的角色 / 装备 / 队伍结果。
@rpc("authority", "reliable")
func receive_player_setup_confirmed(selection: Dictionary) -> void:
	# 服务端这里不需要处理。
	pass


# 作用：
# 客户端接收配置被服务器拒绝的原因。
@rpc("authority", "reliable")
func receive_player_setup_rejected(reason: String) -> void:
	# 服务端这里不需要处理。
	pass


@rpc("any_peer", "unreliable")
func request_player_input(input_frame: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	players[sender_id]["last_client_time_msec"] = int(input_frame.get("client_time_msec", 0))
	GameAuthority.server_receive_player_input(sender_id, input_frame)


@rpc("any_peer", "reliable")
func request_select_tool(tool_index: int, tool_id := "") -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_select_tool(sender_id, tool_index, tool_id)


@rpc("any_peer", "reliable")
func request_use_tool(tool_request: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_try_use_tool(sender_id, tool_request)


@rpc("any_peer", "reliable")
func request_reload_weapon(tool_id: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_reload_weapon(sender_id, tool_id)


@rpc("any_peer", "reliable")
func request_shop_transaction(transaction: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_shop_transaction(sender_id, transaction)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_farm_action(action: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_farm_action(sender_id, action)


@rpc("any_peer", "reliable")
func request_ingredient_pickup_action(action: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_ingredient_pickup_action(sender_id, action)


@rpc("any_peer", "unreliable")
func request_remote_control_input(input_frame: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_remote_control_input(sender_id, input_frame)


@rpc("any_peer", "reliable")
func request_remote_control_session(device_id: String, connected: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_remote_control_session(sender_id, device_id, connected)


@rpc("any_peer", "reliable")
func request_remote_action(action: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_remote_action(sender_id, action)


@rpc("any_peer", "unreliable")
func request_vehicle_input(input_frame: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_vehicle_input(sender_id, input_frame)


@rpc("any_peer", "reliable")
func request_vehicle_session(vehicle_id: String, connected: bool, seat_index: int = -1) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_vehicle_session(sender_id, vehicle_id, connected, seat_index)


@rpc("any_peer", "call_remote", "reliable", 4)
func request_team_chat(message: String, scope: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or match_state != MatchState.IN_GAME:
		return
	GameAuthority.server_team_chat(sender_id, message, scope)


@rpc("authority", "unreliable")
func receive_world_snapshot(snapshot: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 1)
func receive_reliable_world_event(event: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "unreliable", 5)
func receive_visual_world_event(event: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 2)
func receive_bulk_world_event(event: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 3)
func receive_hit_confirmation(event: Dictionary) -> void:
	pass


@rpc("authority", "reliable")
func receive_inventory_state(state: Dictionary) -> void:
	pass


@rpc("authority", "unreliable")
func receive_player_correction(correction: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable", 4)
func receive_team_chat_message(message: Dictionary) -> void:
	pass


# ============================================================
# 八、开局判断
# ============================================================

# 作用：
# 尝试开始比赛。
func _try_start_match() -> void:
	if not can_start_match():
		return

	start_match()


# 作用：
# 判断是否满足开局条件。
#
# 当前规则：
# 1. 服务器处于 WAITING_PLAYERS
# 2. 玩家总数 >= 4
# 3. 玩家总数 <= max_clients
# 4. 红蓝队人数相同
# 5. 所有玩家都在 red 或 blue
# 6. 所有玩家都完成角色 / 道具 / 队伍选择
#
# 注意：
# 如果你想允许 2v2，把 total_players <= 4 改成 total_players < 4。
func can_start_match() -> bool:
	if match_state != MatchState.WAITING_PLAYERS:
		return false

	var total_players := players.size()

	if total_players < 2:  # WARNING 当前最少2人就可以开服
		return false

	if total_players > max_clients:
		return false

	var red_count := get_team_count(TEAM_RED)
	var blue_count := get_team_count(TEAM_BLUE)

	if red_count != blue_count:
		return false

	if red_count + blue_count != total_players:
		return false

	if not _all_players_have_completed_setup():
		return false

	return true


# ============================================================
# 九、正式开始游戏
# ============================================================

# 作用：
# 正式进入游戏状态。
#
# 这里不要写太多具体战斗逻辑。
# 具体地图加载、玩家生成、农田初始化、炮塔初始化，
# 后面可以拆给 ServerGameWorld / MatchManager / PlayerManager。
func start_match() -> void:
	if match_state == MatchState.IN_GAME:
		return

	match_state = MatchState.IN_GAME
	match_started_unix_time = int(Time.get_unix_time_from_system())
	match_end_unix_time = match_started_unix_time + get_match_duration_seconds()
	public_info_broadcast_accumulator = 0.0

	print("====================================")
	print("开始游戏！")
	print("服务器名：", server_name)
	print("地图：%s (%s)" % [current_map_name, current_map_id])
	print("模式：", game_mode)
	print("玩家数：", players.size())
	print("红队人数：", get_team_count(TEAM_RED))
	print("蓝队人数：", get_team_count(TEAM_BLUE))
	print("战局时长：%.1f 分钟，结束时间戳：%d" % [match_duration_minutes, match_end_unix_time])
	print("死亡掉落模式：", death_drop_mode)
	print("====================================")

	_load_server_world()
	if server_world is FarmWorldInitializer:
		await (server_world as FarmWorldInitializer).wait_until_initialized()
	var spawn_indices := {TEAM_RED: 0, TEAM_BLUE: 0}
	var authoritative_players: Array[Dictionary] = []
	for peer_id in players.keys():
		var authoritative_selection := _make_authoritative_selection_for_peer(int(peer_id))
		authoritative_selection["position"] = _get_spawn_position_for_selection(authoritative_selection, spawn_indices)
		GameAuthority.register_or_update_player(int(peer_id), authoritative_selection)
		authoritative_players.append(authoritative_selection.duplicate(true))

	var info := get_server_public_info()
	info["authoritative_players"] = authoritative_players

	_emit_and_broadcast_server_public_info()
	_on_inventory_state_ready({
		"tick": GameAuthority.server_tick,
		"teams": GlobalVar.team_storage.duplicate(true),
		"scores": GlobalVar.get_team_scores(),
	})

	if multiplayer.multiplayer_peer != null:
		receive_match_started.rpc(info)

	match_started.emit(info)

	_on_start_match_game_logic()


func _finish_match_due_to_time_limit() -> void:
	if match_state != MatchState.IN_GAME:
		return
	print("战局倒计时结束，发送结算结果并等待玩家返回。")
	var final_info := get_server_public_info()
	final_info["remaining_time_seconds"] = 0
	var settlement := {
		"scores": GlobalVar.get_team_scores(),
		"money": {
			"red": int(round(GlobalVar.check_team_item_amount("red", "money"))),
			"blue": int(round(GlobalVar.check_team_item_amount("blue", "money"))),
		},
		"stats": GlobalVar.get_all_team_match_stats(),
	}
	if multiplayer.multiplayer_peer != null:
		receive_reliable_world_event.rpc({
			"type": "match_ended",
			"reason": "time_limit",
			"final_info": final_info,
			"settlement": settlement,
			"tick": GameAuthority.server_tick,
		})
	# 等待客户端在结算页主动返回；不能立即断开，否则可靠事件可能尚未显示。
	match_state = MatchState.WAITING_PLAYERS
	_emit_and_broadcast_server_public_info()


# 作用：
# 开始游戏后的具体逻辑入口。
#
# 你后面可以在这里继续实现：
# 1. 加载服务器地图
# 2. 初始化农田状态
# 3. 初始化队伍分数
# 4. 生成服务器权威玩家实体
# 5. 根据角色和道具配置生成玩家初始装备
# 6. 通知客户端切换到 GameWorld
# 7. 等待客户端加载完成
# 8. 正式开始比赛倒计时
func _on_start_match_game_logic() -> void:
	print("正式游戏逻辑入口：服务器权威地图、玩家代理、战斗同步已启动。")

	for peer_id in players.keys():
		print("玩家开局数据 peer_id=%d data=%s" % [peer_id, str(players[peer_id])])


func _get_spawn_position_for_selection(selection: Dictionary, spawn_indices: Dictionary) -> Vector3:
	var team := str(selection.get("team", TEAM_BLUE))
	var index := int(spawn_indices.get(team, 0))
	spawn_indices[team] = index + 1
	if is_instance_valid(server_world) and server_world.has_method("get_team_spawn_position"):
		return server_world.call(
			"get_team_spawn_position",
			team,
			index,
			match_started_unix_time
		) as Vector3
	return Vector3.ZERO


func _load_server_world() -> void:
	if is_instance_valid(server_world):
		return
	var packed := load(SERVER_WORLD_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("服务端无法加载地图：" + SERVER_WORLD_SCENE_PATH)
		return
	server_world = packed.instantiate() as Node3D
	if server_world == null:
		push_error("服务端地图根节点不是 Node3D：" + SERVER_WORLD_SCENE_PATH)
		return
	add_child(server_world)
	GlobalVar.gameworld = server_world
	print("服务端权威地图已加载：", SERVER_WORLD_SCENE_PATH)


# 作用：
# 客户端接收比赛开始信息。
#
# 客户端收到后可以：
# 1. 关闭大厅 UI
# 2. 切换到游戏场景
# 3. 显示地图名
# 4. 显示游戏模式
# 5. 等待服务器生成玩家
# 客户端已由 ClientServerRpcEndpoint.receive_match_started 接收，
# 再通过 MultiplayerNetwork.match_started_received 转发给 MainMenuRoot。
# 当前 MainMenuRoot 收到后会调用 MultiplayerBattleRoomPage.load_multiplayer_map()。
# 也就是说：客户端当前会加载与服务器一致的 Creston Town 场景；
# 后续正式多人版再把地图内玩家/农田/武器改成服务器权威同步。
@rpc("authority", "reliable")
func receive_match_started(info: Dictionary) -> void:
	# 服务端这里不需要处理。
	# 客户端实现 UI / 切场景逻辑。
	pass
