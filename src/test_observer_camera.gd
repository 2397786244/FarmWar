extends Camera3D
## 测试场景自由观察相机。WASD 移动，鼠标右键拖拽 look，滚轮调高度，不捕获鼠标。

const MOVE_SPEED := 25.0
const FAST_MOVE_SPEED := 60.0
const LOOK_SENSITIVITY := 0.0025
const MIN_Y := 3.0
const MAX_Y := 50.0

var yaw := 0.0
var pitch := -0.6
var is_looking := false


func _ready() -> void:
	current = true
	rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	_handle_movement(delta)


func _handle_movement(delta: float) -> void:
	var speed := FAST_MOVE_SPEED if Input.is_key_pressed(KEY_SHIFT) else MOVE_SPEED
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir += -global_transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir += -global_transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		input_dir += Vector3.DOWN
	if Input.is_key_pressed(KEY_E):
		input_dir += Vector3.UP
	if input_dir.length_squared() > 0.001:
		global_position += input_dir.normalized() * speed * delta
	global_position.y = clampf(global_position.y, MIN_Y, MAX_Y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			global_position += -global_transform.basis.z * 2.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			global_position += global_transform.basis.z * 2.0
	elif event is InputEventMouseMotion and is_looking:
		yaw -= event.screen_relative.x * LOOK_SENSITIVITY
		pitch -= event.screen_relative.y * LOOK_SENSITIVITY
		pitch = clampf(pitch, -1.5, 0.2)
		rotation = Vector3(pitch, yaw, 0.0)
