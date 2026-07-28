extends Node
class_name MultiplayerWorldReplicatorService

const CombatBalance = preload("res://src/combat_balance.gd")
const PLAYER_SCENE := preload("res://character/player.tscn")
const BOOM_EFFECT_SCENE := preload("res://character/weapons/BoomEffect.tscn")
const GRENADE_EXPLOSION_SCENE := preload("res://character/weapons/GrenadeExplosion.tscn")
const BUG_STORM_SCENE := preload("res://character/weapons/BugStorm.tscn")
const MEDICINE_STORM_SCENE := preload("res://character/weapons/MedicineStorm.tscn")
const SPICY_AREA_SCENE := preload("res://character/weapons/SpicyArea.tscn")
const PICKUP_ITEM_SCENE := preload("res://items/pickup_item.tscn")
const LIGHTNING_EFFECT_SCENE := preload("res://character/weapons/LighteningEffect.tscn")
const PROJECTILE_SCENES := {
	"rubber_bullet": "res://character/weapons/RubberBullet.tscn",
	"color_bullet": "res://character/weapons/ColorBullet.tscn",
	"nail_bullet": "res://character/weapons/NailBullet.tscn",
	"medicine_bullet": "res://character/weapons/MedicineBullet.tscn",
	"tranquilizer_bullet": "res://character/weapons/TranquilizerBullet.tscn",
	"defend_bullet": "res://character/weapons/DefendBullet.tscn",
	"detect_laser_bullet": "res://character/weapons/DetectLaserBullet.tscn",
	"repair_laser": "res://character/weapons/RepairLaser.tscn",
	"boom": "res://character/weapons/boom.tscn",
	"bug_boom": "res://character/weapons/BugBoom.tscn",
	"medicine_boom": "res://character/weapons/MedicineBoom.tscn",
	"spicy_bullet": "res://character/weapons/SpicyBullet.tscn",
	"drone_bomb": "res://character/weapons/boom.tscn",
	"auto_shooter_boom": "res://character/weapons/boom.tscn",
	"wheat_sentry_bullet": "res://character/weapons/NailBullet.tscn",
	"grenade": "res://character/weapons/Grenade.tscn",
	"vehicle_shield_laser": "res://character/weapons/ShieldLaser.tscn",
}
const PROJECTILE_VISUAL_RADIUS := 0.16
const ABSORPTION_END_SCALE := 0.06
const REMOTE_SCENES := {
	"action_drone": "res://character/weapons/ActionDrone.tscn",
	"normal_drone": "res://character/weapons/NormalDrone.tscn",
	"tech_drone": "res://character/weapons/TechDrone.tscn",
	"boom_buggy": "res://character/weapons/BoomBuggy.tscn",
	"small_mouse": "res://character/weapons/SmallMouse.tscn",
}
const PLACED_TOOL_SCENES := {
	"farm_runner": "res://character/weapons/FarmRunner.tscn",
	"signal_jam": "res://character/weapons/SignalJam.tscn",
	"signal_augment": "res://character/weapons/SignalAugment.tscn",
	"anti_air": "res://character/weapons/AntiAir.tscn",
	"area_protector": "res://character/weapons/AreaProtector.tscn",
	"auto_cooker": "res://character/weapons/AutomaticCook.tscn",
	"trap": "res://character/weapons/Trap.tscn",
	"big_mouth": "res://character/weapons/BigMouth.tscn",
	"fake_player": "res://character/weapons/FakePlayer.tscn",
	"rift_anchor": "res://character/weapons/RiftAnchor.tscn",
}
const REMOTE_CONTROLLED_DEVICE_TYPES := {
	"action_drone": true,
	"normal_drone": true,
	"tech_drone": true,
	"boom_buggy": true,
	"small_mouse": true,
}
const TILE_TOOL_NAMES := {
	"AutoShooter": true,
	"ShieldDoor": true,
	"WheatSentry": true,
	"PlantProtector": true,
	"Brick": true,
	"FarmRunner": true,
}

var remote_players: Dictionary = {}
var projectile_visuals: Dictionary = {}
var transient_projectile_visuals: Dictionary = {}
var absorption_visuals: Dictionary = {}
var absorbed_projectile_ids: Dictionary = {}
var processed_absorption_ids: Dictionary = {}
var remote_device_visuals: Dictionary = {}
var placed_tool_visuals: Dictionary = {}
var dropped_item_visuals: Dictionary = {}
var wild_animal_visuals: Dictionary = {}
var rare_resource_visual: Node3D = null
var world_root: Node3D
var nature_resource_visuals_by_id: Dictionary = {}
var nature_resource_index_world_id := 0


func _ready() -> void:
	_connect_network_signals()
	set_process(true)


func _exit_tree() -> void:
	_clear_all()


func _process(delta: float) -> void:
	if not GameAuthority.is_client_proxy():
		return
	_resolve_world_root()
	_update_transient_projectile_visuals(delta)
	_update_absorption_visuals(delta)


func _connect_network_signals() -> void:
	if not MultiplayerNetwork.world_snapshot_received.is_connected(_on_world_snapshot_received):
		MultiplayerNetwork.world_snapshot_received.connect(_on_world_snapshot_received)
	if not MultiplayerNetwork.reliable_world_event_received.is_connected(_on_reliable_world_event_received):
		MultiplayerNetwork.reliable_world_event_received.connect(_on_reliable_world_event_received)
	if not MultiplayerNetwork.visual_world_event_received.is_connected(_on_visual_world_event_received):
		MultiplayerNetwork.visual_world_event_received.connect(_on_visual_world_event_received)
	if not MultiplayerNetwork.inventory_state_received.is_connected(_on_inventory_state_received):
		MultiplayerNetwork.inventory_state_received.connect(_on_inventory_state_received)
	if not MultiplayerNetwork.disconnected.is_connected(_on_disconnected):
		MultiplayerNetwork.disconnected.connect(_on_disconnected)


func _resolve_world_root() -> Node3D:
	if is_instance_valid(world_root):
		return world_root
	if is_instance_valid(GlobalVar.gameworld):
		world_root = GlobalVar.gameworld
		_invalidate_nature_resource_index()
		return world_root
	var scene := get_tree().current_scene
	if scene is Node3D:
		world_root = scene
		_invalidate_nature_resource_index()
	return world_root


func _invalidate_nature_resource_index() -> void:
	nature_resource_visuals_by_id.clear()
	nature_resource_index_world_id = 0


