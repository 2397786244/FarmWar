extends Node3D


@onready var flash: MeshInstance3D = $Flash
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var blast_light: OmniLight3D = $BlastLight


func _ready() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).restart()
			(child as GPUParticles3D).emitting = true
	_animate_flash()
	_animate_shockwave()
	var light_tween := create_tween()
	light_tween.tween_property(blast_light, "light_energy", 0.0, 0.25)
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _animate_flash() -> void:
	var material := flash.material_override.duplicate() as StandardMaterial3D
	flash.material_override = material
	flash.scale = Vector3.ONE * 0.2
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 3.6, 0.15)
	tween.tween_method(func(alpha: float) -> void: material.albedo_color.a = alpha, 0.82, 0.0, 0.21)


func _animate_shockwave() -> void:
	var material := shockwave.material_override.duplicate() as StandardMaterial3D
	shockwave.material_override = material
	shockwave.scale = Vector3.ONE * 0.2
	var tween := create_tween().set_parallel(true)
	tween.tween_property(shockwave, "scale", Vector3.ONE * 5.4, 0.34)
	tween.tween_method(func(alpha: float) -> void: material.albedo_color.a = alpha, 0.62, 0.0, 0.34)
