extends Node3D
class_name BucketTool

## Handheld bucket with three mutually exclusive contents.  The authoritative
## interaction is performed by GameAuthority; this script only swaps the held
## model and exposes the same item-info hook used by other handheld tools.

const MODEL_PATHS := {
	"empty_bucket": "res://assets/tools/MetalBucket_Empty.glb",
	"water_bucket": "res://assets/tools/MetalBucket_Water.glb",
	"milk_bucket": "res://assets/tools/MetalBucket_Milk.glb",
}

const STATE_LABELS := {
	"empty_bucket": "空桶",
	"water_bucket": "水桶",
	"milk_bucket": "牛奶桶",
}

@export var bucket_state := "empty_bucket"
@export var tool_owner := ""


func _ready() -> void:
	set_bucket_state(bucket_state)


func set_bucket_state(state_id: String) -> void:
	var normalized := state_id if MODEL_PATHS.has(state_id) else "empty_bucket"
	if normalized == bucket_state and get_node_or_null("Mesh") != null:
		return
	bucket_state = normalized
	var old_mesh := get_node_or_null("Mesh") as Node3D
	var old_transform := Transform3D.IDENTITY
	if old_mesh != null:
		old_transform = old_mesh.transform
		remove_child(old_mesh)
		old_mesh.free()
	var packed := load(str(MODEL_PATHS[normalized])) as PackedScene
	if packed == null:
		return
	var mesh := packed.instantiate() as Node3D
	if mesh == null:
		return
	mesh.name = "Mesh"
	mesh.transform = old_transform
	add_child(mesh)


func get_bucket_state() -> String:
	return bucket_state


func get_held_item_info_text(item: Dictionary, definition: Dictionary) -> String:
	var state_id := str(item.get("tool_id", bucket_state))
	var state_label := str(STATE_LABELS.get(state_id, "桶"))
	# The lower-left selected-item area is intentionally compact.  The full
	# liquid description remains available in the inventory tooltip.
	return str(definition.get("name", state_label))


func emit() -> Dictionary:
	# Bucket filling is resolved by the authoritative tool request.  Filled
	# buckets intentionally have no pour action yet.
	return {
		"ok": false,
		"reason": "bucket_requires_target" if bucket_state == "empty_bucket" else "bucket_cannot_pour",
	}
