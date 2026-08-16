extends Node3D

## 可视化兴趣区块测试场景：
## - 世界范围 1024m x 1024m，划分为 16 个 256m x 256m 区块。
## - Camera3D 初始位于玩家位置 (0, 0, 0) 上方，可按地图编辑器方式自由移动和观察。
## - 每个区块默认放置 2 个蓝队 AI，类型在 Warrior/Engineer/Bandit/Assistant 之间轮换。
## - 每个区块只有一个 Node3D 战略目标；目标节点收集到 target_nodes 数组中。
## - 黄色光柱跟随目标节点，每 20 秒把目标移动到同一区块内的另一个明显位置。

const MAP_SIZE_METERS := 1024.0
const CHUNK_SIZE_METERS := 256.0
const CHUNK_COUNT_PER_AXIS := 4
const DEFAULT_AI_PER_CHUNK := 2
const TARGET_MOVE_INTERVAL_SECONDS := 20.0
const FLOOR_Y := 0.0

const AI_SCENES := {
	"warrior": "res://character/FutureWarriorAI.tscn",
	"engineer": "res://character/FutureEngineerAI.tscn",
	"bandit": "res://character/BanditAI.tscn",
	"assistant": "res://character/AssistantAI.tscn",
}
const AI_TYPE_ORDER: Array[String] = ["warrior", "engineer", "bandit", "assistant"]
const TARGET_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(60.0, 0.0, 60.0),
	Vector3(-60.0, 0.0, 55.0),
	Vector3(0.0, 0.0, -60.0),
]

@export_range(2, 3, 1) var ai_per_chunk := DEFAULT_AI_PER_CHUNK
@export var target_move_interval_seconds := TARGET_MOVE_INTERVAL_SECONDS
@export var enable_ai_interest_sleep := true
@export var quit_after_headless_frames := 0

## 公开数组：每个 256m 区块一个目标 Node3D。
var target_nodes: Array[Node3D] = []
var ai_nodes: Array[Node3D] = []

var _target_chunk_centers: Array[Vector3] = []
var _target_move_phase := 0
var _target_move_remaining := TARGET_MOVE_INTERVAL_SECONDS
var _status_label: Label
var _authority_started := false
var _headless_frames := 0
var _grid_material: StandardMaterial3D
var _active_chunk_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _target_material: StandardMaterial3D
var _target_core_material: StandardMaterial3D
var _camera_rig: CharacterBody3D
var _editor_camera: Camera3D
var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(-35.0)
var _camera_speed := 28.0
var _camera_look_active := false
var _camera_ground_clearance := 1.5
var _camera_boundary_margin := 4.0
var _active_chunk_surfaces: Dictionary = {}
var _camera_player_chunk := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	_target_move_remaining = maxf(1.0, target_move_interval_seconds)
	# 让真实 AI 的权威逻辑在这个独立场景中可运行；测试中的玩家只用
	# GameAuthority.player_states 表示，不额外创建一个会干扰 AI 目标筛选的 GamePlayer。
	GlobalVar.gameworld = self
	GameAuthority.start_local_mode({
		"display_name": "AIInterestVisualizationPlayer",
		"team": "red",
		"position": Vector3(0.0, FLOOR_Y, 0.0),
	})
	_authority_started = true

	_build_environment()
	_build_floor()
	_build_chunk_grid()
	_build_active_chunk_surfaces()
	_build_navigation_region()
	_build_player_center_marker()
	_build_status_overlay()
	_build_targets_and_ai()
	if enable_ai_interest_sleep:
		GameAuthority.refresh_ai_interest(true)


