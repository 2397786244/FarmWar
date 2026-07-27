class_name DayNightSystem3D
extends Node3D

const TICK_RATE := 60.0
const SUNRISE_ALTITUDE := deg_to_rad(-0.833)

@export_group("Scene Nodes")
@export var sun_path := NodePath("../Sun")
@export var world_environment_path := NodePath("../WorldEnvironment")
@export var cloud_system_path := NodePath("../CloudSystem")

@export_group("Clock")
@export_range(60.0, 7200.0, 1.0) var real_day_duration_seconds := 1440.0
@export_range(0.0, 24.0, 0.1) var initial_hour := 8.0

@export_group("Summer Location")
@export_range(-89.0, 89.0, 0.1) var latitude_degrees := 38.0
@export_range(1, 365, 1) var day_of_year := 180

@export_group("Lighting")
@export_range(0.0, 4.0, 0.05) var maximum_sun_energy := 1.2
@export_range(0.0, 1.0, 0.01) var maximum_moon_energy := 0.16
@export_range(0.0, 1.0, 0.01) var night_ambient_energy := 0.12
@export_range(0.0, 2.0, 0.01) var day_ambient_energy := 0.8

@export_group("Street Lights")
@export_range(0.0, 24.0, 0.1) var street_lights_on_hour := 19.0
@export_range(0.0, 24.0, 0.1) var street_lights_off_hour := 5.0

var current_hour := 8.0
var daylight_factor := 1.0

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _cloud_system: Node
var _game_authority: Node
var _sun_visual: MeshInstance3D
var _moon_visual: MeshInstance3D
var _fallback_elapsed := 0.0
var _client_tick_anchor := 0.0
var _client_anchor_msec := 0
var _last_client_snapshot_tick := -1
var _update_accumulator := 0.0


func _ready() -> void:
	add_to_group("day_night_systems")
	_game_authority = get_node_or_null("/root/GameAuthority")
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	_cloud_system = get_node_or_null(cloud_system_path)
	_prepare_environment_resources()
	_create_moon()
	_create_celestial_visuals()
	_apply_time_of_day()


func _process(delta: float) -> void:
	_fallback_elapsed += delta
	_update_accumulator += delta
	if _update_accumulator < 0.05:
		return
	_update_accumulator = 0.0
	_apply_time_of_day()


func get_daylight_game_hours() -> float:
	var latitude := deg_to_rad(latitude_degrees)
	var declination := _solar_declination()
	var denominator := cos(latitude) * cos(declination)
	if absf(denominator) < 0.0001:
		return 24.0 if sin(latitude) * sin(declination) > sin(SUNRISE_ALTITUDE) else 0.0
	var cosine_hour_angle := (
		sin(SUNRISE_ALTITUDE) - sin(latitude) * sin(declination)
	) / denominator
	if cosine_hour_angle <= -1.0:
		return 24.0
	if cosine_hour_angle >= 1.0:
		return 0.0
	return 2.0 * rad_to_deg(acos(cosine_hour_angle)) / 15.0


func _apply_time_of_day() -> void:
	current_hour = fposmod(
		initial_hour + _synchronized_elapsed_seconds() / real_day_duration_seconds * 24.0,
		24.0
	)
	var solar := _calculate_solar_state(current_hour)
	var altitude := float(solar["altitude"])
	var sun_direction := solar["direction"] as Vector3
	daylight_factor = smoothstep(deg_to_rad(-6.0), deg_to_rad(8.0), altitude)
	var night_factor := 1.0 - daylight_factor
	_apply_directional_lights(sun_direction, altitude, night_factor)
	_apply_environment(altitude)
	_update_celestial_visuals(sun_direction)
	if _cloud_system != null and _cloud_system.has_method("set_daylight_state"):
		_cloud_system.call("set_daylight_state", daylight_factor, sun_direction)
	get_tree().call_group(
		"day_night_lamps", "set_night_factor", get_street_light_factor()
	)


func get_street_light_factor() -> float:
	return 1.0 if _is_hour_in_wrapped_range(
		current_hour, street_lights_on_hour, street_lights_off_hour
	) else 0.0


func _is_hour_in_wrapped_range(hour: float, start_hour: float, end_hour: float) -> bool:
	var start := fposmod(start_hour, 24.0)
	var end := fposmod(end_hour, 24.0)
	if is_equal_approx(start, end):
		return true
	if start < end:
		return hour >= start and hour < end
	return hour >= start or hour < end


func _synchronized_elapsed_seconds() -> float:
	if _game_authority != null and bool(_game_authority.call("is_client_proxy")):
		var snapshot_value: Variant = _game_authority.get("last_snapshot")
		var snapshot := snapshot_value as Dictionary if snapshot_value is Dictionary else {}
		var snapshot_tick := int(snapshot.get("tick", -1))
		if snapshot_tick >= 0 and snapshot_tick != _last_client_snapshot_tick:
			_last_client_snapshot_tick = snapshot_tick
			_client_tick_anchor = float(snapshot_tick)
			_client_anchor_msec = Time.get_ticks_msec()
		if _last_client_snapshot_tick >= 0:
			return (_client_tick_anchor + (
				float(Time.get_ticks_msec() - _client_anchor_msec) * 0.001 * TICK_RATE
			)) / TICK_RATE
	if _game_authority != null and (
		bool(_game_authority.call("is_server_authority"))
		or bool(_game_authority.call("is_local_authority"))
	):
		return float(_game_authority.get("server_tick")) / TICK_RATE
	return _fallback_elapsed


