extends RefCounted
class_name NatureResourceHitEffect

const PARTICLE_COUNT := 8
const PARTICLE_LIFETIME := 0.48


static func spawn(world_parent: Node, world_position: Vector3, fragment_color: Color) -> void:
	if not is_instance_valid(world_parent) or not world_parent.is_inside_tree():
		return

	var particles := GPUParticles3D.new()
	particles.name = "NatureResourceHitEffect"
	particles.amount = PARTICLE_COUNT
	particles.lifetime = PARTICLE_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.35
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.10
	process_material.direction = Vector3.UP
	process_material.spread = 85.0
	process_material.gravity = Vector3(0.0, -7.0, 0.0)
	process_material.initial_velocity_min = 1.4
	process_material.initial_velocity_max = 2.8
	process_material.damping_min = 0.4
	process_material.damping_max = 1.0
	process_material.scale_min = 0.65
	process_material.scale_max = 1.25
	process_material.color = fragment_color
	particles.process_material = process_material

	var fragment_mesh := BoxMesh.new()
	fragment_mesh.size = Vector3(0.045, 0.035, 0.045)
	var fragment_material := StandardMaterial3D.new()
	fragment_material.albedo_color = fragment_color
	fragment_material.roughness = 1.0
	fragment_mesh.material = fragment_material
	particles.draw_pass_1 = fragment_mesh

	world_parent.add_child(particles)
	particles.global_position = world_position
	particles.emitting = true
	world_parent.get_tree().create_timer(PARTICLE_LIFETIME + 0.35).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)