func _ensure_nature_resource_index() -> void:
	var world := _resolve_world_root()
	if world == null:
		return
	var world_id := world.get_instance_id()
	if nature_resource_index_world_id == world_id and not nature_resource_visuals_by_id.is_empty():
		return
	nature_resource_visuals_by_id.clear()
	var candidates: Array[Node] = []
	for group_name in ["nature_resources", "harvest_trees", "harvest_ores", "harvest_mushrooms"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and world.is_ancestor_of(node) and not candidates.has(node):
				candidates.append(node)
	for node in candidates:
		var resource_id := str(node.get("resource_id")) if _replicator_has_property(node, "resource_id") \
			else str(node.get("tree_id")) if _replicator_has_property(node, "tree_id") else ""
		if resource_id.is_empty():
			continue
		if nature_resource_visuals_by_id.has(resource_id):
			push_error("Duplicate nature resource_id in client map: %s" % resource_id)
			continue
		nature_resource_visuals_by_id[resource_id] = node
	nature_resource_index_world_id = world_id


func _nature_resource_by_id(resource_id: String) -> Node:
	if resource_id.is_empty():
		return null
	_ensure_nature_resource_index()
	var node: Node = nature_resource_visuals_by_id.get(resource_id, null)
	return node if is_instance_valid(node) else null


func _on_world_snapshot_received(snapshot: Dictionary) -> void:
	if not GameAuthority.is_client_proxy():
		return
	if _resolve_world_root() == null:
		return
	_sync_vehicles(snapshot.get("vehicles", []))
	_sync_players(snapshot.get("players", []), snapshot)
	_sync_projectiles(snapshot.get("projectiles", []))
	_sync_remote_devices(snapshot.get("remote_devices", []))
	_sync_placed_tool_health(snapshot.get("placed_tools", []))
	_sync_wild_animals(snapshot.get("wild_animals", []))


func _on_visual_world_event_received(event: Dictionary) -> void:
	if not GameAuthority.is_client_proxy() or str(event.get("type", "")) != "nature_resource_hit":
		return
	var resource := _nature_resource_by_id(str(event.get("resource_id", "")))
	if resource != null and resource.has_method("play_hit_effect"):
		resource.call("play_hit_effect")


func _sync_players(players_value: Variant, world_snapshot: Dictionary) -> void:
	if not players_value is Array:
		return
	var seen := {}
	var local_peer_id := MultiplayerNetwork.get_unique_peer_id()
	for item: Variant in players_value:
		if not item is Dictionary:
			continue
		var data := (item as Dictionary)
		var peer_id := int(data.get("peer_id", 0))
		if peer_id <= 0:
			continue
		seen[peer_id] = true
		if peer_id == local_peer_id:
			_apply_local_player_snapshot(data)
			continue
		var player := _get_or_create_remote_player(peer_id, data)
		if player != null and player.has_method("apply_remote_snapshot"):
			var timed_data = data.duplicate(true)
			timed_data["tick"] = int(world_snapshot.get("tick", -1))
			timed_data["server_time_msec"] = int(world_snapshot.get("server_time_msec", 0))
			player.call("apply_remote_snapshot", timed_data)
	for peer_id in remote_players.keys():
		if not seen.has(int(peer_id)):
			var node: Node = remote_players[peer_id]
			if is_instance_valid(node):
				node.queue_free()
			remote_players.erase(peer_id)


func _sync_wild_animals(animals_value: Variant) -> void:
	if not animals_value is Array:
		return
	var seen := {}
	for item: Variant in animals_value:
		if not item is Dictionary:
			continue
		var data := item as Dictionary
		var animal_id := str(data.get("animal_id", ""))
		if animal_id.is_empty():
			continue
		seen[animal_id] = true
		var animal := wild_animal_visuals.get(animal_id, null) as Node3D
		if not is_instance_valid(animal):
			var scene_path := str(data.get("scene_path", "res://items/BlackBear.tscn"))
			var packed := load(scene_path) as PackedScene
			animal = packed.instantiate() as Node3D if packed != null else null
			if animal == null or world_root == null:
				continue
			animal.set("animal_id", animal_id)
			animal.set("network_proxy", true)
			world_root.add_child(animal)
			var spawn_position: Variant = data.get("position", Vector3.ZERO)
			if spawn_position is Vector3:
				animal.global_position = spawn_position
			wild_animal_visuals[animal_id] = animal
		if animal.has_method("apply_network_state"):
			animal.call("apply_network_state", data)
	for animal_id_value: Variant in wild_animal_visuals.keys():
		var animal_id := str(animal_id_value)
		if seen.has(animal_id):
			continue
		var animal: Node = wild_animal_visuals[animal_id]
		if is_instance_valid(animal):
			animal.queue_free()
		wild_animal_visuals.erase(animal_id)


func _get_or_create_remote_player(peer_id: int, data: Dictionary) -> GamePlayer:
	var existing: Node = remote_players.get(peer_id, null)
	if is_instance_valid(existing):
		return existing as GamePlayer
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	if player == null or world_root == null:
		return null
	player.is_remote_proxy = true
	player.authority_peer_id = peer_id
	world_root.add_child(player)
	var selection := {
		"peer_id": peer_id,
		"display_name": data.get("display_name", "Player_%d" % peer_id),
		"team": data.get("team", ""),
		"hero_id": data.get("hero_id", "farmer"),
		"primary_weapon_ids": data.get("primary_weapon_ids", ["rubber_revolver"]),
		"special_tool_ids": data.get("special_tool_ids", []),
	}
	player.configure_remote_proxy(peer_id, selection)
	remote_players[peer_id] = player
	return player


func _apply_local_player_snapshot(data: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == int(data.get("peer_id", 0)):
			var equipped_value: Variant = data.get("equipped_items", {})
			if equipped_value is Dictionary:
				node.call("apply_equipped_items_snapshot", equipped_value as Dictionary)
			else:
				node.call("apply_equipped_backpack_snapshot", str(data.get("equipped_backpack_id", "")))
			var hp := float(data.get("hp", 200.0))
			node.set("labeled_remaining", maxf(0.0, float(data.get("labeled_remaining", 0.0))))
			var respawn_left := float(data.get("respawn_left", 0.0))
			var respawn_position: Variant = null
			if respawn_left <= 0.0 and bool(node.get("is_respawning")):
				respawn_position = data.get("position", null)
			node.set("server_hp", hp)
			var capture_anchor: Variant = data.get("big_mouth_anchor", Vector3.ZERO)
			if capture_anchor is Vector3:
				node.call(
					"apply_big_mouth_capture_snapshot",
					float(data.get("big_mouth_capture_remaining", 0.0)),
					capture_anchor
				)
			node.call("apply_respawn_state", respawn_left, respawn_position)
			node.call(
				"apply_vehicle_snapshot", str(data.get("vehicle_id", "")),
				int(data.get("vehicle_seat_index", -1))
			)
			break


func _sync_vehicles(vehicles_value: Variant) -> void:
	if not vehicles_value is Array:
		return
	for item: Variant in vehicles_value:
		if not item is Dictionary:
			continue
		var data := item as Dictionary
		var vehicle := _get_or_create_vehicle_visual(
			str(data.get("vehicle_id", "")),
			str(data.get("scene_path", "")),
			str(data.get("owner_team", ""))
		)
		if vehicle != null:
			vehicle.apply_network_state(data)


func _find_vehicle_visual(vehicle_id: String) -> VehicleBase:
	if vehicle_id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).get_vehicle_id() == vehicle_id:
			return node as VehicleBase
	return null


func _get_or_create_vehicle_visual(vehicle_id: String, scene_path: String, owner_team := "") -> VehicleBase:
	var existing := _find_vehicle_visual(vehicle_id)
	if existing != null or vehicle_id.is_empty() or scene_path.is_empty():
		return existing
	var packed := load(scene_path) as PackedScene
	var vehicle := packed.instantiate() as VehicleBase if packed != null else null
	var root := _resolve_world_root()
	if vehicle == null or root == null:
		return null
	vehicle.network_id = vehicle_id
	vehicle.owner_team = owner_team
	root.add_child(vehicle)
	if vehicle.has_method("set_kitchen_team"):
		vehicle.call("set_kitchen_team", owner_team)
	return vehicle


func _sync_projectiles(projectiles_value: Variant) -> void:
	if not projectiles_value is Array:
		return
	var seen := {}
	for item: Variant in projectiles_value:
		if not item is Dictionary:
			continue
		var data := item as Dictionary
		var projectile_id := int(data.get("projectile_id", 0))
		if projectile_id <= 0:
			continue
		if absorbed_projectile_ids.has(projectile_id):
			continue
		seen[projectile_id] = true
		var visual := _get_or_create_projectile_visual(projectile_id, data)
		var pos: Variant = data.get("position", Vector3.ZERO)
		if visual != null and pos is Vector3:
			visual.global_position = visual.global_position.lerp(pos, 0.65)
			_orient_projectile_visual(visual, data.get("velocity", Vector3.ZERO))
	for projectile_id in projectile_visuals.keys():
		if not seen.has(int(projectile_id)):
			if absorbed_projectile_ids.has(int(projectile_id)):
				continue
			var node: Node = projectile_visuals[projectile_id]
			if is_instance_valid(node):
				node.queue_free()
			projectile_visuals.erase(projectile_id)


func _get_or_create_projectile_visual(projectile_id: int, data: Dictionary) -> Node3D:
	var existing: Node = projectile_visuals.get(projectile_id, null)
	if is_instance_valid(existing):
		return existing as Node3D
	var visual := _instantiate_projectile_visual(data)
	visual.name = "NetProjectile_%d" % projectile_id
	world_root.add_child(visual)
	_disable_visual_runtime(visual)
	var pos: Variant = data.get("position", Vector3.ZERO)
	if pos is Vector3:
		visual.global_position = pos
	projectile_visuals[projectile_id] = visual
	return visual


func _instantiate_projectile_visual(data: Dictionary) -> Node3D:
	var visual_type := str(data.get("type", data.get("visual_type", "")))
	var scene_path := str(PROJECTILE_SCENES.get(visual_type, ""))
	var visual: Node3D = null
	if not scene_path.is_empty():
		var packed := load(scene_path) as PackedScene
		if packed != null:
			visual = packed.instantiate() as Node3D
	if visual == null:
		var fallback := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = PROJECTILE_VISUAL_RADIUS
		mesh.height = PROJECTILE_VISUAL_RADIUS * 2.0
		fallback.mesh = mesh
		visual = fallback
	var effect := str(data.get("effect", ""))
	if visual_type == "color_bullet":
		visual.set("color", _effect_color(effect))
	return visual


func _orient_projectile_visual(visual: Node3D, velocity_value: Variant) -> void:
	if not velocity_value is Vector3:
		return
	var velocity := velocity_value as Vector3
	if velocity.length_squared() > 0.001:
		visual.look_at(visual.global_position + velocity, Vector3.UP)


func _spawn_transient_projectile_visual(event: Dictionary) -> void:
	var visual_id := int(event.get("visual_id", 0))
	if visual_id <= 0 or transient_projectile_visuals.has(visual_id):
		return
	var owner_peer_id := int(event.get("owner_peer_id", 0))
	if owner_peer_id == MultiplayerNetwork.get_unique_peer_id() and not bool(event.get("spawn_for_owner", false)):
		return
	var origin: Variant = event.get("origin", Vector3.ZERO)
	var direction: Variant = event.get("direction", Vector3.FORWARD)
	if not origin is Vector3 or not direction is Vector3:
		return
	var normalized_direction := (direction as Vector3).normalized()
	if normalized_direction.length_squared() <= 0.001:
		return
	var visual := _instantiate_projectile_visual({
		"visual_type": event.get("visual_type", ""),
		"effect": event.get("effect", ""),
	})
	world_root.add_child(visual)
	_disable_visual_runtime(visual)
	visual.global_position = origin
	var velocity := normalized_direction * float(event.get("speed", 0.0))
	_orient_projectile_visual(visual, velocity)
	transient_projectile_visuals[visual_id] = {
		"node": visual,
		"velocity": velocity,
		"remaining": maxf(0.01, float(event.get("lifetime", 0.1))),
		"team": str(event.get("team", "")),
	}


func _update_transient_projectile_visuals(delta: float) -> void:
	for visual_id in transient_projectile_visuals.keys():
		var state: Dictionary = transient_projectile_visuals[visual_id]
		var visual: Node3D = state.get("node", null)
		var remaining := float(state.get("remaining", 0.0)) - delta
		if not is_instance_valid(visual) or remaining <= 0.0:
			if is_instance_valid(visual):
				visual.queue_free()
			transient_projectile_visuals.erase(visual_id)
			continue
		var velocity: Variant = state.get("velocity", Vector3.ZERO)
		if velocity is Vector3:
			visual.global_position += velocity * delta
			_orient_projectile_visual(visual, velocity)
		state["remaining"] = remaining
		transient_projectile_visuals[visual_id] = state


func _sync_remote_devices(devices_value: Variant) -> void:
	if not devices_value is Array:
		return
	var seen := {}
	for item: Variant in devices_value:
		if not item is Dictionary:
			continue
		var data := item as Dictionary
		var device_id := str(data.get("device_id", data.get("device_path", "")))
		if device_id.is_empty():
			continue
		seen[device_id] = true
		var visual := _get_or_create_remote_device_visual(device_id, data)
		if visual != null:
			if REMOTE_CONTROLLED_DEVICE_TYPES.has(str(data.get("device_type", ""))):
				_set_remote_device_jam_ratio(visual, float(data.get("jam_ratio", 1.0)))
				_set_remote_device_augment_ratio(visual, float(data.get("aug_ratio", 1.0)))
			visual.set_meta("network_effective_signal", float(data.get("effective_signal", 0.0)))
			visual.set_meta("network_jam_ratio", float(data.get("jam_ratio", 1.0)))
			visual.set_meta("network_aug_ratio", float(data.get("aug_ratio", 1.0)))
		if visual != null and visual.has_method("apply_network_health"):
			visual.call("apply_network_health", float(data.get("hp", 0.0)))
		var pos: Variant = data.get("position", Vector3.ZERO)
		if visual != null and _is_local_remote_device_active(device_id) and visual.has_method("apply_authoritative_snapshot"):
			visual.call("apply_authoritative_snapshot", data)
		elif visual != null and pos is Vector3:
			visual.global_position = visual.global_position.lerp(pos, 0.55)
			visual.rotation.y = float(data.get("yaw", visual.rotation.y))
	for device_id in remote_device_visuals.keys():
		if not seen.has(str(device_id)):
			if _is_local_remote_device_active(str(device_id)):
				continue
			var node: Node = remote_device_visuals[device_id]
			if is_instance_valid(node):
				node.queue_free()
			remote_device_visuals.erase(device_id)


func _sync_placed_tool_health(tools_value: Variant) -> void:
	if not tools_value is Array:
		return
	for item: Variant in tools_value:
		if not item is Dictionary:
			continue
		var data := item as Dictionary
		var tool_id := str(data.get("tool_id", ""))
		var node := get_node_or_null(NodePath(str(data.get("path", data.get("tool_id", "")))))
		if node == null:
			node = _get_or_create_placed_tool_visual(tool_id, data)
		if node is Node3D and not tool_id.is_empty():
			placed_tool_visuals[tool_id] = node
		if node is FarmTile:
			node = (node as FarmTile).tool_child
		if node == null:
			var tile := _find_farm_tile("", data.get("position", Vector3.ZERO))
			if tile is FarmTile:
				node = (tile as FarmTile).tool_child
		if node is Node3D:
			var position: Variant = data.get("position", Vector3.ZERO)
			if position is Vector3 and not node is FarmTile:
				(node as Node3D).global_position = position
			(node as Node3D).rotation.y = float(data.get("yaw", (node as Node3D).rotation.y))
		if node != null and node.has_method("apply_network_health"):
			node.call("apply_network_health", float(data.get("hp", 0.0)))
		if node != null and node.has_method("apply_network_visual_state"):
			var visual_state: Variant = data.get("visual_state", {})
			if visual_state is Dictionary:
				node.call("apply_network_visual_state", visual_state)
		if bool(data.get("anchor_landed", false)) and node.has_method("apply_network_activated"):
			node.call("apply_network_activated")


func _get_or_create_remote_device_visual(device_id: String, data: Dictionary, keep_runtime := false) -> Node3D:
	var existing: Node = remote_device_visuals.get(device_id, null)
	if is_instance_valid(existing):
		if keep_runtime and not bool(existing.get_meta("runtime_enabled", false)):
			remote_device_visuals.erase(device_id)
			existing.queue_free()
		else:
			if keep_runtime and existing.has_method("activate_tool"):
				existing.call("activate_tool")
				existing.set_meta("runtime_enabled", true)
			return existing as Node3D
	var device_type := str(data.get("device_type", ""))
	var scene_path := str(REMOTE_SCENES.get(device_type, ""))
	var visual: Node3D = null
	if not scene_path.is_empty():
		var packed := load(scene_path) as PackedScene
		if packed != null:
			visual = packed.instantiate() as Node3D
	if visual == null:
		visual = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8, 0.35, 0.8)
		(visual as MeshInstance3D).mesh = mesh
	visual.name = "NetDevice_" + device_id.get_file().replace(":", "_")
	world_root.add_child(visual)
	if not keep_runtime:
		_disable_visual_runtime(visual)
		if visual.has_method("enable_network_visuals"):
			visual.call("enable_network_visuals")
	visual.set("tool_owner", str(data.get("team", "")))
	if visual is KitchenAppliance:
		(visual as KitchenAppliance).owner_team = str(data.get("team", ""))
	if visual is AutoCooker:
		(visual as AutoCooker).activate_tool()
	visual.set_meta("network_device_id", device_id)
	visual.set_meta("runtime_enabled", keep_runtime)
	if keep_runtime and visual.has_method("activate_tool"):
		visual.call("activate_tool")
	var pos: Variant = data.get("position", Vector3.ZERO)
	if pos is Vector3:
		visual.global_position = pos
	remote_device_visuals[device_id] = visual
	return visual


