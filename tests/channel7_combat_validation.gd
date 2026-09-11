extends Node

const PLAYER_SCENE := preload("res://character/player.tscn")

const CHANNEL7_FIRE_IDS := [
	"rubber_revolver", "nail_gun", "suppressed_pistol", "m17", "shotgun", "remington870",
	"hunting_rifle", "crossbow", "m4", "ar15", "ak47", "mpx", "p90",
	"future_m4", "future_mpx",
	"suppressed_pistol_hardenedsteel", "suppressed_pistol_ruralcamo",
	"suppressed_pistol_snowcamo", "m17_snowcamo", "m17_ruralcamo",
	"m17_hardenedsteel", "shotgun_rusted", "remington870_ruralcamo",
	"remington870_snowcamo", "remington870_rusted",
	"remington870_hardenedsteel", "crossbow_hardenedsteel",
	"m4_hardenedsteel", "m4_ruralcamo", "m4_snowcamo",
	"ak47_ruralcamo", "ak47_snowcamo", "ak47_golden", "ak47_rusted",
	"ak47_hardenedsteel", "mpx_hardenedsteel", "mpx_ruralcamo",
	"mpx_snowcamo", "p90_ruralcamo", "p90_snowcamo",
	"ar15_hardenedsteel", "ar15_ruralcamo", "ar15_snowcamo",
]

const NON_CHANNEL7_USE_IDS := [
	"medicine_pistol", "medicine_cannon", "grenade", "repair_welder",
	"vehicle_shield_shooter", "sprout_blaster", "eater", "long_spear",
	"tranquilizer_pistol", "wand", "wreck", "bug_cannon", "spicy_blaster",
	"flame_gun", "freeze_gun",
]

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_combat_classification()
	_validate_rpc_declarations()
	_validate_steam_transport_handshake()
	_validate_combat_visual_event_contract()
	_validate_request_routing()
	_validate_ammo_revision_protection()
	await _validate_ammo_revision_ordering()
	if failures == 0:
		print("[Channel7CombatValidation] PASS all checks")
	else:
		push_error("[Channel7CombatValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _validate_combat_classification() -> void:
	for tool_id: String in CHANNEL7_FIRE_IDS:
		_check(
			CombatBalance.is_channel7_combat_fire_weapon(tool_id),
			"%s uses the Channel 7 combat request profile" % tool_id
		)
	for tool_id: String in NON_CHANNEL7_USE_IDS:
		_check(
			not CombatBalance.is_channel7_combat_fire_weapon(tool_id),
			"%s remains on the normal use_tool request path" % tool_id
		)
	_check(
		CombatBalance.resolve_profile_id("ak47_golden") == "ak47",
		"cosmetic IDs resolve only for combat classification"
	)
	_check(
		CombatBalance.resolve_profile_id("remington870_hardenedsteel") == "remington870",
		"Remington870 cosmetic IDs resolve to their base profile"
	)


func _validate_rpc_declarations() -> void:
	var channel7_rpc_files := [
		"res://src/client_server_rpc_endpoint.gd",
		"res://src/cooperative_session.gd",
		"res://src/server_src/DedicatedServerManager.gd",
	]
	for path: String in channel7_rpc_files:
		var source := _read_source(path)
		for function_name: String in [
			"request_combat_fire", "request_combat_reload_weapon",
			"request_combat_select_tool", "receive_combat_event",
		]:
			_check(
				source.contains(
					"@rpc(\"any_peer\", \"call_remote\", \"reliable\", 7)\nfunc " + function_name
				) if function_name.begins_with("request_") else source.contains(
					"@rpc(\"authority\", \"call_remote\", \"reliable\", 7)\nfunc " + function_name
				),
				"%s declares Channel 7 RPC in %s" % [function_name, path]
			)
	_check(
		_read_source("res://src/multiplayer_network.gd").contains("const ENET_CHANNEL_COUNT := 8"),
		"ENet client reserves at least eight channels"
	)
	_check(
		_read_source("res://src/multiplayer_network.gd").contains(
			"peer.create_client(address, port, ENET_CHANNEL_COUNT)"
		),
		"ENet client creates the peer with Channel 7 available"
	)
	_check(
		_read_source("res://src/server_src/DedicatedServerManager.gd").contains(
			"enet_host.channel_limit(ENET_CHANNEL_COUNT)"
		),
		"dedicated ENet server reserves at least eight channels"
	)
	for path: String in channel7_rpc_files:
		_check(
			_read_source(path).contains(
				"@rpc(\"authority\", \"call_remote\", \"unreliable_ordered\", 5)\nfunc receive_combat_visual_event"
			),
			"combat visual event uses Channel 5 unreliable ordered transport in %s" % path
		)
	_check(
		int(ProjectSettings.get_setting("steam/multiplayer_peer/max_channels", 0)) == 9,
		"Steam peer reserves nine lanes so Godot Channel 7 does not fall back to lane 0"
	)


func _validate_steam_transport_handshake() -> void:
	var session_source := _read_source("res://src/cooperative_session.gd")
	var steam_source := _read_source("res://src/steam_service.gd")
	_check(
		bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false))
			and str(ProjectSettings.get_setting("debug/file_logging/log_path", "")) \
				== "user://logs/godot.log",
		"exported clients persist cooperative diagnostics to user://logs/godot.log"
	)
	_check(
		session_source.contains("const STEAM_MULTIPLAYER_LANE_COUNT := 9")
			and steam_source.contains("const STEAM_MULTIPLAYER_LANE_COUNT := 9"),
		"co-op session and Lobby advertise the same nine-lane Steam configuration"
	)
	_check(
		session_source.contains("const COOP_TRANSPORT_PROTOCOL_VERSION := 2")
			and steam_source.contains("const COOP_TRANSPORT_PROTOCOL_VERSION := 2"),
		"co-op session and Lobby use the same transport protocol version"
	)
	_check(
		session_source.contains(
			"@rpc(\"authority\", \"call_remote\", \"reliable\", 0)\nfunc receive_join_transport_ready"
		),
		"host transport-ready acknowledgement uses reliable Channel 0"
	)
	_check(
		session_source.contains("HOST_TRANSPORT_READY_RETRY_SECONDS := 0.5")
			and session_source.contains("CLIENT_JOIN_REQUEST_RETRY_SECONDS := 1.0"),
		"transport-ready and join requests have bounded reliable retries"
	)
	_check(
		session_source.contains("CLIENT_JOIN_NEGOTIATION_TIMEOUT_SECONDS := 30.0")
			and session_source.contains("Steam 已连接，但加入世界握手超时"),
		"client aborts a stalled post-connect handshake after thirty seconds"
	)
	_check(
		session_source.contains("host_transport_ready_peers.erase(sender_id)")
			and session_source.contains("request_join_world.rpc_id(1, _make_join_request())"),
		"join request acknowledges transport-ready and keeps Channel 1 ordering"
	)
	_check(
		session_source.contains("\"transport_protocol_version\": COOP_TRANSPORT_PROTOCOL_VERSION")
			and session_source.contains("\"steam_lane_count\": STEAM_MULTIPLAYER_LANE_COUNT")
			and session_source.contains("客户端 Steam 合作协议不兼容"),
		"client declares protocol and lane count for host-side handshake validation"
	)
	_check(
		session_source.contains("if client_world_manifest_received:")
			and session_source.contains("duplicate world manifest ignored")
			and session_source.contains("client_world_manifest_received = true"),
		"duplicate manifests cannot load the client world twice"
	)
	_check(
		session_source.contains("not client_transport_handshake_confirmed")
			and session_source.contains("func _process_rtt_probes"),
		"RTT probes wait until transport-ready has been validated"
	)
	_check(
		steam_source.contains("\"transport_protocol_version\"")
			and steam_source.contains("\"steam_lane_count\"")
			and steam_source.contains("Steam 合作协议不兼容"),
		"Steam Lobby advertises and validates protocol and lane metadata"
	)
	_check(
		session_source.contains("[CoopJoin][client]")
			and session_source.contains("func _log_join_stage")
			and session_source.contains("world manifest accepted; loading map")
			and session_source.contains("authoritative world state received"),
		"client log records every join-world handshake boundary"
	)


