extends Node3D

const BLOCKER_SCENE := preload("res://character/RoadBlockerAI.tscn")

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameAuthority.start_local_mode({"team": "red", "position": Vector3.ZERO})
	var reward_events: Array[Dictionary] = []
	GameAuthority.reliable_world_event_ready.connect(func(event: Dictionary) -> void:
		if str(event.get("type", "")) == "action_reward":
			reward_events.append(event)
	)
	var blocker := BLOCKER_SCENE.instantiate() as RoadBlockerAI
	add_child(blocker)
	await get_tree().process_frame
	_check(is_equal_approx(blocker.max_hp, 100.0) and is_equal_approx(blocker.current_hp, 100.0), "Blocker starts at 100 HP")
	_check(blocker.state == RoadBlockerAI.State.IDLE, "Blocker starts IDLE")
	_check(blocker.get_node_or_null("NavigationAgent3D") == null, "Blocker has no navigation agent")
	_check(blocker.weapon_id in ["remington870", "shotgun", "remington870_rusted", "shotgun_rusted"], "Blocker chooses a supported weapon")
	var appearance := blocker.get_node_or_null("Appearance") as Node3D
	_check(appearance != null and is_equal_approx(absf(appearance.rotation.y), PI), "Blocker uses the FutureWarrior model-facing correction")
	var right_target := blocker.get_node_or_null("Head/RightHandIKTarget") as Marker3D
	_check(right_target != null and right_target.position.is_equal_approx(Vector3(0.28, -0.28, -0.42)), "Blocker uses the fixed player-style right hand position")
	var right_socket := blocker.get_node_or_null("RightHandSocket") as BoneAttachment3D
	_check(right_socket != null and right_socket.use_external_skeleton and blocker.get_node_or_null("RightHandSocket/WeaponPivot") != null, "Blocker mounts its weapon through the player-style Hand.R socket")
	_check(is_equal_approx(blocker.turn_speed_degrees, 90.0), "Blocker uses visible limited-speed turning")
	_check(blocker.ammo_in_mag == blocker.magazine_capacity and blocker.magazine_capacity == 6, "Blocker starts with the selected weapon's full magazine")
	_check(is_equal_approx(blocker.aim_spread_degrees, 5.0), "Blocker uses its configured 5 degree standing aim spread")
	var pellet_directions: Array[Vector3] = GameAuthority.call(
		"_sample_circular_pellet_directions",
		Vector3.FORWARD,
		64,
		2.0
	) as Array[Vector3]
	var has_horizontal_spread := false
	var has_vertical_spread := false
	var all_pellets_inside_cone := pellet_directions.size() == 64
	for pellet_direction in pellet_directions:
		has_horizontal_spread = has_horizontal_spread or absf(pellet_direction.x) > 0.00001
		has_vertical_spread = has_vertical_spread or absf(pellet_direction.y) > 0.00001
		var offset_degrees := rad_to_deg(acos(clampf(Vector3.FORWARD.dot(pellet_direction), -1.0, 1.0)))
		all_pellets_inside_cone = all_pellets_inside_cone and offset_degrees <= 1.001
	_check(all_pellets_inside_cone, "Shotgun pellet directions remain inside the original angular limit")
	_check(has_horizontal_spread and has_vertical_spread, "Shotgun pellets fill a circular area instead of a line")
	blocker.ammo_in_mag = 0
	blocker.call("_start_reload")
	_check(is_equal_approx(blocker.reload_remaining, 2.4), "Blocker uses the player shotgun reload time")
	blocker.reload_remaining = 0.0
	blocker.ammo_in_mag = blocker.magazine_capacity
	_check(is_instance_valid(blocker.get_node_or_null("Hit3D")), "Blocker creates Warrior-compatible Hit3D")
	var hit_shape := blocker.get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
	var capsule := hit_shape.shape as CapsuleShape3D if hit_shape != null else null
	_check(capsule != null and is_equal_approx(capsule.height, 3.0), "Blocker Hit3D covers its 3m body and head")
	var spawn := preload("res://character/RoadBlockerSpawn.tscn").instantiate() as RoadBlockerSpawn
	_check(spawn != null and is_equal_approx(spawn.respawn_seconds, 10.0), "RoadBlocker spawn exposes its editable respawn time")
	if spawn != null:
		spawn.queue_free()
	blocker.set_checkpoint_attack_team("red")
	blocker.set_checkpoint_attack_permission(true)
	await get_tree().physics_frame
	_check(blocker.state == RoadBlockerAI.State.ATTACK, "Alarm permission enters ATTACK")
	blocker.set_checkpoint_attack_permission(false)
	_check(blocker.state == RoadBlockerAI.State.IDLE, "Clearing alarm returns IDLE")
	blocker.impact("nail", 1.0, "red")
	_check(blocker.state == RoadBlockerAI.State.ATTACK, "Independent damaged blocker enters retaliation ATTACK")
	blocker.impact("nail", 99.0, "red")
	_check(blocker.state == RoadBlockerAI.State.DEATH, "Lethal damage enters DEATH")
	var found_road_blocker_reward := false
	for event in reward_events:
		if int(event.get("amount", 0)) == 200 and str(event.get("description", "")).contains("RoadBlocker"):
			found_road_blocker_reward = true
			break
	_check(found_road_blocker_reward, "RoadBlocker death displays its own +200 RoadBlocker reward")
	if failures.is_empty():
		print("[RoadBlockerValidation] PASS")
	else:
		for failure in failures: push_error("[RoadBlockerValidation] " + failure)
	get_tree().quit(1 if not failures.is_empty() else 0)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