func _process(delta: float) -> void:
	_update_free_camera(delta)
	_sync_visualization_player_position()
	_target_move_remaining -= delta
	if _target_move_remaining <= 0.0:
		_target_move_remaining += maxf(1.0, target_move_interval_seconds)
		_move_all_targets()
	_update_status_overlay()

	if DisplayServer.get_name() == "headless" and quit_after_headless_frames > 0:
		_headless_frames += 1
		if _headless_frames >= quit_after_headless_frames:
			get_tree().quit(0)


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _authority_started and GameAuthority.is_local_authority():
		GameAuthority.stop_authority()
	if GlobalVar.gameworld == self:
		GlobalVar.gameworld = null


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "VisualizationEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.05, 0.075, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.9, 1.0)
	environment.ambient_light_energy = 0.85
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "VisualizationKeyLight"
	key_light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	add_child(key_light)

	_camera_rig = CharacterBody3D.new()
	_camera_rig.name = "PlayerCameraRig"
	_camera_rig.collision_layer = 0
	_camera_rig.collision_mask = GameAuthority.COLLISION_LAYER_GROUND
	_camera_rig.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_child(_camera_rig)
	var rig_collision := CollisionShape3D.new()
	rig_collision.name = "CameraCollisionShape"
	var rig_sphere := SphereShape3D.new()
	rig_sphere.radius = 1.0
	rig_collision.shape = rig_sphere
	_camera_rig.add_child(rig_collision)

	_editor_camera = Camera3D.new()
	_editor_camera.name = "PlayerCamera"
	_editor_camera.near = 0.1
	_editor_camera.far = 1600.0
	_editor_camera.fov = 65.0
	_editor_camera.current = true
	_camera_rig.add_child(_editor_camera)
	_camera_rig.position = Vector3(0.0, 45.0, 0.0)
	_camera_yaw = 0.0
	_camera_pitch = deg_to_rad(-35.0)
	_camera_speed = 28.0
	_apply_camera_rotation()


func _build_floor() -> void:
	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_color = Color("#183b2a")
	_floor_material.roughness = 0.92

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "VisualizationFloor"
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(MAP_SIZE_METERS, 0.10, MAP_SIZE_METERS)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0.0, FLOOR_Y - 0.05, 0.0)
	floor_mesh.material_override = _floor_material
	add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.name = "VisualizationGroundCollision"
	floor_body.collision_layer = GameAuthority.COLLISION_LAYER_GROUND
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box_shape := BoxShape3D.new()
	floor_box_shape.size = Vector3(MAP_SIZE_METERS, 0.10, MAP_SIZE_METERS)
	floor_shape.shape = floor_box_shape
	floor_shape.position = Vector3(0.0, FLOOR_Y - 0.05, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)


func _build_chunk_grid() -> void:
	_grid_material = StandardMaterial3D.new()
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_material.albedo_color = Color(1.0, 0.035, 0.035, 1.0)
	_grid_material.emission_enabled = true
	_grid_material.emission = Color(1.0, 0.01, 0.01, 1.0)
	_grid_material.emission_energy_multiplier = 3.5

	var half_map := MAP_SIZE_METERS * 0.5
	for index in range(CHUNK_COUNT_PER_AXIS + 1):
		var coordinate := -half_map + float(index) * CHUNK_SIZE_METERS
		_add_grid_bar(
			"GridX_%02d" % index,
			Vector3(coordinate, FLOOR_Y + 0.035, 0.0),
			Vector3(1.8, 0.07, MAP_SIZE_METERS + 2.0)
		)
		_add_grid_bar(
			"GridZ_%02d" % index,
			Vector3(0.0, FLOOR_Y + 0.035, coordinate),
			Vector3(MAP_SIZE_METERS + 2.0, 0.07, 1.8)
		)


func _build_active_chunk_surfaces() -> void:
	_active_chunk_material = StandardMaterial3D.new()
	_active_chunk_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_active_chunk_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_active_chunk_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_active_chunk_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_active_chunk_material.albedo_color = Color(0.05, 0.32, 1.0, 0.24)
	_active_chunk_material.emission_enabled = true
	_active_chunk_material.emission = Color(0.02, 0.24, 1.0, 1.0)
	_active_chunk_material.emission_energy_multiplier = 1.4

	var half_map := MAP_SIZE_METERS * 0.5
	for z_index in range(CHUNK_COUNT_PER_AXIS):
		for x_index in range(CHUNK_COUNT_PER_AXIS):
			var chunk := Vector2i(
				floori((-half_map + float(x_index) * CHUNK_SIZE_METERS) / CHUNK_SIZE_METERS),
				floori((-half_map + float(z_index) * CHUNK_SIZE_METERS) / CHUNK_SIZE_METERS)
			)
			var surface := MeshInstance3D.new()
			surface.name = "ActiveChunkSurface_%d_%d" % [chunk.x, chunk.y]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(CHUNK_SIZE_METERS, 0.018, CHUNK_SIZE_METERS)
			surface.mesh = mesh
			surface.position = Vector3(
				(float(chunk.x) + 0.5) * CHUNK_SIZE_METERS,
				FLOOR_Y + 0.009,
				(float(chunk.y) + 0.5) * CHUNK_SIZE_METERS
			)
			surface.material_override = _active_chunk_material
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			surface.visible = false
			add_child(surface)
			_active_chunk_surfaces[chunk] = surface


