extends Marker3D
class_name RoadBlockerSpawn

@export var road_blocker_id := ""
@export_range(1.0, 600.0, 1.0) var respawn_seconds := 10.0
var _active_blocker: RoadBlockerAI
var _respawn_pending := false

func _ready() -> void:
	add_to_group("road_blocker_spawns")

func activate() -> void:
	if _active_blocker == null and not _respawn_pending: _spawn()

func _spawn() -> void:
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()): return
	var packed := load("res://character/RoadBlockerAI.tscn") as PackedScene
	if packed == null: return
	_active_blocker = packed.instantiate() as RoadBlockerAI
	if _active_blocker == null: return
	_active_blocker.name = "RoadBlocker_%s" % road_blocker_id
	_active_blocker.road_blocker_id = road_blocker_id
	_active_blocker.set_meta("network_ai_id", "road_blocker_%s" % road_blocker_id)
	get_tree().current_scene.add_child(_active_blocker)
	_active_blocker.global_transform = global_transform
	_active_blocker.died.connect(_on_blocker_died)

func _on_blocker_died(_blocker: RoadBlockerAI) -> void:
	if _respawn_pending: return
	_respawn_pending = true
	await get_tree().create_timer(respawn_seconds).timeout
	_respawn_pending = false
	_spawn()
