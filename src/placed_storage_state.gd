extends RefCounted
class_name PlacedStorageState

## Common persistence contract for placeable storage facilities.
##
## A storage-capable scene must join `persistent_placed_storage` and expose:
##   get_persistent_storage_state() -> Dictionary
##   apply_persistent_storage_state(state: Dictionary) -> void
##
## The payload is deliberately facility-defined. This lets racks, crates,
## cabinets, and future containers keep different item layouts without making
## WorldPersistence know their internal inventory rules.
const STORAGE_GROUP := "persistent_placed_storage"
const GET_STATE_METHOD := "get_persistent_storage_state"
const APPLY_STATE_METHOD := "apply_persistent_storage_state"


static func is_storage_node(node: Node) -> bool:
	return node != null and is_instance_valid(node) \
			and node.is_in_group(STORAGE_GROUP) \
			and node.has_method(GET_STATE_METHOD) \
			and node.has_method(APPLY_STATE_METHOD)


static func capture(node: Node) -> Dictionary:
	if not is_storage_node(node):
		return {}
	var value: Variant = node.call(GET_STATE_METHOD)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func apply(node: Node, state: Variant) -> bool:
	if not is_storage_node(node) or not state is Dictionary:
		return false
	var payload := (state as Dictionary).duplicate(true)
	if payload.is_empty():
		return false
	node.call(APPLY_STATE_METHOD, payload)
	return true


static func state_from_record(record: Dictionary) -> Dictionary:
	var storage_value: Variant = record.get("storage_state", {})
	if storage_value is Dictionary and not (storage_value as Dictionary).is_empty():
		return (storage_value as Dictionary).duplicate(true)
	# Backward compatibility for saves created before the common storage
	# protocol: the old rack/crate fields were stored as visual state.
	var visual_value: Variant = record.get("visual_state", {})
	if visual_value is Dictionary and not (visual_value as Dictionary).is_empty():
		return (visual_value as Dictionary).duplicate(true)
	if record.has("rack_slots"):
		return {"rack_slots": record.get("rack_slots", [])}
	if record.has("crate_data"):
		return {"crate_data": record.get("crate_data", {})}
	return {}


static func apply_record(node: Node, record: Dictionary) -> bool:
	return apply(node, state_from_record(record))
