extends Node3D

var _failed := false


func _ready() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var original_mode := GameAuthority.mode
	var original_world := GlobalVar.gameworld
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	add_child(floor_body)
	GlobalVar.gameworld = self
	GameAuthority.start_server_mode()
	GameAuthority.register_or_update_player(77, {
		"team": "red",
		"position": Vector3(0.0, 0.02, 0.0),
	})
	for _frame in range(4):
		await get_tree().physics_frame
	var proxy := GameAuthority.player_physics_nodes.get(77, null) as CharacterBody3D
	_check(is_instance_valid(proxy) and proxy.is_on_floor(), "server player proxy settles on the floor")
	GameAuthority.server_receive_player_input(77, {
		"input_seq": 1,
		"client_time_msec": Time.get_ticks_msec(),
		"move": Vector2.ZERO,
		"jump_seq": 1,
		"yaw": 0.0,
		"pitch": 0.0,
		"prone": false,
	})
	await get_tree().physics_frame
	var state: Dictionary = GameAuthority.player_states.get(77, {})
	_check(int(state.get("last_jump_seq", 0)) == 1, "accepted jump sequence is consumed")
	_check(float((state.get("velocity", Vector3.ZERO) as Vector3).y) > 0.0, "accepted jump keeps positive vertical velocity")
	var correction := GameAuthority._make_player_correction(77)
	_check(not bool(correction.get("grounded", true)), "jump correction reports airborne state")
	_check(int(correction.get("last_jump_seq", 0)) == 1, "jump correction includes accepted sequence")

	GameAuthority.stop_authority()
	GlobalVar.gameworld = original_world
	GameAuthority.mode = original_mode
	print("Player jump sync validation: %s" % ("FAILED" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failed = true
		push_error("[FAIL] %s" % message)
