extends Control
class_name VehicleUpgradePage

const INTERACTION_DISTANCE := 4.0

@onready var window: PanelContainer = $Window
@onready var team_label: Label = $Window/Margin/VBox/Header/Team
@onready var status_label: Label = $Window/Margin/VBox/Status
@onready var hp_value: Label = $Window/Margin/VBox/Stats/HPValue
@onready var cargo_value: Label = $Window/Margin/VBox/Stats/CargoValue
@onready var max_speed_value: Label = $Window/Margin/VBox/Stats/MaxSpeedValue
@onready var acceleration_value: Label = $Window/Margin/VBox/Stats/AccelerationValue

var garage: TeamGarage
var player: GamePlayer
var refresh_accumulator := 0.0


func _ready() -> void:
	window.visible = false
	$Window/Margin/VBox/Header/CloseButton.pressed.connect(close)


func _process(delta: float) -> void:
	if not is_open():
		return
	if not is_instance_valid(garage) or not is_instance_valid(player) \
			or player.global_position.distance_to(garage.get_upgrade_interaction_position()) > INTERACTION_DISTANCE:
		close()
		return
	refresh_accumulator += delta
	if refresh_accumulator >= 0.2:
		refresh_accumulator = 0.0
		_refresh()


func is_open() -> bool:
	return window.visible


func open_for(next_garage: TeamGarage, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_garage) or not is_instance_valid(next_player):
		return
	garage = next_garage
	player = next_player
	refresh_accumulator = 0.0
	window.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	window.visible = false
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if not is_instance_valid(garage):
		return
	var stats := garage.get_vehicle_stats()
	team_label.text = "红队专属货运车" if str(stats.get("team", "")) == "red" else "蓝队专属货运车"
	if bool(stats.get("available", false)):
		status_label.text = "状态：可用"
		status_label.add_theme_color_override("font_color", Color("#76D99A"))
	elif bool(stats.get("respawn_active", false)):
		status_label.text = "状态：重生中（%d 秒）" % ceili(float(stats.get("respawn_remaining", 0.0)))
		status_label.add_theme_color_override("font_color", Color("#FFB85C"))
	else:
		status_label.text = "状态：不可用"
		status_label.add_theme_color_override("font_color", Color("#FF6E73"))
	hp_value.text = "%.0f / %.0f" % [float(stats.get("hp", 0.0)), float(stats.get("max_hp", 0.0))]
	cargo_value.text = "%.1f / %.1f kg" % [float(stats.get("cargo_weight_kg", 0.0)), float(stats.get("cargo_capacity_kg", 0.0))]
	max_speed_value.text = "%.1f m/s" % float(stats.get("max_forward_speed", 0.0))
	acceleration_value.text = "%.1f m/s²" % float(stats.get("acceleration", 0.0))
