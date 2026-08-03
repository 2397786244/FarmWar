extends Control
class_name GameExitDialog

signal resume_requested
signal exit_requested
signal save_game_requested

@onready var resume_button: Button = $Dimmer/Window/Margin/VBox/ResumeButton
@onready var save_button: Button = $Dimmer/Window/Margin/VBox/SaveButton
@onready var exit_button: Button = $Dimmer/Window/Margin/VBox/ExitButton


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	save_button.pressed.connect(func() -> void: save_game_requested.emit())
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	save_button.visible = false


func open_dialog() -> void:
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
	visible = false


func is_open() -> bool:
	return visible
