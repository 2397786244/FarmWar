extends KitchenAppliance
class_name LivestockChop

const STATE_SYNC_INTERVAL := 1.0
const LIVESTOCK_SCENES := {
	"chicken": preload("res://items/Chicken.tscn"),
	"pig": preload("res://items/Pig.tscn"),
	"angus_cow": preload("res://items/AngusCow.tscn"),
}

@export_enum("livestock", "chicken") var chop_kind := "livestock"
@export var initially_completed := false
@export var construction_seconds := 180.0
@export var required_log_kg := 30.0
@export var required_iron_kg := 10.0
@export var completed_model_scene: PackedScene
@export var frame_model_path := NodePath("FrameModel")

var completed := false
var constructing := false
var construction_started_msec := 0
var slot_items: Array[Dictionary] = []
var slot_animals: Array[FarmLivestock] = []
var _completed_visual: Node3D
var _dust: GPUParticles3D
var _last_sync_msec := 0


func _ready() -> void:
	completed = initially_completed
	display_name = "鸡舍" if chop_kind == "chicken" else "牲畜棚"
	add_to_group("livestock_chops")
	_ensure_slots()
	_create_interaction_area()
	_create_construction_dust()
	_refresh_visuals()


func _process(_delta: float) -> void:
	if GameAuthority.is_client_proxy():
		return
	if constructing and get_construction_progress() >= 1.0:
		constructing = false
		completed = true
		_refresh_visuals()
		_emit_state()
	var now := Time.get_ticks_msec()
	if now - _last_sync_msec >= int(STATE_SYNC_INTERVAL * 1000.0):
		_last_sync_msec = now
		if constructing or completed:
			_emit_state()


func get_slot_count() -> int:
	return 8 if chop_kind == "chicken" else 4


func accepts_species(species_id: String) -> bool:
	return species_id == "chicken" if chop_kind == "chicken" \
		else species_id in ["pig", "angus_cow"]


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方养殖建筑"
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用%s" % display_name
	if not completed:
		return "需要足够的材料建造 | [E] 打开养殖界面"
	return "[E] 打开%s养殖界面" % display_name


func get_construction_progress(now_msec := Time.get_ticks_msec()) -> float:
	if completed:
		return 1.0
	if not constructing or construction_seconds <= 0.0:
		return 0.0
	return clampf(
		float(now_msec - construction_started_msec) / (construction_seconds * 1000.0),
		0.0, 1.0
	)


func start_construction() -> bool:
	if completed or constructing:
		return false
	constructing = true
	construction_started_msec = Time.get_ticks_msec()
	_refresh_visuals()
	return true


func put_livestock(slot_index: int, item: Dictionary) -> bool:
	_ensure_slots()
	var species_id := str(item.get("species_id", str(item.get("tool_id", "")).trim_prefix("animal_")))
	if not completed or slot_index < 0 or slot_index >= slot_items.size() \
			or not slot_items[slot_index].is_empty() or not accepts_species(species_id):
		return false
	var stored := item.duplicate(true)
	stored["species_id"] = species_id
	slot_items[slot_index] = stored
	if not GameAuthority.is_client_proxy():
		_spawn_slot_animal(slot_index)
	return true


func take_livestock(slot_index: int) -> Dictionary:
	_ensure_slots()
	if slot_index < 0 or slot_index >= slot_items.size() or slot_items[slot_index].is_empty():
		return {}
	_update_slot_item_from_animal(slot_index)
	var result := slot_items[slot_index].duplicate(true)
	slot_items[slot_index] = {}
	var animal := slot_animals[slot_index]
	if is_instance_valid(animal):
		animal.remove_from_group("wild_animals")
		animal.remove_from_group("farm_livestock")
		animal.queue_free()
	slot_animals[slot_index] = null
	return result


