extends Node3D

const FENCE_SCENE := preload("res://character/weapons/ChainLinkFence.tscn")
const VEHICLE_SCENE := preload("res://vehicles/mini_car.tscn")
const TEST_TOOL_ID := "test:chain_link_fence_vehicle_crush"

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "ChainLinkFenceVehicleCrushValidation",
		"team": "blue",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self

	var fence := FENCE_SCENE.instantiate() as ChainLinkFence
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleBase
	_check(fence != null and vehicle != null, "fence and vehicle scenes instantiate")
	if fence == null or vehicle == null:
		_finish()
		return
	_check(is_equal_approx(fence.max_hp, 100.0), "ground fence max HP is 100")

	fence.position = Vector3.ZERO
	vehicle.position = Vector3.ZERO
	vehicle.owner_team = "blue"
	add_child(fence)
	add_child(vehicle)
	await get_tree().process_frame
	_check(is_equal_approx(fence.current_hp, 100.0), "ground fence starts with 100 HP")
	vehicle.set_physics_process(false)
	fence.activate_tool()
	await get_tree().physics_frame
	# ChainLinkFence enables its hit shape with set_deferred(); wait one more
	# physics step for Area3D's overlapping-body cache to include the vehicle.
	await get_tree().physics_frame

	var hit_area := fence.get_node_or_null("Hit3D") as Area3D
	_check(hit_area != null and hit_area.monitoring, "active fence monitors overlapping bodies")
	var overlapping_bodies := hit_area.get_overlapping_bodies() if hit_area != null else []
	_check(overlapping_bodies.has(vehicle), "fence overlap detects a vehicle body")

	var registered := GameAuthority.register_map_placed_tool(
		fence,
		"chain_link_fence",
		TEST_TOOL_ID,
		""
	)
	_check(registered, "fence registers for authoritative state updates")

	# The vehicle is stationary, so this proves the crush path is based on
	# continuous overlap rather than VehicleBase's speed threshold.
	vehicle.current_speed = 0.0
	vehicle.velocity = Vector3.ZERO
	var hp_before := fence.current_hp
	fence.set_physics_process(false)
	fence.call("_physics_process", 0.5)
	fence.call("_physics_process", 0.5)
	_check(
		is_equal_approx(fence.current_hp, hp_before - 50.0),
		"stationary overlapping vehicle crushes fence at 50 HP per second"
	)
	var state: Dictionary = GameAuthority.placed_tool_states.get(TEST_TOOL_ID, {})
	_check(
		is_equal_approx(float(state.get("hp", -1.0)), fence.current_hp),
		"crush damage updates the registered placed-tool HP"
	)

	var snapshot_value: Variant = GameAuthority.call("_build_world_snapshot")
	var snapshot_tools: Variant = (snapshot_value as Dictionary).get("placed_tools", []) \
		if snapshot_value is Dictionary else []
	var snapshot_hp := -1.0
	if snapshot_tools is Array:
		for tool_value: Variant in snapshot_tools:
			if tool_value is Dictionary and str((tool_value as Dictionary).get("tool_id", "")) == TEST_TOOL_ID:
				snapshot_hp = float((tool_value as Dictionary).get("hp", -1.0))
				break
	_check(is_equal_approx(snapshot_hp, fence.current_hp), "crush HP is present in the world snapshot")

	var effect_before := get_tree().get_nodes_in_group("chain_link_fence_break_effects").size()
	var effect_fence := FENCE_SCENE.instantiate() as ChainLinkFence
	_check(effect_fence != null, "fence scene is available for break-effect validation")
	if effect_fence != null:
		effect_fence.position = Vector3(5.0, 0.0, 0.0)
		add_child(effect_fence)
		await get_tree().process_frame
		effect_fence.call("_apply_impact_strength", 100.0)
		await get_tree().process_frame
		var effects := get_tree().get_nodes_in_group("chain_link_fence_break_effects")
		_check(effects.size() == effect_before + 1, "destroyed fence spawns one gray break particle effect")
		if effects.size() > effect_before:
			_check(effects[effects.size() - 1] is GPUParticles3D, "break effect uses one-shot GPU particles")
		for effect_value: Variant in effects:
			if effect_value is Node and is_instance_valid(effect_value):
				(effect_value as Node).queue_free()
		effect_fence.free()

	fence.free()
	vehicle.free()
	GameAuthority.placed_tool_states.erase(TEST_TOOL_ID)
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[ChainLinkFenceVehicleCrushValidation] PASS " + label)
	else:
		failures += 1
		push_error("[ChainLinkFenceVehicleCrushValidation] FAIL " + label)


func _finish() -> void:
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
