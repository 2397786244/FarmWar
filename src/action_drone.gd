extends NormalDrone
class_name ActionDrone

const RECORDER_SCRIPT := preload("res://src/mjpeg_avi_recorder.gd")
const CAPTURE_DIRECTORY := "user://captures"
const MAX_RECORDING_SECONDS := 60.0
const MAX_RECORDING_SIZE := Vector2i(1920, 1080)

@export_range(5, 30, 1) var recording_fps := 15
@export_range(0.1, 1.0, 0.05) var recording_jpeg_quality := 0.85

var _recorder: MjpegAviRecorder
var _recording := false
var _recording_elapsed := 0.0
var _recording_frame_accumulator := 0.0
var _recording_capture_pending := false
var _recording_label: Label
var _toast_label: Label
var _toast_timer: Timer


func _ready() -> void:
	use_distance = 10000.0
	super._ready()
	_create_capture_ui()


func _process(delta: float) -> void:
	super._process(delta)
	if not _recording:
		return
	_recording_elapsed = minf(MAX_RECORDING_SECONDS, _recording_elapsed + delta)
	_update_recording_ui()
	_recording_frame_accumulator += delta
	var frame_interval := 1.0 / float(maxi(1, recording_fps))
	if _recording_frame_accumulator >= frame_interval and not _recording_capture_pending:
		_recording_frame_accumulator = fmod(_recording_frame_accumulator, frame_interval)
		_capture_recording_frame()
	if _recording_elapsed >= MAX_RECORDING_SECONDS:
		_stop_recording("录像已达到 1 分钟上限，已自动保存")


func request_primary_action() -> void:
	if not _placed or not _remote_control_active:
		return
	_capture_screenshot()


func request_secondary_action() -> void:
	if not _placed or not _remote_control_active:
		return
	if _recording:
		_stop_recording("录像已保存")
	else:
		_start_recording()


func _allows_secondary_remote_actions() -> bool:
	return false


func get_distance_signal_strength(_receiver: Node3D) -> float:
	return 1.0


func get_signal_strength(_receiver: Node3D) -> float:
	return 1.0


func get_effective_signal_strength(_receiver: Node3D) -> float:
	return 1.0


func set_jam_ratio(_value: float) -> void:
	jam_ratio = 1.0


func set_aug_ratio(_value: float) -> void:
	aug_ratio = 1.0


func activate_tool() -> void:
	super.activate_tool()
	use_distance = 10000.0
	_bomb_cooldown_left = 0.0


func end_remote_control() -> void:
	if _recording:
		_stop_recording("录像已保存")
	super.end_remote_control()


func emit():
	var user_node := get_node_or_null("../../../")
	if user_node == null or tool_owner.is_empty():
		return
	var raycast := user_node.find_child("LookAtTarget", true)
	if raycast == null or not raycast.is_colliding():
		return
	var drone := load("res://character/weapons/ActionDrone.tscn").instantiate() as ActionDrone
	GlobalVar.gameworld.add_child(drone)
	drone.global_position = raycast.get_collision_point() + Vector3(0.0, 0.3, 0.0)
	drone.tool_owner = tool_owner
	drone.activate_tool()
	return {"remote_node": drone}


func _capture_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	var path := "%s/action_drone_%s.png" % [CAPTURE_DIRECTORY, _timestamp()]
	var image := await GlobalCaptureManager.capture_viewport_without_ui(get_viewport())
	var error := image.save_png(path)
	if error == OK:
		_show_capture_notice("截图已保存\n%s" % ProjectSettings.globalize_path(path))
	else:
		_show_capture_notice("截图保存失败：%s" % error_string(error))


func _start_recording() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	var viewport_size := get_viewport().get_visible_rect().size
	var output_size := _limited_recording_size(Vector2i(roundi(viewport_size.x), roundi(viewport_size.y)))
	var path := "%s/action_drone_%s.avi" % [CAPTURE_DIRECTORY, _timestamp()]
	_recorder = RECORDER_SCRIPT.new() as MjpegAviRecorder
	if not _recorder.start(path, output_size.x, output_size.y, recording_fps):
		_recorder = null
		_show_capture_notice("无法创建录像文件")
		return
	_recording = true
	_recording_elapsed = 0.0
	_recording_frame_accumulator = 1.0 / float(maxi(1, recording_fps))
	_recording_capture_pending = false
	_update_recording_ui()
	_recording_label.visible = true


func _stop_recording(message: String) -> void:
	if not _recording:
		return
	_recording = false
	if is_instance_valid(_recording_label):
		_recording_label.visible = false
	var saved_path := _recorder.finish() if _recorder != null else ""
	_recorder = null
	if saved_path.is_empty():
		_show_capture_notice("录像保存失败")
	else:
		_show_capture_notice("%s\n%s" % [message, ProjectSettings.globalize_path(saved_path)])


func _capture_recording_frame() -> void:
	_recording_capture_pending = true
	await RenderingServer.frame_post_draw
	if _recording and _recorder != null:
		var image := get_viewport().get_texture().get_image()
		_recorder.add_frame(image, recording_jpeg_quality)
	_recording_capture_pending = false


func _limited_recording_size(source_size: Vector2i) -> Vector2i:
	var width := maxi(2, source_size.x)
	var height := maxi(2, source_size.y)
	var scale_factor := minf(
		1.0,
		minf(float(MAX_RECORDING_SIZE.x) / float(width), float(MAX_RECORDING_SIZE.y) / float(height))
	)
	return Vector2i(
		maxi(2, roundi(width * scale_factor) & ~1),
		maxi(2, roundi(height * scale_factor) & ~1)
	)


func _create_capture_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_recording_label = Label.new()
	_recording_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_recording_label.position = Vector2(-260.0, 24.0)
	_recording_label.size = Vector2(236.0, 42.0)
	_recording_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_recording_label.add_theme_color_override("font_color", Color(1.0, 0.12, 0.08))
	_recording_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
	_recording_label.add_theme_constant_override("outline_size", 6)
	_recording_label.add_theme_font_size_override("font_size", 24)
	_recording_label.visible = false
	layer.add_child(_recording_label)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast_label.position = Vector2(-650.0, -112.0)
	_toast_label.size = Vector2(620.0, 88.0)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.add_theme_color_override("font_color", Color.WHITE)
	_toast_label.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.03))
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.add_theme_font_size_override("font_size", 18)
	_toast_label.visible = false
	layer.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 5.0
	_toast_timer.timeout.connect(func():
		if is_instance_valid(_toast_label):
			_toast_label.visible = false
	)
	add_child(_toast_timer)


func _update_recording_ui() -> void:
	if not is_instance_valid(_recording_label):
		return
	var seconds := mini(60, floori(_recording_elapsed))
	var dot_visible := fmod(_recording_elapsed, 1.0) < 0.55
	_recording_label.text = "%s REC %02d:%02d / 01:00" % [
		"●" if dot_visible else " ",
		floori(float(seconds) / 60.0),
		seconds % 60,
	]


func _show_capture_notice(message: String) -> void:
	if not is_instance_valid(_toast_label):
		return
	_toast_label.text = message
	_toast_label.visible = true
	_toast_timer.start()


func _timestamp() -> String:
	var time := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(time.year), int(time.month), int(time.day),
		int(time.hour), int(time.minute), int(time.second),
		Time.get_ticks_msec() % 1000,
	]


func _exit_tree() -> void:
	if _recording and _recorder != null:
		_recording = false
		_recorder.finish()
