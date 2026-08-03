extends Node3D
class_name FarmWorldInitializer

signal map_initialization_progress(progress: float, status: String)
signal map_initialization_completed

@export var loading_map_name := "Creston Town"
@export_dir var loading_images_directory := "res://assets/loading/creston_town"
@export_file("*.json") var loading_tips_path := "res://data/loading_tips.json"

var is_map_initialized := false
var _configured_ai_nodes: Array[Node] = []

const FUTURE_WARRIOR_AI_SCENE := preload("res://character/FutureWarriorAI.tscn")
const FARMER_AI_SCENE := preload("res://character/FarmerAI.tscn")
const ASSISTANT_AI_SCENE := preload("res://character/AssistantAI.tscn")
const AI_SCENE_PATHS := {
	"futurewarrior": "res://character/FutureWarriorAI.tscn",
	"future_warrior": "res://character/FutureWarriorAI.tscn",
	"farmer": "res://character/FarmerAI.tscn",
	"farmerai": "res://character/FarmerAI.tscn",
	"assistant": "res://character/AssistantAI.tscn",
	"assistantai": "res://character/AssistantAI.tscn",
}


func _ready() -> void:
	GlobalVar.gameworld = self
	# Custom maps exported by the runtime editor are user:// scenes, so their
	# serialized light settings can lag behind editor changes.  Enforce the same
	# near-field dynamic-shadow contract here after child DayNightSystem nodes
	# have initialized.  This applies equally to built-in and user maps.
	_configure_runtime_shadow_contract()
	# Existing editor packages were saved with a noon start time.  Use the same
	# morning angle as Creston for editor-generated worlds, so directional
	# shadows remain visibly offset from trees, characters, and buildings.
	_configure_editor_map_daylight()
	# Older editor packages persist manually painted MultiMeshes with shadow
	# casting disabled. Run after child _ready/deferred builders so both old
	# packages and newly generated resource MultiMeshes use the same setting.
	call_deferred("_enforce_runtime_shadow_casters")
	# Pre-fix editor packages embedded a modified two-sided terrain shader. Use
	# the same receiver shader as Creston at runtime as well, so players do not
	# need to recreate existing maps just to obtain dynamic shadows.
	call_deferred("_restore_editor_terrain_shadow_receiver")
	# Old packages saved their full-map terrain and foundation as shadow casters.
	# Disable those legacy casters after the scene has finished constructing.
	call_deferred("_disable_editor_terrain_shadow_casters")
	MapLoading.ensure_loading(loading_map_name, loading_images_directory, loading_tips_path)
	_set_loading_progress(0.25, "正在初始化地图系统")
	await get_tree().process_frame
	await _initialize_farm_fields()
	_set_loading_progress(0.96, "正在完成地图初始化")
	await get_tree().process_frame
	var player := _create_pending_player()
	var configured_ai: Array[Node] = []
	if player != null:
		_set_loading_progress(0.99, "正在生成玩家")
		await get_tree().process_frame
	# AI is a map rule, not a mode-wide default.  A map with no AI entries
	# deliberately creates no NPCs.  The host/server owns these nodes in both
	# single-player and cooperative PvE; clients only receive their replicated
	# state through the normal authority/replicator path.
	var is_cooperative_host := CooperativeSession.is_active() and CooperativeSession.is_host()
	if GameAuthority.is_local_authority() or (GameAuthority.is_server_authority() and is_cooperative_host):
		configured_ai = _spawn_configured_ai()
	_configured_ai_nodes = configured_ai
	var cooperative_loading := CooperativeSession.is_active()
	if not cooperative_loading:
		await MapLoading.finish_loading()
	if is_instance_valid(player) and not cooperative_loading:
		player.process_mode = Node.PROCESS_MODE_INHERIT
	if not cooperative_loading:
		for ai_value in configured_ai:
			if is_instance_valid(ai_value):
				ai_value.process_mode = Node.PROCESS_MODE_INHERIT
	is_map_initialized = true
	map_initialization_completed.emit()


func activate_runtime_entities() -> void:
	for ai_value in _configured_ai_nodes:
		if is_instance_valid(ai_value):
			ai_value.process_mode = Node.PROCESS_MODE_INHERIT


func _configure_runtime_shadow_contract() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		push_warning("Map is missing Sun; dynamic shadows are unavailable.")
		return
	sun.shadow_enabled = true
	# Deliberately matches Creston's default DirectionalLight3D settings. This
	# also overwrites old editor packages that saved the problematic 512m CSM.
	sun.directional_shadow_max_distance = 100.0


func _configure_editor_map_daylight() -> void:
	if not bool(get_meta("farmwar_editor_generated", false)):
		return
	var day_night := get_node_or_null("DayNightSystem")
	if day_night == null:
		return
	day_night.set("initial_hour", 10.0)
	# DayNightSystem has already run _ready by the time FarmWorldInitializer is
	# ready, so reapply immediately instead of leaving one noon-lit frame.
	day_night.call("_apply_time_of_day")