func _find_map_placed_tool(tool_id: String) -> Node3D:
	for node in get_tree().get_nodes_in_group("network_map_devices"):
		if node is Node3D and is_instance_valid(node) \
				and str(node.get_meta("network_device_id", "")) == tool_id:
				return node as Node3D
	return null


func _get_or_create_placed_tool_visual(tool_id: String, data: Dictionary) -> Node3D:
	var existing: Node = placed_tool_visuals.get(tool_id, null)
	if not is_instance_valid(existing):
		existing = _find_map_placed_tool(tool_id)
	if is_instance_valid(existing):
		placed_tool_visuals[tool_id] = existing
		return existing as Node3D
	var scene_path := str(data.get("scene_path", ""))
	if scene_path.is_empty():
		var tool_name := str(data.get("tool_name", ""))
		scene_path = str(PLACED_TOOL_SCENES.get(tool_name, ""))
	var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
	var visual := packed.instantiate() as Node3D if packed != null else null
	if visual == null:
		return null
	world_root.add_child(visual)
	visual.set("tool_owner", str(data.get("team", "")))
	if visual is KitchenAppliance:
		(visual as KitchenAppliance).owner_team = str(data.get("team", ""))
	if visual is AutoCooker:
		(visual as AutoCooker).activate_tool()
	visual.set_meta("network_device_id", str(data.get("device_id", tool_id)))
	# Placed tools are normally presentation-only on clients. RiftAnchor is
	# different: clients need its short flight animation before it lands.
	if visual is RiftAnchor:
		(visual as CollisionObject3D).collision_layer = 0
		(visual as CollisionObject3D).collision_mask = 0
	elif visual is CargoCrateGround:
		visual.call("enable_network_visuals")
	else:
		_disable_visual_runtime(visual)
		if visual.has_method("enable_network_visuals"):
			visual.call("enable_network_visuals")
	var position: Variant = data.get("position", Vector3.ZERO)
	if position is Vector3:
		visual.global_position = position
	visual.rotation.y = float(data.get("yaw", 0.0))
	placed_tool_visuals[tool_id] = visual
	return visual


func _set_remote_device_jam_ratio(device: Node, ratio: float) -> void:
	if device.has_method("set_jam_ratio"):
		device.call("set_jam_ratio", ratio)
	else:
		device.set("jam_ratio", clampf(ratio, 0.01, 1.0))


func _set_remote_device_augment_ratio(device: Node, ratio: float) -> void:
	if device.has_method("set_aug_ratio"):
		device.call("set_aug_ratio", ratio)
	else:
		device.set("aug_ratio", clampf(ratio, 1.0, 100.0))


