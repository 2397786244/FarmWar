extends StaticBody3D
class_name PlantProtector

@export var tool_owner:String = ""
@export var set_hp:float = 500
@export var hp_debug_label: bool = true
var current_hp:float = set_hp
var _is_active:bool = false  # 表示工作中。如果被干扰，那么_is_active就是false表示不在工作中
var _is_placed:bool = false # 表示被放置
var _near_tiles:Array = []
var _electronics_disabled_remaining := 0.0
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

func _apply_damage(strength:float):
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	return
	
func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not attacker_team.is_empty() and tool_owner == attacker_team:
		return false
	var last_effect = effect.to_lower()
	if last_effect == "repair_laser" or last_effect == "lightening" or last_effect == "lightning":
		var duration_effect := "repair_laser" if last_effect == "repair_laser" else "lightning"
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("plant_protector", duration_effect))
		_is_active = false
		_remove_farm_tiles_protector()
		_near_tiles.clear()
		return true
	if strength <= 0.0:
		return false
	_apply_damage(strength)
	if current_hp <= 0.0:
		# 调用所有farmtile设置remove
		_remove_farm_tiles_protector()
		call_deferred("queue_free")
		return true
	match last_effect:
		"flame":
			pass
		"freeze":
			pass
		"lightening":
			pass
		"labeled":
			pass
	return true

# 放置工具	
func emit() -> Dictionary:
	if tool_owner.is_empty():
		return {}
	var setting_player: Node3D = get_node_or_null("../../../") as Node3D
	if setting_player == null:
		return {}
	var raycast: RayCast3D = setting_player.find_child("LookAtTarget", true) as RayCast3D
	if raycast == null:
		return {}

	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return {}

	var tile := Farmlandmanager.resolve_raycast_tile(raycast)
	if tile != null:
		tile.setting_tool("PlantProtector", tool_owner, setting_player)
	return {}
	
func _ready() -> void:
	print("GENERATE PROTECTOR")
	_update_health_label()
	
func activate_tool():
	_is_placed = true
	collision_layer = 128
	_update_health_label()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_is_placed = true
	_update_health_label()


func get_network_visual_state() -> Dictionary:
	return {
		"electronics_disabled_remaining": _electronics_disabled_remaining,
		"is_active": _is_active,
	}


func apply_network_visual_state(state: Dictionary) -> void:
	_electronics_disabled_remaining = maxf(
		_electronics_disabled_remaining,
		float(state.get("electronics_disabled_remaining", 0.0))
	)
	if _electronics_disabled_remaining > 0.0:
		_is_active = false
		_remove_farm_tiles_protector()
		_near_tiles.clear()
	else:
		_is_active = bool(state.get("is_active", _is_active))
	_update_health_label()


func _update_health_label() -> void:
	#print("CALL! UPDATE LABEL")
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and _is_placed
	health_label.text = "%d" % int(ceil(current_hp))
	
func _physics_process(delta: float) -> void:
	_electronics_disabled_remaining = maxf(0.0, _electronics_disabled_remaining - delta)
	if _electronics_disabled_remaining > 0.0:
		return
	if _is_placed:
		if _near_tiles.is_empty():
			# 查找一下周围的FarmTile
			var shape_cast = $ShapeCast3D
			shape_cast.force_shapecast_update()
			var count = shape_cast.get_collision_count()
			for i in range(count):
				var tile := Farmlandmanager.resolve_shapecast_tile(shape_cast, i)
				if tile != null and not _near_tiles.has(tile):
					_near_tiles.append(tile)
					tile.set_tile_protector(self)
			_is_active = true	


func is_electronics_disabled() -> bool:
	return _electronics_disabled_remaining > 0.0
					
func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet or \
	body is DetectLaserBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()

func _remove_farm_tiles_protector():
	for each in _near_tiles:
		if is_instance_valid(each):
			each.remove_tile_protector(self)