func _enforce_runtime_shadow_casters() -> void:
	for root_name in ["ManualGrass", "GrassScatter", "Trees", "Ores", "Buildings"]:
		var root := get_node_or_null(NodePath(root_name))
		if root != null:
			_set_shadow_casting_recursive(root)


func _set_shadow_casting_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_set_shadow_casting_recursive(child)


func _restore_editor_terrain_shadow_receiver() -> void:
	if not bool(get_meta("farmwar_editor_generated", false)):
		return
	var source_shader := load("res://src/terrain/terrain_surface.gdshader") as Shader
	var terrain_root := get_node_or_null("Ground/Grass")
	if source_shader == null or terrain_root == null:
		return
	var needs_winding_repair := int(get_meta("farmwar_terrain_winding_version", 1)) < 2
	var replacements: Dictionary = {}
	for mesh_value in terrain_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		var material := mesh_instance.material_override as ShaderMaterial
		if material != null:
			var material_id := material.get_instance_id()
			var corrected := replacements.get(material_id, null) as ShaderMaterial
			if corrected == null:
				corrected = material.duplicate() as ShaderMaterial
				corrected.shader = source_shader
				replacements[material_id] = corrected
			mesh_instance.material_override = corrected
		if needs_winding_repair:
			_repair_editor_terrain_winding(mesh_instance)
	if needs_winding_repair:
		set_meta("farmwar_terrain_winding_version", 2)


func _repair_editor_terrain_winding(mesh_instance: MeshInstance3D) -> void:
	if bool(mesh_instance.get_meta("farmwar_shadow_winding_fixed", false)):
		return
	var source_mesh := mesh_instance.mesh as ArrayMesh
	if source_mesh == null or source_mesh.get_surface_count() != 1:
		return
	var arrays := source_mesh.surface_get_arrays(0)
	var source_indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	if source_indices.is_empty() or source_indices.size() % 3 != 0:
		return
	var corrected_indices := source_indices.duplicate()
	for index in range(0, corrected_indices.size(), 3):
		var second := corrected_indices[index + 1]
		corrected_indices[index + 1] = corrected_indices[index + 2]
		corrected_indices[index + 2] = second
	arrays[Mesh.ARRAY_INDEX] = corrected_indices
	var repaired_mesh := ArrayMesh.new()
	repaired_mesh.add_surface_from_arrays(
		source_mesh.surface_get_primitive_type(0), arrays
	)
	mesh_instance.mesh = repaired_mesh
	mesh_instance.set_meta("farmwar_shadow_winding_fixed", true)


