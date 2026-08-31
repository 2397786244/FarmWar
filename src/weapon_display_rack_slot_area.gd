extends Area3D
class_name WeaponDisplayRackSlotArea

@export_range(0, 2, 1) var slot_index := 0


func get_weapon_display_rack() -> Node3D:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("get_rack_slot_item") and cursor.has_method("get_network_device_id"):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null


func get_interaction_hint() -> String:
	var rack := get_weapon_display_rack()
	if rack == null:
		return ""
	var item: Variant = rack.call("get_rack_slot_item", slot_index)
	return "[E] 拿下来" if item is Dictionary and not (item as Dictionary).is_empty() \
		else "[E] 把武器放上去"