func _add_grid_bar(bar_name: String, position: Vector3, size: Vector3) -> void:
	var bar := MeshInstance3D.new()
	bar.name = bar_name
	var mesh := BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.position = position
	bar.material_override = _grid_material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bar)


func _build_navigation_region() -> void:
	var region := NavigationRegion3D.new()
	region.name = "VisualizationNavigationRegion"
	var navigation_mesh := NavigationMesh.new()
	var half_map := MAP_SIZE_METERS * 0.5
	# Counter-clockwise when viewed from above, producing an upward-facing quad.
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-half_map, FLOOR_Y, -half_map),
		Vector3(-half_map, FLOOR_Y, half_map),
		Vector3(half_map, FLOOR_Y, half_map),
		Vector3(half_map, FLOOR_Y, -half_map),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = navigation_mesh
	add_child(region)


func _build_player_center_marker() -> void:
	var marker := Node3D.new()
	marker.name = "PlayerPosition_CameraCenter"
	marker.position = Vector3(0.0, FLOOR_Y + 0.08, 0.0)
	marker.set_meta("represents_player_position", true)
	add_child(marker)

	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 7.0
	mesh.bottom_radius = 7.0
	mesh.height = 0.12
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_emission_material(Color("#20d8ff"), 2.5)
	marker.add_child(mesh_instance)

	var label := Label3D.new()
	label.text = "PLAYER / CAMERA"
	label.position = Vector3(0.0, 3.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 46
	label.modulate = Color("#55eaff")
	label.outline_size = 8
	label.outline_modulate = Color(0.02, 0.08, 0.12, 1.0)
	marker.add_child(label)


func _build_status_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VisualizationStatusLayer"
	add_child(layer)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(24.0, 20.0)
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color("#f0f5ff"))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_status_label.add_theme_constant_override("shadow_offset_x", 2)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_status_label)


func _build_targets_and_ai() -> void:
	var half_map := MAP_SIZE_METERS * 0.5
	var chunk_index := 0
	for z_index in range(CHUNK_COUNT_PER_AXIS):
		for x_index in range(CHUNK_COUNT_PER_AXIS):
			var center := Vector3(
				-half_map + CHUNK_SIZE_METERS * 0.5 + float(x_index) * CHUNK_SIZE_METERS,
				FLOOR_Y,
				-half_map + CHUNK_SIZE_METERS * 0.5 + float(z_index) * CHUNK_SIZE_METERS
			)
			var target := _create_target_node(chunk_index, center)
			target_nodes.append(target)
			_target_chunk_centers.append(center)
			for slot in range(ai_per_chunk):
				var type_index := (chunk_index * ai_per_chunk + slot) % AI_TYPE_ORDER.size()
				_spawn_visual_ai(
					AI_TYPE_ORDER[type_index],
					center + _ai_spawn_offset(slot, chunk_index),
					target,
					chunk_index,
					slot
				)
			chunk_index += 1


