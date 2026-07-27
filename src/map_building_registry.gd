extends Node
class_name MapBuildingRegistryService

signal buildings_changed(buildings: Array[Dictionary])

const DELIVERY_NAME_HINTS := [
	"kitchen", "restaurant", "market", "shop", "store", "warehouse",
	"storage", "garage", "depot", "delivery", "pickup",
]

var buildings: Dictionary = {}
var _scan_generation := 0


func _ready() -> void:
	call_deferred("rescan_current_map")


func rescan_current_map() -> void:
	_scan_generation += 1
	var generation := _scan_generation
	var next: Dictionary = {}
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "Node3D", true, false):
		if generation != _scan_generation or not is_instance_valid(node):
			return
		var entry := _describe_building(node as Node3D)
		if not entry.is_empty():
			next[str(entry["building_id"])] = entry
	buildings = next
	buildings_changed.emit(get_buildings())


func register_building(building: Node3D, building_id := "", display_name := "", building_type := "") -> Dictionary:
	if building == null or not is_instance_valid(building):
		return {}
	var entry := _describe_building(building, building_id, display_name, building_type)
	if entry.is_empty():
		return {}
	buildings[str(entry["building_id"])] = entry
	buildings_changed.emit(get_buildings())
	return entry.duplicate(true)


func get_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in buildings.values():
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


func get_delivery_locations(building_type := "", delivery_category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in buildings.values():
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		if not bool(entry.get("accepts_delivery", false)):
			continue
		if not building_type.is_empty() and str(entry.get("building_type", "")) != building_type:
			continue
		var categories := entry.get("accepted_delivery_categories", PackedStringArray()) as PackedStringArray
		if not delivery_category.is_empty() and not categories.is_empty() \
				and not categories.has(delivery_category):
			continue
		result.append({
			"id": str(entry.get("building_id", "")),
			"name": str(entry.get("display_name", "")),
			"building_type": str(entry.get("building_type", "")),
			"position": entry.get("delivery_position", Vector3.ZERO),
			"team": str(entry.get("team", "")),
			"accepted_delivery_categories": categories,
		})
	return result


func _describe_building(node: Node3D, forced_id := "", forced_name := "", forced_type := "") -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var node_name := str(node.name)
	var lower := node_name.to_lower()
	var metadata_type := str(node.get_meta("building_type", ""))
	var building_type := forced_type if not forced_type.is_empty() else metadata_type
	if building_type.is_empty():
		building_type = _infer_building_type(lower)
	if building_type.is_empty():
		return {}
	var accepts := bool(node.get_meta("accepts_delivery", false))
	var delivery_node := node.find_child("DeliveryPoint", true, false) as Node3D
	if delivery_node == null:
		delivery_node = node.find_child("Delivery", true, false) as Node3D
	if delivery_node == null:
		delivery_node = node.find_child("CargoArea", true, false) as Node3D
	if delivery_node == null and building_type == "garage":
		delivery_node = node.find_child("CargoCarSpawnPoint", true, false) as Node3D
	var delivery_position := delivery_node.global_position if delivery_node != null else node.global_position
	var id := forced_id if not forced_id.is_empty() else str(node.get_meta("building_id", node.get_path()))
	var display := forced_name if not forced_name.is_empty() else str(node.get_meta("display_name", node_name))
	return {
		"building_id": id,
		"display_name": display,
		"building_type": building_type,
		"team": str(node.get_meta("team", node.get("owner_team") if _has_property(node, "owner_team") else "")),
		"accepts_delivery": accepts,
		"delivery_position": delivery_position,
		"node_path": str(node.get_path()),
		"is_team_base": building_type == "garage" and delivery_node != null,
		"accepted_delivery_categories": _metadata_string_array(
			node.get_meta("accepted_delivery_categories", PackedStringArray())
		),
	}


func _infer_building_type(lower_name: String) -> String:
	if lower_name.contains("kitchen"):
		return "kitchen"
	if lower_name.contains("garage"):
		return "garage"
	if lower_name.contains("restaurant"):
		return "restaurant"
	if lower_name.contains("market") or lower_name.contains("shop") or lower_name.contains("store"):
		return "market"
	if lower_name.contains("warehouse") or lower_name.contains("storage") or lower_name.contains("depot"):
		return "warehouse"
	if lower_name.contains("delivery") or lower_name.contains("pickup"):
		return "delivery"
	return ""


func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _metadata_string_array(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value as PackedStringArray
	var result := PackedStringArray()
	if value is Array:
		for entry: Variant in value:
			result.append(str(entry))
	return result
