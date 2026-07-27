extends Node3D
class_name FarmTile

const NEUTRAL_COLOR := Color(0.0, 0.0, 0.0, 0.0)
const RED_OWNER_COLOR := Color(0.94, 0.18, 0.18, 1.0)
const BLUE_OWNER_COLOR := Color(0.16, 0.38, 1.0, 1.0)

## Shared placement templates. Add a new count here before assigning it below.
const CROP_POSITION_PATTERNS := {
	1: [Vector3(0.0, 0.1, 0.0)],
	2: [
		Vector3(0.4, 0.1, 0.4),
		Vector3(-0.4, 0.1, -0.4),
	],
	4: [
		Vector3(0.4, 0.1, 0.4),
		Vector3(-0.4, 0.1, 0.4),
		Vector3(0.4, 0.1, -0.4),
		Vector3(-0.4, 0.1, -0.4),
	],
}

static func get_crop_layout(seed_name: String) -> Dictionary:
	var layout := IngredientCatalog.get_crop_layout(seed_name)
	if layout.is_empty():
		return {}
	var count := int(layout.get("count", 1))
	var positions: Variant = CROP_POSITION_PATTERNS.get(count, CROP_POSITION_PATTERNS[1])
	layout["positions"] = (positions as Array).duplicate(true)
	return layout


static func is_reharvestable_crop(seed_name: String) -> bool:
	return IngredientCatalog.is_reharvestable(seed_name)


static func get_harvest_drop_scene_path(seed_name: String) -> String:
	return IngredientCatalog.get_harvest_drop_scene_path(seed_name)

@export var land_owner := ""
@export var max_hp := 100.0

var current_hp := 0.0
var grid_coordinate := Vector2i.ZERO
var field_id := ""
var tile_spacing := 2.2
var growth_value := 0
var plant_children: Array[Node3D] = []
var crop_positions: Array[Vector3] = []
var tool_child: Node3D
var tool_record := ""
var seed_record := ""
var can_harvest := false
var plant_mode := "Plant"
var last_effect := ""
var burn_remaining := 0.0
var burn_dps := 0.0
var farm_revision := 0
var last_received_farm_revision := 0
var owner_color := NEUTRAL_COLOR
var owner_color_tween: Tween
var field_visual_generator: Node
var field_visual_index := -1
var fallback_owner_material: ShaderMaterial
var plant_protector:Array[PlantProtector] = []
var bug_effects:bool = false  # 
var fertilizer_multiplier := 1.0
var fertilizer_blocked := false

func _ready() -> void:
	add_to_group("farm_tiles")
	Farmlandmanager.register_land(self)
	_update_owner_visual(false)


func prepare_for_batched_visual(generator: Node, instance_index: int) -> void:
	field_visual_generator = generator
	field_visual_index = instance_index
	for visual_name in ["OwnerTint"]:
		var visual := get_node_or_null(visual_name)
		if visual == null:
			continue
		remove_child(visual)
		visual.free()


func _exit_tree() -> void:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null:
		manager.unregister_land(self)


func step() -> void:
	var hp_before := current_hp
	var crop_before := seed_record
	var burn_before := burn_remaining
	var bug_before := bug_effects
	var growth_before := growth_value
	var harvest_before := can_harvest
	_tick_burn(1.0)
	if bug_effects:
		_tick_bug()
		if current_hp != hp_before or seed_record != crop_before or burn_remaining != burn_before or bug_effects != bug_before:
			_publish_farm_tile_delta("bug")
		return
	if current_hp != hp_before or seed_record != crop_before or burn_remaining != burn_before or bug_effects != bug_before:
		_publish_farm_tile_delta("flame")
		
	if seed_record.is_empty() or can_harvest:
		return
	# freeze 不暂停作物生长。
	var base_growth := randi_range(1, 3)
	growth_value = mini(100, growth_value + roundi(float(base_growth) * fertilizer_multiplier))
	if growth_value >= 100:
		can_harvest = true
		$Label3D.text = "可收获"
	else:
		$Label3D.text = "%d%%" % growth_value
	if growth_value != growth_before or can_harvest != harvest_before:
		_publish_farm_tile_delta("growth")


