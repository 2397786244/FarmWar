extends RefCounted
class_name RealtimeInputStream

## Shared wire helper for high-frequency cooperative control. Each unreliable
## packet repeats the current command plus the two immediately preceding ones,
## so a single lost Steam P2P packet does not create an input hole.
const REDUNDANT_FRAME_COUNT := 3
const ROUTING_FIELDS: Array[String] = [
	"vehicle_id",
	"device_id",
	"device_path",
	"device_type",
	"control_mode",
]


static func make_packet(latest_frame: Dictionary, history: Array[Dictionary]) -> Dictionary:
	var frames: Array[Dictionary] = []
	var seen_sequences := {}
	_append_unique_frame(frames, seen_sequences, latest_frame)
	for index in range(history.size() - 1, -1, -1):
		if frames.size() >= REDUNDANT_FRAME_COUNT:
			break
		_append_unique_frame(frames, seen_sequences, history[index])
	var packet := {"frames": frames}
	# Routing metadata is intentionally duplicated outside the frame list. The
	# authority must be able to validate the target before accepting a redundant
	# frame batch, while each frame still carries the same metadata for auditing.
	for field_name: String in ROUTING_FIELDS:
		if latest_frame.has(field_name):
			packet[field_name] = latest_frame.get(field_name)
	return packet


static func extract_frames(payload: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_frames: Variant = payload.get("frames", [])
	if raw_frames is Array:
		for value: Variant in raw_frames:
			if value is Dictionary:
				result.append((value as Dictionary).duplicate(true))
	if result.is_empty() and payload.has("input_seq"):
		result.append(payload.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("input_seq", -1)) < int(b.get("input_seq", -1))
	)
	return result


static func _append_unique_frame(
	frames: Array[Dictionary],
	seen_sequences: Dictionary,
	frame: Dictionary
) -> void:
	var sequence := int(frame.get("input_seq", -1))
	if sequence < 0 or seen_sequences.has(sequence):
		return
	seen_sequences[sequence] = true
	frames.append(frame.duplicate(true))