func _disable_editor_terrain_shadow_casters() -> void:
	if not bool(get_meta("farmwar_editor_generated", false)):
		return
	for root_path in [NodePath("Ground/Grass"), NodePath("TerrainFoundation")]:
		var root := get_node_or_null(root_path)
		if root == null:
			continue
		for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
			(mesh_value as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground_base := get_node_or_null("Ground/GroundBase") as MeshInstance3D
	if ground_base != null:
		ground_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground_base.visible = false


func wait_until_initialized() -> void:
	if is_map_initialized:
		return
	await map_initialization_completed


func _initialize_farm_fields() -> void:
	var fields: Array[FarmFieldGenerator] = []
	_collect_farm_fields(self, fields)
	var total_tiles := 0
	for field in fields:
		total_tiles += field.length_tiles * field.width_tiles
	if total_tiles <= 0:
		_set_loading_progress(0.9, "地图系统已准备")
		return

	var completed_tiles := 0
	for field in fields:
		var completed_before_field := completed_tiles
		var progress_callback := func(_field_id: String, generated: int, _total: int) -> void:
			var overall := float(completed_before_field + generated) / float(total_tiles)
			var progress := lerpf(0.25, 0.92, overall)
			_set_loading_progress(progress, "正在生成%s农田" % _field_display_name(field))
		field.generation_progress.connect(progress_callback)
		await field.generate_field_async()
		if field.generation_progress.is_connected(progress_callback):
			field.generation_progress.disconnect(progress_callback)
		completed_tiles += field.length_tiles * field.width_tiles


func _collect_farm_fields(node: Node, result: Array[FarmFieldGenerator]) -> void:
	for child in node.get_children():
		if child is FarmFieldGenerator:
			result.append(child as FarmFieldGenerator)
		_collect_farm_fields(child, result)


func _field_display_name(field: FarmFieldGenerator) -> String:
	if field.field_label.begins_with("red"):
		return "红队"
	if field.field_label.begins_with("blue"):
		return "蓝队"
	return field.field_label


func _create_pending_player() -> GamePlayer:
	if GlobalVar.pending_player_selection.is_empty():
		return null
	if CooperativeSession.is_active():
		GlobalVar.pending_player_selection = {}
		return null
	var selection := GlobalVar.pending_player_selection.duplicate(true)
	var player := load("res://character/player.tscn").instantiate() as GamePlayer
	if player == null:
		push_error("地图初始化完成，但无法创建玩家场景。")
		return null
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.apply_loadout_selection(selection)
	if selection.has("position") and selection["position"] is Vector3:
		player.global_position = selection["position"]
	else:
		player.global_position = get_team_spawn_position(
			str(selection.get("team", "red")),
			0,
			int(selection.get("peer_id", GameAuthority.LOCAL_PLAYER_ID))
		)
	if not GameAuthority.is_client_proxy():
		selection["position"] = player.global_position
		GameAuthority.register_or_update_player(
			int(selection.get("peer_id", GameAuthority.LOCAL_PLAYER_ID)),
			selection
		)
	GlobalVar.pending_player_selection = {}
	return player


func _spawn_configured_ai() -> Array[Node]:
	var result: Array[Node] = []
	var configured_value: Variant = get_meta("farmwar_ai_configuration", [])
	if not configured_value is Array:
		return result
	var configured := configured_value as Array
	for index in range(configured.size()):
		if not configured[index] is Dictionary:
			continue
		var entry := configured[index] as Dictionary
		var ai_type := _normalize_ai_type(str(entry.get("ai_type", entry.get("type", ""))))
		var scene_path := str(AI_SCENE_PATHS.get(ai_type, ""))
		if scene_path.is_empty():
			push_warning("地图 AI 配置 #%d 使用了未知类型：%s" % [index + 1, ai_type])
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("无法加载地图 AI 场景：%s" % scene_path)
			continue
		var ai := packed.instantiate() as Node
		if ai == null:
			continue
		var team := str(entry.get("team", "" )).to_lower()
		if team not in ["red", "blue"]:
			push_warning("地图 AI #%d 的队伍无效，跳过生成。" % (index + 1))
			ai.free()
			continue
		var spawn_id := str(entry.get("spawn_point_id", "")).strip_edges()
		var spawn_position := get_spawn_position_for_id(
			spawn_id,
			team,
			index,
			GameAuthority.LOCAL_PLAYER_ID + index
		)
		if spawn_position == Vector3.INF:
			push_warning("地图 AI #%d 没有可用的 %s 队出生点，跳过生成。" % [index + 1, team])
			ai.free()
			continue
		ai.name = str(entry.get("name", "%s_%s_%02d" % [ai_type.capitalize(), team.capitalize(), index + 1]))
		ai.set_meta("network_ai_id", "map_ai_%02d" % (index + 1))
		ai.set_meta("map_ai_type", ai_type)
		_set_property_if_present(ai, "team_id", team)
		_set_property_if_present(ai, "spawn_point_id", spawn_id)
		_set_property_if_present(ai, "respawn_seconds", clampf(float(entry.get("respawn_seconds", 10.0)), 1.0, 600.0))
		ai.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(ai)
		if ai is Node3D:
			(ai as Node3D).global_position = spawn_position
		result.append(ai)
	return result


func _normalize_ai_type(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_")


func _set_property_if_present(object: Object, property_name: String, value: Variant) -> void:
	if object == null:
		return
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			object.set(property_name, value)
			return


func get_team_spawn_position(team: String, player_index := 0, random_seed := 0) -> Vector3:
	var points := get_team_spawn_points(team)
	if points.is_empty():
		push_warning("地图缺少 %s 队独立出生点，使用地图中心作为后备出生点。" % team)
		return Vector3(0.0, 1.5, 0.0)
	points.sort_custom(func(left: TeamSpawnPoint, right: TeamSpawnPoint) -> bool:
		return left.spawn_point_id < right.spawn_point_id
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%d" % [random_seed, team, player_index])
	var point := points[rng.randi_range(0, points.size() - 1)]
	return point.get_spawn_position(player_index, random_seed)


func get_team_spawn_points(team: String) -> Array[TeamSpawnPoint]:
	var points: Array[TeamSpawnPoint] = []
	for point_value: Node in get_tree().get_nodes_in_group("team_spawn_points"):
		if point_value is TeamSpawnPoint and str((point_value as TeamSpawnPoint).team).to_lower() == team.to_lower():
			points.append(point_value as TeamSpawnPoint)
	points.sort_custom(func(left: TeamSpawnPoint, right: TeamSpawnPoint) -> bool:
		return left.spawn_point_id < right.spawn_point_id
	)
	return points


func get_spawn_position_for_id(spawn_point_id: String, team: String, player_index := 0, random_seed := 0) -> Vector3:
	var points := get_team_spawn_points(team)
	if not spawn_point_id.is_empty():
		for point in points:
			if point.spawn_point_id == spawn_point_id:
				return point.get_spawn_position(player_index, random_seed)
	if points.is_empty():
		return Vector3.INF
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ai:%d:%s:%d" % [random_seed, team, player_index])
	return points[rng.randi_range(0, points.size() - 1)].get_spawn_position(player_index, random_seed)


func get_random_enemy_spawn_position(team: String, random_seed := 0, player_index := 0) -> Vector3:
	var enemy_team := "blue" if team.to_lower() == "red" else "red"
	return get_spawn_position_for_id("", enemy_team, player_index, random_seed)


func _set_loading_progress(progress: float, status: String) -> void:
	map_initialization_progress.emit(progress, status)
	MapLoading.update_progress(progress, status)
