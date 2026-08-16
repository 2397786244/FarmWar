class_name WeatherSystem3D
extends Node3D

signal weather_changed(weather_type: String, intensity: float)
signal eclipse_changed(active: bool)

const AUTHORITY_TICK_RATE := 60.0
const ECLIPSE_TRIGGER_START_HOUR := 9.0
const ECLIPSE_TRIGGER_END_HOUR := 12.0
const ECLIPSE_LATEST_END_HOUR := 18.0

@export_group("Scene Nodes")
@export var day_night_system_path := NodePath("../DayNightSystem")
@export var cloud_system_path := NodePath("../CloudSystem")

@export_group("Weather Schedule")
@export_enum("auto", "clear", "rain") var weather_override := "auto"
# Kept for scene compatibility with the former cycle-based scheduler. Automatic
# weather is now selected once per in-game day using the three probabilities
# below, so this value is no longer used for probability decisions.
@export_range(60.0, 3600.0, 1.0) var weather_cycle_seconds := 480.0
@export_range(0, 2147483647, 1) var weather_seed := 90731
@export_range(0.1, 1.0, 0.01) var rain_intensity := 0.82
@export_range(0.2, 20.0, 0.1) var transition_seconds := 5.0

@export_group("Automatic Weather Probabilities")
@export_range(0.0, 1.0, 0.01) var clear_weather_probability := 0.50
@export_range(0.0, 1.0, 0.01) var rain_weather_probability := 0.40
@export_range(0.0, 1.0, 0.01) var eclipse_weather_probability := 0.10

@export_group("Legacy Probability Compatibility")
# Older map scenes and editor manifests used these names. They are copied into
# the new probability fields only when they contain a non-default old value.
@export var rain_cycle_probability := 0.40
@export var eclipse_daily_probability := 0.10

@export_group("Rain Rendering")
@export_range(100, 4000, 25) var rain_particle_amount := 1350
@export_range(8.0, 60.0, 1.0) var rain_area_radius := 24.0
@export_range(8.0, 40.0, 1.0) var rain_spawn_height := 15.0

var current_weather := "clear"
var current_intensity := 0.0
var eclipse_active := false
var eclipse_intensity := 0.0
var _fallback_elapsed := 0.0
var _rain_particles: GPUParticles3D
var _day_night_system: Node
var _cloud_system: Node
var _authoritative_weather_active := false
var _authoritative_weather_type := "clear"
var _authoritative_weather_intensity := 0.0
var _authoritative_eclipse_active := false
var _authoritative_eclipse_intensity := 0.0


func _ready() -> void:
	if not is_equal_approx(rain_cycle_probability, 0.40):
		rain_weather_probability = clampf(rain_cycle_probability, 0.0, 1.0)
	if not is_equal_approx(eclipse_daily_probability, 0.10):
		eclipse_weather_probability = clampf(eclipse_daily_probability, 0.0, 1.0)
	add_to_group("weather_systems")
	_day_night_system = get_node_or_null(day_night_system_path)
	_cloud_system = get_node_or_null(cloud_system_path)
	_create_rain_particles()
	_apply_weather_visuals()


func _process(delta: float) -> void:
	_fallback_elapsed += delta
	var elapsed_seconds := _synchronized_elapsed_seconds()
	var target_weather := (
		_authoritative_weather_type
		if _authoritative_weather_active
		else _scheduled_weather_condition(elapsed_seconds)
	)
	if not _authoritative_weather_active and weather_override != "auto":
		# An explicit override is authoritative for the complete weather choice;
		# it must not allow a scheduled eclipse to overlap forced rain/clear.
		target_weather = "rain" if weather_override == "rain" else "clear"

	if target_weather != current_weather:
		var previous_eclipse_active := eclipse_active
		current_weather = target_weather
		eclipse_active = current_weather == "eclipse"
		# The inactive branch is cleared immediately. This prevents the visual
		# transition from leaving rain and eclipse active at the same time.
		if current_weather != "rain":
			current_intensity = 0.0
		if not eclipse_active:
			eclipse_intensity = 0.0
		weather_changed.emit(
			current_weather,
			rain_intensity if current_weather == "rain" else 0.0
		)
		if current_weather == "rain":
			_notify_weather_started("现在下雨了！")
		elif current_weather == "eclipse":
			_notify_weather_started("出现了日食！")
		if previous_eclipse_active != eclipse_active:
			eclipse_changed.emit(eclipse_active)

	var target_intensity := (
		_authoritative_weather_intensity
		if _authoritative_weather_active and current_weather == "rain"
		else rain_intensity if current_weather == "rain" else 0.0
	)
	current_intensity = move_toward(
		current_intensity, target_intensity, delta / maxf(0.1, transition_seconds)
	)
	if current_weather != "rain":
		current_intensity = 0.0

	var target_eclipse_intensity := (
		_authoritative_eclipse_intensity
		if _authoritative_weather_active and current_weather == "eclipse"
		else 1.0 if current_weather == "eclipse" else 0.0
	)
	eclipse_intensity = move_toward(
		eclipse_intensity,
		target_eclipse_intensity,
		delta / maxf(0.1, transition_seconds)
	)
	if current_weather != "eclipse":
		eclipse_intensity = 0.0
	_apply_weather_visuals()
	_update_rain_anchor()


