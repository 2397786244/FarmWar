extends Node3D
class_name PlacementPreviewController

const PlacementQueryScript = preload("res://src/placement_query.gd")

const PREVIEW_GREEN := Color(0.15, 1.0, 0.30, 0.42)
const PREVIEW_RED := Color(1.0, 0.12, 0.12, 0.42)
const PREVIEW_GRAY := Color(0.58, 0.60, 0.64, 0.42)
const PREVIEW_GREEN_EMISSION := Color(0.03, 0.12, 0.04, 1.0)
const PREVIEW_RED_EMISSION := Color(0.15, 0.01, 0.01, 1.0)
const PREVIEW_GRAY_EMISSION := Color(0.08, 0.09, 0.12, 1.0)
const PREVIEW_TARGET_MASK := (
	1 | 2 | 8 | 64 | 128 | 4096 | 8192 | 16384 | 32768
)
const PREVIEW_BLOCKING_MASK := (
	2 | 8 | 128 | 4096 | 8192 | 32768
	| 16384
)
const FARM_TILE_TOOL_IDS := {
	"auto_shooter": "AutoShooter",
	"shield_door": "ShieldDoor",
	"wheat_sentry": "WheatSentry",
	"plant_protector": "PlantProtector",
	"brick": "Brick",
	"farm_runner": "FarmRunner",
}
const VEHICLE_TOOL_IDS := {
	"survey_rider": "res://character/weapons/SurveyRider.tscn",
	"field_kitchen": "res://character/weapons/KitchenCar.tscn",
}
const LIVESTOCK_TOOL_SCENES := {
	"animal_chicken": "res://items/Chicken.tscn",
	"animal_pig": "res://items/Pig.tscn",
	"animal_angus_cow": "res://items/AngusCow.tscn",
}

var player: Node3D
var preview_root: Node3D
var preview_model: Node3D
var preview_material_green: StandardMaterial3D
var preview_material_red: StandardMaterial3D
var preview_material_gray: StandardMaterial3D
var current_tool_id := ""
var current_mode := ""
var current_scene_path := ""
var current_definition: Dictionary = {}
var current_item: Dictionary = {}
var source_collision_shape: Shape3D
var source_collision_transform := Transform3D.IDENTITY
var preview_valid := false
var preview_cooldown_active := false


func setup(next_player: Node3D) -> void:
	player = next_player
	process_mode = Node.PROCESS_MODE_DISABLED
	preview_root = Node3D.new()
	preview_root.name = "LocalPlacementPreview"
	preview_root.top_level = true
	preview_root.visible = false
	add_child(preview_root)
	preview_material_green = _make_preview_material(PREVIEW_GREEN, PREVIEW_GREEN_EMISSION)
	preview_material_red = _make_preview_material(PREVIEW_RED, PREVIEW_RED_EMISSION)
	preview_material_gray = _make_preview_material(PREVIEW_GRAY, PREVIEW_GRAY_EMISSION)


func set_selection(definition: Dictionary, item: Dictionary = {}) -> void:
	clear_selection()
	if player == null or not is_instance_valid(player):
		return
	if bool(player.get("is_remote_proxy")):
		return
	current_definition = definition.duplicate(true)
	current_item = item.duplicate(true)
	current_tool_id = str(definition.get("id", item.get("tool_id", "")))

	var placement := _resolve_placement_definition(definition, item)
	if placement.is_empty() or not bool(placement.get("enabled", false)):
		return
	current_mode = str(placement.get("mode", ""))
	current_scene_path = str(placement.get("scene_path", ""))
	if current_scene_path.is_empty():
		return
	_build_preview_model(current_scene_path)


func clear_selection() -> void:
	current_tool_id = ""
	current_mode = ""
	current_scene_path = ""
	current_definition.clear()
	current_item.clear()
	source_collision_shape = null
	source_collision_transform = Transform3D.IDENTITY
	preview_valid = false
	preview_cooldown_active = false
	if is_instance_valid(preview_root):
		preview_root.visible = false
	if is_instance_valid(preview_model):
		preview_model.queue_free()
		preview_model = null


