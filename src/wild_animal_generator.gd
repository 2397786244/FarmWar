extends Marker3D
class_name WildAnimalGenerator

const NatureResourceIdentity = preload("res://src/nature_resource_identity.gd")

@export var generator_id := ""
@export var animal_scene: PackedScene = preload("res://items/BlackBear.tscn")
@export_range(1, 10, 1) var maximum_animals := 2
@export_range(1.0, 600.0, 1.0) var spawn_interval_seconds := 60.0
@export_range(1.0, 100.0, 1.0) var player_clear_radius := 25.0
@export_range(0.0, 30.0, 0.5) var spawn_radius := 8.0
@export_range(0.0, 120.0, 1.0) var initial_spawn_delay := 60.0

var _spawn_timer := 0.0
var _spawn_sequence := 0
var _animals: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if generator_id.is_empty():
		generator_id = NatureResourceIdentity.make_stable_id(self)
	_rng.seed = hash(generator_id)
	_spawn_timer = maxf(0.0, spawn_interval_seconds - initial_spawn_delay)
	add_to_group("wild_animal_generators")


func _process(delta: float) -> void:
	if not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	_prune_animals()
	if _animals.size() >= maximum_animals:
		return
	_spawn_timer += delta
	if _spawn_timer < spawn_interval_seconds:
		return
	_spawn_timer = 0.0
	if _players_nearby():
		return
	_spawn_animal()


func on_animal_removed(animal: Node3D) -> void:
	_animals.erase(animal)
	_spawn_timer = 0.0


func _spawn_animal() -> void:
	if animal_scene == null:
		return
	var animal := animal_scene.instantiate() as Node3D
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if animal == null or world == null:
		return
	_spawn_sequence += 1
	animal.set("animal_id", "%s:%d" % [generator_id, _spawn_sequence])
	animal.set("home_generator", self)
	animal.set("home_position", global_position)
	if animal is FarmLivestock:
		(animal as FarmLivestock).owner_team = ""
		(animal as FarmLivestock).housed_in_chop = false
		(animal as FarmLivestock).naturally_spawned = true
	world.add_child(animal)
	animal.global_position = _find_spawn_position()
	animal.set("home_position", global_position)
	_animals.append(animal)


func _find_spawn_position() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * spawn_radius
	var candidate := global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	var world_3d := get_world_3d()
	if world_3d == null:
		return candidate
	var query := PhysicsRayQueryParameters3D.create(
		candidate + Vector3.UP * 20.0,
		candidate + Vector3.DOWN * 40.0,
		GameAuthority.COLLISION_LAYER_GROUND
	)
	var hit := world_3d.direct_space_state.intersect_ray(query)
	return hit.get("position", candidate) if not hit.is_empty() else candidate


func _players_nearby() -> bool:
	for raw_peer_id: Variant in GameAuthority.player_states.keys():
		var player_state: Dictionary = GameAuthority.player_states[raw_peer_id]
		if float(player_state.get("respawn_left", 0.0)) > 0.0:
			continue
		var position_value: Variant = player_state.get("position", null)
		if position_value is Vector3 and (position_value as Vector3).distance_to(global_position) <= player_clear_radius:
			return true
	return false


func _prune_animals() -> void:
	var removed_invalid := false
	for index in range(_animals.size() - 1, -1, -1):
		if not is_instance_valid(_animals[index]):
			_animals.remove_at(index)
			removed_invalid = true
	if removed_invalid:
		_spawn_timer = 0.0
