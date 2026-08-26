extends Node3D

const BLACK_BEAR_SCENE := preload("res://items/BlackBear.tscn")
const TREE_SCENE := preload("res://buildings/nature/Oak.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var asset_paths := {
		"animal hide": "res://assets/other_items/Material/AnimalHide.glb",
		"plant fiber bundle": "res://assets/other_items/Material/PlantFiberBundle.glb",
		"plant fiber cloth": "res://assets/other_items/industrials/PlantFiberCloth.glb",
		"electronic detonator module": "res://assets/other_items/industrials/FTF_Tool_ElectronicDetonatorModule.glb",
		"vehicle roof cooling system": "res://assets/other_items/industrials/FTF_Tool_VehicleRoofCoolingSystem_White_2_3m.glb",
		"vehicle signal augment": "res://assets/other_items/industrials/FTF_Tool_VehicleSignalAugment_Black_1_9m.glb",
	}
	for label_value: Variant in asset_paths:
		var label := str(label_value)
		var path := str(asset_paths[label_value])
		_check(ResourceLoader.exists(path), "%s model exists" % label)
		_check(load(path) is PackedScene, "%s model imports as a PackedScene" % label)

	_check(
		not ResourceLoader.exists("res://assets/AnimalHide.glb")
			and not ResourceLoader.exists("res://assets/PlantFiberBundle.glb")
			and not ResourceLoader.exists("res://assets/PlantFiberCloth.glb"),
		"source GLBs are no longer left in the root assets folder"
	)

	var expected_items := {
		"animal_hide": {
			"display_name": "动物皮",
			"category": "animal_product",
			"model_path": asset_paths["animal hide"],
		},
		"plant_fiber": {
			"display_name": "植物纤维",
			"category": "industrial_material",
			"model_path": asset_paths["plant fiber bundle"],
		},
		"plant_fiber_cloth": {
			"display_name": "植物纤维布",
			"category": "industrial_product",
			"model_path": asset_paths["plant fiber cloth"],
		},
		"iron_ingot": {
			"display_name": "铁锭",
			"category": "industrial_material",
			"model_path": "res://assets/other_items/industrials/FTF_Product_IronIngot_Drop.glb",
		},
		"copper_ingot": {
			"display_name": "铜锭",
			"category": "industrial_material",
			"model_path": "res://assets/other_items/industrials/FTF_Product_CopperIngot_Drop.glb",
		},
		"steel_plate": {
			"display_name": "钢板",
			"category": "industrial_product",
			"model_path": "res://assets/other_items/industrials/FTF_Product_SteelPlate_Drop.glb",
		},
		"metal_connector": {
			"display_name": "金属连接件",
			"category": "industrial_product",
			"model_path": "res://assets/other_items/industrials/FTF_Product_MetalConnector_Drop.glb",
		},
		"cotton_thread": {
			"display_name": "棉线",
			"category": "industrial_material",
			"model_path": "res://assets/other_items/industrials/FTF_Product_CottonThreadSpool_Drop.glb",
		},
		"cotton_cloth": {
			"display_name": "棉布",
			"category": "industrial_product",
			"model_path": "res://assets/other_items/industrials/FTF_Product_CottonCloth_Drop.glb",
		},
		"engineering_plastic_pellets": {
			"display_name": "工程塑料颗粒",
			"category": "industrial_material",
			"model_path": "res://assets/other_items/industrials/FTF_Product_EngineeringPlasticPellets_Drop.glb",
		},
		"hard_drive": {
			"display_name": "硬盘",
			"category": "industrial_product",
			"model_path": "res://assets/other_items/industrials/FTF_Product_SolidStateDrive_Drop.glb",
		},
		"metal_defense_net": {
			"display_name": "金属防护网",
			"category": "industrial_product",
			"model_path": "res://assets/other_items/industrials/FTF_Product_MetalDefenseNetPiece_Drop.glb",
		},
		"electronic_detonator_module": {
			"display_name": "电子引爆模块",
			"category": "industrial_product",
			"model_path": asset_paths["electronic detonator module"],
		},
		"vehicle_roof_cooling_system": {
			"display_name": "载具冷却系统",
			"category": "industrial_product",
			"model_path": asset_paths["vehicle roof cooling system"],
		},
		"vehicle_signal_augment": {
			"display_name": "车载信号增强模块",
			"category": "industrial_product",
			"model_path": asset_paths["vehicle signal augment"],
		},
	}
	for item_id_value: Variant in expected_items:
		var item_id := str(item_id_value)
		var expected := expected_items[item_id] as Dictionary
		var definition := IngredientCatalog.get_definition(item_id)
		_check(not definition.is_empty(), "%s is registered in the ingredient catalog" % item_id)
		_check(
			str(definition.get("display_name", "")) == str(expected.get("display_name", "")),
			"%s has the expected display name" % item_id
		)
		_check(
			str(definition.get("category", "")) == str(expected.get("category", "")),
			"%s has the expected category" % item_id
		)
		_check(
			IngredientCatalog.get_harvest_drop_scene_path(item_id) == str(expected.get("model_path", "")),
			"%s points to its imported model" % item_id
		)
		_check(IngredientCatalog.is_team_storage_material(item_id), "%s is a team storage material" % item_id)
		if item_id in [
			"iron_ingot",
			"copper_ingot",
			"steel_plate",
			"metal_connector",
			"cotton_thread",
			"cotton_cloth",
			"engineering_plastic_pellets",
			"hard_drive",
			"metal_defense_net",
			"electronic_detonator_module",
			"vehicle_roof_cooling_system",
			"vehicle_signal_augment",
		]:
			var shop_product := GlobalVar.get_shop_product(item_id)
			_check(not shop_product.is_empty(), "%s is registered in the shop price list" % item_id)
			_check(
				int(shop_product.get("buy_price", 0)) > int(shop_product.get("sell_price", 0))
					and int(shop_product.get("sell_price", 0)) > 0,
				"%s has a positive buy/sell price spread" % item_id
			)
	_check(IngredientCatalog.get_definition("bear_hide").is_empty(), "bear_hide is not registered")

	GameAuthority.start_local_mode({
		"display_name": "IndustrialMaterialAssetsValidation",
		"team": "blue",
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self
	var bear := BLACK_BEAR_SCENE.instantiate() as BlackBear
	_check(bear != null, "black bear scene instantiates")
	if bear == null:
		GameAuthority.stop_authority()
		_finish()
		return
	add_child(bear)
	await get_tree().process_frame
	bear._die()
	await get_tree().process_frame

	_check(GameAuthority.dropped_item_nodes.size() == 5, "black bear drops five animal hides")
	for pickup_value: Variant in GameAuthority.dropped_item_nodes.values():
		var pickup := pickup_value as PickupItem
		_check(pickup != null, "black bear drop is a PickupItem")
		if pickup == null:
			continue
		_check(pickup.item_id.begins_with("nature_drop_"), "black bear drop has a nature-drop id")
		_check(pickup.item_data.get("ingredient_id", "") == "animal_hide", "black bear drop item id is animal_hide")
		_check(pickup.model_path == asset_paths["animal hide"], "black bear drop uses AnimalHide.glb")

	var tree := TREE_SCENE.instantiate() as HarvestTree
	_check(tree != null, "oak tree scene instantiates")
	if tree != null:
		add_child(tree)
		await get_tree().process_frame
		for _index in range(20):
			var planned_drops := tree.get_authoritative_harvest_drops()
			var fiber_drop_count := 0
			for drop_value: Variant in planned_drops:
				var drop := drop_value as Dictionary
				if str(drop.get("item_id", "")) == "plant_fiber":
					fiber_drop_count = int(drop.get("count", 0))
			_check(
				fiber_drop_count >= HarvestTree.PLANT_FIBER_DROP_MIN_COUNT
					and fiber_drop_count <= HarvestTree.PLANT_FIBER_DROP_MAX_COUNT,
				"tree plant fiber count stays in the 2-5 range"
			)
		var drops_before_tree := GameAuthority.dropped_item_nodes.size()
		tree.begin_authoritative_destroy(tree.log_drop_count)
		await get_tree().create_timer(1.2).timeout
		var spawned_fiber_count := 0
		var saw_cloth_drop := false
		for pickup_value: Variant in GameAuthority.dropped_item_nodes.values():
			var pickup := pickup_value as PickupItem
			if pickup == null or pickup.item_data.get("ingredient_id", "") == "":
				continue
			if pickup.item_data.get("ingredient_id", "") == "plant_fiber":
				spawned_fiber_count += 1
				_check(is_equal_approx(float(pickup.item_data.get("weight_kg", 0.0)), 1.0), "tree fiber drop weighs 1 kg")
				_check(pickup.model_path == asset_paths["plant fiber bundle"], "tree fiber drop uses PlantFiberBundle.glb")
			if pickup.item_data.get("ingredient_id", "") == "plant_fiber_cloth":
				saw_cloth_drop = true
		_check(
			spawned_fiber_count >= HarvestTree.PLANT_FIBER_DROP_MIN_COUNT
				and spawned_fiber_count <= HarvestTree.PLANT_FIBER_DROP_MAX_COUNT
				and GameAuthority.dropped_item_nodes.size() >= drops_before_tree + spawned_fiber_count,
			"tree harvest spawns 2-5 separate plant fiber items"
		)
		_check(not saw_cloth_drop, "tree harvest does not drop plant fiber cloth")

	bear.queue_free()
	GameAuthority.stop_authority()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[IndustrialMaterialAssetsValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[IndustrialMaterialAssetsValidation] " + failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
