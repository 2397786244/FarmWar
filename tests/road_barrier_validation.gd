extends Node

const BARRIER_SCENE := "res://buildings/RoadBarrierLeft.tscn"

var failures: Array[String] = []
var hit_confirmation_events: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(BARRIER_SCENE) as PackedScene
	_check(packed != null, "RoadBarrierLeft scene loads")
	if packed == null:
		_finish()
		return
	var barrier := packed.instantiate() as Node3D
	_check(barrier is RoadBarrier, "scene resolves to RoadBarrier")
	if barrier == null:
		_finish()
		return
	add_child(barrier)
	await get_tree().process_frame

	_check(barrier.is_in_group("road_barriers"), "barrier is in road_barriers group")
	_check(barrier.is_in_group("ai_demolition_target"), "barrier is an AI demolition target")
	_check(barrier.find_child("BarrierArm", true, false) != null, "BarrierArm is found recursively")
	_check(barrier.get_node_or_null("PlacementFootprint") != null, "placement footprint exists")
	_check(barrier.get_node_or_null("NavigationObstacle3D") != null, "navigation obstacle exists")
	_check(int(barrier.collision_layer) == 128, "root uses the tool collision layer")
	_check(int(barrier.collision_mask) == 12427, "root allows vehicle/world collisions")
	_check(is_equal_approx(float(barrier.get("max_hp")), 500.0), "control box max HP is 500")
	_check(is_equal_approx(float(barrier.get("arm_max_hp")), 100.0), "arm max HP is 100")
	_check(not barrier.is_barrier_raised(), "barrier starts lowered")
	await _validate_player_hit_confirmations(barrier)

	var arm_shape := barrier.get_node("ArmShape") as CollisionShape3D
	var arm_hit_area := barrier.get_node("ArmHit3D") as Area3D
	var arm_hit_shape := arm_hit_area.get_node("ArmShape") as CollisionShape3D
	var arm_visual := barrier.find_child("BarrierArm", true, false) as Node3D
	var control_area := barrier.get_node("ControlHit3D") as Area3D
	var footprint := barrier.get_node("PlacementFootprint") as StaticBody3D
	var obstacle := barrier.get_node("NavigationObstacle3D") as NavigationObstacle3D
	_check(control_area != null and int(control_area.collision_layer) == 128 \
		and int(control_area.collision_mask) == 32, "control hitbox uses bullet mask")
	_check(arm_hit_area != null and int(arm_hit_area.collision_layer) == 128 \
		and int(arm_hit_area.collision_mask) == 32, "arm hitbox uses bullet mask")
	_check(footprint != null and int(footprint.collision_layer) == 16 \
		and int(footprint.collision_mask) == 0, "placement footprint is query-only")
	_check(obstacle != null and obstacle.affect_navigation_mesh \
		and obstacle.carve_navigation_mesh and obstacle.avoidance_enabled, "navigation obstacle is enabled")
	_check(arm_shape != null and arm_shape.shape is BoxShape3D, "root ArmShape is a BoxShape3D")
	_check(arm_hit_shape != null and arm_hit_shape.shape is BoxShape3D, "ArmHit3D has one BoxShape3D")
	_check(arm_visual != null, "visual arm node exists")
	if arm_shape == null or arm_hit_shape == null or arm_visual == null:
		barrier.free()
		_finish()
		return

	var root_arm_box := arm_shape.shape as BoxShape3D
	var hit_arm_box := arm_hit_shape.shape as BoxShape3D
	var initial_root_pivot := _arm_endpoint(arm_shape, root_arm_box)
	var initial_hit_pivot := _arm_endpoint(arm_hit_shape, hit_arm_box)
	var initial_visual_origin := arm_visual.global_position
	var initial_root_transform := arm_shape.global_transform
	var initial_hit_area_transform := arm_hit_area.global_transform
	var initial_visual_transform := arm_visual.global_transform
	var arm_shape_index := -1
	for owner_id in barrier.get_shape_owners():
		if barrier.shape_owner_get_owner(owner_id) == arm_shape:
			arm_shape_index = barrier.shape_owner_get_shape_index(owner_id, 0)
	_check(arm_shape_index >= 0, "root ArmShape has a collision shape index")

	_check(barrier.raise_barrier(), "barrier raises")
	await _wait_for_barrier_motion()
	_check(barrier.is_barrier_raised(), "raised state is true")
	_check(_arm_endpoint(arm_shape, root_arm_box).is_equal_approx(initial_root_pivot), "root arm pivot stays fixed")
	_check(_arm_endpoint(arm_hit_shape, hit_arm_box).is_equal_approx(initial_hit_pivot), "ArmHit3D pivot stays fixed")
	_check(arm_visual.global_position.is_equal_approx(initial_visual_origin), "visual arm hinge stays fixed")
	_check(
		(arm_shape.global_transform.basis * Vector3.RIGHT).normalized().dot(Vector3.UP) > 0.99,
		"raised arm points upward"
	)
	_check(not arm_shape.global_transform.is_equal_approx(initial_root_transform), "root arm shape rotates")
	_check(not arm_hit_area.global_transform.is_equal_approx(initial_hit_area_transform), "ArmHit3D parent rotates")

	var raised_obstacle := barrier.get_node("NavigationObstacle3D") as NavigationObstacle3D
	var raised_max_x := _obstacle_max_x(raised_obstacle)
	_check(raised_max_x < -1.70, "raised navigation obstacle excludes arm")
	var replicated_state: Dictionary = barrier.get_network_state()
	var replica := packed.instantiate() as Node3D
	_check(replica is RoadBarrier, "network replica uses RoadBarrier")
	if replica != null:
		add_child(replica)
		await get_tree().process_frame
		if replica.has_method("apply_network_state"):
			replica.call("apply_network_state", replicated_state)
		_check(replica.is_barrier_raised(), "network state restores raised state")
		_check(is_equal_approx(float(replica.get("arm_current_hp")), 100.0), "network state restores arm HP")
		if replica.has_method("enable_network_visuals"):
			replica.call("enable_network_visuals")
		var replica_arm := replica.find_child("BarrierArm", true, false) as Node3D
		_check(replica_arm != null and replica_arm.visible, "network visual replica keeps arm visible")
		replica.free()

	for _cycle in range(3):
		_check(barrier.lower_barrier(), "barrier lowers during cycle")
		await _wait_for_barrier_motion()
		_check(barrier.raise_barrier(), "barrier raises during cycle")
		await _wait_for_barrier_motion()
	_check(_arm_endpoint(arm_shape, root_arm_box).is_equal_approx(initial_root_pivot), "repeated raises do not drift root pivot")
	_check(arm_visual.global_position.is_equal_approx(initial_visual_origin), "repeated raises do not drift visual hinge")
	_check(_obstacle_max_x(raised_obstacle) < -1.70, "raised obstacle remains control-box-only")

	_check(barrier.lower_barrier(), "barrier returns to lowered state")
	await _wait_for_barrier_motion()
	_check(arm_shape.global_transform.is_equal_approx(initial_root_transform), "lowering restores root arm transform")
	_check(arm_hit_area.global_transform.is_equal_approx(initial_hit_area_transform), "lowering restores ArmHit3D transform")
	_check(arm_visual.global_transform.is_equal_approx(initial_visual_transform), "lowering restores visual transform")
	_check(_obstacle_max_x(raised_obstacle) > 2.0, "lowered navigation obstacle includes arm")

	barrier.apply_network_respawned(500.0)
	var root_arm_damage_applied: bool = bool(barrier.impact_from_collider(
		barrier, "test", 100.0, "enemy", arm_shape_index, 0, null
	))
	_check(root_arm_damage_applied, "root vehicle-style arm shape damage is accepted")
	_check(bool(barrier.get("arm_destroyed")), "root arm shape maps to arm component")
	_check(is_equal_approx(float(barrier.get("current_hp")), 500.0), "root arm hit preserves control HP")
	barrier.apply_network_respawned(500.0)

	var arm_damage_applied: bool = bool(barrier.impact_from_collider(
		arm_hit_area, "test", 100.0, "enemy", -1, 0, null
	))
	_check(arm_damage_applied, "arm damage is accepted")
	_check(bool(barrier.get("arm_destroyed")), "arm destruction state is set")
	_check(is_equal_approx(float(barrier.get("current_hp")), 500.0), "arm damage preserves control HP")
	_check(not arm_visual.visible, "destroyed arm is hidden")
	_check(bool(barrier.visible), "destroyed arm leaves control box visible")

	barrier.apply_network_respawned(500.0)
	_check(not bool(barrier.get("arm_destroyed")), "respawn restores arm")
	_check(is_equal_approx(float(barrier.get("arm_current_hp")), 100.0), "respawn restores arm HP")
	_check(not barrier.is_barrier_raised(), "respawn resets arm to lowered")
	var control_damage_applied: bool = bool(barrier.impact_from_collider(
		control_area, "test", 500.0, "enemy", -1, 0, null
	))
	_check(control_damage_applied, "control-box damage is accepted")
	_check(bool(barrier.get("destroyed")), "control-box destruction state is set")
	_check(not bool(barrier.visible), "control-box destruction hides entire barrier")
	_check(not barrier.raise_barrier(), "destroyed barrier cannot raise")

	var state: Dictionary = barrier.get_network_state()
	for key: String in ["raised", "arm_hp", "arm_max_hp", "arm_destroyed"]:
		_check(state.has(key), "network state includes %s" % key)

	barrier.free()
	_finish()


