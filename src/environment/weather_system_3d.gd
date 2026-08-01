class_name WeatherSystem3D
extends Node3D

signal weather_changed(weather_type: String, intensity: float)

const AUTHORITY_TICK_RATE := 60.0

@export_group("Scene Nodes")
@export var day_night_system_path := NodePath("../DayNightSystem")
@export var cloud_system_path := NodePath("../CloudSystem")

@export_group("Weather Schedule")
@export_enum("auto", "clear", "rain") var weather_override := "auto"
@export_range(60.0, 3600.0, 1.0) var weather_cycle_seconds := 480.0
@export_range(0.0, 1.0, 0.01) var rain_cycle_probability := 0.42
@export_range(0, 2147483647, 1) var weather_seed := 90731
@export_range(0.1, 1.0, 0.01) var rain_intensity := 0.82
@export_range(0.2, 20.0, 0.1) var transition_seconds := 5.0

@export_group("Rain Rendering")
@export_range(100, 4000, 25) var rain_particle_amount := 1350
@export_range(8.0, 60.0, 1.0) var rain_area_radius := 24.0
@export_range(8.0, 40.0, 1.0) var rain_spawn_height := 15.0

var current_weather := "clear"
var current_intensity := 0.0
var _fallback_elapsed := 0.0
var _rain_particles: GPUParticles3D
var _day_night_system: Node
var _cloud_system: Node
var _authoritative_weather_active := false
var _authoritative_weather_type := "clear"
var _authoritative_weather_intensity := 0.0


func _ready() -> void:
	add_to_group("weather_systems")
	_day_night_system = get_node_or_null(day_night_system_path)
	_cloud_system = get_node_or_null(cloud_system_path)
	_create_rain_particles()
	_apply_weather_visuals()


func _process(delta: float) -> void:
	_fallback_elapsed += delta
	var target_weather := _authoritative_weather_type if _authoritative_weather_active else _scheduled_weather(_synchronized_elapsed_seconds())
	if not _authoritative_weather_active and weather_override != "auto":
		target_weather = weather_override
	var target_intensity := _authoritative_weather_intensity if _authoritative_weather_active else rain_intensity if target_weather == "rain" else 0.0
	current_intensity = move_toward(
		current_intensity, target_intensity, delta / maxf(0.1, transition_seconds)
	)
	var next_weather := "rain" if current_intensity > 0.01 else "clear"
	if next_weather != current_weather:
		current_weather = next_weather
		weather_changed.emit(current_weather, current_intensity)
	_apply_weather_visuals()
	_update_rain_anchor()


func set_weather_override(next_override: String) -> void:
	weather_override = next_override if next_override in ["auto", "clear", "rain"] else "auto"


func get_authoritative_weather_state() -> Dictionary:
	return {
		"weather_type": current_weather,
		"intensity": current_intensity,
	}


func apply_authoritative_weather_state(state: Dictionary) -> void:
	_authoritative_weather_active = true
	_authoritative_weather_type = "rain" if str(state.get("weather_type", "clear")) == "rain" else "clear"
	_authoritative_weather_intensity = clampf(float(state.get("intensity", 0.0)), 0.0, 1.0)


func clear_authoritative_weather_state() -> void:
	_authoritative_weather_active = false


func _scheduled_weather(elapsed_seconds: float) -> String:
	var cycle_duration := maxf(1.0, weather_cycle_seconds)
	var cycle_index := floori(elapsed_seconds / cycle_duration)
	var cycle_phase := fposmod(elapsed_seconds, cycle_duration) / cycle_duration
	if _hash01(cycle_index, 1) > rain_cycle_probability:
		return "clear"
	var start_phase := lerpf(0.12, 0.32, _hash01(cycle_index, 2))
	var duration := lerpf(0.30, 0.54, _hash01(cycle_index, 3))
	return "rain" if cycle_phase >= start_phase and cycle_phase < start_phase + duration else "clear"


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
	if _day_night_system != null and _day_night_system.has_method("set_weather_state"):
		_day_night_system.call("set_weather_state", "rain", current_intensity)
	if _cloud_system != null and _cloud_system.has_method("set_weather_state"):
		_cloud_system.call("set_weather_state", "rain", current_intensity)
	if _rain_particles != null:
		_rain_particles.emitting = current_intensity > 0.02
		_rain_particles.amount = maxi(1, roundi(float(rain_particle_amount) * current_intensity))


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