func _validate_combat_visual_event_contract() -> void:
	var authority_source := _read_source("res://src/game_authority.gd")
	_check(
		authority_source.contains("var is_channel7_weapon := CombatBalance.is_channel7_combat_fire_weapon(tool_id)"),
		"authority classifies the combat visual event with the Channel 7 weapon allowlist"
	)
	_check(
		authority_source.contains("_emit_combat_weapon_fired_event(peer_id, tool_id, result)"),
		"authority emits the dedicated combat weapon visual event"
	)
	_check(
		authority_source.contains("if not is_channel7_weapon:\n\t\treliable_world_event_ready.emit({"),
		"non-Channel 7 tools retain the legacy tool_used event"
	)
	var replicator_source := _read_source("res://src/multiplayer_world_replicator.gd")
	_check(
		replicator_source.contains("_apply_combat_weapon_fired_event(event)"),
		"replicator handles combat weapon visual events separately"
	)
	_check(
		replicator_source.contains("remote_player.play_remote_tool_action")
			and replicator_source.contains("remote_player.play_remote_tool_visual"),
		"combat visual event drives remote animation and muzzle presentation"
	)
	for path: String in ["res://src/cooperative_session.gd", "res://src/server_src/DedicatedServerManager.gd"]:
		var source := _read_source(path)
		_check(
			source.contains("str(event.get(\"type\", \"\")) == \"combat_weapon_fired\""),
			"%s routes combat weapon visuals through the dedicated RPC" % path
		)


