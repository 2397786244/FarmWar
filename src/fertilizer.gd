extends Node3D
class_name Fertilizer

@export var tool_owner := ""

@onready var emitter: GPUParticles3D = $Emitter
@onready var target_cast: RayCast3D = $RayCast3D


func emit() -> void:
	play_muzzle_visual()


func play_muzzle_visual() -> void:
	if emitter == null:
		return
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = true


func get_fertilizer_targeting_request() -> Dictionary:
	if target_cast == null:
		return {}
	target_cast.force_raycast_update()
	var result := {
		"origin": target_cast.global_position,
		"direction": -target_cast.global_transform.basis.z,
		"target_position": Vector3.ZERO,
		"target_tile_path": "",
	}
	if not target_cast.is_colliding():
		return result
	result["target_position"] = target_cast.get_collision_point()
	var tile := Farmlandmanager.resolve_raycast_tile(target_cast)
	if tile != null:
		result["target_tile_path"] = str(tile.get_path())
	return result
