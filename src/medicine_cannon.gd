extends Node3D
class_name MedicineCannon

@export var tool_owner := ""
@export var projectile_speed := 48.0

const BOOM_SCENE := preload("res://character/weapons/MedicineBoom.tscn")


func emit() -> void:
	if tool_owner.is_empty() or not is_instance_valid(GlobalVar.gameworld):
		return
	var boom := BOOM_SCENE.instantiate() as MedicineBoom
	if boom == null:
		return
	GlobalVar.gameworld.add_child(boom)
	# In local-authority mode GameAuthority owns the actual storm. This boom is
	# only the missing flight visual and must not create a second storm on impact.
	boom.visual_only = GameAuthority.is_local_authority()
	var direction: Vector3 = (
		$RayCast3D.to_global($RayCast3D.target_position)
		- $RayCast3D.global_position
	).normalized()
	boom.run($RayCast3D.global_position, direction * projectile_speed, tool_owner)
