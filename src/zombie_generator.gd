extends Marker3D
class_name ZombieGenerator

## A map generator is a clock, not a population controller: every interval
## produces at most one Zombie when its weather/time conditions are satisfied,
## even if the previous zombie is still alive.

const ZOMBIE_SCENE_PATH := "res://character/Zombie.tscn"

@export var generator_id := ""
@export var zombie_scene: PackedScene = preload("res://character/Zombie.tscn")
@export_enum("male", "female") var zombie_gender := "male"
@export_enum("any", "clear", "rain", "eclipse") var weather_condition := "any"
@export_range(0.0, 24.0, 0.25) var time_start_hour := 0.0
@export_range(0.0, 24.0, 0.25) var time_end_hour := 24.0
@export_range(1.0, 86400.0, 1.0) var spawn_interval_seconds := 60.0
@export_range(0.0, 86400.0, 1.0) var initial_spawn_delay := 0.0
@export var enabled := true

var _spawn_timer := 0.0
var _spawn_sequence := 0


func _ready() -> void:
	if generator_id.is_empty():
		generator_id = "%s_%d" % [name.to_snake_case(), get_instance_id()]
	_spawn_timer = maxf(0.0, initial_spawn_delay)
	add_to_group("zombie_generators")


func _process(delta: float) -> void:
	if not enabled or not _has_generation_authority():
		return
	_spawn_timer -= maxf(0.0, delta)
	if _spawn_timer > 0.0:
		return
	_spawn_timer = maxf(1.0, spawn_interval_seconds)
	if not _generation_conditions_met():
		return
	_spawn_zombie()


func _has_generation_authority() -> bool:
	return GameAuthority.is_server_authority() or GameAuthority.is_local_authority()


func _spawn_zombie() -> void:
	var packed := zombie_scene
	if packed == null:
		packed = load(ZOMBIE_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var zombie := packed.instantiate() as Node3D
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if zombie == null or world == null:
		if zombie != null:
			zombie.queue_free()
		return
	_spawn_sequence += 1
	zombie.name = "%s_Zombie_%03d" % [generator_id, _spawn_sequence]
	var assigned_id := "%s:%d" % [generator_id, _spawn_sequence]
	zombie.set("zombie_id", assigned_id)
	zombie.set("animal_id", assigned_id)
	zombie.set("zombie_gender", "female" if zombie_gender == "female" else "male")
	zombie.set("home_generator", self)
	world.add_child(zombie)
	if zombie is Node3D:
		(zombie as Node3D).global_transform = global_transform


func _generation_conditions_met() -> bool:
	return _weather_matches() and _time_matches()


func _weather_matches() -> bool:
	var requested := weather_condition.to_lower()
	if requested == "any" or requested.is_empty():
		return true
	var current := _current_weather().to_lower()
	if requested == "clear":
		return current in ["clear", "sunny"]
	if requested == "rain":
		return current in ["rain", "rainy"]
	if requested == "eclipse":
		return current == "eclipse"
	return false


func _time_matches() -> bool:
	var hour := _current_hour()
	var start := clampf(time_start_hour, 0.0, 24.0)
	var end := clampf(time_end_hour, 0.0, 24.0)
	# Equal endpoints represent an unrestricted full-day window. This also
	# makes the default 0..24 range behave as expected after fposmod wrapping.
	if is_equal_approx(start, end) or (is_equal_approx(start, 0.0) and is_equal_approx(end, 24.0)):
		return true
	if start < end:
		return hour >= start and hour <= end
	return hour >= start or hour <= end


func _current_weather() -> String:
	var weather_system := get_tree().get_first_node_in_group("weather_systems")
	if weather_system == null:
		return "clear"
	if weather_system.has_method("get_authoritative_weather_state"):
		var state_value: Variant = weather_system.call("get_authoritative_weather_state")
		if state_value is Dictionary:
			var weather_type := str((state_value as Dictionary).get("weather_type", ""))
			if not weather_type.is_empty():
				return weather_type
	for property_info: Dictionary in weather_system.get_property_list():
		if str(property_info.get("name", "")) == "current_weather":
			return str(weather_system.get("current_weather"))
	return "clear"


func _current_hour() -> float:
	var day_night := get_tree().get_first_node_in_group("day_night_systems")
	if day_night != null and day_night.has_method("get_current_hour"):
		return fposmod(float(day_night.call("get_current_hour")), 24.0)
	return 12.0
