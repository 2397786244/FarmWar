extends RefCounted
class_name VehicleSpawnCatalog

## Single source of truth for vehicle scene ids used by runtime delivery,
## console/debug spawning and the map editor.  The catalog intentionally
## includes tool vehicles as well as map vehicles so callers do not need to
## maintain a second list for special vehicles.
const VEHICLE_DEFINITIONS := {
	"farm_base_vehicle": {
		"scene_path": "res://vehicles/farm_base_vehicle.tscn",
		"label": "Farm Base Vehicle",
	},
	"sedan": {
		"scene_path": "res://vehicles/sedan.tscn",
		"label": "Sedan",
	},
	"sport_car": {
		"scene_path": "res://vehicles/sport_car.tscn",
		"label": "SportCar",
	},
	"mini_car": {
		"scene_path": "res://vehicles/mini_car.tscn",
		"label": "MiniCar（迷你车）",
	},
	"van": {
		"scene_path": "res://vehicles/van.tscn",
		"label": "Van",
	},
	"atv": {
		"scene_path": "res://vehicles/atv.tscn",
		"label": "ATV",
	},
	"survey_rider": {
		"scene_path": "res://character/weapons/SurveyRider.tscn",
		"label": "SurveyRider",
	},
	"police_car": {
		"scene_path": "res://vehicles/police_car.tscn",
		"label": "PoliceCar",
	},
	"fire_pickup": {
		"scene_path": "res://vehicles/fire_pickup.tscn",
		"label": "FirePickup",
	},
	"cargo_car": {
		"scene_path": "res://vehicles/cargo_car.tscn",
		"label": "CargoCar",
		"team_scene_paths": {
			"red": "res://vehicles/red_cargo_car.tscn",
			"blue": "res://vehicles/blue_cargo_car.tscn",
		},
	},
	"red_cargo_car": {
		"scene_path": "res://vehicles/red_cargo_car.tscn",
		"label": "Red CargoCar",
	},
	"blue_cargo_car": {
		"scene_path": "res://vehicles/blue_cargo_car.tscn",
		"label": "Blue CargoCar",
	},
	"combine_car": {
		"scene_path": "res://vehicles/combine_car.tscn",
		"label": "CombineCar",
	},
	"field_kitchen": {
		"scene_path": "res://character/weapons/KitchenCar.tscn",
		"label": "Field Kitchen",
	},
	"kitchen_car": {
		"scene_path": "res://character/weapons/KitchenCar.tscn",
		"label": "KitchenCar",
	},
}

## The editor has its own visible subset.  Keep the existing visible order and
## labels while sourcing every path from the same catalog as runtime callers.
const EDITOR_VEHICLE_IDS := [
	"cargo_car",
	"mini_car",
	"farm_base_vehicle",
	"combine_car",
	"police_car",
	"fire_pickup",
	"atv",
	"sport_car",
	"van",
	"sedan",
]


static func normalize_id(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")


static func has_vehicle(value: String) -> bool:
	var normalized := normalize_id(value)
	if normalized.begins_with("res://"):
		return is_vehicle_scene_path(normalized)
	return VEHICLE_DEFINITIONS.has(normalized)


static func is_vehicle_scene_path(scene_path: String) -> bool:
	var normalized := scene_path.to_lower()
	for definition_value: Variant in VEHICLE_DEFINITIONS.values():
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if str(definition.get("scene_path", "")).to_lower() == normalized:
			return true
		var team_paths_value: Variant = definition.get("team_scene_paths", {})
		if team_paths_value is Dictionary:
			for path_value: Variant in (team_paths_value as Dictionary).values():
				if str(path_value).to_lower() == normalized:
					return true
	return false


static func resolve_scene_path(vehicle_type: String, team := "") -> Dictionary:
	var normalized := normalize_id(vehicle_type)
	if normalized.begins_with("res://"):
		var normalized_path := vehicle_type.to_lower()
		# Prefer an exact top-level definition.  This makes a direct red/blue
		# CargoCar path resolve to red_cargo_car/blue_cargo_car instead of the
		# generic cargo_car alias.
		for definition_id_value: Variant in VEHICLE_DEFINITIONS.keys():
			var definition_id := str(definition_id_value)
			var definition := VEHICLE_DEFINITIONS[definition_id] as Dictionary
			if str(definition.get("scene_path", "")).to_lower() != normalized_path:
				continue
			return {
				"ok": true,
				"vehicle_id": definition_id,
				"scene_path": vehicle_type,
				"label": str(definition.get("label", definition_id)),
			}
		return {
			"ok": is_vehicle_scene_path(vehicle_type),
			"vehicle_id": normalized,
			"scene_path": vehicle_type,
		}
	if not VEHICLE_DEFINITIONS.has(normalized):
		return {"ok": false, "vehicle_id": normalized, "scene_path": ""}
	var definition := VEHICLE_DEFINITIONS[normalized] as Dictionary
	var scene_path := str(definition.get("scene_path", ""))
	var team_paths_value: Variant = definition.get("team_scene_paths", {})
	if not str(team).is_empty() and team_paths_value is Dictionary:
		var team_paths := team_paths_value as Dictionary
		var team_path := str(team_paths.get(str(team).to_lower(), ""))
		if not team_path.is_empty():
			scene_path = team_path
	return {
		"ok": not scene_path.is_empty(),
		"vehicle_id": normalized,
		"scene_path": scene_path,
		"label": str(definition.get("label", normalized)),
	}


static func get_editor_assets() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	for vehicle_id_value: Variant in EDITOR_VEHICLE_IDS:
		var vehicle_id := str(vehicle_id_value)
		var resolved := resolve_scene_path(vehicle_id)
		if not bool(resolved.get("ok", false)):
			continue
		var asset := {
			"label": str(resolved.get("label", vehicle_id)),
			"path": str(resolved.get("scene_path", "")),
			"id": vehicle_id,
			"placement_category": "vehicle",
		}
		var definition := VEHICLE_DEFINITIONS.get(vehicle_id, {}) as Dictionary
		if definition.has("team_scene_paths"):
			asset["team_scene_paths"] = (definition["team_scene_paths"] as Dictionary).duplicate(true)
		assets.append(asset)
	return assets
