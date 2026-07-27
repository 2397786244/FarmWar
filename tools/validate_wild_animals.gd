extends Node

var _failed := false


func _ready() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var packed := load("res://items/BlackBear.tscn") as PackedScene
	_check(packed != null, "BlackBear scene loads")
	var bear := packed.instantiate() as BlackBear if packed != null else null
	_check(bear != null, "BlackBear scene has BlackBear root")
	if bear == null:
		get_tree().quit(1)
		return
	add_child(bear)
	await get_tree().process_frame
	_check(is_equal_approx(bear.max_hp, 1000.0), "BlackBear max HP is 1000")
	_check(is_equal_approx(bear.current_hp, 1000.0), "BlackBear starts at full HP")
	_check(bear.collision_layer == GameAuthority.COLLISION_LAYER_WILD_ANIMAL, "BlackBear uses WildAnimal layer")
	var hit_area := bear.get_node_or_null("Hit3D") as Area3D
	_check(hit_area != null and hit_area.collision_layer == GameAuthority.COLLISION_LAYER_WILD_ANIMAL, "Hit3D uses WildAnimal layer")
	_check(hit_area != null and hit_area.collision_mask == GameAuthority.COLLISION_LAYER_BULLET, "Hit3D detects bullets")
	var label := bear.get_node_or_null("Label3D") as Label3D
	_check(label != null and label.text.contains("1000"), "HP Label3D is initialized")
	var mesh := bear.get_node_or_null("Mesh") as Node3D
	var animations := mesh.find_child("AnimationPlayer", true, false) as AnimationPlayer if mesh != null else null
	_check(animations != null, "BlackBear GLB contains AnimationPlayer")
	for animation_name in [&"Idle", &"Walk", &"Death", &"Attack"]:
		_check(_has_animation_case_insensitive(animations, animation_name), "BlackBear has %s animation" % animation_name)
	_check(_animation_loop_mode(animations, &"Idle") == Animation.LOOP_LINEAR, "Idle animation loops")
	_check(_animation_loop_mode(animations, &"Walk") == Animation.LOOP_LINEAR, "Walk animation loops")
	_check(_animation_loop_mode(animations, &"Attack") == Animation.LOOP_NONE, "Attack animation does not loop")
	_check(_animation_loop_mode(animations, &"Death") == Animation.LOOP_NONE, "Death animation does not loop")
	_check(is_equal_approx(CombatBalance.get_float("black_bear", "wander_speed"), 6.0), "wander speed is 6 m/s")
	_check(is_equal_approx(CombatBalance.get_float("black_bear", "chase_speed"), 12.0), "chase speed is 12 m/s")
	bear.call("_face_direction", Vector3.BACK, 1.0)
	_check(is_zero_approx(bear.rotation.y), "local +Z faces world +Z")
	bear.call("_set_state", BlackBear.State.WANDER, true)
	_check(is_equal_approx(animations.speed_scale, 1.0), "wander Walk animation uses normal playback speed")
	bear.call("_set_state", BlackBear.State.CHASE, true)
	_check(is_equal_approx(animations.speed_scale, 2.0), "chase Walk animation uses double playback speed")
	GameAuthority.player_states[77] = {
		"position": bear.global_position + Vector3(0.0, 0.0, 1.9),
		"hp": 200.0,
		"respawn_left": 0.0,
	}
	bear.target_peer_id = 77
	bear.rotation.y = PI
	bear.call("_update_chase", 0.016)
	_check(bear.state == BlackBear.State.ATTACK, "BlackBear enters attack inside 2.0 m")
	_check(is_zero_approx(bear.rotation.y), "BlackBear immediately faces its attack target")
	_check(label.text.contains("ATTACK"), "Label3D displays current FSM state")
	bear.set("_state_elapsed", CombatBalance.get_float("black_bear", "attack_windup"))
	bear.call("_update_attack", 0.016)
	_check(is_equal_approx(float(GameAuthority.player_states[77].get("hp", 0.0)), 150.0), "BlackBear attack lands within hit range")
	GameAuthority.player_states.erase(77)
	for hit_index in range(3):
		bear.impact("test", 50.0, "red")
		_check(bear.state != BlackBear.State.FLEE, "accumulated damage below 200 does not trigger flee (%d)" % hit_index)
	bear.impact("test", 50.0, "red")
	_check(is_equal_approx(bear.current_hp, 800.0), "four 50 damage hits reduce BlackBear HP by 200")
	_check(bear.state == BlackBear.State.FLEE, "accumulated 200 damage enters flee state")
	bear.apply_knockback(Vector3.RIGHT, 15.0)
	_check(is_equal_approx((bear.get("_knockback_velocity") as Vector3).length(), 4.0), "BlackBear knockback is scaled and capped")
	bear.apply_knockback(Vector3.RIGHT, 15.0)
	_check(is_equal_approx((bear.get("_knockback_velocity") as Vector3).length(), 4.0), "repeated knockback cannot exceed its cap")
	var hp_before_effects := bear.current_hp
	bear.impact("Freeze", 0.0, "red")
	_check(bear.freeze_remaining > 0.0 and bool(bear.call("_is_immobilized")), "Freeze immobilizes wild animals")
	bear.call("_stop_horizontal", 0.1, true)
	_check((bear.get("_knockback_velocity") as Vector3).is_zero_approx(), "Freeze rapidly clears residual knockback")
	bear.freeze_remaining = 0.0
	bear.impact(TranquilizerBullet.EFFECT_TRANQUILIZER, 0.0, "red")
	_check(is_equal_approx(bear.tranquilizer_remaining, 8.0), "Tranquilizer immobilizes BlackBear for 8 seconds")
	bear.tranquilizer_remaining = 0.0
	bear.impact("Flame", 0.0, "red")
	bear.call("_tick_status_effects", 1.0)
	_check(is_equal_approx(bear.current_hp, hp_before_effects - 15.0), "Flame applies configured damage over time")
	var hp_before_lightning := bear.current_hp
	bear.impact("Lightening", 100.0, "red")
	_check(is_equal_approx(bear.current_hp, hp_before_lightning - 100.0), "Lightning applies immediate high damage without a timer")
	bear.impact("Labeled", 0.0, "red")
	_check(is_equal_approx(bear.labeled_remaining, 6.0), "SmallMouse label lasts 6 seconds on wild animals")
	var outlined_mesh: MeshInstance3D = null
	for candidate in mesh.find_children("*", "MeshInstance3D", true, false):
		outlined_mesh = candidate as MeshInstance3D
		break
	var outline := outlined_mesh.material_overlay as StandardMaterial3D if outlined_mesh != null else null
	_check(outline != null and outline.no_depth_test, "Labeled wild-animal outline renders through depth")
	_check(outline != null and outline.albedo_color.is_equal_approx(Color(0.0, 0.0, 0.0, 0.94)), "Wild-animal labeled outline is black")
	var snapshot := GameAuthority.call("_build_world_snapshot") as Dictionary
	_check((snapshot.get("wild_animals", []) as Array).size() == 1, "multiplayer snapshot contains BlackBear")
	var proxy := packed.instantiate() as BlackBear
	proxy.network_proxy = true
	add_child(proxy)
	proxy.apply_network_state(bear.get_network_state())
	_check(proxy.collision_layer == 0, "multiplayer visual proxy has no authority collision")
	_check(is_equal_approx(proxy.current_hp, bear.current_hp), "multiplayer visual proxy receives HP")
	_check(is_equal_approx(proxy.labeled_remaining, bear.labeled_remaining), "multiplayer visual proxy receives labeled state")
	var proxy_mesh := proxy.get_node_or_null("Mesh") as Node3D
	var proxy_outlined_mesh: MeshInstance3D = null
	for candidate in proxy_mesh.find_children("*", "MeshInstance3D", true, false):
		proxy_outlined_mesh = candidate as MeshInstance3D
		break
	_check(proxy_outlined_mesh != null and proxy_outlined_mesh.material_overlay != null, "multiplayer proxy displays labeled outline")

	var generator_packed := load("res://buildings/nature/WildAnimalGenerator.tscn") as PackedScene
	var generator := generator_packed.instantiate() as WildAnimalGenerator if generator_packed != null else null
	_check(generator != null, "WildAnimalGenerator scene loads")
	_check(generator != null and generator.maximum_animals == 2, "generator cap is two animals")
	var bear_hide := IngredientCatalog.get_definition("bear_hide")
	_check(str(bear_hide.get("display_name", "")) == "黑熊皮", "BlackBear hide item is registered")
	_check(IngredientCatalog.get_harvest_drop_scene_path("bear_hide").contains("RawBeef"), "BlackBear hide temporarily uses the beef model")
	_check(BlackBear.BEAR_HIDE_DROP_COUNT == 5, "BlackBear death drop count is five hides")
	print("Wild animal validation: %s" % ("FAILED" if _failed else "PASS"))
	proxy.free()
	bear.free()
	if generator != null:
		generator.free()
	get_tree().quit(1 if _failed else 0)


func _has_animation_case_insensitive(player: AnimationPlayer, requested: StringName) -> bool:
	if player == null:
		return false
	var requested_lower := str(requested).to_lower()
	for candidate in player.get_animation_list():
		var candidate_lower := str(candidate).to_lower()
		if candidate_lower == requested_lower or candidate_lower.ends_with("/" + requested_lower):
			return true
	return false


func _animation_loop_mode(player: AnimationPlayer, requested: StringName) -> Animation.LoopMode:
	if player == null:
		return Animation.LOOP_NONE
	var requested_lower := str(requested).to_lower()
	for candidate in player.get_animation_list():
		var candidate_lower := str(candidate).to_lower()
		if candidate_lower == requested_lower or candidate_lower.ends_with("/" + requested_lower):
			var animation := player.get_animation(candidate)
			return animation.loop_mode if animation != null else Animation.LOOP_NONE
	return Animation.LOOP_NONE


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failed = true
		push_error("[FAIL] %s" % message)