func update_preview(allowed_by_player_state := true) -> void:
	if not allowed_by_player_state or current_mode.is_empty() or not is_instance_valid(preview_model):
		if is_instance_valid(preview_root):
			preview_root.visible = false
		return
	if player == null or not is_instance_valid(player) or bool(player.get("is_remote_proxy")):
		preview_root.visible = false
		return
	if not player.is_inside_tree() or player.get_world_3d() == null:
		preview_root.visible = false
		return

	var request_value: Variant = player.call("_make_tool_request")
	var request: Dictionary = request_value as Dictionary if request_value is Dictionary else {}
	var yaw := float(player.rotation.y)
	var cooldown_remaining := 0.0
	if player.has_method("get_placement_preview_cooldown_remaining"):
		cooldown_remaining = maxf(
			0.0,
			float(player.call("get_placement_preview_cooldown_remaining"))
		)
	var cooldown_active := cooldown_remaining > 0.0001
	if current_mode == "farm_tile":
		_update_farm_tile_preview(request, yaw, cooldown_active)
	else:
		_update_free_preview(request, yaw, cooldown_active)


func _resolve_placement_definition(definition: Dictionary, item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) == "cargo_crate":
		return {}
	var tool_id := str(definition.get("id", item.get("tool_id", "")))
	if tool_id.is_empty():
		return {}
	if tool_id == "auto_cooker":
		return {}
	var configured_value: Variant = definition.get("placement_preview", null)
	if configured_value is Dictionary:
		var configured := configured_value as Dictionary
		if not bool(configured.get("enabled", false)):
			return {}
		var configured_scene := str(configured.get("scene_path", definition.get("path", "")))
		return {
			"enabled": true,
			"mode": str(configured.get("mode", "free")),
			"scene_path": configured_scene,
		}
	if FARM_TILE_TOOL_IDS.has(tool_id):
		return {
			"enabled": true,
			"mode": "farm_tile",
			"scene_path": "res://character/weapons/%s.tscn" % str(FARM_TILE_TOOL_IDS[tool_id]),
		}
	if VEHICLE_TOOL_IDS.has(tool_id):
		return {
			"enabled": true,
			"mode": "vehicle",
			"scene_path": str(VEHICLE_TOOL_IDS[tool_id]),
		}
	if LIVESTOCK_TOOL_SCENES.has(tool_id):
		return {
			"enabled": true,
			"mode": "livestock",
			"scene_path": str(LIVESTOCK_TOOL_SCENES[tool_id]),
		}
	if bool(definition.get("free_placement", false)):
		return {
			"enabled": true,
			"mode": "free",
			"scene_path": str(definition.get("path", "")),
		}
	return {}