func _is_local_remote_device_active(device_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == MultiplayerNetwork.get_unique_peer_id():
			# The active device ID survives scene teardown without retaining a Node.
			if node.active_remote_device_id == device_id:
				return true
	return false


func _on_reliable_world_event_received(event: Dictionary) -> void:
	if not GameAuthority.is_client_proxy():
		return
	if _resolve_world_root() == null:
		return
	match str(event.get("type", "")):
		"visual_projectile_fired":
			_spawn_transient_projectile_visual(event)
		"absorption_visual":
			_apply_absorption_visual_event(event)
		"tool_selected":
			_apply_tool_selected_event(event)
		"tool_used":
			_apply_tool_used_event(event.get("data", {}))
		"weapon_ammo_state":
			_apply_weapon_ammo_state_event(event)
		"remote_control_session":
			_apply_remote_control_session_event(event.get("data", {}))
		"vehicle_session":
			_apply_vehicle_session_event(event.get("data", {}))
		"cargo_car_action_result":
			_apply_cargo_car_action_result(event.get("data", {}))
		"cargo_crate_action_result":
			_apply_cargo_crate_action_result(event.get("data", {}))
		"cargo_crate_placed":
			_apply_cargo_crate_placed(event.get("crate", {}))
		"cargo_delivery_preview":
			_apply_cargo_delivery_preview(event)
		"cargo_delivery_result":
			_apply_cargo_delivery_result(event.get("data", {}))
		"vehicle_destroyed":
			_apply_vehicle_destroyed_event(event)
		"vehicle_placed":
			_apply_vehicle_placed_event(event)
		"vehicle_shield_applied":
			_apply_vehicle_shield_event(event)
		"cargo_car_respawn_state":
			_apply_cargo_car_respawn_state(event)
		"trap_triggered":
			_apply_trap_triggered_event(event)
		"trap_expired":
			_remove_placed_tool_visual(str(event.get("device_id", "")))
		"big_mouth_triggered":
			_apply_big_mouth_triggered_event(event)
		"rift_anchor_activated":
			_apply_rift_anchor_activated_event(event)
		"harvest_tree_destroyed":
			_apply_harvest_tree_destroyed_event(event)
		"rare_resource_spawned":
			_apply_rare_resource_spawned(event.get("resource", {}))
		"rare_resource_destroyed":
			_remove_rare_resource_visual()
		"rare_resource_health":
			_apply_rare_resource_health(event)
		"nature_resource_health":
			_apply_nature_resource_health(event)
		"rift_teleported":
			_apply_rift_teleported_event(event)
		"big_mouth_released":
			_apply_big_mouth_released_event(event)
		"farm_action_requested":
			_apply_farm_action_event(event.get("data", {}))
		"farm_tile_delta":
			_apply_farm_tile_delta_event(event.get("data", {}))
		"farm_tile_deltas":
			_apply_farm_tile_deltas_event(event.get("tiles", []))
		"farm_reconcile_chunk":
			_apply_farm_state_chunk(event.get("tiles", []))
		"projectile_exploded":
			_apply_projectile_explosion(event)
		"projectile_intercepted":
			_apply_projectile_explosion(event)
		"player_damaged":
			_apply_player_damage_event(event)
		"player_healed":
			_apply_player_healed_event(event)
		"player_died", "player_respawned":
			_apply_player_respawn_state_event(event)
		"tool_destroyed":
			_apply_tool_destroyed_event(event)
		"lightning_struck":
			_apply_lightning_strike_event(event)
		"dropped_item_action_result":
			_apply_dropped_item_action_result(event.get("data", {}))
		"equipment_action_result":
			_apply_equipment_action_result(event.get("data", {}))
		"dropped_item_spawned":
			var dropped_state: Variant = event.get("item_state", {})
			if dropped_state is Dictionary:
				_spawn_or_update_dropped_item(dropped_state as Dictionary)
		"dropped_item_removed":
			_remove_dropped_item_visual(str(event.get("item_id", "")))
		"ingredient_pickup_action_result":
			_apply_ingredient_pickup_action_result(event.get("data", {}))
		"ingredient_pickup_state":
			_apply_ingredient_pickup_state(event.get("station_state", {}))
		"livestock_chop_action_result":
			_apply_livestock_chop_action_result(event.get("data", {}))
		"livestock_chop_state":
			_apply_livestock_chop_state(event.get("station_state", {}))
		"chopping_action_result":
			_apply_chopping_action_result(event.get("data", {}))
		"plating_station_action_result":
			_apply_plating_station_action_result(event.get("data", {}))
		"plating_station_state":
			_apply_plating_station_state(event.get("station_state", {}))
		"oven_action_result":
			_apply_oven_action_result(event.get("data", {}))
		"oven_state":
			_apply_oven_state(event.get("station_state", {}))
		"griddle_station_action_result":
			_apply_recipe_cooking_station_action_result(event.get("data", {}), "griddle_stations", "SubViewport/GriddleStationPage")
		"griddle_station_state":
			_apply_recipe_cooking_station_state(event.get("station_state", {}), "griddle_stations", "SubViewport/GriddleStationPage")
		"induction_counter_action_result":
			_apply_recipe_cooking_station_action_result(event.get("data", {}), "induction_counters", "SubViewport/InductionCounterPage")
		"induction_counter_state":
			_apply_recipe_cooking_station_state(event.get("station_state", {}), "induction_counters", "SubViewport/InductionCounterPage")
		"smoker_action_result":
			_apply_recipe_cooking_station_action_result(event.get("data", {}), "smoker_stations", "SubViewport/FarmSmokerPage")
		"smoker_state":
			_apply_recipe_cooking_station_state(event.get("station_state", {}), "smoker_stations", "SubViewport/FarmSmokerPage")
		"freezer_action_result":
			_apply_recipe_cooking_station_action_result(event.get("data", {}), "freezer_stations", "SubViewport/FreezerPage")
		"freezer_state":
			_apply_recipe_cooking_station_state(event.get("station_state", {}), "freezer_stations", "SubViewport/FreezerPage")
		"stand_mixer_action_result":
			_apply_mixer_action_result(event.get("data", {}))
		"stand_mixer_state":
			_apply_mixer_state(event.get("station_state", {}))
		"extractor_action_result":
			_apply_extractor_action_result(event.get("data", {}))
		"extractor_state":
			_apply_extractor_state(event.get("station_state", {}))
		"auto_cooker_action_result":
			_apply_auto_cooker_action_result(event.get("data", {}))
		"auto_cooker_state":
			_apply_auto_cooker_state(event.get("station_state", {}))
		"backpack_test_grant":
			_apply_backpack_test_grant(event)
		"low_frequency_snapshot":
			var data: Variant = event.get("data", {})
			if data is Dictionary:
				_apply_low_frequency_snapshot(data)
		_:
			pass


func _apply_backpack_test_grant(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	var entries: Variant = event.get("entries", [])
	if not entries is Array:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_test_backpack_grant(entries as Array)
			return


func _apply_weapon_ammo_state_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	var ammo_value: Variant = event.get("ammo_state", {})
	if not ammo_value is Dictionary:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_weapon_ammo_state(
				str(event.get("tool_id", "")),
				ammo_value as Dictionary
			)
			return


func _apply_rare_resource_spawned(resource_value: Variant) -> void:
	if not resource_value is Dictionary:
		return
	var data := resource_value as Dictionary
	var resource_definition := data.get("resource", {}) as Dictionary
	var resource_id := str(data.get("resource_id", resource_definition.get("id", "")))
	if is_instance_valid(rare_resource_visual) and str(rare_resource_visual.get_meta("rare_resource_id", "")) == resource_id:
		if rare_resource_visual.has_method("apply_network_health") and data.has("hp"):
			rare_resource_visual.call("apply_network_health", float(data.get("hp", 0.0)))
		return
	var scene_path := str(resource_definition.get("scene_path", ""))
	if scene_path.is_empty():
		return
	_remove_rare_resource_visual()
	var packed := load(scene_path) as PackedScene
	if packed == null or world_root == null:
		return
	rare_resource_visual = packed.instantiate() as Node3D
	if rare_resource_visual == null:
		return
	world_root.add_child(rare_resource_visual)
	rare_resource_visual.set_meta("rare_resource_id", resource_id)
	var position_value: Variant = data.get("position", Vector3.ZERO)
	if position_value is Vector3:
		rare_resource_visual.global_position = position_value
	if rare_resource_visual is CollisionObject3D:
		(rare_resource_visual as CollisionObject3D).collision_layer = 0
		(rare_resource_visual as CollisionObject3D).collision_mask = 0
	if rare_resource_visual.has_method("apply_network_health"):
		rare_resource_visual.call("apply_network_health", float(data.get("hp", 1000.0)))


func _remove_rare_resource_visual() -> void:
	if is_instance_valid(rare_resource_visual):
		rare_resource_visual.queue_free()
	rare_resource_visual = null


func _apply_rare_resource_health(event: Dictionary) -> void:
	if not is_instance_valid(rare_resource_visual):
		return
	if rare_resource_visual.has_method("apply_network_health"):
		rare_resource_visual.call("apply_network_health", float(event.get("hp", 0.0)))


func _apply_dropped_item_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	if bool(data.get("ok", false)):
		if str(data.get("action", "")) == "throw":
			var state_value: Variant = data.get("item_state", {})
			if state_value is Dictionary:
				_spawn_or_update_dropped_item(state_value as Dictionary)
		elif str(data.get("action", "")) == "pickup":
			_remove_dropped_item_visual(str(data.get("item_id", "")))
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			(node as GamePlayer).apply_authoritative_dropped_item_action_result(data)
			return


func _apply_equipment_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var dropped_states: Variant = data.get("dropped_item_states", [])
	if dropped_states is Array:
		for state_value: Variant in dropped_states:
			if state_value is Dictionary:
				_spawn_or_update_dropped_item(state_value as Dictionary)
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			(node as GamePlayer).apply_authoritative_equipment_action_result(data)
			return


func _spawn_or_update_dropped_item(state: Dictionary) -> void:
	var item_id := str(state.get("item_id", ""))
	if item_id.is_empty() or _resolve_world_root() == null:
		return
	var pickup := dropped_item_visuals.get(item_id, null) as PickupItem
	if not is_instance_valid(pickup):
		pickup = PICKUP_ITEM_SCENE.instantiate() as PickupItem
		if pickup == null:
			return
		world_root.add_child(pickup)
		pickup.setup(state)
		dropped_item_visuals[item_id] = pickup
	else:
		pickup.apply_authoritative_state(state)


func _remove_dropped_item_visual(item_id: String) -> void:
	var pickup = dropped_item_visuals.get(item_id, null)
	if is_instance_valid(pickup):
		(pickup as Node).queue_free()
	dropped_item_visuals.erase(item_id)


func _sync_dropped_items(states_value: Variant) -> void:
	if not states_value is Array:
		return
	var seen := {}
	for state_value: Variant in states_value:
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var item_id := str(state.get("item_id", ""))
		if item_id.is_empty():
			continue
		seen[item_id] = true
		_spawn_or_update_dropped_item(state)
	for item_id_value in dropped_item_visuals.keys():
		var item_id := str(item_id_value)
		if not seen.has(item_id):
			_remove_dropped_item_visual(item_id)


func _apply_tool_selected_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	var player: Node = remote_players.get(peer_id, null)
	if player is GamePlayer:
		(player as GamePlayer).apply_remote_tool_selection(
			int(event.get("tool_index", 0)),
			str(event.get("tool_id", ""))
		)


func _apply_ingredient_pickup_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_ingredient_pickup_state(data.get("station_state", {}))
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			var page := (node as GamePlayer).get_node_or_null("SubViewport/IngredientPickupPage")
			if page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_ingredient_pickup_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var station := get_node_or_null(NodePath(str(state.get("station_path", ""))))
	if station is IngredientPickup:
		(station as IngredientPickup).apply_authoritative_staged_state(state)


func _apply_livestock_chop_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_livestock_chop_state(data.get("station_state", {}))
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == int(data.get("peer_id", 0)):
			var page := (node as GamePlayer).livestock_chop_page
			if is_instance_valid(page):
				page.apply_authoritative_result(data)
			return


func _apply_livestock_chop_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var chop := get_node_or_null(NodePath(str(state.get("station_path", "")))) as LivestockChop
	if chop == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group("livestock_chops"):
				if node is LivestockChop:
					var distance := (node as LivestockChop).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						chop = node as LivestockChop
						best_distance = distance
	if chop != null:
		chop.apply_authoritative_chop_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).livestock_chop_page
			if is_instance_valid(page) and page.is_open() and page.chop == chop:
				page.station_state = state.duplicate(true)
				page.call("_refresh")


func _apply_chopping_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var station_state: Variant = data.get("station_state", {})
	if station_state is Dictionary:
		var state := station_state as Dictionary
		var station := get_node_or_null(NodePath(str(state.get("station_path", "")))) as ChoppingStation
		if station == null:
			var target_position: Variant = state.get("station_position", null)
			if target_position is Vector3:
				var best_distance := INF
				for node in get_tree().get_nodes_in_group("chopping_stations"):
					if node is ChoppingStation:
						var distance := (node as ChoppingStation).global_position.distance_squared_to(target_position as Vector3)
						if distance < best_distance:
							station = node as ChoppingStation
							best_distance = distance
		if station != null:
			station.apply_authoritative_station_state(state)
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_chopping_action_result(data)
			return


func _apply_plating_station_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_plating_station_state(data.get("station_state", {}))
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_plating_station_action_result(data)
			var page := (node as GamePlayer).get_node_or_null("SubViewport/PlatingStationPage")
			if str(data.get("action", "")) != "take" and page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_plating_station_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var station := get_node_or_null(NodePath(str(state.get("station_path", "")))) as PlatingStation
	if station == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group("plating_stations"):
				if node is PlatingStation:
					var distance := (node as PlatingStation).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						station = node as PlatingStation
						best_distance = distance
	if station != null:
		station.apply_authoritative_station_state(state)


func _apply_oven_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_oven_state(data.get("station_state", {}))
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_oven_action_result(data)
			var page := (node as GamePlayer).get_node_or_null("SubViewport/OvenPage")
			if page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_oven_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var oven := get_node_or_null(NodePath(str(state.get("station_path", "")))) as Oven
	if oven == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group("oven_stations"):
				if node is Oven:
					var distance := (node as Oven).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						oven = node as Oven
						best_distance = distance
	if oven != null:
		oven.apply_authoritative_station_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).get_node_or_null("SubViewport/OvenPage")
			if page != null and page.has_method("refresh_if_open"):
				page.call("refresh_if_open")


