extends Control
class_name GameExitDialog

signal resume_requested
signal exit_requested
signal save_game_requested
signal main_menu_requested

@onready var resume_button: Button = $Dimmer/Window/Margin/VBox/ResumeButton
@onready var settings_button: Button = $Dimmer/Window/Margin/VBox/SettingsButton
@onready var save_button: Button = $Dimmer/Window/Margin/VBox/SaveButton
@onready var main_menu_button: Button = $Dimmer/Window/Margin/VBox/MainMenuButton
@onready var exit_button: Button = $Dimmer/Window/Margin/VBox/ExitButton
@onready var settings_panel: Node = $SettingsPanel


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	settings_button.pressed.connect(_open_settings)
	save_button.pressed.connect(func() -> void: save_game_requested.emit())
	main_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	save_button.visible = false


func bind_player(player: Node) -> void:
	if is_instance_valid(settings_panel) and settings_panel.has_method("bind_player"):
		settings_panel.call("bind_player", player)


func open_dialog() -> void:
	if is_instance_valid(settings_panel) and settings_panel.has_method("close"):
		settings_panel.call("close")
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func set_save_game_visible(value: bool) -> void:
	if is_instance_valid(save_button):
		save_button.visible = value


func show_save_feedback(saved: bool) -> void:
	if not is_instance_valid(save_button):
		return
	save_button.text = "游戏已保存" if saved else "保存失败"
	save_button.disabled = true
	var timer := get_tree().create_timer(1.5)
	await timer.timeout
	if is_instance_valid(save_button):
		save_button.text = "保存游戏"
		save_button.disabled = false


func close_dialog() -> void:
	if is_instance_valid(settings_panel) and settings_panel.has_method("close"):
		settings_panel.call("close")
	visible = false


func is_open() -> bool:
	return visible


func handle_escape() -> bool:
	if is_instance_valid(settings_panel) and settings_panel.has_method("is_open") \
			and bool(settings_panel.call("is_open")):
		settings_panel.call("close")
		return true
	return false


func _open_settings() -> void:
	if is_instance_valid(settings_panel) and settings_panel.has_method("open"):
		settings_panel.call("open")