func _create_target_node(index: int, center: Vector3) -> Node3D:
	var target := Node3D.new()
	target.name = "TargetNode_%02d" % index
	target.position = center + Vector3.UP * 0.06
	target.add_to_group("squad_target_points")
	target.set_meta("visualization_chunk_index", index)
	add_child(target)

	var pillar := MeshInstance3D.new()
	pillar.name = "YellowTargetPillar"
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 1.5
	pillar_mesh.bottom_radius = 1.5
	pillar_mesh.height = 36.0
	pillar.mesh = pillar_mesh
	pillar.position = Vector3(0.0, 18.0, 0.0)
	pillar.material_override = _get_target_material()
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(pillar)

	var core := MeshInstance3D.new()
	core.name = "TargetCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 3.8
	core_mesh.height = 7.6
	core.mesh = core_mesh
	core.position = Vector3(0.0, 1.0, 0.0)
	core.material_override = _get_target_core_material()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(core)

	var light := OmniLight3D.new()
	light.name = "TargetYellowLight"
	light.position = Vector3(0.0, 14.0, 0.0)
	light.light_color = Color("#ffd21a")
	light.light_energy = 1.25
	light.omni_range = 30.0
	light.shadow_enabled = false
	target.add_child(light)

	var label := Label3D.new()
	label.name = "TargetLabel"
	label.text = "TARGET %02d" % index
	label.position = Vector3(0.0, 39.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.modulate = Color("#ffe34d")
	label.outline_size = 7
	label.outline_modulate = Color(0.12, 0.08, 0.0, 1.0)
	target.add_child(label)
	return target


func _spawn_visual_ai(
	ai_type: String,
	position: Vector3,
	target: Node3D,
	chunk_index: int,
	slot: int
) -> void:
	var scene := load(str(AI_SCENES.get(ai_type, ""))) as PackedScene
	if scene == null:
		push_error("[AIInterestVisualization] Cannot load AI scene: %s" % ai_type)
		return
	var ai := scene.instantiate() as Node3D
	if ai == null:
		push_error("[AIInterestVisualization] Invalid AI root: %s" % ai_type)
		return
	ai.name = "Blue_%s_Chunk%02d_%d" % [ai_type, chunk_index, slot]
	_set_property_if_present(ai, "team_id", "blue")
	_set_property_if_present(ai, "server_authoritative", true)
	_set_property_if_present(ai, "target", target)
	_set_property_if_present(ai, "print_decisions", false)
	_set_property_if_present(ai, "console_debug_enabled", false)
	_set_property_if_present(ai, "starting_grenade_count", 0)
	if ai_type == "assistant":
		# The authored Assistant default uses a case-variant path on macOS;
		# point this visualization at the actual project resource name.
		_set_property_if_present(ai, "nailgun_scene_path", "res://character/weapons/NailGun.tscn")
	add_child(ai)
	ai.global_position = position
	if ai.has_method("set_strategic_target"):
		ai.call("set_strategic_target", target)
	elif ai.has_method("set_target"):
		ai.call("set_target", target)
	ai_nodes.append(ai)


func _ai_spawn_offset(slot: int, chunk_index: int) -> Vector3:
	var side := -1.0 if slot == 0 else 1.0
	var depth := -1.0 if (chunk_index + slot) % 2 == 0 else 1.0
	return Vector3(42.0 * side, 0.05, 34.0 * depth)


func _move_all_targets() -> void:
	_target_move_phase = (_target_move_phase + 1) % TARGET_OFFSETS.size()
	for index in range(target_nodes.size()):
		var target := target_nodes[index]
		if not is_instance_valid(target):
			continue
		var offset_index := (_target_move_phase + index) % TARGET_OFFSETS.size()
		target.global_position = _target_chunk_centers[index] + TARGET_OFFSETS[offset_index] + Vector3.UP * 0.06


func _get_target_material() -> StandardMaterial3D:
	if _target_material == null:
		_target_material = _make_emission_material(Color("#ffd21a"), 5.0)
		_target_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_target_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_target_material.albedo_color = Color(1.0, 0.78, 0.05, 0.72)
	return _target_material


func _get_target_core_material() -> StandardMaterial3D:
	if _target_core_material == null:
		_target_core_material = _make_emission_material(Color("#fff36a"), 7.0)
	return _target_core_material


func _make_emission_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _set_property_if_present(node: Object, property_name: String, value: Variant) -> void:
	for property_info: Dictionary in node.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			node.set(property_name, value)
			return


func _update_status_overlay() -> void:
	if _status_label == null:
		return
	var active_chunk_list: Array[Vector2i] = GameAuthority.get_ai_interest_active_chunks() if enable_ai_interest_sleep else []
	_update_active_chunk_surfaces(active_chunk_list)
	var sleeping := GameAuthority.get_ai_interest_sleeping_count() if enable_ai_interest_sleep else 0
	var active_chunks := active_chunk_list.size()
	var camera_position := _camera_rig.global_position if is_instance_valid(_camera_rig) else Vector3.ZERO
	_status_label.text = (
		"AI Interest Visualization\n"
		+ "Map: 1024m x 1024m   Chunk: 256m x 256m   AI/chunk: %d\n" % ai_per_chunk
		+ "Player/Camera: (%.1f, %.1f)   Active chunks: %d   Sleeping AI: %d\n" % [camera_position.x, camera_position.z, active_chunks, sleeping]
		+ "Targets: %d   Next target movement: %.1fs\n" % [target_nodes.size(), maxf(0.0, _target_move_remaining)]
		+ "Camera: WASD move   Q/E vertical   RMB look   Shift fast   Wheel speed"
	)


func _sync_visualization_player_position() -> void:
	if not _authority_started or not is_instance_valid(_camera_rig):
		return
	var state_value: Variant = GameAuthority.player_states.get(GameAuthority.LOCAL_PLAYER_ID, null)
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var camera_position := _camera_rig.global_position
	# The camera is the controllable representation of the test player. Keep
	# the simulated player on the ground while using the camera's X/Z position
	# for interest-chunk selection.
	state["position"] = Vector3(camera_position.x, FLOOR_Y, camera_position.z)
	state["velocity"] = Vector3.ZERO
	GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] = state

	var player_chunk := Vector2i(
		floori(camera_position.x / CHUNK_SIZE_METERS),
		floori(camera_position.z / CHUNK_SIZE_METERS)
	)
	if player_chunk == _camera_player_chunk:
		return
	_camera_player_chunk = player_chunk
	GameAuthority.refresh_ai_interest(true)


