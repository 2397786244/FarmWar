extends Node3D

const VEHICLE_EXPLOSION_SCENE := preload("res://character/weapons/VehicleExplosion.tscn")
const FOUR_WHEEL_VEHICLE_SCENE := preload("res://vehicles/police_car.tscn")
const TWO_WHEEL_VEHICLE_SCENE := preload("res://character/weapons/SurveyRider.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var four_wheel := VEHICLE_EXPLOSION_SCENE.instantiate() as Node3D
	var two_wheel := VEHICLE_EXPLOSION_SCENE.instantiate() as Node3D
	_check(four_wheel != null and two_wheel != null, "vehicle explosion scene instantiates twice")
	if four_wheel == null or two_wheel == null:
		_finish()
		return
	four_wheel.set("vehicle_variant", "four_wheel")
	two_wheel.set("vehicle_variant", "two_wheel")
	add_child(four_wheel)
	add_child(two_wheel)
	await get_tree().process_frame

	var four_cap_particles := four_wheel.get_node("MushroomCapParticles") as GPUParticles3D
	var two_cap_particles := two_wheel.get_node("MushroomCapParticles") as GPUParticles3D
	var four_shockwave := four_wheel.get_node("Shockwave") as MeshInstance3D
	var two_shockwave := two_wheel.get_node("Shockwave") as MeshInstance3D
	_check(four_wheel.get("vehicle_variant") == "four_wheel", "four-wheel effect selects the large profile")
	_check(two_wheel.get("vehicle_variant") == "two_wheel", "two-wheel effect selects the compact profile")
	_check(
		four_cap_particles != null and two_cap_particles != null
			and four_cap_particles.position.y > two_cap_particles.position.y,
		"four-wheel mushroom cloud is taller than the two-wheel cloud"
	)
	await get_tree().create_timer(0.75).timeout
	_check(
		four_shockwave != null and two_shockwave != null
			and four_shockwave.scale.x > two_shockwave.scale.x,
		"four-wheel shockwave expands farther than the two-wheel shockwave"
	)
	_check(
		four_wheel.get_node_or_null("BlastLight") is OmniLight3D
			and four_wheel.get_node_or_null("FireCore") is MeshInstance3D
			and four_wheel.get_node_or_null("MushroomStemParticles") is GPUParticles3D,
		"effect contains center fire, light, and rising gas components"
	)

	GameAuthority.start_local_mode({
		"display_name": "VehicleExplosionValidation",
		"team": "blue",
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self
	var four_wheel_vehicle := FOUR_WHEEL_VEHICLE_SCENE.instantiate() as VehicleBase
	var two_wheel_vehicle := TWO_WHEEL_VEHICLE_SCENE.instantiate() as VehicleBase
	_check(four_wheel_vehicle != null and two_wheel_vehicle != null, "vehicle scenes instantiate for destruction routing")
	if four_wheel_vehicle != null and two_wheel_vehicle != null:
		add_child(four_wheel_vehicle)
		two_wheel_vehicle.position = Vector3(8.0, 0.0, 0.0)
		add_child(two_wheel_vehicle)
		await get_tree().process_frame
		_check(
			four_wheel_vehicle.get_destruction_effect_variant() == "four_wheel"
				and two_wheel_vehicle.get_destruction_effect_variant() == "two_wheel",
			"four-wheel and two-wheel vehicles select different destruction profiles"
		)
		_check(
			four_wheel_vehicle.get_destruction_effect_radius() > two_wheel_vehicle.get_destruction_effect_radius(),
			"four-wheel damage radius is larger than the two-wheel damage radius"
		)
		var vehicle_max_hp := four_wheel_vehicle.vehicle_config.max_hp
		four_wheel_vehicle.owner_team = ""
		four_wheel_vehicle.current_hp = vehicle_max_hp
		var neutral_direct_hit := bool(GameAuthority.call(
			"_damage_vehicle", four_wheel_vehicle, 1.0, "test_bullet", "blue"
		))
		_check(
			neutral_direct_hit and four_wheel_vehicle.current_hp < vehicle_max_hp,
			"unowned vehicle direct hit remains eligible for player hit confirmation"
		)
		four_wheel_vehicle.owner_team = "blue"
		four_wheel_vehicle.current_hp = vehicle_max_hp
		var friendly_direct_hit := bool(GameAuthority.call(
			"_damage_vehicle", four_wheel_vehicle, 1.0, "test_bullet", "blue"
		))
		_check(
			not friendly_direct_hit and four_wheel_vehicle.current_hp < vehicle_max_hp,
			"same-team vehicle damage suppresses player hit confirmation"
		)
		four_wheel_vehicle.owner_team = ""
		four_wheel_vehicle.current_hp = vehicle_max_hp
		var neutral_radius_hits := int(GameAuthority.call(
			"_damage_vehicles_in_radius",
			four_wheel_vehicle.global_position,
			0.5,
			1.0,
			"blue",
			"test_cannonball"
		))
		_check(
			neutral_radius_hits == 1 and four_wheel_vehicle.current_hp < vehicle_max_hp,
			"unowned vehicle radius hit is counted for player projectile confirmation"
		)
		four_wheel_vehicle.impact("Explosion", four_wheel_vehicle.current_hp + 1.0, "red")
		_check(
			two_wheel_vehicle.current_hp < two_wheel_vehicle.vehicle_config.max_hp,
			"vehicle explosion applies radius damage to a nearby vehicle"
		)
		two_wheel_vehicle.impact("Explosion", two_wheel_vehicle.current_hp + 1.0, "red")
		await get_tree().process_frame
		var spawned_explosions := get_tree().get_nodes_in_group("vehicle_explosions")
		var saw_four_wheel := false
		var saw_two_wheel := false
		for explosion_value in spawned_explosions:
			var explosion := explosion_value as Node
			if not is_instance_valid(explosion):
				continue
			var variant := str(explosion.get("vehicle_variant"))
			saw_four_wheel = saw_four_wheel or variant == "four_wheel"
			saw_two_wheel = saw_two_wheel or variant == "two_wheel"
		_check(saw_four_wheel and saw_two_wheel, "HP zero spawns the matching explosion variant")
		four_wheel_vehicle = null
		two_wheel_vehicle = null
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[VehicleExplosionValidation] PASS all checks")
	else:
		push_error("[VehicleExplosionValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[VehicleExplosionValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[VehicleExplosionValidation] FAIL: %s" % description)
