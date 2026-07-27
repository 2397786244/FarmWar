extends Node3D
class_name TeamGarage

const RED_CARGO_CONFIG := preload("res://vehicles/red_cargo_car_config.tres")
const BLUE_CARGO_CONFIG := preload("res://vehicles/blue_cargo_car_config.tres")

@export_enum("red", "blue") var owner_team := "red"
@export var cargo_car_respawn_seconds := 60.0

@onready var cargo_car_spawn_point: Marker3D = $CargoCarSpawnPoint
@onready var upgrade_terminal: GarageUpgradeTerminal = $UpgradeTerminal
@onready var respawn_label: Label3D = $CargoCarSpawnPoint/RespawnDisplay/RespawnLabel
@onready var progress_back: MeshInstance3D = $CargoCarSpawnPoint/RespawnDisplay/ProgressBack
@onready var progress_fill: MeshInstance3D = $CargoCarSpawnPoint/RespawnDisplay/ProgressFill

var respawn_active := false
var respawn_remaining := 0.0


func _ready() -> void:
	add_to_group("team_garages")
	if is_instance_valid(upgrade_terminal):
		upgrade_terminal.owner_team = owner_team
		upgrade_terminal.garage = self
	set_respawn_state(false, 0.0)


func _process(delta: float) -> void:
	if respawn_active and GameAuthority.is_client_proxy():
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		_refresh_respawn_display()


func get_cargo_car_spawn_transform() -> Transform3D:
	return cargo_car_spawn_point.global_transform


func get_upgrade_interaction_position() -> Vector3:
	return upgrade_terminal.global_position if is_instance_valid(upgrade_terminal) else global_position


func get_cargo_config() -> VehicleConfig:
	return RED_CARGO_CONFIG if owner_team == "red" else BLUE_CARGO_CONFIG


func set_respawn_state(active: bool, remaining_seconds: float) -> void:
	respawn_active = active
	respawn_remaining = maxf(0.0, remaining_seconds)
	_refresh_respawn_display()


func get_vehicle_stats() -> Dictionary:
	var vehicle := GameAuthority.get_team_cargo_car(owner_team)
	var config := get_cargo_config()
	return {
		"team": owner_team,
		"available": is_instance_valid(vehicle),
		"respawn_active": respawn_active,
		"respawn_remaining": respawn_remaining,
		"hp": vehicle.current_hp if is_instance_valid(vehicle) else 0.0,
		"max_hp": config.max_hp,
		"cargo_weight_kg": vehicle.cargo_weight_kg if is_instance_valid(vehicle) else 0.0,
		"cargo_capacity_kg": config.cargo_capacity_kg,
		"max_forward_speed": config.max_forward_speed,
		"acceleration": config.acceleration,
	}


func _refresh_respawn_display() -> void:
	if not is_instance_valid(respawn_label):
		return
	var visible := respawn_active
	respawn_label.visible = visible
	progress_back.visible = visible
	progress_fill.visible = visible
	if not visible:
		return
	respawn_label.text = "货运车重生  %d 秒" % ceili(respawn_remaining)
	var duration := maxf(0.01, cargo_car_respawn_seconds)
	var progress := clampf(1.0 - respawn_remaining / duration, 0.0, 1.0)
	progress_fill.scale.x = maxf(0.001, progress)