func _calculate_solar_state(hour: float) -> Dictionary:
	var latitude := deg_to_rad(latitude_degrees)
	var declination := _solar_declination()
	var hour_angle := deg_to_rad((hour - 12.0) * 15.0)
	var altitude := asin(clampf(
		sin(latitude) * sin(declination)
		+ cos(latitude) * cos(declination) * cos(hour_angle),
		-1.0,
		1.0
	))
	var azimuth := atan2(
		-sin(hour_angle),
		tan(declination) * cos(latitude) - sin(latitude) * cos(hour_angle)
	)
	var horizontal := cos(altitude)
	return {
		"altitude": altitude,
		"azimuth": azimuth,
		"direction": Vector3(
			horizontal * sin(azimuth),
			sin(altitude),
			-horizontal * cos(azimuth)
		).normalized(),
	}


func _solar_declination() -> float:
	return deg_to_rad(23.44) * sin(TAU * (float(day_of_year) - 81.0) / 365.0)


func _apply_directional_lights(
	sun_direction: Vector3, altitude: float, night_factor: float
) -> void:
	if _sun != null:
		_set_light_direction(_sun, -sun_direction)
		_sun.light_energy = pow(maxf(sin(altitude), 0.0), 0.35) * maximum_sun_energy
		var warm_factor := 1.0 - smoothstep(deg_to_rad(2.0), deg_to_rad(22.0), altitude)
		_sun.light_color = Color(1.0, 0.58, 0.32).lerp(
			Color(1.0, 0.95, 0.82), 1.0 - warm_factor
		)
		_sun.visible = _sun.light_energy > 0.002
	if _moon != null:
		_set_light_direction(_moon, sun_direction)
		_moon.light_energy = maximum_moon_energy * smoothstep(0.35, 0.92, night_factor)
		_moon.visible = _moon.light_energy > 0.002


func _set_light_direction(light: DirectionalLight3D, ray_direction: Vector3) -> void:
	var up := Vector3.FORWARD if absf(ray_direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	light.global_basis = Basis.looking_at(ray_direction.normalized(), up)


func _prepare_environment_resources() -> void:
	if _world_environment == null or _world_environment.environment == null:
		return
	_environment = _world_environment.environment.duplicate(true) as Environment
	_world_environment.environment = _environment
	if _environment.sky == null:
		return
	var runtime_sky := _environment.sky.duplicate(true) as Sky
	_environment.sky = runtime_sky
	if runtime_sky.sky_material is ProceduralSkyMaterial:
		_sky_material = runtime_sky.sky_material.duplicate(true) as ProceduralSkyMaterial
		runtime_sky.sky_material = _sky_material


func _apply_environment(altitude: float) -> void:
	if _environment == null:
		return
	var twilight := smoothstep(deg_to_rad(-8.0), deg_to_rad(0.0), altitude) * (
		1.0 - smoothstep(deg_to_rad(10.0), deg_to_rad(22.0), altitude)
	)
	_environment.ambient_light_energy = lerpf(
		night_ambient_energy, day_ambient_energy, daylight_factor
	)
	_environment.ambient_light_color = Color(0.16, 0.21, 0.36).lerp(
		Color.WHITE, daylight_factor
	)
	if _sky_material == null:
		return
	var top := Color(0.008, 0.018, 0.055).lerp(
		Color(0.26, 0.60, 0.88), daylight_factor
	)
	var horizon := Color(0.035, 0.055, 0.12).lerp(
		Color(0.72, 0.88, 0.97), daylight_factor
	)
	horizon = horizon.lerp(Color(1.0, 0.32, 0.12), twilight * 0.72)
	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_bottom_color = Color(0.012, 0.018, 0.028).lerp(
		Color(0.25, 0.40, 0.22), daylight_factor
	)
	_sky_material.ground_horizon_color = Color(0.03, 0.04, 0.07).lerp(
		Color(0.62, 0.73, 0.54), daylight_factor
	).lerp(Color(0.62, 0.20, 0.10), twilight * 0.45)


func _create_moon() -> void:
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.58, 0.70, 1.0)
	_moon.shadow_enabled = false
	_moon.directional_shadow_max_distance = 180.0
	add_child(_moon)


func _create_celestial_visuals() -> void:
	_sun_visual = _create_celestial_body(
		"SunVisual", 4.0, Color(1.0, 0.72, 0.30), 3.0
	)
	_moon_visual = _create_celestial_body(
		"MoonVisual", 3.2, Color(0.70, 0.80, 1.0), 1.5
	)


func _create_celestial_body(
	body_name: String, diameter: float, color: Color, emission_energy: float
) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.name = body_name
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	mesh.radial_segments = 20
	mesh.rings = 10
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	mesh.material = material
	body.mesh = mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(body)
	return body


func _update_celestial_visuals(sun_direction: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	var center := camera.global_position if camera != null else global_position
	if _sun_visual != null:
		_sun_visual.global_position = center + sun_direction * 320.0
		_sun_visual.visible = sun_direction.y > -0.08
	if _moon_visual != null:
		_moon_visual.global_position = center - sun_direction * 300.0
		_moon_visual.visible = sun_direction.y < 0.12