func _update_active_chunk_surfaces(active_chunks: Array[Vector2i]) -> void:
	var active_lookup: Dictionary = {}
	for chunk in active_chunks:
		active_lookup[chunk] = true
	for chunk_value: Variant in _active_chunk_surfaces.keys():
		var surface := _active_chunk_surfaces[chunk_value] as MeshInstance3D
		if not is_instance_valid(surface):
			continue
		surface.visible = active_lookup.has(chunk_value)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_camera_look_active = mouse_button.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_button.pressed else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_speed = minf(_camera_speed * 1.15, 500.0)
			get_viewport().set_input_as_handled()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_speed = maxf(_camera_speed / 1.15, 2.0)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _camera_look_active:
		var motion := event as InputEventMouseMotion
		_camera_yaw -= motion.relative.x * 0.003
		_camera_pitch = clampf(
			_camera_pitch - motion.relative.y * 0.003,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)
		_apply_camera_rotation()
		get_viewport().set_input_as_handled()


func _update_free_camera(delta: float) -> void:
	if _camera_rig == null or _editor_camera == null:
		return
	var movement := Vector3.ZERO
	var forward := -_editor_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	var right := _editor_camera.global_basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	if Input.is_key_pressed(KEY_W):
		movement += forward
	if Input.is_key_pressed(KEY_S):
		movement -= forward
	if Input.is_key_pressed(KEY_D):
		movement += right
	if Input.is_key_pressed(KEY_A):
		movement -= right
	if Input.is_key_pressed(KEY_E):
		movement += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		movement -= Vector3.UP
	if movement.length_squared() > 0.0001:
		var speed_multiplier := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var motion := movement.normalized() * _camera_speed * speed_multiplier * delta
		_camera_rig.move_and_collide(motion)
	_camera_rig.global_position = _clamp_camera_position(_camera_rig.global_position)


func _apply_camera_rotation() -> void:
	if _editor_camera != null:
		_editor_camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _clamp_camera_position(position_value: Vector3) -> Vector3:
	var half_map := MAP_SIZE_METERS * 0.5
	position_value.x = clampf(
		position_value.x,
		-half_map + _camera_boundary_margin,
		half_map - _camera_boundary_margin
	)
	position_value.z = clampf(
		position_value.z,
		-half_map + _camera_boundary_margin,
		half_map - _camera_boundary_margin
	)
	position_value.y = maxf(position_value.y, FLOOR_Y + _camera_ground_clearance)
	return position_value