func _apply_recipe_cooking_station_action_result(data_value: Variant, group_name: String, page_path: String) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_recipe_cooking_station_state(data.get("station_state", {}), group_name, page_path)
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_recipe_station_action_result(data)
			var page := (node as GamePlayer).get_node_or_null(NodePath(page_path))
			if page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_recipe_cooking_station_state(state_value: Variant, group_name: String, page_path: String) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var station := get_node_or_null(NodePath(str(state.get("station_path", "")))) as RecipeCookingStation
	if station == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group(group_name):
				if node is RecipeCookingStation:
					var distance := (node as RecipeCookingStation).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						station = node as RecipeCookingStation
						best_distance = distance
	if station != null and station.is_in_group(group_name):
		station.apply_authoritative_station_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).get_node_or_null(NodePath(page_path))
			if page != null and page.has_method("refresh_if_open"):
				page.call("refresh_if_open")


func _find_auto_cooker(state: Dictionary) -> AutoCooker:
	var station := get_node_or_null(NodePath(str(state.get("station_path", "")))) as AutoCooker
	if station != null: return station
	var position: Variant = state.get("station_position", null)
	if position is Vector3:
		for node in get_tree().get_nodes_in_group("auto_cookers"):
			if node is AutoCooker and (node as AutoCooker).global_position.distance_squared_to(position as Vector3) < 0.25:
				return node as AutoCooker
	return null

func _apply_auto_cooker_state(state_value: Variant) -> void:
	if not state_value is Dictionary: return
	var state := state_value as Dictionary
	var cooker := _find_auto_cooker(state)
	if cooker != null: cooker.apply_authoritative_cook_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).get_node_or_null("SubViewport/AutoCookerPage")
			if page != null: page.call("refresh_if_open")

func _apply_auto_cooker_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary: return
	var data := data_value as Dictionary
	_apply_auto_cooker_state(data.get("station_state", {}))
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id(): return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and (node as GamePlayer).authority_peer_id == int(data.get("peer_id", 0)):
			var page := (node as GamePlayer).get_node_or_null("SubViewport/AutoCookerPage")
			if page != null: page.call("apply_authoritative_action_result", data)
			return

func _apply_extractor_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_extractor_state(data.get("station_state", {}))
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_extractor_action_result(data)
			var page := (node as GamePlayer).get_node_or_null("SubViewport/IngredientExtractorPage")
			if str(data.get("action", "")) != "take" and page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_extractor_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var station := get_node_or_null(NodePath(str(state.get("station_path", "")))) as IngredientExtractor
	if station == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group("ingredient_extractors"):
				if node is IngredientExtractor:
					var distance := (node as IngredientExtractor).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						station = node as IngredientExtractor
						best_distance = distance
	if station != null:
		station.apply_authoritative_extractor_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).get_node_or_null("SubViewport/IngredientExtractorPage")
			if page != null and page.has_method("refresh_if_open"):
				page.call("refresh_if_open")


