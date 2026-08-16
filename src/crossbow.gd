extends Node3D
class_name CrossbowTool

const CombatBalance = preload("res://src/combat_balance.gd")
const BOLT_SCENE := preload("res://character/weapons/CrossbowBolt.tscn")
const LOADED_BOLT_NODE_NAMES: Array[String] = [
	"LoadedBoltTip",
	"LoadedBoltShaft",
	"LoadedBoltNock",
	"LoadedBoltFin01",
	"LoadedBoltFin02",
	"LoadedBoltFin03",
]

@export var tool_owner := ""
@export var profile_id := "crossbow"

@onready var muzzle: Marker3D = $Muzzle
@onready var model: Node3D = $Mesh

var is_aiming := false
var model_rest_position := Vector3.ZERO
var loaded_bolt_nodes: Array[Node3D] = []
var ammo_loaded := true


func _ready() -> void:
	model_rest_position = model.position
	_cache_loaded_bolt_nodes()
	set_ammo_loaded(ammo_loaded)


func emit() -> void:
	_emit_bolt(false)


func emit_visual_only() -> void:
	_emit_bolt(true)


## AI authority uses a server-side hitscan for gameplay, then calls this method
## to draw the same shot locally without creating a damage projectile.
func emit_visual_only_tracer(
	direction: Vector3,
	travel_distance: float = -1.0
) -> void:
	_emit_bolt(true, direction, travel_distance)


func get_fire_origin() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position


func get_fire_direction() -> Vector3:
	if is_instance_valid(muzzle):
		return -muzzle.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func set_aiming(value: bool) -> void:
	is_aiming = value


func set_ammo_loaded(value: bool) -> void:
	ammo_loaded = value
	if loaded_bolt_nodes.is_empty():
		_cache_loaded_bolt_nodes()
	for bolt_part: Node3D in loaded_bolt_nodes:
		if is_instance_valid(bolt_part):
			bolt_part.visible = value


func is_ammo_loaded() -> bool:
	return ammo_loaded


func get_held_item_info_text(item: Dictionary, definition: Dictionary) -> String:
	var tool_name := str(definition.get("name", definition.get("short", "弩")))
	return "%s\n%d" % [
		tool_name,
		int(item.get("ammo_in_mag", 0)),
	]


func play_muzzle_visual() -> void:
	# The crossbow has no muzzle flash. Remote shots still hide the loaded bolt
	# and use the same profile-based recoil presentation as the local shot.
	set_ammo_loaded(false)
	_play_recoil()


func _cache_loaded_bolt_nodes() -> void:
	loaded_bolt_nodes.clear()
	if not is_instance_valid(model):
		return
	for node_name: String in LOADED_BOLT_NODE_NAMES:
		# The imported Mesh scene can nest these parts several levels deep.
		var bolt_part := model.find_child(node_name, true, false) as Node3D
		if bolt_part != null:
			loaded_bolt_nodes.append(bolt_part)


func _emit_bolt(
	visual_only: bool,
	direction_override: Vector3 = Vector3.ZERO,
	travel_distance: float = -1.0
) -> void:
	if tool_owner.is_empty() or profile_id.is_empty() \
			or not is_instance_valid(GlobalVar.gameworld):
		return

	var shooter := _get_shooter()
	var direction := _get_center_screen_direction(shooter)
	if direction_override.length_squared() > 0.001:
		direction = direction_override.normalized()
	if direction.length_squared() <= 0.001:
		return

	var bolt := BOLT_SCENE.instantiate() as CrossbowBolt
	if bolt == null:
		return
	bolt.speed = CombatBalance.get_float(profile_id, "visual_speed", 90.0)
	bolt.max_distance = CombatBalance.get_float(profile_id, "range", 120.0)
	bolt.max_lifetime = CombatBalance.get_float(
		profile_id,
		"visual_lifetime",
		bolt.max_lifetime
	)
	bolt.bullet_strength = CombatBalance.get_float(profile_id, "damage", 80.0)
	bolt.knockback_force = CombatBalance.get_float(profile_id, "knockback", 20.0)
	if travel_distance >= 0.0:
		bolt.max_distance = minf(bolt.max_distance, maxf(0.01, travel_distance))
		if bolt.speed > 0.01:
			bolt.max_lifetime = minf(
				bolt.max_lifetime,
				maxf(0.01, travel_distance / bolt.speed)
			)
	if visual_only:
		bolt.make_visual_only()
	GlobalVar.gameworld.add_child(bolt)
	bolt.run(get_fire_origin(), direction.normalized(), tool_owner, shooter)
	set_ammo_loaded(false)
	_play_recoil()


func _get_shooter() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node as CollisionObject3D
		node = node.get_parent()
	return null


func _get_center_screen_direction(shooter: CollisionObject3D) -> Vector3:
	if not is_instance_valid(shooter):
		return get_fire_direction()

	var camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return get_fire_direction()

	var max_distance := CombatBalance.get_float(profile_id, "range", 120.0)
	var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_direction := camera.project_ray_normal(screen_center).normalized()
	var aim_point := ray_origin + ray_direction * max_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, aim_point, 139)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]
	return (aim_point - get_fire_origin()).normalized()


func _play_recoil() -> void:
	if not is_instance_valid(model):
		return
	var tween := create_tween()
	var recoil_offset := CombatBalance.get_model_recoil_offset(profile_id)
	model.position = model_rest_position + recoil_offset
	tween.tween_property(
		model, "position", model_rest_position, CombatBalance.MODEL_RECOIL_DURATION
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