func _arm_endpoint(shape_node: CollisionShape3D, box: BoxShape3D) -> Vector3:
	return shape_node.global_transform * Vector3(-box.size.x * 0.5, 0.0, 0.0)


func _obstacle_max_x(obstacle: NavigationObstacle3D) -> float:
	var maximum := -INF
	for vertex in obstacle.vertices:
		maximum = maxf(maximum, (obstacle.global_transform * vertex).x)
	return maximum


func _wait_for_barrier_motion() -> void:
	await get_tree().create_timer(RoadBarrier.BARRIER_MOTION_DURATION + 0.05).timeout


func _validate_player_hit_confirmations(barrier: RoadBarrier) -> void:
	GameAuthority.reliable_world_event_ready.connect(_on_authority_event)
	GameAuthority.start_local_mode({
		"team": "red",
		"position": Vector3(-10.0, 0.155, 0.0),
	})
	barrier.tool_owner = "red"
	var registered := GameAuthority.register_map_placed_tool(
		barrier,
		"road_barrier_left",
		"test:road_barrier_hit_feedback",
		"red"
	)
	_check(registered, "neutral road barrier registers for hit testing")
	var registered_state: Dictionary = GameAuthority.placed_tool_states.get(
		"test:road_barrier_hit_feedback", {}
	)
	_check(str(registered_state.get("team", "red")).is_empty(), "road barrier remains unowned")
	var restored_team_value: Variant = WorldPersistence.call(
		"_restored_tool_team", barrier, {"team": "red"}
	)
	_check(str(restored_team_value).is_empty(), "saved road barrier restores without an owner")

	barrier.apply_network_respawned(500.0)
	hit_confirmation_events.clear()
	var hitscan_value: Variant = GameAuthority.call(
		"_server_hitscan",
		1,
		{
			"origin": Vector3(-10.0, 0.155, 0.0),
			"direction": Vector3.RIGHT,
		},
		30.0,
		25.0,
		0.0,
		"nail"
	)
	var hitscan_result: Dictionary = hitscan_value as Dictionary if hitscan_value is Dictionary else {}
	_check(float(hitscan_result.get("damage", 0.0)) > 0.0, "player hitscan damages road barrier")
	_check(_has_hit_confirmation("nail"), "player hitscan confirms road barrier hit")

	barrier.apply_network_respawned(500.0)
	GameAuthority.register_map_placed_tool(
		barrier,
		"road_barrier_left",
		"test:road_barrier_hit_feedback",
		""
	)
	hit_confirmation_events.clear()
	GameAuthority.apply_local_boom_explosion(
		Vector3(-2.1, 0.155, 0.0),
		"red",
		25.0,
		5.0,
		"Explosion",
		20.0,
		false
	)
	_check(_has_hit_confirmation("Explosion"), "local player cannonball confirms road barrier hit")

	barrier.apply_network_respawned(500.0)
	GameAuthority.register_map_placed_tool(
		barrier,
		"road_barrier_left",
		"test:road_barrier_hit_feedback",
		""
	)
	hit_confirmation_events.clear()
	var projectile_value: Variant = GameAuthority.call(
		"_spawn_server_projectile",
		1,
		{
			"origin": Vector3(-2.1, 0.155, 0.0),
			"direction": Vector3.RIGHT,
		},
		"boom",
		1.0,
		25.0,
		5.0,
		"Explosion",
		-1,
		true
	)
	var projectile_state: Dictionary = projectile_value as Dictionary if projectile_value is Dictionary else {}
	var projectile_id := int(projectile_state.get("projectile_id", 0))
	_check(projectile_id > 0, "player projectile is created for hit testing")
	GameAuthority.call(
		"_explode_projectile",
		projectile_id,
		Vector3(-2.1, 0.155, 0.0),
		0,
		true
	)
	_check(_has_hit_confirmation("boom"), "player projectile confirms road barrier hit")

	GameAuthority.stop_authority()
	if GameAuthority.reliable_world_event_ready.is_connected(_on_authority_event):
		GameAuthority.reliable_world_event_ready.disconnect(_on_authority_event)


func _on_authority_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "hit_confirmed":
		hit_confirmation_events.append(event.duplicate(true))


func _has_hit_confirmation(source: String) -> bool:
	for event: Dictionary in hit_confirmation_events:
		if str(event.get("source", "")) == source \
				and int(event.get("attacker_peer_id", 0)) == 1:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[RoadBarrierValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[RoadBarrierValidation] " + failure)
	get_tree().quit(1)
