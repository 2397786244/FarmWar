extends Control
class_name GameExitDialog

signal resume_requested
signal exit_requested

@onready var resume_button: Button = $Dimmer/Window/Margin/VBox/ResumeButton
@onready var exit_button: Button = $Dimmer/Window/Margin/VBox/ExitButton


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	exit_button.pressed.connect(func() -> void: exit_requested.emit())


func open_dialog() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func close_dialog() -> void:
	visible = false


func is_open() -> bool:
	return visible