func _build_preview_model(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var source := packed.instantiate() as Node3D
	if source == null:
		return
	var source_collision := _find_collision_shape(source)
	if source_collision != null and source_collision.shape != null:
		source_collision_shape = source_collision.shape.duplicate(true) as Shape3D
		source_collision_transform = source_collision.transform
	var clone := source.duplicate() as Node3D
	source.free()
	if clone == null:
		return
	preview_model = clone
	preview_model.name = "PreviewModel"
	_sanitize_preview_tree(preview_model)
	preview_root.add_child(preview_model)
	preview_root.visible = false


func _find_collision_shape(node: Node) -> CollisionShape3D:
	var direct := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if direct != null and direct.shape != null:
		return direct
	var vehicle_shape := node.get_node_or_null("VehicleShape") as CollisionShape3D
	if vehicle_shape != null and vehicle_shape.shape != null:
		return vehicle_shape
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			return child as CollisionShape3D
		var nested := _find_collision_shape(child)
		if nested != null:
			return nested
	return null


func _sanitize_preview_tree(node: Node) -> void:
	if node.has_method("set_script"):
		node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for group_value: StringName in node.get_groups():
		node.remove_from_group(group_value)
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is RigidBody3D:
		var rigid_body := node as RigidBody3D
		rigid_body.freeze = true
		rigid_body.sleeping = true
	if node is Area3D:
		var area := node as Area3D
		area.monitoring = false
		area.monitorable = false
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is RayCast3D:
		(node as RayCast3D).enabled = false
	if node is ShapeCast3D:
		(node as ShapeCast3D).enabled = false
	if node is NavigationAgent3D:
		(node as NavigationAgent3D).avoidance_enabled = false
	if node is NavigationObstacle3D:
		(node as NavigationObstacle3D).enabled = false
	if node is Timer:
		(node as Timer).stop()
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is Light3D:
		(node as Light3D).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(node as GeometryInstance3D).material_override = preview_material_green
	for child in node.get_children():
		_sanitize_preview_tree(child)


func _update_farm_tile_preview(request: Dictionary, yaw: float, cooldown_active := false) -> void:
	var tile := _resolve_target_farm_tile()
	if tile == null:
		_set_preview_transform(_resolve_fallback_target(request), yaw, false, cooldown_active)
		return
	var owner_value: Variant = tile.get("land_owner")
	var tile_owner := "" if owner_value == null else str(owner_value)
	var player_team := str(player.get("team"))
	var seed_value: Variant = tile.get("seed_record")
	var tool_value: Variant = tile.get("tool_child")
	var occupied := (seed_value != null and not str(seed_value).is_empty()) \
		or is_instance_valid(tool_value)
	var valid := not occupied and (tile_owner.is_empty() or tile_owner == player_team)
	if valid:
		var placement := PlacementQueryScript.resolve_free_placement(
			player.get_world_3d(),
			tile.global_position,
			player.global_position,
			yaw,
			source_collision_shape,
			source_collision_transform,
			PREVIEW_BLOCKING_MASK,
			_placement_exceptions()
		)
		valid = bool(placement.get("ok", false))
	_set_preview_transform(tile.global_position + Vector3.UP * 0.1, yaw, valid, cooldown_active)


func _update_free_preview(request: Dictionary, yaw: float, cooldown_active := false) -> void:
	var fallback_distance := 3.0 if current_mode == "livestock" else 4.0
	var requested_position := _resolve_fallback_target(request, fallback_distance)
	var result := PlacementQueryScript.resolve_free_placement(
		player.get_world_3d(),
		requested_position,
		player.global_position,
		yaw,
		source_collision_shape,
		source_collision_transform,
		PREVIEW_BLOCKING_MASK,
		_placement_exceptions(),
	)
	var position := result.get("position", requested_position) as Vector3
	_set_preview_transform(position, yaw, bool(result.get("ok", false)), cooldown_active)


func _resolve_target_farm_tile() -> Node3D:
	var cast := player.find_child("LookAtTarget", true, false) as RayCast3D
	if cast == null:
		return null
	cast.force_raycast_update()
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null or not manager.has_method("resolve_raycast_tile"):
		return null
	return manager.call("resolve_raycast_tile", cast) as Node3D


func _resolve_fallback_target(request: Dictionary, fallback_distance := 4.0) -> Vector3:
	var origin := request.get("origin", player.global_position) as Vector3
	var direction := request.get("direction", -player.global_transform.basis.z) as Vector3
	if direction.length_squared() <= 0.001:
		direction = -player.global_transform.basis.z
	direction = direction.normalized()
	var target_value: Variant = request.get("target_position", Vector3.ZERO)
	if target_value is Vector3 and (target_value as Vector3) != Vector3.ZERO:
		var target_position := target_value as Vector3
		if target_position.distance_to(player.global_position) <= 10.0:
			return target_position
		return player.global_position + direction * fallback_distance
	var world := player.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 12.0)
		query.collision_mask = PREVIEW_TARGET_MASK
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.exclude = _placement_exceptions()
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.has("position"):
			return hit.get("position") as Vector3
	return player.global_position + direction * 4.0


func _placement_exceptions() -> Array:
	var result: Array = []
	if player is CollisionObject3D:
		result.append((player as CollisionObject3D).get_rid())
	var authority := get_node_or_null("/root/GameAuthority")
	var authority_value: Variant = authority.get("player_physics_nodes") if authority != null else null
	if authority_value is Dictionary:
		var physics_node: Variant = (authority_value as Dictionary).get(
			int(player.get("authority_peer_id")),
			null
		)
		if physics_node is CollisionObject3D:
			result.append((physics_node as CollisionObject3D).get_rid())
	return result


func _set_preview_transform(
	position: Vector3,
	yaw: float,
	valid: bool,
	cooldown_active := false
) -> void:
	if not is_instance_valid(preview_root):
		return
	preview_valid = valid
	preview_cooldown_active = cooldown_active
	preview_root.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	preview_root.visible = true
	var material := preview_material_gray if cooldown_active else preview_material_green if valid else preview_material_red
	_apply_preview_material(preview_model, material)


func _apply_preview_material(node: Node, material: Material) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material
	for child in node.get_children():
		_apply_preview_material(child, material)


func _make_preview_material(color: Color, emission_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = 0.35
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
