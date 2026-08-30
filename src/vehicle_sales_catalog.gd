extends RefCounted
class_name VehicleSalesCatalog

const VehicleSpawnCatalogScript = preload("res://src/vehicle_spawn_catalog.gd")

## AutoSales deliberately has its own allow-list.  Special vehicles remain
## spawnable through the editor/debug systems but cannot be bought here.
const PRODUCTS: Array[Dictionary] = [
	{
		"vehicle_id": "atv",
		"name": "越野摩托车",
		"price": 20000,
		"description": "轻巧的单人越野载具，适合在农场道路和崎岖地形间快速移动。",
	},
	{
		"vehicle_id": "mini_car",
		"name": "迷你车",
		"price": 22000,
		"description": "小型双座载具，转向灵活，适合短途通勤。",
	},
	{
		"vehicle_id": "van",
		"name": "厢式货车",
		"price": 26000,
		"description": "封闭式双座车辆，适合在道路网络中稳定行驶。",
	},
	{
		"vehicle_id": "farm_base_vehicle",
		"name": "农场基础载具",
		"price": 30000,
		"description": "面向农场作业的多用途车辆，可在载具店安装专用配件。",
	},
	{
		"vehicle_id": "sedan",
		"name": "轿车",
		"price": 32000,
		"description": "四座公路载具，兼顾乘坐空间和日常操控。",
	},
	{
		"vehicle_id": "sport_car",
		"name": "运动型跑车",
		"price": 39000,
		"description": "强调速度的双座载具，适合在开阔道路上行驶。",
	},
]


static func get_products() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for product_value: Variant in PRODUCTS:
		if product_value is Dictionary:
			result.append((product_value as Dictionary).duplicate(true))
	return result


static func get_product(vehicle_id: String) -> Dictionary:
	var normalized := VehicleSpawnCatalogScript.normalize_id(vehicle_id)
	for product_value: Variant in PRODUCTS:
		if not product_value is Dictionary:
			continue
		var product := product_value as Dictionary
		if str(product.get("vehicle_id", "")) == normalized:
			var result := product.duplicate(true)
			var resolved := VehicleSpawnCatalogScript.resolve_scene_path(normalized)
			result["scene_path"] = str(resolved.get("scene_path", ""))
			return result
	return {}


static func is_available(vehicle_id: String) -> bool:
	return not get_product(vehicle_id).is_empty()
