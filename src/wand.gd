extends Node3D
class_name WandTool

@export var  tool_owner :String = ""
# 魔杖可以召唤闪电攻击对方敌人（操控距离内） 攻击对方放置类的工具
var owner_node:Node3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	owner_node = get_node_or_null("../../../")
	
	#print("Hello,",tool_owner)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func emit():
	if owner_node == null:
		return
	if not (owner_node is AIPlayer or owner_node is GamePlayer):
		return
	var raycast = owner_node.find_child("LookAtTarget",true)
	if raycast == null:
		return
	var collider = raycast.get_collider()
	var tile := Farmlandmanager.resolve_raycast_tile(raycast as RayCast3D)
	if tile != null:
		_apply_legacy_damage_if_needed(tile)
		_spawn_lightning(tile.global_position)
		return
	var impact_target := _resolve_impact_target(collider)
	if impact_target != null:
		_apply_legacy_damage_if_needed(impact_target)
		var hit_position: Vector3 = impact_target.global_position
		if raycast is RayCast3D and (raycast as RayCast3D).is_colliding():
			hit_position = (raycast as RayCast3D).get_collision_point()
		_spawn_lightning(hit_position)


func play_lightning_at(hit_position: Vector3) -> void:
	_spawn_lightning(hit_position)


func _resolve_impact_target(collider: Variant) -> Node3D:
	if not collider is Node:
		return null
	var cursor := collider as Node
	while cursor != null:
		if cursor is Node3D and cursor.has_method("impact"):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null


func _apply_legacy_damage_if_needed(target: Node) -> void:
	# GameAuthority already applied authoritative damage in normal single- and
	# multiplayer games. Only legacy scenes with authority disabled need Wand to
	# invoke impact directly.
	if GameAuthority.is_local_authority() or GameAuthority.is_server_authority() \
			or GameAuthority.should_send_network_requests():
		return
	if target != null and target.has_method("impact"):
		target.call("impact", "lightening", 100.0, tool_owner)


func _spawn_lightning(hit_position: Vector3) -> void:
	if GlobalVar.gameworld == null:
		return
	var flash = load("res://character/weapons/LighteningEffect.tscn").instantiate()
	GlobalVar.gameworld.add_child(flash)
	flash.strike(hit_position + Vector3.UP * 20.0, hit_position)