func claim_land(new_owner: String) -> bool:
	if new_owner.is_empty():
		return false
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action({
			"type": "claim_land",
			"tile_path": str(get_path()),
			"tile_position": global_position,
			"team": new_owner,
		})
		return false
	var owner_changed := land_owner != new_owner
	var changed := Farmlandmanager.change_land_owner(self, new_owner)
	if changed and owner_changed:
		_publish_farm_tile_delta("owner")
	return changed


func _on_land_owner_changed(_old_owner: String, _new_owner: String) -> void:
	_update_owner_visual(true)


func impact(
	effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if GameAuthority.should_send_network_requests():
		return false
	if strength <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == land_owner:
		return false
	if plant_mode == "Tool":
		if not is_instance_valid(tool_child):
			tool_child = null
			plant_mode = "Plant"
			return false
		if tool_child.has_method("impact"):
			return bool(tool_child.call(
				"impact",
				effect,
				strength,
				attacker_team
			))
		return false

	if seed_record.is_empty() or plant_children.is_empty():
		return true

	last_effect = effect.to_lower()

	if last_effect in ["flame","freeze","lightening","bug"]:  # 如果
		if get_tile_property("immune"):  # 如果被保护，免疫，那么下面的不会执行
			return true	
			
	_apply_crop_damage(strength)	
			
	match last_effect:
		"flame":
			burn_remaining = 3.0
			burn_dps = maxf(burn_dps, strength * 0.1)
		"freeze":
			# 作物只承受直接伤害，不暂停生长。
			pass
		"lightening":
			# 植物的HP为100，刚好等于雷击的伤害，所以通常不会到这里
			pass
		"bug":
			# 停止生长，并且持续扣血
			bug_effects = true  # 停止生长并且bugeffects的时候就会持续扣血，直到虫灾消失并且受到虫灾影响的作物被摧毁重新种植之后
			apply_authoritative_fertilizer(1.0, true)
	_publish_farm_tile_delta(last_effect)
	return true


func harvest(absorb_source: Vector3, absorption_context: Dictionary = {}) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action({
			"type": "harvest",
			"tile_path": str(get_path()),
			"tile_position": global_position,
			"absorb_source": absorb_source,
		})
		return false
	if seed_record.is_empty() or not can_harvest or plant_children.is_empty():
		return false

	var harvested_seed := seed_record
	if not _spawn_harvest_visual(harvested_seed, absorb_source):
		return false

	var harvested_weight_kg := _get_harvest_weight_kg(harvested_seed, plant_children.size())
	_store_harvest_result(harvested_seed, harvested_weight_kg, absorption_context)
	if GameAuthority.is_server_authority():
		GameAuthority.emit_crop_absorption_visual(
			harvested_seed,
			global_position,
			absorb_source,
			absorption_context
		)
	if is_reharvestable_crop(harvested_seed):
		_reset_crop_for_regrowth()
	else:
		_clear_crop()
	_publish_farm_tile_delta("harvest")
	return true


func harvest_one(
	absorb_source: Vector3,
	crop_index: int,
	absorption_context: Dictionary = {}
) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action({
			"type": "harvest_one",
			"tile_path": str(get_path()),
			"tile_position": global_position,
			"crop_index": crop_index,
			"absorb_source": absorb_source,
		})
		return false
	var crop := get_harvestable_crop(crop_index)
	if crop == null:
		return false
	var harvested_seed := seed_record
	var harvested_position := crop.position
	if not _spawn_harvest_visual(harvested_seed, absorb_source, [harvested_position]):
		return false

	# 每一株可交互的成熟作物默认产出 1 kg，可由食材定义覆盖。
	_store_harvest_result(
		harvested_seed,
		_get_harvest_weight_kg(harvested_seed, 1),
		absorption_context
	)
	if GameAuthority.is_server_authority():
		var visual_context := absorption_context.duplicate(true)
		visual_context["crop_positions"] = [harvested_position]
		GameAuthority.emit_crop_absorption_visual(
			harvested_seed,
			global_position,
			absorb_source,
			visual_context
		)
	if is_reharvestable_crop(harvested_seed):
		_reset_crop_for_regrowth()
	else:
		_remove_crop_at(crop_index)
		if plant_children.is_empty():
			_clear_crop()
	_publish_farm_tile_delta("harvest_one")
	return true


func _get_harvest_weight_kg(seed_name: String, crop_count: int) -> float:
	var layout := get_crop_layout(seed_name)
	var kg_per_instance := maxf(0.01, float(layout.get("harvest_kg_per_instance", 1.0)))
	return float(maxi(0, crop_count)) * kg_per_instance


func _store_harvest_result(
	harvested_seed: String,
	harvested_weight_kg: float,
	absorption_context: Dictionary
) -> void:
	if str(absorption_context.get("absorption_type", "")) == "farm_runner_crop":
		GlobalVar.add_item(land_owner, harvested_seed, harvested_weight_kg)
		return
	var harvester_peer_id := int(absorption_context.get("owner_peer_id", 0))
	if harvester_peer_id > 0 and is_instance_valid(GameAuthority) \
			and GameAuthority.has_method("grant_crop_harvest"):
		GameAuthority.grant_crop_harvest(
			harvester_peer_id,
			harvested_seed,
			harvested_weight_kg,
			land_owner,
			global_position
		)
		return
	GameAuthority.spawn_nature_resource_drops(global_position, [{
		"kind": "ingredient", "ingredient_id": harvested_seed,
		"item_id": harvested_seed, "count": 1, "weight_kg": harvested_weight_kg,
	}])


func get_harvestable_crop(crop_index: int) -> Node3D:
	if seed_record.is_empty() or not can_harvest:
		return null
	if crop_index < 0 or crop_index >= plant_children.size():
		return null
	var crop := plant_children[crop_index]
	return crop if is_instance_valid(crop) else null


func get_harvestable_crop_index_at_position(world_position: Vector3, max_distance := 1.25) -> int:
	var best_index := -1
	var best_distance_squared := max_distance * max_distance
	for crop_index in range(plant_children.size()):
		var crop := get_harvestable_crop(crop_index)
		if crop == null:
			continue
		var distance_squared := crop.global_position.distance_squared_to(world_position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_index = crop_index
	return best_index


func _spawn_harvest_visual(
	harvested_seed: String,
	absorb_source: Vector3,
	harvested_positions: Array = []
) -> bool:
	var world_parent: Node = GlobalVar.gameworld
	if world_parent == null:
		world_parent = get_tree().current_scene
	if world_parent == null:
		return true
	var harvest_scene := load("res://items/HarvestScene.tscn").instantiate() as Node3D
	if harvest_scene == null:
		return false
	world_parent.add_child(harvest_scene)
	harvest_scene.global_position = global_position
	harvest_scene.set_appearance(harvested_seed, harvested_positions)
	harvest_scene.absorb(absorb_source)
	return true


func _remove_crop_at(crop_index: int) -> void:
	if crop_index < 0 or crop_index >= plant_children.size():
		return
	var crop := plant_children[crop_index]
	if is_instance_valid(crop):
		crop.queue_free()
	plant_children.remove_at(crop_index)
	if crop_index < crop_positions.size():
		crop_positions.remove_at(crop_index)

## setting_player是放置者的节点，可以是AIPlayer也可以是GamePlayer
func setting_tool(tool_name: String, tool_owner: String, setting_player: CharacterBody3D = null, placement_yaw := 0.0) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action({
			"type": "place_tool",
			"tile_path": str(get_path()),
			"tile_position": global_position,
			"tool_name": tool_name,
			"team": tool_owner,
			"yaw": placement_yaw,
		})
		return false
	if tool_owner.is_empty():
		return false
	if is_instance_valid(tool_child):
		return false
	if not seed_record.is_empty():
		return false

	if land_owner == "" or land_owner != tool_owner:
		claim_land(tool_owner)
	var packed_scene := load(
		"res://character/weapons/%s.tscn" % tool_name
	) as PackedScene
	if packed_scene == null:
		return false
	
	var scene := packed_scene.instantiate() as Node3D
	if scene == null:
		return false
	add_child(scene)
	scene.position = Vector3(0.0, 0.1, 0.0)
	scene.set("tool_owner", land_owner)
	# 再获取放置者的节点
	if is_instance_valid(setting_player):
		placement_yaw = setting_player.rotation.y
	scene.rotation.y = placement_yaw
	tool_child = scene
	tool_record = tool_name
	plant_mode = "Tool"
	farm_revision += 1
	_create_farm_runner_home_if_needed(tool_name)
	if scene.has_method("activate_tool"):
		scene.call("activate_tool")
	_notify_manager_state_changed()
	return true


func apply_authoritative_tool(tool_name: String, tool_owner: String, placement_yaw := 0.0) -> bool:
	if tool_name.is_empty() or tool_owner.is_empty():
		return false
	if is_instance_valid(tool_child):
		return true
	if not seed_record.is_empty():
		_clear_crop()
	land_owner = tool_owner
	_update_owner_visual(true)
	var packed_scene := load("res://character/weapons/%s.tscn" % tool_name) as PackedScene
	if packed_scene == null:
		return false
	var scene := packed_scene.instantiate() as Node3D
	if scene == null:
		return false
	add_child(scene)
	scene.position = Vector3(0.0, 0.1, 0.0)
	scene.rotation.y = placement_yaw
	scene.set("tool_owner", land_owner)
	_disable_network_visual_runtime(scene)
	if scene is FarmRunner:
		(scene as FarmRunner).enable_network_visuals()
	tool_child = scene
	tool_record = tool_name
	plant_mode = "Tool"
	_create_farm_runner_home_if_needed(tool_name)
	_notify_manager_state_changed()
	return true


func _create_farm_runner_home_if_needed(tool_name: String) -> void:
	if tool_name != "FarmRunner":
		return
	if get_node_or_null("RunnerHome") != null:
		return
	var packed := load("res://character/weapons/RunnerHome.tscn") as PackedScene
	if packed == null:
		return
	var home := packed.instantiate() as Node3D
	if home == null:
		return
	home.name = "RunnerHome"
	add_child(home)
	home.global_position = global_position + Vector3(0.0, 0.1, 0.0)


func plant(seed_name: String, tool_owner: String) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action({
			"type": "plant",
			"tile_path": str(get_path()),
			"tile_position": global_position,
			"seed_name": seed_name,
			"team": tool_owner,
		})
		return false
	if tool_owner.is_empty() or not seed_record.is_empty():
		return false
	if is_instance_valid(tool_child) or not IngredientCatalog.is_plantable(seed_name):
		return false

	var crop_config := get_crop_layout(seed_name)
	var packed_scene := load(str(crop_config["scene"])) as PackedScene
	if packed_scene == null:
		return false
	
	bug_effects = false
	apply_authoritative_fertilizer(1.0, false)
	farm_revision += 1
	plant_mode = "Plant"
	growth_value = 0
	can_harvest = false
	seed_record = seed_name
	current_hp = max_hp
	burn_remaining = 0.0
	burn_dps = 0.0
	last_effect = ""
	$Label3D.text = "0%"
	$Label3D.visible = true

	crop_positions.clear()
	for crop_position: Vector3 in crop_config["positions"]:
		var crop := packed_scene.instantiate() as Node3D
		if crop == null:
			continue
		add_child(crop)
		crop.position = crop_position
		plant_children.append(crop)
		crop_positions.append(crop_position)

	if plant_children.is_empty():
		_clear_crop()
		return false
	claim_land(tool_owner)
	_notify_manager_state_changed()
	return true


func apply_authoritative_plant(
	seed_name: String,
	tool_owner: String,
	growth := 0,
	ready := false,
	authoritative_positions: Array = []
) -> bool:
	if seed_name.is_empty() or tool_owner.is_empty() or not IngredientCatalog.is_plantable(seed_name):
		return false
	if is_instance_valid(tool_child):
		tool_child.queue_free()
		tool_child = null
		tool_record = ""
	_clear_crop()
	land_owner = tool_owner
	_update_owner_visual(true)
	var crop_config := get_crop_layout(seed_name)
	var packed_scene := load(str(crop_config["scene"])) as PackedScene
	if packed_scene == null:
		return false
	plant_mode = "Plant"
	growth_value = clampi(growth, 0, 100)
	can_harvest = ready or growth_value >= 100
	seed_record = seed_name
	current_hp = max_hp
	bug_effects = false
	apply_authoritative_fertilizer(1.0, false)
	$Label3D.text = "可收获" if can_harvest else "%d%%" % growth_value
	$Label3D.visible = true
	var positions: Array = crop_config["positions"]
	if not authoritative_positions.is_empty():
		positions = authoritative_positions
	crop_positions.clear()
	for crop_position_value: Variant in positions:
		if not crop_position_value is Vector3:
			continue
		var crop_position := crop_position_value as Vector3
		var crop := packed_scene.instantiate() as Node3D
		if crop == null:
			continue
		add_child(crop)
		crop.position = crop_position
		plant_children.append(crop)
		crop_positions.append(crop_position)
	var planted := not plant_children.is_empty()
	_notify_manager_state_changed()
	return planted


func apply_authoritative_harvest() -> void:
	if is_reharvestable_crop(seed_record):
		_reset_crop_for_regrowth()
	else:
		_clear_crop()


func apply_authoritative_harvest_one(crop_index: int) -> void:
	if is_reharvestable_crop(seed_record):
		_reset_crop_for_regrowth()
		return
	_remove_crop_at(crop_index)
	if plant_children.is_empty():
		_clear_crop()


func apply_authoritative_tool_destroyed() -> void:
	if is_instance_valid(tool_child):
		tool_child.queue_free()
	tool_child = null
	tool_record = ""
	plant_mode = "Plant"
	var runner_home := get_node_or_null("RunnerHome")
	if is_instance_valid(runner_home):
		runner_home.queue_free()
	if seed_record.is_empty():
		$Label3D.visible = false
	_notify_manager_state_changed()


func apply_authoritative_owner(new_owner: String) -> void:
	land_owner = new_owner
	_update_owner_visual(true)


func get_authoritative_state() -> Dictionary:
	return {
		"tile_path": str(get_path()),
		"tile_position": global_position,
		"land_owner": land_owner,
		"plant_mode": plant_mode,
		"seed_record": seed_record,
		"growth_value": growth_value,
		"can_harvest": can_harvest,
		"crop_positions": crop_positions.duplicate(true),
		"tool_record": tool_record,
		"tool_yaw": tool_child.rotation.y if is_instance_valid(tool_child) else 0.0,
		"has_tool": is_instance_valid(tool_child),
		"current_hp": current_hp,
		"burn_remaining": burn_remaining,
		"burn_dps": burn_dps,
		"bug_effects": bug_effects,
		"fertilizer_multiplier": fertilizer_multiplier,
		"fertilizer_blocked": fertilizer_blocked,
		"immune": _is_immune(),
		"last_effect": last_effect,
		"farm_revision": farm_revision,
	}


func apply_authoritative_state(state: Dictionary) -> void:
	var incoming_revision := int(state.get("farm_revision", 0))
	if incoming_revision < last_received_farm_revision:
		return
	var next_owner := str(state.get("land_owner", land_owner))
	if next_owner != land_owner:
		apply_authoritative_owner(next_owner)
	var next_mode := str(state.get("plant_mode", "Plant"))
	var next_seed := str(state.get("seed_record", ""))
	var next_tool := str(state.get("tool_record", ""))
	var next_tool_yaw := float(state.get("tool_yaw", 0.0))
	if next_mode == "Tool" and bool(state.get("has_tool", false)) and not next_tool.is_empty():
		if tool_record != next_tool or not is_instance_valid(tool_child):
			_clear_crop()
			if is_instance_valid(tool_child):
				tool_child.queue_free()
				tool_child = null
			apply_authoritative_tool(next_tool, next_owner, next_tool_yaw)
		elif is_instance_valid(tool_child):
			tool_child.rotation.y = next_tool_yaw
	elif not next_seed.is_empty():
		var next_growth := int(state.get("growth_value", growth_value))
		var next_ready := bool(state.get("can_harvest", can_harvest))
		var next_positions: Variant = state.get("crop_positions", null)
		var positions_changed := next_positions is Array and not _crop_positions_match(next_positions as Array)
		if seed_record != next_seed or plant_mode != "Plant" or positions_changed:
			if is_instance_valid(tool_child):
				tool_child.queue_free()
				tool_child = null
				tool_record = ""
			apply_authoritative_plant(
				next_seed,
				next_owner,
				next_growth,
				next_ready,
				next_positions as Array if next_positions is Array else []
			)
		else:
			growth_value = clampi(next_growth, 0, 100)
			can_harvest = next_ready
			$Label3D.text = "可收获" if can_harvest else "%d%%" % growth_value
			$Label3D.visible = true
	else:
		_clear_crop()
		if is_instance_valid(tool_child):
			tool_child.queue_free()
		tool_child = null
		tool_record = ""
		plant_mode = "Plant"
	current_hp = float(state.get("current_hp", current_hp))
	burn_remaining = maxf(0.0, float(state.get("burn_remaining", burn_remaining)))
	burn_dps = maxf(0.0, float(state.get("burn_dps", burn_dps)))
	bug_effects = bool(state.get("bug_effects", bug_effects))
	apply_authoritative_fertilizer(
		float(state.get("fertilizer_multiplier", fertilizer_multiplier)),
		bool(state.get("fertilizer_blocked", fertilizer_blocked))
	)
	apply_authoritative_protection(state.get("immune", _is_immune()) == true)
	last_effect = str(state.get("last_effect", last_effect))
	if incoming_revision > 0:
		last_received_farm_revision = maxi(last_received_farm_revision, incoming_revision)
		farm_revision = maxi(farm_revision, incoming_revision)


func apply_authoritative_delta(delta: Dictionary) -> void:
	var incoming_revision := int(delta.get("revision", 0))
	if incoming_revision > 0 and incoming_revision <= last_received_farm_revision:
		return
	var next_owner := str(delta.get("land_owner", land_owner))
	if next_owner != land_owner:
		apply_authoritative_owner(next_owner)
	var next_seed := str(delta.get("seed_record", seed_record))
	if bool(delta.get("crop_removed", false)) or next_seed.is_empty():
		_clear_crop()
	else:
		var next_growth := clampi(int(delta.get("growth_value", growth_value)), 0, 100)
		var next_ready := bool(delta.get("can_harvest", can_harvest))
		var next_positions: Variant = delta.get("crop_positions", null)
		var positions_changed := next_positions is Array and not _crop_positions_match(next_positions as Array)
		if next_seed != seed_record or plant_children.is_empty() or positions_changed:
			apply_authoritative_plant(
				next_seed,
				land_owner,
				next_growth,
				next_ready,
				next_positions as Array if next_positions is Array else []
			)
		else:
			growth_value = next_growth
			can_harvest = next_ready
			$Label3D.text = "可收获" if can_harvest else "%d%%" % growth_value
			$Label3D.visible = true
		current_hp = maxf(0.0, float(delta.get("current_hp", current_hp)))
		burn_remaining = maxf(0.0, float(delta.get("burn_remaining", burn_remaining)))
		burn_dps = maxf(0.0, float(delta.get("burn_dps", burn_dps)))
		bug_effects = bool(delta.get("bug_effects", bug_effects))
		apply_authoritative_fertilizer(
			float(delta.get("fertilizer_multiplier", fertilizer_multiplier)),
			bool(delta.get("fertilizer_blocked", fertilizer_blocked))
		)
		last_effect = str(delta.get("effect", last_effect))
	apply_authoritative_protection(delta.get("immune", _is_immune()) == true)
	if incoming_revision > 0:
		last_received_farm_revision = incoming_revision
		farm_revision = maxi(farm_revision, incoming_revision)


func get_farm_tile_delta(effect: String) -> Dictionary:
	var delta := {
		"field_id": field_id,
		"grid_coordinate": grid_coordinate,
		"tile_position": global_position,
		"revision": farm_revision,
		"land_owner": land_owner,
		"seed_record": seed_record,
		"growth_value": growth_value,
		"can_harvest": can_harvest,
		"crop_positions": crop_positions.duplicate(true),
		"current_hp": current_hp,
		"crop_removed": seed_record.is_empty(),
		"burn_remaining": burn_remaining,
		"burn_dps": burn_dps,
		"bug_effects": bug_effects,
		"fertilizer_multiplier": fertilizer_multiplier,
		"fertilizer_blocked": fertilizer_blocked,
		"immune": _is_immune(),
		"effect": effect,
	}
	# Generated fields have a stable field/grid identity on every peer. Keep the
	# path fallback only for legacy hand-authored tiles without that identity.
	# Position is always included because field_id currently derives from each
	# peer's scene-tree path, which differs between client and dedicated server.
	if field_id.is_empty():
		delta["tile_path"] = str(get_path())
	return delta


func _publish_farm_tile_delta(effect: String) -> void:
	if not GameAuthority.is_server_authority():
		return
	farm_revision += 1
	GameAuthority.report_farm_tile_delta(self, get_farm_tile_delta(effect))


func _disable_network_visual_runtime(root: Node) -> void:
	root.set_process(false)
	root.set_physics_process(false)
	root.set_process_input(false)
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	for child in root.get_children():
		if child is Node:
			_disable_network_visual_runtime(child)


func is_empty() -> bool:
	return seed_record.is_empty() and not is_instance_valid(tool_child)


func needs_simulation_tick() -> bool:
	return not seed_record.is_empty() and (not can_harvest or burn_remaining > 0.0 or bug_effects)


func _notify_manager_state_changed() -> void:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null and manager.has_method("refresh_land_state"):
		manager.call("refresh_land_state", self)


func apply_fertilizer(tool_owner: String, multiplier: float) -> bool:
	if tool_owner.is_empty() or tool_owner != land_owner:
		return false
	if seed_record.is_empty() or can_harvest or bug_effects or fertilizer_blocked or fertilizer_multiplier > 1.0:
		return false
	fertilizer_multiplier = maxf(1.0, multiplier)
	_publish_farm_tile_delta("fertilizer")
	return true


func apply_authoritative_fertilizer(multiplier: float, blocked: bool) -> void:
	fertilizer_blocked = blocked
	fertilizer_multiplier = 1.0 if fertilizer_blocked else maxf(1.0, multiplier)


func _apply_crop_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - amount)
	if current_hp <= 0.0:
		_clear_crop()


func _tick_bug():
	if bug_effects==false:
		return
	_apply_crop_damage(10)  # 设置了虫灾每次的固定伤害值
			
func _tick_burn(delta: float) -> void:
	if burn_remaining <= 0.0 or seed_record.is_empty():
		return
	var tick_time := minf(delta, burn_remaining)
	burn_remaining = maxf(0.0, burn_remaining - delta)
	_apply_crop_damage(burn_dps * tick_time)
	if burn_remaining <= 0.0:
		burn_dps = 0.0


func _clear_crop() -> void:
	for crop in plant_children:
		if is_instance_valid(crop):
			crop.queue_free()
	plant_children.clear()
	crop_positions.clear()
	growth_value = 0
	current_hp = 0.0
	seed_record = ""
	can_harvest = false
	burn_remaining = 0.0
	burn_dps = 0.0
	bug_effects = false
	apply_authoritative_fertilizer(1.0, false)
	plant_mode = "Plant"
	$Label3D.visible = false
	$Label3D.text = "0%"
	_notify_manager_state_changed()


func _reset_crop_for_regrowth() -> void:
	growth_value = 0
	can_harvest = false
	current_hp = max_hp
	burn_remaining = 0.0
	burn_dps = 0.0
	bug_effects = false
	last_effect = ""
	apply_authoritative_fertilizer(1.0, false)
	plant_mode = "Plant"
	$Label3D.visible = true
	$Label3D.text = "0%"
	_notify_manager_state_changed()


func _crop_positions_match(other_positions: Array) -> bool:
	if crop_positions.size() != other_positions.size():
		return false
	for index in range(crop_positions.size()):
		var other_position: Variant = other_positions[index]
		if not other_position is Vector3:
			return false
		if crop_positions[index].distance_squared_to(other_position as Vector3) > 0.0001:
			return false
	return true


func _update_owner_visual(animate: bool) -> void:
	var target_color := _owner_color_for_team(land_owner)
	if is_instance_valid(owner_color_tween):
		owner_color_tween.kill()
	if is_instance_valid(field_visual_generator):
		_set_owner_color(target_color)
		return
	if not animate or not is_inside_tree():
		_set_owner_color(target_color)
		return
	owner_color_tween = create_tween()
	owner_color_tween.tween_method(
		_set_owner_color,
		owner_color,
		target_color,
		0.2
	)


func _set_owner_color(color: Color) -> void:
	owner_color = color
	if is_instance_valid(field_visual_generator) and field_visual_generator.has_method("set_tile_owner_color"):
		field_visual_generator.call("set_tile_owner_color", field_visual_index, owner_color)
		return
	var owner_tint := get_node_or_null("OwnerTint") as MeshInstance3D
	if owner_tint == null:
		return
	if fallback_owner_material == null:
		fallback_owner_material = owner_tint.get_active_material(0).duplicate() as ShaderMaterial
		owner_tint.material_override = fallback_owner_material
	fallback_owner_material.set_shader_parameter("owner_color", owner_color)


func _owner_color_for_team(team: String) -> Color:
	match team:
		"red":
			return RED_OWNER_COLOR
		"blue":
			return BLUE_OWNER_COLOR
		_:
			return NEUTRAL_COLOR

var tile_property:Dictionary = {}
func set_tile_property(property_name:String,value:Variant):
	tile_property.set(property_name,value)

func get_tile_property(property_name:String):
	return tile_property.get(property_name)


func _is_immune() -> bool:
	return get_tile_property("immune") == true

func set_tile_protector(node:PlantProtector):
	if plant_protector.has(node):
		return
	else:
		plant_protector.append(node)	
		apply_authoritative_protection(true)
		_publish_farm_tile_delta("protection")

func remove_tile_protector(node:PlantProtector):
	if not plant_protector.has(node):
		return
	plant_protector.erase(node)
	# 擦出这个Protector之后，看看还有没有，如果没有的话，就会设置immune为false
	if plant_protector.is_empty():
		apply_authoritative_protection(false)
		_publish_farm_tile_delta("protection")


func apply_authoritative_protection(is_immune: bool) -> void:
	set_tile_property("immune", is_immune)
	if is_immune:
		_set_owner_color(Color.YELLOW)
	else:
		_update_owner_visual(true)


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is RubberBullet or body is ColorBullet or body is NailBullet or \
	body is DetectLaserBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == land_owner:
		return

	var effect = "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()


func handle_chunk_hit_body(body: Node3D) -> void:
	_on_hit_3d_body_entered(body)
