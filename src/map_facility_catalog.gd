extends RefCounted
class_name MapFacilityCatalog

const INTERIOR_FACILITY_ROOT := "res://facilities/interior"

const KITCHEN_ASSETS: Array[Dictionary] = [
	{"id": "canning_station", "label": "罐头台", "path": "res://kitchens/canning_station.tscn", "category": "kitchen"},
	{"id": "chopping_station", "label": "切菜台", "path": "res://kitchens/chopping_station.tscn", "category": "kitchen"},
	{"id": "farm_smoker", "label": "烟熏炉", "path": "res://kitchens/farm_smoker.tscn", "category": "kitchen"},
	{"id": "freezer", "label": "冷冻柜", "path": "res://kitchens/freezer.tscn", "category": "kitchen"},
	{"id": "griddle_station", "label": "煎台", "path": "res://kitchens/griddle_station.tscn", "category": "kitchen"},
	{"id": "induction_counter", "label": "电磁炉", "path": "res://kitchens/induction_counter.tscn", "category": "kitchen"},
	{"id": "ingredient_extractor", "label": "食材提取器", "path": "res://kitchens/ingredient_extractor.tscn", "category": "kitchen"},
	{"id": "ingredient_pickup", "label": "食材取料台", "path": "res://kitchens/ingredient_pickup.tscn", "category": "kitchen"},
	{"id": "oven", "label": "烤箱", "path": "res://kitchens/oven.tscn", "category": "kitchen"},
	{"id": "plating_station", "label": "配餐台", "path": "res://kitchens/plating_station.tscn", "category": "kitchen"},
	{"id": "sink", "label": "水槽", "path": "res://kitchens/sink.tscn", "category": "kitchen"},
	{"id": "stand_mixer", "label": "立式搅拌机", "path": "res://kitchens/stand_mixer.tscn", "category": "kitchen"},
]

const DEFENSE_ASSETS: Array[Dictionary] = [
	{"id": "tall_brick", "label": "高大砖墙", "path": "res://character/weapons/TallBrick.tscn", "category": "defense"},
	{"id": "tall_log_wall", "label": "高大木墙", "path": "res://character/weapons/TallLogWall.tscn", "category": "defense"},
	{"id": "tall_mesh_wall", "label": "高大铁丝网", "path": "res://character/weapons/TallMeshWall.tscn", "category": "defense"},
	{"id": "wire_mesh_gate", "label": "铁丝网门", "path": "res://character/weapons/WireMeshGate.tscn", "category": "defense"},
]


static func get_assets(category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if category.is_empty() or category == "kitchen":
		result.append_array(KITCHEN_ASSETS.duplicate(true))
	if category.is_empty() or category == "defense":
		result.append_array(DEFENSE_ASSETS.duplicate(true))
	if category.is_empty() or category == "interior":
		result.append_array(_scan_interior_assets())
	return result


static func _scan_interior_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_scan_interior_directory(INTERIOR_FACILITY_ROOT, result)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return str(first.get("label", "")).naturalnocasecmp_to(str(second.get("label", ""))) < 0
	)
	return result


static func _scan_interior_directory(directory_path: String, result: Array[Dictionary]) -> void:
	if DirAccess.open(directory_path) == null:
		return
	for entry_value in ResourceLoader.list_directory(directory_path):
		var entry := str(entry_value)
		if entry.ends_with("/"):
			_scan_interior_directory(directory_path.path_join(entry.trim_suffix("/")), result)
			continue
		if entry.get_extension().to_lower() != "tscn":
			continue
		var resource_path := directory_path.path_join(entry)
		var relative_path := resource_path.trim_prefix(INTERIOR_FACILITY_ROOT + "/")
		var id_path := relative_path.trim_suffix(".tscn").replace("/", "_").to_snake_case()
		result.append({
			"id": "interior_%s" % id_path,
			"label": _humanize_asset_name(entry.get_basename()),
			"path": resource_path,
			"category": "interior",
		})


static func _humanize_asset_name(value: String) -> String:
	var result := value.replace("_", " ").replace("-", " ")
	var output := ""
	for index in range(result.length()):
		var character := result[index]
		if index > 0 and character == character.to_upper() and character != character.to_lower():
			var previous := result[index - 1]
			if previous != " " and previous == previous.to_lower():
				output += " "
		output += character
	return output.strip_edges()


static func get_asset_by_path(path: String) -> Dictionary:
	for asset in get_assets():
		if str(asset.get("path", "")) == path:
			return asset.duplicate(true)
	return {}


static func get_asset_by_id(asset_id: String) -> Dictionary:
	for asset in get_assets():
		if str(asset.get("id", "")) == asset_id:
			return asset.duplicate(true)
	return {}