func get_chop_state() -> Dictionary:
	_ensure_slots()
	for index in range(slot_items.size()):
		_update_slot_item_from_animal(index)
	var state := {
		"station_path": str(get_path()),
		"station_position": global_position,
		"owner_team": owner_team,
		"chop_kind": chop_kind,
		"completed": completed,
		"constructing": constructing,
		"construction_progress": get_construction_progress(),
		"construction_seconds": construction_seconds,
		"required_log_kg": required_log_kg,
		"required_iron_kg": required_iron_kg,
		"slots": slot_items.duplicate(true),
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_chop_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	completed = bool(state.get("completed", completed))
	constructing = bool(state.get("constructing", constructing))
	construction_seconds = float(state.get("construction_seconds", construction_seconds))
	if constructing:
		construction_started_msec = Time.get_ticks_msec() - int(
			clampf(float(state.get("construction_progress", 0.0)), 0.0, 1.0)
			* construction_seconds * 1000.0
		)
	var value: Variant = state.get("slots", [])
	if value is Array:
		_ensure_slots()
		for index in range(slot_items.size()):
			slot_items[index] = ((value as Array)[index] as Dictionary).duplicate(true) \
				if index < (value as Array).size() and (value as Array)[index] is Dictionary else {}
			if not GameAuthority.is_client_proxy() and not slot_items[index].is_empty() \
					and not is_instance_valid(slot_animals[index]):
				_spawn_slot_animal(index)
	_refresh_visuals()


func _ensure_slots() -> void:
	var count := get_slot_count()
	while slot_items.size() < count:
		slot_items.append({})
		slot_animals.append(null)
	if slot_items.size() > count:
		slot_items.resize(count)
		slot_animals.resize(count)


func _spawn_slot_animal(slot_index: int) -> void:
	var item := slot_items[slot_index]
	var species_id := str(item.get("species_id", ""))
	var packed: PackedScene = LIVESTOCK_SCENES.get(species_id, null)
	if packed == null or not is_instance_valid(GlobalVar.gameworld):
		return
	var animal := packed.instantiate() as FarmLivestock
	if animal == null:
		return
	animal.owner_team = owner_team
	animal.animal_id = str(item.get("livestock_instance_id", "chop:%d:%d" % [get_instance_id(), slot_index]))
	animal.initial_hp = float(item.get("current_hp", animal.max_hp))
	animal.initial_growth_progress = float(item.get("growth_progress", 0.0))
	animal.housed_in_chop = true
	GlobalVar.gameworld.add_child(animal)
	animal.global_position = get_slot_global_position(slot_index)
	animal.home_position = animal.global_position
	slot_animals[slot_index] = animal


func get_slot_global_position(slot_index: int) -> Vector3:
	var slot_name := "ChickenSlot_%02d" % (slot_index + 1) if chop_kind == "chicken" \
		else "Slot%d" % (slot_index + 1)
	var anchor := find_child(slot_name, true, false) as Node3D
	if anchor != null:
		return anchor.global_position
	if chop_kind == "chicken":
		return to_global(Vector3(-1.5 + float(slot_index % 4), 0.1, -0.7 + float(slot_index / 4) * 1.4))
	return to_global(Vector3(-2.1 + float(slot_index) * 1.4, 0.1, -0.15))


func _update_slot_item_from_animal(slot_index: int) -> void:
	var animal := slot_animals[slot_index]
	if not is_instance_valid(animal) or slot_items[slot_index].is_empty():
		return
	var item := slot_items[slot_index]
	item["current_hp"] = animal.current_hp
	item["max_hp"] = animal.max_hp
	item["growth_progress"] = animal.get_growth_progress()
	slot_items[slot_index] = item


func _refresh_visuals() -> void:
	var frame_model := get_node_or_null(frame_model_path) as Node3D
	if frame_model != null:
		frame_model.visible = not completed
	if completed and _completed_visual == null and completed_model_scene != null:
		_completed_visual = completed_model_scene.instantiate() as Node3D
		if _completed_visual != null:
			_completed_visual.name = "CompletedModel"
			add_child(_completed_visual)
	if is_instance_valid(_completed_visual):
		_completed_visual.visible = completed
	if is_instance_valid(_dust):
		_dust.emitting = constructing and not completed


func _create_interaction_area() -> void:
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = GameAuthority.COLLISION_LAYER_CHARACTER
	area.monitoring = true
	area.monitorable = false
	area.add_to_group("livestock_chop_interaction_areas")
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.0, 3.0, 7.0)
	shape_node.position.y = 1.5
	shape_node.shape = shape
	area.add_child(shape_node)
	add_child(area)


func _create_construction_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "ConstructionDust"
	_dust.position = Vector3(0.0, 1.0, 0.0)
	_dust.amount = 32
	_dust.lifetime = 0.9
	_dust.randomness = 0.65
	_dust.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 5.0, 8.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.4, 0.25, 2.4)
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, -0.4, 0.0)
	process.scale_min = 0.2
	process.scale_max = 0.65
	process.color = Color(0.78, 0.78, 0.75, 0.55)
	_dust.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.55, 0.55)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.82, 0.82, 0.8, 0.48)
	mesh.material = material
	_dust.draw_pass_1 = mesh
	add_child(_dust)
	_dust.emitting = false


func _emit_state() -> void:
	if GameAuthority.is_client_proxy():
		return
	GameAuthority.reliable_world_event_ready.emit({
		"type": "livestock_chop_state", "station_state": get_chop_state(),
		"tick": GameAuthority.server_tick,
	})
