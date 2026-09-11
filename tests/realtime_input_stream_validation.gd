extends Node

const REALTIME_INPUT_STREAM_SCRIPT := preload("res://src/realtime_input_stream.gd")

var failures: Array[String] = []


func _ready() -> void:
	_run()


func _run() -> void:
	var history: Array[Dictionary] = [
		{"input_seq": 41, "move": Vector2.LEFT},
		{"input_seq": 42, "move": Vector2.RIGHT},
		{"input_seq": 43, "move": Vector2.UP},
	]
	var packet := REALTIME_INPUT_STREAM_SCRIPT.make_packet({
		"input_seq": 43,
		"move": Vector2.UP,
		"vehicle_id": "vehicle/test",
	}, history)
	var frames := REALTIME_INPUT_STREAM_SCRIPT.extract_frames(packet)
	_check(frames.size() == 3, "current input and two redundant frames are transmitted")
	_check(int(frames[0].get("input_seq", 0)) == 41, "server extraction sorts redundant frames by sequence")
	_check(int(frames[2].get("input_seq", 0)) == 43, "latest sequence is preserved")
	_check(str(packet.get("vehicle_id", "")) == "vehicle/test", "vehicle routing metadata survives packet wrapping")
	var legacy_frames := REALTIME_INPUT_STREAM_SCRIPT.extract_frames({"input_seq": 9, "move": Vector2.ZERO})
	_check(legacy_frames.size() == 1 and int(legacy_frames[0].get("input_seq", 0)) == 9, "legacy single-frame local path remains supported")
	var device_packet := REALTIME_INPUT_STREAM_SCRIPT.make_packet({
		"input_seq": 8,
		"move": Vector2.ZERO,
		"device_id": "remote/test",
		"device_path": "remote/test",
		"device_type": "normal_drone",
	}, [])
	_check(str(device_packet.get("device_id", "")) == "remote/test", "remote device routing metadata survives packet wrapping")
	_validate_authority_queue_acknowledgement()
	_validate_duplicate_packet_does_not_acknowledge()
	_validate_queue_overflow_does_not_fake_acknowledgement()
	_validate_route_metadata_is_not_mixed()
	_finish()


func _validate_authority_queue_acknowledgement() -> void:
	var queues := {}
	var state := {"last_received_input_seq": 0, "last_processed_input_seq": 0, "last_input_seq": 0}
	var queued_state: Dictionary = GameAuthority.call(
		"_enqueue_realtime_input_frames",
		queues,
		"player_test",
		state,
		{"frames": [{"input_seq": 3}, {"input_seq": 1}, {"input_seq": 2}]}
	)
	_check(int(queued_state.get("last_received_input_seq", 0)) == 3, "authority tracks the newest received sequence independently")
	_check(int(queued_state.get("last_processed_input_seq", 0)) == 0, "receiving frames does not acknowledge them as simulated")
	var first_result: Dictionary = GameAuthority.call(
		"_consume_realtime_input_frame", queues, "player_test", {}
	)
	_check(int((first_result.get("input", {}) as Dictionary).get("input_seq", 0)) == 1, "authority consumes only the oldest queued frame per tick")
	_check(bool(first_result.get("consumed", false)), "queued frame is marked as consumed")


func _validate_duplicate_packet_does_not_acknowledge() -> void:
	var queues := {}
	var state := {"last_received_input_seq": 3, "last_processed_input_seq": 2, "last_input_seq": 2}
	var duplicate_state: Dictionary = GameAuthority.call(
		"_enqueue_realtime_input_frames",
		queues,
		"duplicate_test",
		state,
		{"frames": [{"input_seq": 1}, {"input_seq": 2}, {"input_seq": 3}]}
	)
	_check(int(duplicate_state.get("last_received_input_seq", 0)) == 3, "duplicate packets keep the received high-water mark")
	_check(int(duplicate_state.get("last_processed_input_seq", 0)) == 2, "duplicate packets do not alter the processed sequence")
	_check((queues.get("duplicate_test", []) as Array).is_empty(), "duplicate packets do not create phantom queued frames")


func _validate_queue_overflow_does_not_fake_acknowledgement() -> void:
	var queues := {}
	var state := {"last_received_input_seq": 0, "last_processed_input_seq": 0, "last_input_seq": 0}
	var frames: Array[Dictionary] = []
	for sequence in range(1, 122):
		frames.append({"input_seq": sequence})
	var overflow_state: Dictionary = GameAuthority.call(
		"_enqueue_realtime_input_frames",
		queues,
		"overflow_test",
		state,
		{"frames": frames}
	)
	_check(int(overflow_state.get("last_received_input_seq", 0)) == 121, "queue overflow still records the newest received sequence")
	_check(int(overflow_state.get("last_processed_input_seq", 0)) == 0, "queue overflow does not acknowledge an unprocessed frame")
	_check(bool(overflow_state.get("realtime_input_resync", false)), "queue overflow sets the resynchronization marker")
	var retained: Array = queues.get("overflow_test", [])
	_check(retained.size() == 1 and int((retained[0] as Dictionary).get("input_seq", 0)) == 121, "queue overflow retains only the newest frame")


func _validate_route_metadata_is_not_mixed() -> void:
	var valid_frames: Array[Dictionary] = [
		{"input_seq": 1, "vehicle_id": "vehicle/a"},
		{"input_seq": 2, "vehicle_id": "vehicle/a"},
	]
	var mixed_frames: Array[Dictionary] = [
		{"input_seq": 1, "vehicle_id": "vehicle/a"},
		{"input_seq": 2, "vehicle_id": "vehicle/b"},
	]
	var first_valid_frames: Array[Dictionary] = [
		{},
		{"input_seq": 2, "vehicle_id": "vehicle/a"},
	]
	var valid := bool(GameAuthority.call(
		"_realtime_packet_routes_match", valid_frames, "vehicle/a", "vehicle_id"
	))
	var mixed := bool(GameAuthority.call(
		"_realtime_packet_routes_match", mixed_frames, "vehicle/a", "vehicle_id"
	))
	var first_valid_frame := bool(GameAuthority.call(
		"_realtime_packet_routes_match",
		first_valid_frames,
		"vehicle/a",
		"vehicle_id"
	))
	var first_valid_route := str(GameAuthority.call(
		"_realtime_packet_route_id",
		{},
		first_valid_frames,
		"vehicle_id"
	))
	var conflicting_outer_routes := bool(GameAuthority.call(
		"_realtime_packet_outer_routes_match",
		{"device_id": "remote/a", "device_path": "remote/b"},
		"remote/a",
		"device_id",
		"device_path"
	))
	_check(valid, "frames with one vehicle route are accepted")
	_check(not mixed, "frames mixing vehicle routes are rejected")
	_check(first_valid_frame and first_valid_route == "vehicle/a", "server accepts the first valid frame route")
	_check(not conflicting_outer_routes, "conflicting outer device routes are rejected")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[RealtimeInputStreamValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[RealtimeInputStreamValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[RealtimeInputStreamValidation] PASS all checks")
	else:
		print("[RealtimeInputStreamValidation] FAIL count=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