func set_weather_override(next_override: String) -> void:
	weather_override = next_override if next_override in ["auto", "clear", "rain"] else "auto"


func get_authoritative_weather_state() -> Dictionary:
	return {
		"weather_type": current_weather,
		"intensity": current_intensity if current_weather == "rain" else 0.0,
		"eclipse_active": current_weather == "eclipse",
		"eclipse_intensity": eclipse_intensity if current_weather == "eclipse" else 0.0,
	}


func apply_authoritative_weather_state(state: Dictionary) -> void:
	_authoritative_weather_active = true
	var requested_weather_type := str(state.get("weather_type", "clear"))
	var requested_eclipse_active := bool(state.get("eclipse_active", false))
	if requested_weather_type == "eclipse" or requested_eclipse_active:
		_authoritative_weather_type = "eclipse"
	else:
		_authoritative_weather_type = "rain" if requested_weather_type == "rain" else "clear"
	_authoritative_weather_intensity = clampf(
		float(state.get("intensity", 0.0)),
		0.0,
		1.0
	)
	_authoritative_eclipse_active = _authoritative_weather_type == "eclipse"
	_authoritative_eclipse_intensity = clampf(
		float(state.get("eclipse_intensity", 1.0 if _authoritative_eclipse_active else 0.0)),
		0.0,
		1.0
	)


func clear_authoritative_weather_state() -> void:
	_authoritative_weather_active = false
	_authoritative_weather_type = "clear"
	_authoritative_eclipse_active = false
	_authoritative_eclipse_intensity = 0.0


func _scheduled_weather_condition(elapsed_seconds: float) -> String:
	var clock := _get_world_clock_state(elapsed_seconds)
	var day_index := int(clock.get("day_index", 0))
	var daily_weather := _daily_weather_kind(day_index)
	if daily_weather != "eclipse":
		return daily_weather
	var scheduled_eclipse := _scheduled_eclipse(elapsed_seconds)
	return "eclipse" if bool(scheduled_eclipse.get("active", false)) else "clear"


func _daily_weather_kind(day_index: int) -> String:
	var probabilities := _get_weather_probabilities()
	var roll := _hash01(day_index, 21)
	var clear_limit := float(probabilities.get("clear", 1.0))
	var rain_limit := clear_limit + float(probabilities.get("rain", 0.0))
	if roll < clear_limit:
		return "clear"
	if roll < rain_limit:
		return "rain"
	return "eclipse"


func _get_weather_probabilities() -> Dictionary:
	var clear_probability := maxf(0.0, clear_weather_probability)
	var rain_probability := maxf(0.0, rain_weather_probability)
	var eclipse_probability := maxf(0.0, eclipse_weather_probability)
	var total := clear_probability + rain_probability + eclipse_probability
	if total <= 0.0001:
		return {"clear": 1.0, "rain": 0.0, "eclipse": 0.0}
	return {
		"clear": clear_probability / total,
		"rain": rain_probability / total,
		"eclipse": eclipse_probability / total,
	}


func get_weather_probabilities() -> Dictionary:
	return _get_weather_probabilities()


func _scheduled_eclipse(elapsed_seconds: float) -> Dictionary:
	var clock := _get_world_clock_state(elapsed_seconds)
	var day_index := int(clock.get("day_index", 0))
	var start_hour := lerpf(
		ECLIPSE_TRIGGER_START_HOUR,
		ECLIPSE_TRIGGER_END_HOUR,
		_hash01(day_index, 11)
	)
	var end_hour := minf(ECLIPSE_LATEST_END_HOUR, start_hour + 6.0)
	var selected_for_day := _daily_weather_kind(day_index) == "eclipse"
	var current_hour := float(clock.get("hour", 0.0))
	return {
		"day_index": day_index,
		"start_hour": start_hour,
		"end_hour": end_hour,
		"selected": selected_for_day,
		"active": selected_for_day and current_hour >= start_hour and current_hour < end_hour,
	}


