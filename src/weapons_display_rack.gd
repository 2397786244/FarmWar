extends StaticBody3D
class_name WeaponDisplayRack

const SLOT_COUNT := 3
const MAX_DISPLAY_LENGTH := 4.0
const MAX_DISPLAY_HEIGHT := 0.9

@export var indestructible := true

var rack_slots: Array[Dictionary] = [{}, {}, {}]
var _slot_markers: Array[Marker3D] = []
var _slot_visuals: Array[Node3D] = [null, null, null]


func _ready() -> void:
	add_to_group("weapon_display_racks")
	add_to_group("persistent_placed_storage")
	_slot_markers = [
		get_node_or_null("Bottom") as Marker3D,
		get_node_or_null("Medium") as Marker3D,
		get_node_or_null("Top") as Marker3D,
	]
	_refresh_all_slot_visuals()


func get_network_device_id() -> String:
	return str(get_meta("network_device_id", get_path()))


func get_rack_slot_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {}
	return rack_slots[slot_index].duplicate(true)


func set_rack_slot_item(slot_index: int, item: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	rack_slots[slot_index] = item.duplicate(true)
	_refresh_slot_visual(slot_index)
	return true


func get_persistent_storage_state() -> Dictionary:
	return {"rack_slots": rack_slots.duplicate(true)}


func apply_persistent_storage_state(state: Dictionary) -> void:
	var slots_value: Variant = state.get("rack_slots", [])
	if not slots_value is Array:
		return
	var next_slots: Array[Dictionary] = [{}, {}, {}]
	for index in range(mini(SLOT_COUNT, (slots_value as Array).size())):
		var item_value: Variant = (slots_value as Array)[index]
		if item_value is Dictionary:
			next_slots[index] = (item_value as Dictionary).duplicate(true)
	rack_slots = next_slots
	_refresh_all_slot_visuals()


func get_network_visual_state() -> Dictionary:
	return get_persistent_storage_state()


func apply_network_visual_state(state: Dictionary) -> void:
	apply_persistent_storage_state(state)


func _refresh_all_slot_visuals() -> void:
	for index in range(SLOT_COUNT):
		_refresh_slot_visual(index)


func _refresh_slot_visual(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT or slot_index >= _slot_markers.size():
		return
	var previous := _slot_visuals[slot_index]
	if is_instance_valid(previous):
		previous.queue_free()
	_slot_visuals[slot_index] = null
	var marker := _slot_markers[slot_index]
	var item := rack_slots[slot_index]
	if marker == null or item.is_empty():
		return
	var definition := GameAuthority.authoritative_tool_definitions.get(str(item.get("tool_id", "")), {}) as Dictionary
	var scene_path := str(definition.get("path", ""))
	var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
	var visual := packed.instantiate() as Node3D if packed != null else null
	if visual == null:
		return
	visual.name = "DisplayedWeapon"
	_prepare_visual_only(visual)
	marker.add_child(visual)
	visual.position = Vector3.ZERO
	visual.rotation = Vector3(0.0, PI * 0.5, 0.0)
	_fit_visual_to_slot(visual, marker)
	_slot_visuals[slot_index] = visual


func _prepare_visual_only(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stream = null
	if node is Light3D:
		(node as Light3D).visible = false
	for child in node.get_children():
		_prepare_visual_only(child)


func _fit_visual_to_slot(visual: Node3D, marker: Marker3D) -> void:
	var bounds := _combined_visual_aabb(visual, marker)
	if bounds.size.length_squared() <= 0.000001:
		return
	var fit_scale := minf(1.0, minf(
		MAX_DISPLAY_LENGTH / maxf(bounds.size.x, 0.001),
		MAX_DISPLAY_HEIGHT / maxf(bounds.size.y, 0.001)
	))
	visual.scale = Vector3.ONE * fit_scale
	bounds = _combined_visual_aabb(visual, marker)
	visual.position -= bounds.get_center()


func _combined_visual_aabb(root: Node, relative_to: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or not mesh_instance.visible:
			continue
		var local_transform := relative_to.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := local_transform * mesh_instance.get_aabb()
		result = transformed if not has_bounds else result.merge(transformed)
		has_bounds = true
	return result if has_bounds else AABB()