func _apply_mixer_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	_apply_mixer_state(data.get("station_state", {}))
	var peer_id := int(data.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_authoritative_mixer_action_result(data)
			var page := (node as GamePlayer).get_node_or_null("SubViewport/StandMixerPage")
			if str(data.get("action", "")) != "take" and page != null and page.has_method("apply_authoritative_action_result"):
				page.call("apply_authoritative_action_result", data)
			return


func _apply_mixer_state(state_value: Variant) -> void:
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var mixer := get_node_or_null(NodePath(str(state.get("station_path", "")))) as StandMixer
	if mixer == null:
		var position_value: Variant = state.get("station_position", null)
		if position_value is Vector3:
			var best_distance := INF
			for node in get_tree().get_nodes_in_group("stand_mixers"):
				if node is StandMixer:
					var distance := (node as StandMixer).global_position.distance_squared_to(position_value as Vector3)
					if distance < best_distance:
						mixer = node as StandMixer
						best_distance = distance
	if mixer != null:
		mixer.apply_authoritative_mixer_state(state)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			var page := (node as GamePlayer).get_node_or_null("SubViewport/StandMixerPage")
			if page != null and page.has_method("refresh_if_open"):
				page.call("refresh_if_open")


func _apply_tool_used_event(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var peer_id := int(data.get("peer_id", 0))
	var player: Node = remote_players.get(peer_id, null)
	if player is GamePlayer:
		(player as GamePlayer).play_remote_tool_action(str(data.get("animation_action", "utility")))
		if str(data.get("tool_id", "")) != "fist":
			(player as GamePlayer).play_remote_tool_visual(
				str(data.get("tool_id", "")),
				int(data.get("tool_index", -1))
			)
	# SproutBlaster's authoritative result already identifies the accepted tile
	# and seed. Apply it immediately instead of waiting for the 1 Hz farm snapshot.
	if bool(data.get("ok", false)) and str(data.get("farm_action", "")) == "plant":
		var planted_tile := _find_farm_tile(
			str(data.get("tile_path", "")),
			data.get("tile_position", Vector3.ZERO)
		)
		if planted_tile is FarmTile:
			planted_tile.apply_authoritative_plant(
				str(data.get("seed_id", "")),
				str(data.get("team", ""))
			)
	if bool(data.get("ok", false)) and str(data.get("farm_action", "")) == "fertilize":
		var fertilized_tile := _find_farm_tile(
			str(data.get("tile_path", "")),
			data.get("tile_position", Vector3.ZERO)
		)
		if fertilized_tile is FarmTile:
			fertilized_tile.apply_authoritative_fertilizer(
				float(data.get("fertilizer_multiplier", 1.0)),
				bool(data.get("fertilizer_blocked", false))
			)
	var placed := str(data.get("placed", ""))
	if not placed.is_empty():
		var tile_path := str(data.get("tile_path", ""))
		if not tile_path.is_empty() and TILE_TOOL_NAMES.has(placed):
			var tile := _find_farm_tile(tile_path, data.get("tile_position", Vector3.ZERO))
			if tile is FarmTile:
				tile.apply_authoritative_tool(
					placed,
					str(data.get("team", "")),
					float(data.get("yaw", 0.0))
				)
			return
		if data.has("device_id"):
			var device_id := str(data.get("device_id", ""))
			var is_owner := int(data.get("peer_id", 0)) == MultiplayerNetwork.get_unique_peer_id()
			var is_remote_controlled := str(data.get("category", "utility")) == "remote"
			var visual_data := {
				"device_id": data.get("device_id", ""),
				"team": data.get("team", ""),
				"position": data.get("position", Vector3.ZERO),
				"yaw": data.get("yaw", 0.0),
				"scene_path": data.get("scene_path", ""),
			}
			var device: Node3D = null
			if is_remote_controlled:
				visual_data["device_type"] = placed
				device = _get_or_create_remote_device_visual(
					device_id,
					visual_data,
					is_owner
				)
			else:
				visual_data["tool_name"] = placed
				device = _get_or_create_placed_tool_visual(device_id, visual_data)
			if placed == "rift_anchor" and bool(data.get("ok", false)) \
					and str(data.get("rift_action", "")) == "launch" \
					and device is RiftAnchor:
				var launch_position: Variant = data.get("origin", data.get("position", Vector3.ZERO))
				var launch_direction: Variant = data.get("direction", Vector3.FORWARD)
				if launch_position is Vector3 and launch_direction is Vector3:
					(device as RiftAnchor).apply_network_launch(
						launch_position as Vector3,
						launch_direction as Vector3,
						peer_id,
						str(data.get("team", ""))
					)
			if is_owner and is_remote_controlled and device != null:
				_start_local_remote_control(device)
			return
func _start_local_remote_control(device: Node3D) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == MultiplayerNetwork.get_unique_peer_id():
			node.remote_device_reset(device)
			node.remote_device_start()
			return


func _apply_remote_control_session_event(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id():
		return
	var device_id := str(data.get("device_id", ""))
	if device_id.is_empty():
		return
	var device: Node3D = null
	if bool(data.get("ok", false)) and bool(data.get("connected", false)):
		device = _get_or_create_remote_device_visual(device_id, {
			"device_id": device_id,
			"device_type": data.get("device_type", ""),
			"team": data.get("team", ""),
			"position": data.get("position", Vector3.ZERO),
		}, true)
		if device != null:
			_set_remote_device_jam_ratio(device, float(data.get("jam_ratio", 1.0)))
			_set_remote_device_augment_ratio(device, float(data.get("aug_ratio", 1.0)))
			device.set_meta("network_effective_signal", float(data.get("effective_signal", 0.0)))
			device.set_meta("network_jam_ratio", float(data.get("jam_ratio", 1.0)))
			device.set_meta("network_aug_ratio", float(data.get("aug_ratio", 1.0)))
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == MultiplayerNetwork.get_unique_peer_id():
			node.apply_remote_control_session_result(data, device)
			return


func _apply_vehicle_session_event(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	if int(data.get("peer_id", 0)) != MultiplayerNetwork.get_unique_peer_id():
		return
	var vehicle := _find_vehicle_visual(str(data.get("vehicle_id", "")))
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == MultiplayerNetwork.get_unique_peer_id():
			node.apply_vehicle_session_result(data, vehicle)
			return


func _local_human_player(peer_id: int) -> GamePlayer:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			return node as GamePlayer
	return null


func _apply_cargo_car_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var player := _local_human_player(MultiplayerNetwork.get_unique_peer_id())
	if player != null and int(data.get("peer_id", 0)) == player.authority_peer_id:
		player.apply_cargo_car_action_result(data)


func _apply_cargo_crate_action_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var player := _local_human_player(MultiplayerNetwork.get_unique_peer_id())
	if player != null and int(data.get("peer_id", 0)) == player.authority_peer_id:
		player.apply_cargo_crate_action_result(data)


func _apply_cargo_crate_placed(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var crate_id := str(data.get("tool_id", data.get("device_id", "")))
	if crate_id.is_empty():
		return
	var visual := _get_or_create_placed_tool_visual(crate_id, data)
	if visual != null and visual.has_method("apply_network_visual_state"):
		visual.call("apply_network_visual_state", {"crate_data": data.get("crate_data", {})})


func _apply_cargo_delivery_preview(event: Dictionary) -> void:
	var player := _local_human_player(MultiplayerNetwork.get_unique_peer_id())
	var data: Variant = event.get("data", {})
	if player != null and int(event.get("peer_id", 0)) == player.authority_peer_id and data is Dictionary:
		player.show_cargo_delivery_preview(data as Dictionary)


func _apply_cargo_delivery_result(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	var player := _local_human_player(MultiplayerNetwork.get_unique_peer_id())
	if player != null and int(data.get("peer_id", 0)) == player.authority_peer_id:
		player.apply_cargo_delivery_result(data)


func _apply_vehicle_destroyed_event(event: Dictionary) -> void:
	var vehicle := _find_vehicle_visual(str(event.get("vehicle_id", "")))
	if vehicle != null:
		vehicle.queue_free()
	var position: Variant = event.get("position", Vector3.ZERO)
	if position is Vector3:
		_spawn_boom_effect(position)


func _apply_vehicle_shield_event(event: Dictionary) -> void:
	var vehicle := _find_vehicle_visual(str(event.get("vehicle_id", "")))
	if vehicle == null:
		return
	vehicle.apply_network_shield(
		float(event.get("shield_remaining", 0.0)),
		float(event.get("shield_hp", 0.0)),
		float(event.get("shield_max_hp", 0.0))
	)


func _apply_vehicle_placed_event(event: Dictionary) -> void:
	var vehicle_id := str(event.get("vehicle_id", ""))
	if vehicle_id.is_empty() or _find_vehicle_visual(vehicle_id) != null:
		return
	var vehicle := _get_or_create_vehicle_visual(
		vehicle_id,
		str(event.get("scene_path", "")),
		str(event.get("owner_team", ""))
	)
	if vehicle == null:
		return
	var position: Variant = event.get("position", Vector3.ZERO)
	if position is Vector3:
		vehicle.global_position = position
	vehicle.rotation.y = float(event.get("yaw", 0.0))


func _apply_trap_triggered_event(event: Dictionary) -> void:
	var device_id := str(event.get("device_id", ""))
	var visual: Node = placed_tool_visuals.get(device_id, null)
	if not is_instance_valid(visual):
		visual = _get_or_create_placed_tool_visual(device_id, {
			"device_id": device_id,
			"tool_name": "trap",
			"scene_path": "res://character/weapons/Trap.tscn",
			"position": event.get("position", Vector3.ZERO),
		})
	if is_instance_valid(visual) and visual.has_method("apply_network_triggered"):
		visual.call("apply_network_triggered")


func _apply_big_mouth_triggered_event(event: Dictionary) -> void:
	var device_id := str(event.get("device_id", ""))
	var visual: Node = placed_tool_visuals.get(device_id, null)
	if not is_instance_valid(visual):
		visual = _find_map_placed_tool(device_id)
	if not is_instance_valid(visual):
		visual = _get_or_create_placed_tool_visual(device_id, {
			"device_id": device_id,
			"tool_name": "big_mouth",
			"scene_path": "res://character/weapons/BigMouth.tscn",
			"position": event.get("position", Vector3.ZERO),
		})
	if is_instance_valid(visual) and visual.has_method("apply_network_triggered"):
		visual.call("apply_network_triggered")
	var victim_peer_id := int(event.get("victim_peer_id", 0))
	if victim_peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	var anchor: Variant = event.get("anchor_position", Vector3.ZERO)
	if not anchor is Vector3:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == victim_peer_id:
			(node as GamePlayer).apply_big_mouth_capture(
				anchor as Vector3,
				float(event.get("capture_seconds", 5.0)),
				float(event.get("pull_seconds", 0.28))
			)
			return


func _apply_big_mouth_released_event(event: Dictionary) -> void:
	var device_id := str(event.get("device_id", ""))
	var visual: Node = placed_tool_visuals.get(device_id, null)
	if not is_instance_valid(visual):
		visual = _find_map_placed_tool(device_id)
	var reason := str(event.get("reason", "released"))
	if reason != "timeout" and is_instance_valid(visual) and visual.has_method("release_capture_early"):
		visual.call("release_capture_early")
	var victim_peer_id := int(event.get("victim_peer_id", 0))
	if victim_peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == victim_peer_id:
			(node as GamePlayer).release_big_mouth_capture()
			return


func _apply_rift_anchor_activated_event(event: Dictionary) -> void:
	var anchor_id := str(event.get("anchor_id", ""))
	var visual: Node = placed_tool_visuals.get(anchor_id, null)
	if not is_instance_valid(visual):
		visual = _find_map_placed_tool(anchor_id)
	if is_instance_valid(visual) and visual.has_method("apply_network_activated"):
		visual.call("apply_network_activated")


func _apply_harvest_tree_destroyed_event(event: Dictionary) -> void:
	var tree_id := str(event.get("resource_id", event.get("tree_id", "")))
	var tree := _nature_resource_by_id(tree_id)
	if tree is HarvestTree:
		var direction: Variant = event.get("fall_direction", Vector3.ZERO)
		(tree as HarvestTree).apply_network_destroyed(direction as Vector3 if direction is Vector3 else Vector3.ZERO)


func _apply_rift_teleported_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	var position: Variant = event.get("position", null)
	if not position is Vector3:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).global_position = position as Vector3
			(node as GamePlayer).velocity = Vector3.ZERO
			return


func _remove_remote_device_visual(device_id: String) -> void:
	if device_id.is_empty() or not remote_device_visuals.has(device_id):
		return
	var visual: Node = remote_device_visuals[device_id]
	if is_instance_valid(visual):
		visual.queue_free()
	remote_device_visuals.erase(device_id)


func _remove_placed_tool_visual(tool_id: String) -> void:
	if tool_id.is_empty() or not placed_tool_visuals.has(tool_id):
		return
	var visual: Node = placed_tool_visuals[tool_id]
	if is_instance_valid(visual):
		visual.queue_free()
	placed_tool_visuals.erase(tool_id)


func _apply_cargo_car_respawn_state(event: Dictionary) -> void:
	var team := str(event.get("team", ""))
	if team.is_empty():
		return
	for node in get_tree().get_nodes_in_group("team_garages"):
		if node is TeamGarage and (node as TeamGarage).owner_team == team:
			(node as TeamGarage).set_respawn_state(
				bool(event.get("active", false)),
				float(event.get("remaining", 0.0))
			)
			return


func _apply_farm_action_event(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var data := data_value as Dictionary
	if not bool(data.get("ok", false)):
		return
	var tile_path := str(data.get("tile_path", ""))
	var tile_position: Variant = data.get("tile_position", Vector3.ZERO)
	if tile_path.is_empty() and not tile_position is Vector3:
		return
	var tile := _find_farm_tile(tile_path, tile_position)
	if not tile is FarmTile:
		return
	var action: Variant = data.get("action", {})
	if not action is Dictionary:
		return
	var action_type := str(action.get("type", ""))
	match action_type:
		"claim_land":
			tile.apply_authoritative_owner(str(data.get("team", "")))
		"plant":
			tile.apply_authoritative_plant(str(data.get("seed_name", (action as Dictionary).get("seed_name", ""))), str(data.get("team", "")))
		"harvest":
			tile.apply_authoritative_harvest()
		"harvest_one":
			if bool(data.get("ok", false)):
				var crop_index := int(data.get("crop_index", -1))
				var crop_position: Variant = data.get("crop_position", null)
				if crop_position is Vector3:
					crop_index = tile.get_harvestable_crop_index_at_position(crop_position as Vector3)
				if crop_index >= 0:
					tile.apply_authoritative_harvest_one(crop_index)
		"place_tool":
			tile.apply_authoritative_tool(
				str((action as Dictionary).get("tool_name", "")),
				str(data.get("team", "")),
				float(data.get("yaw", 0.0))
			)
		_:
			pass


func _apply_farm_tile_delta_event(data_value: Variant) -> void:
	if not data_value is Dictionary:
		return
	var delta := data_value as Dictionary
	var tile: FarmTile = null
	var field_id := str(delta.get("field_id", ""))
	var grid_coordinate: Variant = delta.get("grid_coordinate", Vector2i.ZERO)
	if not field_id.is_empty() and grid_coordinate is Vector2i:
		tile = _find_farm_tile_by_grid(field_id, grid_coordinate)
	if tile == null:
		tile = _find_farm_tile(
			str(delta.get("tile_path", "")),
			delta.get("tile_position", Vector3.ZERO)
		)
	if tile is FarmTile:
		tile.apply_authoritative_delta(delta)


func _apply_farm_tile_deltas_event(tiles_value: Variant) -> void:
	if not tiles_value is Array:
		return
	for delta_value in tiles_value:
		_apply_farm_tile_delta_event(delta_value)


func _apply_farm_state_chunk(tiles_value: Variant) -> void:
	if not tiles_value is Array:
		return
	for state_value: Variant in tiles_value:
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var tile := _find_farm_tile(
			str(state.get("tile_path", "")),
			state.get("tile_position", Vector3.ZERO)
		)
		if tile is FarmTile:
			tile.apply_authoritative_state(state)


func _find_farm_tile_by_grid(field_id: String, grid_coordinate: Vector2i) -> FarmTile:
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if node is FarmTile:
			var tile := node as FarmTile
			if tile.field_id == field_id and tile.grid_coordinate == grid_coordinate:
				return tile
	return null


func _apply_projectile_explosion(event: Dictionary) -> void:
	var projectile_id := int(event.get("projectile_id", 0))
	if projectile_visuals.has(projectile_id):
		var visual: Node = projectile_visuals[projectile_id]
		if is_instance_valid(visual):
			visual.queue_free()
		projectile_visuals.erase(projectile_id)
	var pos: Variant = event.get("position", Vector3.ZERO)
	if pos is Vector3:
		var projectile_type := str(event.get("projectile_type", ""))
		if projectile_type == "bug_boom":
			_spawn_bug_storm_visual(pos, str(event.get("team", "")))
		elif projectile_type == "medicine_boom":
			_spawn_medicine_storm_visual(pos, str(event.get("team", "")))
		elif projectile_type == "spicy_bullet" and bool(event.get("hit_world", false)):
			_spawn_spicy_area_visual(pos, str(event.get("team", "")), event.get("direction", Vector3.FORWARD))
		elif projectile_type == "grenade":
			_spawn_grenade_explosion(pos)
		elif projectile_type in ["boom", "drone_bomb", "auto_shooter_boom"]:
			_spawn_boom_effect(pos)
		else:
			_spawn_impact_flash(pos, str(event.get("effect", "Explosion")))


func _apply_absorption_visual_event(event: Dictionary) -> void:
	var absorption_id := int(event.get("absorption_id", 0))
	if absorption_id <= 0 or processed_absorption_ids.has(absorption_id):
		return
	var start_value: Variant = event.get("start_position", Vector3.ZERO)
	var end_value: Variant = event.get("end_position", Vector3.ZERO)
	if not start_value is Vector3 or not end_value is Vector3:
		return
	processed_absorption_ids[absorption_id] = true
	var visual: Node3D = null
	var projectile_id := int(event.get("projectile_id", 0))
	if projectile_id > 0:
		absorbed_projectile_ids[projectile_id] = absorption_id
		var existing: Node = projectile_visuals.get(projectile_id, null)
		if is_instance_valid(existing) and existing is Node3D:
			visual = existing as Node3D
			projectile_visuals.erase(projectile_id)
		else:
			visual = _instantiate_projectile_visual({
				"visual_type": event.get("visual_type", ""),
				"effect": event.get("effect", ""),
			})
	else:
		visual = _instantiate_crop_absorption_visual(event)
	if visual == null:
		return
	if visual.get_parent() == null:
		world_root.add_child(visual)
		_disable_visual_runtime(visual)
	visual.global_position = start_value as Vector3
	absorption_visuals[absorption_id] = {
		"node": visual,
		"projectile_id": projectile_id,
		"start_position": start_value,
		"end_position": end_value,
		"initial_scale": visual.scale,
		"elapsed": 0.0,
		"duration": maxf(0.05, float(event.get("duration", 0.35))),
	}


func _instantiate_crop_absorption_visual(event: Dictionary) -> Node3D:
	var seed_name := str(event.get("seed_name", ""))
	var crop_layout := FarmTile.get_crop_layout(seed_name)
	var default_scene_path := FarmTile.get_harvest_drop_scene_path(seed_name)
	var scene_path := str(event.get("visual_scene", default_scene_path))
	if scene_path.is_empty():
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var visual := Node3D.new()
	var positions: Variant = event.get("crop_positions", crop_layout.get("positions", [Vector3.ZERO]))
	if not positions is Array or (positions as Array).is_empty():
		positions = crop_layout.get("positions", [Vector3.ZERO])
	for crop_position_value: Variant in positions:
		if not crop_position_value is Vector3:
			continue
		var crop_position := crop_position_value as Vector3
		var crop := packed.instantiate() as Node3D
		if crop == null:
			continue
		visual.add_child(crop)
		crop.position = crop_position
	return visual if visual.get_child_count() > 0 else null


func _update_absorption_visuals(delta: float) -> void:
	for absorption_id in absorption_visuals.keys():
		var state: Dictionary = absorption_visuals[absorption_id]
		var visual: Node3D = state.get("node", null)
		var elapsed := float(state.get("elapsed", 0.0)) + delta
		var duration := maxf(0.05, float(state.get("duration", 0.35)))
		if not is_instance_valid(visual) or elapsed >= duration:
			if is_instance_valid(visual):
				visual.queue_free()
			absorption_visuals.erase(absorption_id)
			continue
		var t := clampf(elapsed / duration, 0.0, 1.0)
		var eased_t := 1.0 - pow(1.0 - t, 3.0)
		var start_position: Vector3 = state.get("start_position", visual.global_position)
		var end_position: Vector3 = state.get("end_position", visual.global_position)
		var initial_scale: Vector3 = state.get("initial_scale", visual.scale)
		visual.global_position = start_position.lerp(end_position, eased_t)
		var shrink_factor := lerpf(1.0, ABSORPTION_END_SCALE, eased_t)
		visual.scale = initial_scale * shrink_factor
		state["elapsed"] = elapsed
		absorption_visuals[absorption_id] = state


func _spawn_boom_effect(position: Vector3) -> void:
	if _resolve_world_root() == null:
		return
	var effect := BOOM_EFFECT_SCENE.instantiate() as Node3D
	if effect == null:
		return
	world_root.add_child(effect)
	effect.global_position = position


func _spawn_grenade_explosion(position: Vector3) -> void:
	if _resolve_world_root() == null:
		return
	var effect := GRENADE_EXPLOSION_SCENE.instantiate() as Node3D
	if effect == null:
		return
	world_root.add_child(effect)
	effect.global_position = position


func _spawn_bug_storm_visual(position: Vector3, source_team: String) -> void:
	if _resolve_world_root() == null:
		return
	var storm := BUG_STORM_SCENE.instantiate() as Node3D
	if storm == null:
		return
	storm.set("visual_only", true)
	storm.set("source_team", source_team)
	storm.set("effect_distance", CombatBalance.get_float("bug_storm", "radius"))
	storm.set("lifetime", CombatBalance.get_float("bug_storm", "lifetime"))
	storm.set("tick_interval", CombatBalance.get_float("bug_storm", "tick_interval"))
	storm.set("bug_strength", CombatBalance.get_float("bug_storm", "strength"))
	storm.set("fade_time", CombatBalance.get_float("bug_storm", "fade_time"))
	world_root.add_child(storm)
	storm.global_position = position


func _spawn_medicine_storm_visual(position: Vector3, source_team: String) -> void:
	if _resolve_world_root() == null:
		return
	var storm := MEDICINE_STORM_SCENE.instantiate() as Node3D
	if storm == null:
		return
	storm.set("visual_only", true)
	storm.set("source_team", source_team)
	storm.set("effect_distance", CombatBalance.get_float("medicine_storm", "radius"))
	storm.set("lifetime", CombatBalance.get_float("medicine_storm", "lifetime"))
	world_root.add_child(storm)
	storm.global_position = position


func _spawn_spicy_area_visual(position: Vector3, source_team: String, direction_value: Variant) -> void:
	if _resolve_world_root() == null:
		return
	var area := SPICY_AREA_SCENE.instantiate() as Node3D
	if area == null:
		return
	var direction := direction_value as Vector3 if direction_value is Vector3 else Vector3.FORWARD
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	area.set("source_team", source_team)
	area.set("visual_only", true)
	area.set("lifetime", CombatBalance.get_float("spicy_blaster", "area_lifetime"))
	area.set("fade_time", CombatBalance.get_float("spicy_blaster", "area_fade_time"))
	area.set("area_length", CombatBalance.get_float("spicy_blaster", "area_length"))
	area.set("area_width", CombatBalance.get_float("spicy_blaster", "area_width"))
	area.set("area_height", CombatBalance.get_float("spicy_blaster", "area_height"))
	area.set("tick_interval", CombatBalance.get_float("spicy_blaster", "area_tick_interval"))
	world_root.add_child(area)
	area.global_position = position
	area.look_at(area.global_position + direction.normalized(), Vector3.UP)


func _apply_lightning_strike_event(event: Dictionary) -> void:
	# Wand hits are server-confirmed. Render the same confirmed strike for the
	# caster and observers so targets outside the local aim RayCast mask (nature
	# resources and wild animals) still produce the lightning effect.
	var origin: Variant = event.get("origin", Vector3.ZERO)
	var hit_position: Variant = event.get("hit_position", Vector3.ZERO)
	if not origin is Vector3 or not hit_position is Vector3:
		return
	var lightning := LIGHTNING_EFFECT_SCENE.instantiate() as Node3D
	if lightning == null:
		return
	world_root.add_child(lightning)
	if lightning.has_method("strike"):
		lightning.call("strike", origin, hit_position)
	else:
		lightning.queue_free()


func _spawn_laser_line(origin: Vector3, hit_position: Vector3, color: Color) -> void:
	if _resolve_world_root() == null:
		return
	var delta := hit_position - origin
	if delta.length() <= 0.01:
		return
	var visual := MeshInstance3D.new()
	visual.name = "RemoteLaserVisual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = delta.length()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	visual.material_override = material
	world_root.add_child(visual)
	visual.global_position = origin + delta * 0.5
	visual.look_at(hit_position, Vector3.UP)
	visual.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	get_tree().create_timer(0.16).timeout.connect(func() -> void:
		if is_instance_valid(visual):
			visual.queue_free()
	)


func _effect_color(effect: String) -> Color:
	match effect.strip_edges().to_lower():
		"flame", "fire":
			return Color("#FF5A3D")
		"freeze", "ice":
			return Color("#8EEAFF")
		"nail":
			return Color("#D8DEE9")
		"rubber":
			return Color("#FFF4A6")
		"lightening", "lightning":
			return Color("#B78CFF")
		"labeled", "labelled":
			return Color("#54D6A2")
		_:
			return Color("#F6F7FF")


func _spawn_impact_flash(position: Vector3, effect: String) -> void:
	if _resolve_world_root() == null:
		return
	var visual := MeshInstance3D.new()
	visual.name = "ImpactFlashVisual"
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.9
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	var color := Color("#FF8A24") if effect == "Explosion" else Color("#F6F7FF")
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	visual.material_override = material
	world_root.add_child(visual)
	visual.global_position = position
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE * 1.8, 0.18)
	tween.finished.connect(func() -> void:
		if is_instance_valid(visual):
			visual.queue_free()
	)


func _apply_player_damage_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	if peer_id == MultiplayerNetwork.get_unique_peer_id():
		for node in get_tree().get_nodes_in_group("human_players"):
			if node is GamePlayer and int(node.authority_peer_id) == peer_id:
				node.set("server_hp", float(event.get("hp", node.get("server_hp"))))
				node.call("apply_chest_armor_state", event.get("chest_armor", {}))
				node.call("apply_legwear_state", event.get("legwear", {}))
				if str(event.get("effect", "")).to_lower() == TranquilizerBullet.EFFECT_TRANQUILIZER:
					node.call("apply_tranquilizer_effect")
				elif str(event.get("effect", "")).to_lower() in ["labeled", "labelled"]:
					node.set(
						"labeled_remaining",
						CombatBalance.get_float("small_mouse", "labeled_duration")
					)
				var direction: Variant = event.get("direction", Vector3.ZERO)
				if direction is Vector3:
					node.receive_bullet_hit(direction, float(event.get("knockback", 0.0)), "")
				node.call("_update_health_ui")
				break


func _apply_player_healed_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	if peer_id != MultiplayerNetwork.get_unique_peer_id():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == peer_id:
			node.set("server_hp", float(event.get("hp", node.get("server_hp"))))
			node.call("_update_health_ui")
			break


func _apply_player_respawn_state_event(event: Dictionary) -> void:
	var peer_id := int(event.get("peer_id", 0))
	var respawn_left := float(event.get("respawn_seconds", 0.0))
	var spawn_position: Variant = null
	if str(event.get("type", "")) == "player_respawned":
		respawn_left = 0.0
		spawn_position = event.get("position", null)
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == peer_id:
			if str(event.get("type", "")) == "player_died" and not (node as GamePlayer).is_remote_proxy:
				(node as GamePlayer).apply_death_inventory_drop(event.get("dropped_inventory_items", []))
			node.call("apply_respawn_state", respawn_left, spawn_position)
			break


func _apply_tool_destroyed_event(event: Dictionary) -> void:
	var tile_path := str(event.get("tile_path", ""))
	var tile_position: Variant = event.get("position", Vector3.ZERO)
	if not tile_path.is_empty() or tile_position is Vector3:
		var tile := _find_farm_tile(tile_path, tile_position)
		if tile is FarmTile:
			tile.apply_authoritative_tool_destroyed()
	var device_id := str(event.get("device_id", ""))
	if not device_id.is_empty() and remote_device_visuals.has(device_id):
		var visual: Node = remote_device_visuals[device_id]
		if is_instance_valid(visual):
			visual.queue_free()
		remote_device_visuals.erase(device_id)
	if not device_id.is_empty() and placed_tool_visuals.has(device_id):
		var placed_visual: Node = placed_tool_visuals[device_id]
		if is_instance_valid(placed_visual):
			placed_visual.queue_free()
		placed_tool_visuals.erase(device_id)


func _apply_low_frequency_snapshot(snapshot: Dictionary) -> void:
	var rare_resource: Variant = snapshot.get("rare_resource", {})
	if rare_resource is Dictionary and not (rare_resource as Dictionary).is_empty():
		_apply_rare_resource_spawned(rare_resource as Dictionary)
	else:
		_remove_rare_resource_visual()
	var nature_resources: Variant = snapshot.get("nature_resources", [])
	if nature_resources is Array:
		for state_value: Variant in nature_resources:
			if state_value is Dictionary:
				_apply_nature_resource_health(state_value as Dictionary)
	var livestock_growth: Variant = snapshot.get("livestock_growth", [])
	if livestock_growth is Array:
		for growth_value: Variant in livestock_growth:
			if not growth_value is Dictionary:
				continue
			var growth_state := growth_value as Dictionary
			var animal_id := str(growth_state.get("animal_id", ""))
			var animal: Node = wild_animal_visuals.get(animal_id, null)
			if is_instance_valid(animal) and animal.has_method("apply_network_growth_state"):
				animal.call("apply_network_growth_state", growth_state)
	var inventory: Variant = snapshot.get("inventory", {})
	if inventory is Dictionary:
		_on_inventory_state_received(inventory)
	var active_respawn_teams := {}
	var cargo_respawns: Variant = snapshot.get("cargo_car_respawns", [])
	if cargo_respawns is Array:
		for state_value: Variant in cargo_respawns:
			if not state_value is Dictionary:
				continue
			var state := state_value as Dictionary
			var team := str(state.get("team", ""))
			if team.is_empty():
				continue
			active_respawn_teams[team] = true
			_apply_cargo_car_respawn_state(state)
		for node in get_tree().get_nodes_in_group("team_garages"):
			if node is TeamGarage and not active_respawn_teams.has((node as TeamGarage).owner_team):
				(node as TeamGarage).set_respawn_state(false, 0.0)
	var farm_tiles: Variant = snapshot.get("farm_tiles", [])
	if farm_tiles is Array:
		for item: Variant in farm_tiles:
			if not item is Dictionary:
				continue
			var state := item as Dictionary
			var tile_path := str(state.get("tile_path", ""))
			var tile_position: Variant = state.get("tile_position", Vector3.ZERO)
			if tile_path.is_empty() and not tile_position is Vector3:
				continue
			var tile := _find_farm_tile(tile_path, tile_position)
			if tile is FarmTile:
				tile.apply_authoritative_state(state)
	var extractors: Variant = snapshot.get("extractors", [])
	if extractors is Array:
		for state_value: Variant in extractors:
			_apply_extractor_state(state_value)
	var auto_cookers: Variant = snapshot.get("auto_cookers", [])
	if auto_cookers is Array:
		for state_value: Variant in auto_cookers:
			_apply_auto_cooker_state(state_value)
	var induction_counters: Variant = snapshot.get("induction_counters", [])
	if induction_counters is Array:
		for state_value: Variant in induction_counters:
			_apply_recipe_cooking_station_state(state_value, "induction_counters", "SubViewport/InductionCounterPage")
	var freezers: Variant = snapshot.get("freezers", [])
	if freezers is Array:
		for state_value: Variant in freezers:
			_apply_recipe_cooking_station_state(state_value, "freezer_stations", "SubViewport/FreezerPage")
	var stand_mixers: Variant = snapshot.get("stand_mixers", [])
	if stand_mixers is Array:
		for state_value: Variant in stand_mixers:
			_apply_mixer_state(state_value)
	var livestock_chops: Variant = snapshot.get("livestock_chops", [])
	if livestock_chops is Array:
		for state_value: Variant in livestock_chops:
			_apply_livestock_chop_state(state_value)
	_sync_dropped_items(snapshot.get("dropped_items", []))


func _apply_nature_resource_health(state: Dictionary) -> void:
	var resource_id := str(state.get("resource_id", ""))
	if resource_id.is_empty():
		return
	var resource := _nature_resource_by_id(resource_id)
	if resource == null:
		return
	if resource.has_method("apply_network_health"):
		resource.call("apply_network_health", float(state.get("hp", 0.0)))
	var resource_destroyed := bool(resource.get("destroyed")) if _replicator_has_property(resource, "destroyed") else false
	if bool(state.get("destroyed", false)) and resource.has_method("apply_network_destroyed") and not resource_destroyed:
		resource.call("apply_network_destroyed", Vector3.ZERO)
	elif not bool(state.get("destroyed", false)) and resource_destroyed and resource.has_method("apply_network_respawned"):
		resource.call("apply_network_respawned")


func _replicator_has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _find_farm_tile(tile_path: String, tile_position_value: Variant) -> FarmTile:
	if not tile_path.is_empty():
		var node := get_node_or_null(NodePath(tile_path))
		if node is FarmTile:
			return node as FarmTile
	if tile_position_value is Vector3:
		var tile_position: Vector3 = tile_position_value
		var manager := get_node_or_null("/root/Farmlandmanager")
		if manager != null and manager.has_method("get_plots_in_radius"):
			var plots: Array = manager.call("get_plots_in_radius", tile_position, 1.4)
			var best: FarmTile = null
			var best_distance := INF
			for plot in plots:
				if not plot is FarmTile:
					continue
				var distance := (plot as FarmTile).global_position.distance_squared_to(tile_position)
				if distance < best_distance:
					best_distance = distance
					best = plot
			if best != null:
				return best
	return null


func _on_inventory_state_received(state: Dictionary) -> void:
	var teams: Variant = state.get("teams", {})
	if teams is Dictionary:
		GlobalVar.team_storage = (teams as Dictionary).duplicate(true)
		for team in GlobalVar.team_storage.keys():
			var team_data: Variant = GlobalVar.team_storage[team]
			if team_data is Dictionary:
				for item_name in (team_data as Dictionary).keys():
					GlobalVar.storage_changed.emit(str(team), str(item_name), float((team_data as Dictionary).get(item_name, 0.0)))
	var scores: Variant = state.get("scores", {})
	if scores is Dictionary:
		GlobalVar.apply_team_scores(scores as Dictionary)


func _disable_visual_runtime(root: Node) -> void:
	if root is Camera3D:
		var proxy_camera := root as Camera3D
		proxy_camera.current = false
		proxy_camera.set_process(false)
		proxy_camera.set_physics_process(false)
		proxy_camera.set_process_input(false)
		return
	# Tracers are presentation-only, but their geometry is rebuilt from their
	# parent's movement in _physics_process(). Do not disable that update when a
	# server-confirmed projectile is converted into a collision-free visual.
	if root is BulletTracerSegment:
		return
	# Preserve the cooker animation and local interaction collision on clients.
	if root is AutoCooker:
		return
	root.set_process(false)
	root.set_physics_process(false)
	root.set_process_input(false)
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	for child in root.get_children():
		if child is Node:
			_disable_visual_runtime(child)


func _on_disconnected(_reason: String) -> void:
	_clear_all()


func _clear_all() -> void:
	_remove_rare_resource_visual()
	for collection in [remote_players, projectile_visuals, transient_projectile_visuals, absorption_visuals, remote_device_visuals, placed_tool_visuals, dropped_item_visuals, wild_animal_visuals]:
		for key in collection.keys():
			var item = collection[key]
			var node: Node = item.get("node", null) if item is Dictionary else item
			if is_instance_valid(node):
				node.queue_free()
		collection.clear()
	absorbed_projectile_ids.clear()
	processed_absorption_ids.clear()
	_invalidate_nature_resource_index()
	world_root = null