func get_eclipse_schedule_for_day(day_index: int) -> Dictionary:
	var start_hour := lerpf(
		ECLIPSE_TRIGGER_START_HOUR,
		ECLIPSE_TRIGGER_END_HOUR,
		_hash01(day_index, 11)
	)
	return {
		"day_index": day_index,
		"start_hour": start_hour,
		"end_hour": minf(ECLIPSE_LATEST_END_HOUR, start_hour + 6.0),
		"selected": _daily_weather_kind(day_index) == "eclipse",
	}


func _get_world_clock_state(elapsed_seconds: float) -> Dictionary:
	if _day_night_system != null and _day_night_system.has_method("get_world_clock_state"):
		var state: Variant = _day_night_system.call("get_world_clock_state")
		if state is Dictionary:
			return state as Dictionary
	var total_hours := 8.0 + elapsed_seconds / 1440.0 * 24.0
	return {
		"total_hours": total_hours,
		"day_index": floori(total_hours / 24.0),
		"hour": fposmod(total_hours, 24.0),
	}


func _hash01(cycle_index: int, salt: int) -> float:
	var value := sin(float(cycle_index * 92821 + weather_seed * 31 + salt * 19937)) * 43758.5453
	return value - floor(value)


func _synchronized_elapsed_seconds() -> float:
	if GameAuthority.is_server_authority() or GameAuthority.is_local_authority():
		return float(GameAuthority.server_tick) / AUTHORITY_TICK_RATE
	if GameAuthority.is_client_proxy():
		var snapshot: Dictionary = GameAuthority.last_snapshot
		var snapshot_tick := int(snapshot.get("tick", -1))
		if snapshot_tick >= 0:
			return float(snapshot_tick) / AUTHORITY_TICK_RATE
	return _fallback_elapsed


func _apply_weather_visuals() -> void:
	var active_weather_type := "rain" if current_weather == "rain" else "clear"
	if _day_night_system != null and _day_night_system.has_method("set_atmospheric_state"):
		_day_night_system.call(
			"set_atmospheric_state",
			active_weather_type,
			current_intensity,
			eclipse_active,
			eclipse_intensity
		)
	else:
		if _day_night_system != null and _day_night_system.has_method("set_weather_state"):
			_day_night_system.call("set_weather_state", active_weather_type, current_intensity)
		if _day_night_system != null and _day_night_system.has_method("set_eclipse_state"):
			_day_night_system.call("set_eclipse_state", eclipse_active, eclipse_intensity)
	if _cloud_system != null and _cloud_system.has_method("set_weather_state"):
		_cloud_system.call("set_weather_state", "rain", current_intensity)
	if _rain_particles != null:
		_rain_particles.emitting = current_intensity > 0.02
		_rain_particles.amount = maxi(1, roundi(float(rain_particle_amount) * current_intensity))


func _notify_weather_started(message: String) -> void:
	if message.is_empty():
		return
	# Player owns the actual lower-left HUD. The group call also works for a
	# listen server; remote proxies ignore this local-only presentation method.
	get_tree().call_group("human_players", "show_weather_notice", message, 3.0)


func _create_rain_particles() -> void:
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "LocalRain"
	_rain_particles.amount = rain_particle_amount
	_rain_particles.lifetime = 1.15
	_rain_particles.preprocess = 1.15
	_rain_particles.fixed_fps = 30
	_rain_particles.fract_delta = true
	_rain_particles.local_coords = true
	_rain_particles.visibility_aabb = AABB(
		Vector3(-rain_area_radius, -rain_spawn_height - 8.0, -rain_area_radius),
		Vector3(rain_area_radius * 2.0, rain_spawn_height + 14.0, rain_area_radius * 2.0)
	)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(rain_area_radius, 0.8, rain_area_radius)
	process_material.direction = Vector3(0.05, -1.0, 0.02)
	process_material.spread = 2.0
	process_material.initial_velocity_min = 21.0
	process_material.initial_velocity_max = 26.0
	process_material.gravity = Vector3(0.0, -6.0, 0.0)
	process_material.scale_min = 0.75
	process_material.scale_max = 1.25
	_rain_particles.process_material = process_material
	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.018, 0.72)
	var rain_material := StandardMaterial3D.new()
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.albedo_color = Color(0.54, 0.70, 1.0, 0.42)
	rain_material.vertex_color_use_as_albedo = true
	rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	rain_mesh.material = rain_material
	_rain_particles.draw_pass_1 = rain_mesh
	add_child(_rain_particles)


func _update_rain_anchor() -> void:
	if _rain_particles == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_rain_particles.global_position = camera.global_position + Vector3.UP * rain_spawn_height