func _validate_request_routing() -> void:
	var player_source := _read_source("res://src/player.gd")
	_check(
		player_source.contains("MultiplayerNetwork.submit_combat_fire(tool_request)"),
		"player routes eligible weapon fire through Channel 7"
	)
	_check(
		player_source.contains("MultiplayerNetwork.submit_reload_weapon(tool_id)"),
		"player routes reload requests through the weapon channel selector"
	)
	var network_source := _read_source("res://src/multiplayer_network.gd")
	_check(
		network_source.contains("submit_combat_select_tool(tool_index, tool_id)"),
		"player selection uses the Channel 7 wrapper"
	)
	_check(
		network_source.contains("NetworkSession.submit_action(\"select_tool\","),
		"non-Channel 7 tool selection uses the legacy request path"
	)
	_check(
		network_source.contains("NetworkSession.submit_action(\"reload_weapon\","),
		"non-Channel 7 reload uses the legacy request path"
	)
	_check(
		network_source.contains("\"use_tool\": rpc_endpoint.submit_use_tool(payload)"),
		"non-combat use_tool remains on the legacy endpoint"
	)
	_check(
		_read_source("res://src/cooperative_session.gd").contains("receive_combat_event.rpc(event)"),
		"co-op broadcasts shared combat events through Channel 7"
	)
	_check(
		_read_source("res://src/server_src/DedicatedServerManager.gd").contains("receive_combat_event.rpc_id(owner_peer_id, event)"),
		"dedicated server sends private ammo events through Channel 7"
	)


func _validate_ammo_revision_protection() -> void:
	var authority_source := _read_source("res://src/game_authority.gd")
	var player_source := _read_source("res://src/player.gd")
	_check(authority_source.contains("\"ammo_revision\""), "authority state carries ammo revisions")
	_check(
		authority_source.contains("ammo_state[\"ammo_revision\"] = int(ammo_state.get(\"ammo_revision\", 0)) + 1"),
		"authority increments ammo revisions on combat changes"
	)
	_check(
		authority_source.contains("\"ammo_revision\": int(ammo_state.get(\"ammo_revision\", 0))"),
		"weapon ammo events expose their revision"
	)
	_check(
		player_source.contains("var accepted_ammo_revisions: Dictionary"),
		"player tracks accepted ammo revisions"
	)
	_check(
		player_source.contains("if incoming_revision < accepted_revision"),
		"player ignores stale ammo states"
	)
	_check(
		player_source.contains("_replace_backpack_slots_preserving_newer_ammo"),
		"backpack snapshots preserve newer Channel 7 ammo state"
	)


func _validate_ammo_revision_ordering() -> void:
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene instantiates for ammo revision ordering")
	if player == null:
		return
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	player.backpack_items.clear()
	player.backpack_items.append({
		"kind": "tool",
		"tool_id": "ak47",
		"ammo_in_mag": 30,
		"reserve_ammo": 0,
		"reload_remaining": 0.0,
		"reload_duration": 0.0,
		"reload_ammo_amount": 0,
		"ammo_revision": 0,
	})
	player.current_tool_index = 0
	player.call("apply_weapon_ammo_state", "ak47", {
		"ammo_in_mag": 20,
		"reserve_ammo": 0,
		"reload_remaining": 0.0,
		"reload_duration": 0.0,
		"reload_ammo_amount": 0,
		"ammo_revision": 2,
	})
	_check(
		int(player.backpack_items[0].get("ammo_in_mag", -1)) == 20,
		"newer Channel 7 ammo state applies to the local weapon"
	)
	var stale_slots: Array[Dictionary] = [{
		"kind": "tool",
		"tool_id": "ak47",
		"ammo_in_mag": 29,
		"reserve_ammo": 0,
		"reload_remaining": 0.0,
		"reload_duration": 0.0,
		"reload_ammo_amount": 0,
		"ammo_revision": 1,
	}]
	player.call("apply_cargo_backpack_slots", stale_slots)
	_check(
		int(player.backpack_items[0].get("ammo_in_mag", -1)) == 20,
		"older Channel 1 backpack state cannot overwrite Channel 7 ammo"
	)
	player.call("apply_weapon_ammo_state", "ak47", {
		"ammo_in_mag": 18,
		"reserve_ammo": 0,
		"reload_remaining": 0.0,
		"reload_duration": 0.0,
		"reload_ammo_amount": 0,
		"ammo_revision": 3,
	})
	_check(
		int(player.backpack_items[0].get("ammo_in_mag", -1)) == 18,
		"newer equal-ID Channel 7 revisions continue to apply"
	)
	player.queue_free()
	await get_tree().process_frame


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		_check(false, "source file exists: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[Channel7CombatValidation] PASS: %s" % message)
	else:
		failures += 1
		push_error("[Channel7CombatValidation] FAIL: %s" % message)
