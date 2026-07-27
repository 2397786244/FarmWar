extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var paths := [
		"res://items/CargoCrateSmall.tscn",
		"res://items/CargoCrateMedium.tscn",
		"res://items/CragoCrateLarge.tscn",
	]
	var expected_sizes := ["small", "medium", "large"]
	var expected_capacities := [10.0, 20.0, 40.0]
	var expected_tares := [1.0, 2.0, 4.0]
	var crates: Array[CargoCrateGround] = []
	for index in range(paths.size()):
		var packed := load(paths[index]) as PackedScene
		_check(packed != null, "crate scene loads: %s" % paths[index])
		var crate := packed.instantiate() as CargoCrateGround if packed != null else null
		_check(crate != null, "crate scene has CargoCrateGround root: %s" % paths[index])
		if crate == null:
			continue
		root.add_child(crate)
		crates.append(crate)
		await process_frame
		var data := crate.get_crate_data()
		_check(str(data.get("crate_size", "")) == expected_sizes[index], "crate size configured")
		_check(is_equal_approx(float(data.get("capacity_kg", 0.0)), expected_capacities[index]), "crate capacity configured")
		_check(is_equal_approx(float(data.get("total_weight_kg", 0.0)), expected_tares[index]), "empty crate keeps tare weight")
		_check(crate.collision_layer == 128, "crate body uses tool collision layer")
		_check(crate.hit_area.collision_mask == 32, "crate Hit3D listens for bullets")
		_check(crate.scale.is_equal_approx(Vector3.ONE * 5.0), "ground crate uses five-times world scale")
		_check(crate.get_interaction_hint(null) == "按E打开货运箱子    长按E捡起", "ground crate exposes both interaction hints")
		_check(str(data.get("item_id", "")) == "cargo_crate_" + expected_sizes[index], "crate has a registered item id")

	var held_packed := load(paths[0]) as PackedScene
	var held_preview := held_packed.instantiate() as CargoCrateGround if held_packed != null else null
	if held_preview != null:
		held_preview.set_meta("held_preview", true)
		root.add_child(held_preview)
		await process_frame
		_check(held_preview.scale.is_equal_approx(Vector3.ONE), "held crate preview does not use ground scale")

	var player_packed := load("res://character/player.tscn") as PackedScene
	var player_preview := player_packed.instantiate() if player_packed != null else null
	_check(player_preview != null, "player scene loads for crate interaction validation")
	if player_preview != null:
		var interact_detect := player_preview.get_node_or_null("Head/InteractDetect") as ShapeCast3D
		_check(interact_detect != null and (interact_detect.collision_mask & 128) != 0,
			"player interaction detector includes the crate tool layer")
		player_preview.free()

	if not crates.is_empty():
		var small := crates[0]
		var tomatoes := {"kind": "ingredient", "ingredient_id": "tomato", "display_name": "西红柿", "weight_kg": 6.0}
		_check(small.set_stored_item(tomatoes), "small crate accepts content under ten kilograms")
		_check(not small.set_stored_item({"kind": "tool", "tool_id": "nail_gun"}), "one-slot crate rejects a second item")
		_check(is_equal_approx(float(small.get_crate_data().get("total_weight_kg", 0.0)), 7.0), "crate total equals tare plus content")
		var ingredient_delivery := CargoCrateData.get_delivery_content(small.get_crate_data())
		_check(str(ingredient_delivery.get("content_id", "")) == "tomato", "CargoArea can read the stored ingredient id")
		_check(str(ingredient_delivery.get("unit", "")) == "kg" \
			and is_equal_approx(float(ingredient_delivery.get("quantity", 0.0)), 6.0),
			"CargoArea reads actual ingredient kilograms from a partially filled crate")
		var before_hp := small.current_hp
		_check(small.impact("test", 100.0, "red"), "neutral crate accepts damage")
		_check(is_equal_approx(small.current_hp, before_hp - 100.0), "crate damage reduces HP")

		var material_crate := CargoCrateData.create_empty("medium", "material_delivery")
		material_crate["stored_item"] = {
			"kind": "material", "material_id": "iron_ore", "display_name": "铁矿石",
			"count": 8, "weight_kg": 12.0,
		}
		material_crate = CargoCrateData.refresh_totals(material_crate)
		var material_delivery := CargoCrateData.get_delivery_content(material_crate)
		_check(str(material_delivery.get("content_id", "")) == "iron_ore" \
			and int(material_delivery.get("quantity", 0)) == 8 \
			and str(material_delivery.get("unit", "")) == "count",
			"CargoArea can read material identity and item count")
		material_crate = CargoCrateData.consume_delivery_quantity(material_crate, 3.0)
		_check(int(material_crate.get("content_quantity", 0)) == 5, "partial material delivery keeps the remaining count")
		_check(is_equal_approx(float(material_crate.get("content_weight_kg", 0.0)), 7.5),
			"partial material delivery reduces physical weight proportionally")

		var mined_ore_crate := CargoCrateData.create_empty("medium", "mined_ore_delivery")
		mined_ore_crate["stored_item"] = {
			"kind": "ingredient", "ingredient_id": "iron", "display_name": "铁矿",
			"weight_kg": 8.0,
		}
		mined_ore_crate = CargoCrateData.refresh_totals(mined_ore_crate)
		var mined_ore_delivery := CargoCrateData.get_delivery_content(mined_ore_crate)
		_check(str(mined_ore_delivery.get("content_id", "")) == "iron" \
			and str(mined_ore_delivery.get("unit", "")) == "count" \
			and int(mined_ore_delivery.get("quantity", 0)) == 8,
			"mined ore stored in the backpack ingredient format is exposed as item count")
		mined_ore_crate = CargoCrateData.consume_delivery_quantity(mined_ore_crate, 3.0)
		_check(is_equal_approx(float(mined_ore_crate.get("content_weight_kg", 0.0)), 5.0),
			"ore count settlement updates its remaining physical kilograms")

	var vehicle_packed := load("res://vehicles/red_cargo_car.tscn") as PackedScene
	var vehicle: Node = vehicle_packed.instantiate() if vehicle_packed != null else null
	_check(vehicle != null, "CargoCar scene loads")
	if vehicle != null:
		root.add_child(vehicle)
		await process_frame
		_check(is_zero_approx(vehicle.get_cargo_weight_kg()), "CargoCar starts with zero actual cargo weight")
		var empty_crate := CargoCrateData.create_empty("medium", "vehicle_empty_crate")
		_check(vehicle.try_load_cargo_crate(empty_crate, 0) == 0, "CargoCar accepts an empty reusable crate")
		_check(is_equal_approx(vehicle.get_cargo_weight_kg(), 2.0), "CargoCar reads empty crate tare weight")

	var authority: Node = get_root().get_node("GameAuthority")
	authority.register_or_update_player(9901, {
		"display_name": "CrateGetValidation", "team": "red",
		"primary_weapon_ids": [], "special_tool_ids": [],
	})
	var first_get: Dictionary = authority.server_team_chat(9901, "[get] cargo_crate_small")
	var second_get: Dictionary = authority.server_team_chat(9901, "[get] cargo_crate_small")
	_check(bool(first_get.get("ok", false)) and bool(second_get.get("ok", false)), "[get] grants registered cargo crate items")
	var granted_crates: Array = (authority.player_states[9901] as Dictionary).get("personal_cargo_crates", [])
	_check(granted_crates.size() == 2, "repeated [get] grants occupy two cargo crate entries")
	if granted_crates.size() == 2:
		_check(str((granted_crates[0] as Dictionary).get("crate_instance_id", "")) \
			!= str((granted_crates[1] as Dictionary).get("crate_instance_id", "")),
			"repeated [get] grants keep unique non-stackable crate instances")

	root.queue_free()
	if failures.is_empty():
		print("[CargoCrateValidation] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[CargoCrateValidation] " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
