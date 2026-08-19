extends Node
class_name DisplaySettingsService

## Runtime display settings shared by every mode and every map.
## ConfigFile writes to user://, so exported builds keep the player's choices
## outside the project files and preserve them across launches.

signal changed(settings: Dictionary)

const SETTINGS_PATH := "user://farmwar_display_settings.cfg"
const SETTINGS_SECTION := "display"
const SETTINGS_VERSION := 2
const AA_MODES := ["off", "fxaa", "smaa", "taa", "fsr2"]
const POST_PROCESS_PARAMETERS := [
	"effect_strength",
	"brightness",
	"contrast",
	"saturation",
	"grade_strength",
	"shadow_tint",
	"highlight_tint",
	"sharpen_strength",
	"vignette_strength",
	"vignette_start",
	"vignette_end",
	"motion_blur_enabled",
	"motion_blur_strength",
	"soft_glow_enabled",
	"soft_glow_strength",
	"soft_glow_threshold",
	"chromatic_aberration_enabled",
	"chromatic_aberration_strength",
]

var values: Dictionary = {}
var _save_queued := false


func _ready() -> void:
	values = _make_default_values()
	_load_from_user_file()
	if not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)
	# The root viewport exists before the first menu scene, while map players can
	# be spawned later by FarmWorldInitializer or CooperativeSession.
	call_deferred("apply_settings")


func get_defaults() -> Dictionary:
	return _make_default_values()


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return values.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	if not values.has(key):
		return
	values[key] = _sanitize_value(key, value)
	_apply_viewport_settings()
	_apply_scene_post_process()
	_queue_save()
	changed.emit(values.duplicate(true))


func reset_to_defaults() -> void:
	values = _make_default_values()
	apply_settings()
	_queue_save()
	changed.emit(values.duplicate(true))


func apply_settings() -> void:
	_apply_viewport_settings()
	_apply_scene_post_process()


func apply_to_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	var world_post := player.get_node_or_null("EffectLayer/WorldPostProcess") as ColorRect
	_apply_to_post_process(world_post)


func _make_default_values() -> Dictionary:
	return {
		"effect_strength": 1.0,
		"brightness": 1.0,
		"contrast": 1.05,
		"saturation": 1.08,
		"grade_strength": 0.18,
		"shadow_tint": Color(0.97, 0.99, 1.02, 1.0),
		"highlight_tint": Color(1.02, 0.99, 0.95, 1.0),
		"sharpen_strength": 0.12,
		"vignette_strength": 0.10,
		"vignette_start": 1.50,
		"vignette_end": 1.95,
		"motion_blur_enabled": 1.0,
		"motion_blur_strength": 0.22,
		"soft_glow_enabled": 1.0,
		"soft_glow_strength": 0.24,
		"soft_glow_threshold": 0.72,
		"chromatic_aberration_enabled": 1.0,
		"chromatic_aberration_strength": 0.16,
		"aa_mode": "off",
		"msaa_3d": 2,
		"msaa_2d": 2,
		"fsr2_scale": 0.77,
		"debanding_enabled": false,
		"settings_version": SETTINGS_VERSION,
	}


func _load_from_user_file() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_queue_save()
		return
	for key: Variant in values.keys():
		var setting_key := str(key)
		if config.has_section_key(SETTINGS_SECTION, setting_key):
			values[setting_key] = _sanitize_value(
				setting_key,
				config.get_value(SETTINGS_SECTION, setting_key, values[key])
			)
	var stored_version := int(config.get_value(SETTINGS_SECTION, "settings_version", 1))
	if stored_version < SETTINGS_VERSION:
		# The old vignette defaults darkened too much of the image. Move existing
		# installs to the new corner-only defaults once.
		values["vignette_start"] = 1.50
		values["vignette_end"] = 1.95
		values["settings_version"] = SETTINGS_VERSION
		_queue_save()


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_flush_save")


func _flush_save() -> void:
	_save_queued = false
	var config := ConfigFile.new()
	for key: Variant in values.keys():
		if str(key) != "settings_version":
			config.set_value(SETTINGS_SECTION, str(key), values[key])
	config.set_value(SETTINGS_SECTION, "settings_version", SETTINGS_VERSION)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("无法保存画面设置：错误码 %d" % error)


func _sanitize_value(key: String, value: Variant) -> Variant:
	match key:
		"aa_mode":
			var mode := str(value).to_lower()
			return mode if AA_MODES.has(mode) else "off"
		"msaa_3d", "msaa_2d":
			return clampi(int(value), 0, 3)
		"fsr2_scale":
			return clampf(float(value), 0.5, 1.0)
		"debanding_enabled":
			return bool(value)
		_:
			return value


func _apply_viewport_settings() -> void:
	var viewport := get_tree().root
	if viewport == null:
		return
	var aa_mode := str(values.get("aa_mode", "off"))
	viewport.screen_space_aa = _screen_space_aa_for_mode(aa_mode)
	viewport.use_taa = aa_mode == "taa"
	viewport.msaa_3d = int(values.get("msaa_3d", 2))
	viewport.msaa_2d = int(values.get("msaa_2d", 2))
	viewport.use_debanding = bool(values.get("debanding_enabled", false))
	if aa_mode == "fsr2":
		# FSR2 at a scale below 1.0 upscales the 3D buffer. At 1.0 it
		# becomes a native-resolution temporal AA solution.
		viewport.scaling_3d_mode = 2
		viewport.scaling_3d_scale = float(values.get("fsr2_scale", 0.77))
	else:
		viewport.scaling_3d_mode = 0
		viewport.scaling_3d_scale = 1.0


func _screen_space_aa_for_mode(aa_mode: String) -> int:
	match aa_mode:
		"fxaa":
			return 1
		"smaa":
			return 2
		_:
			return 0


func _on_scene_changed() -> void:
	# Scene changes replace map-local nodes but not this autoload or the root
	# viewport. Reapply both sides so settings are in place before gameplay.
	call_deferred("apply_settings")


func _apply_scene_post_process() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("WorldPostProcess", "ColorRect", true, false):
		_apply_to_post_process(node as ColorRect)
	for player in get_tree().get_nodes_in_group("human_players"):
		apply_to_player(player)


func _apply_to_post_process(world_post: ColorRect) -> void:
	if not is_instance_valid(world_post):
		return
	var material := world_post.material as ShaderMaterial
	if material == null:
		return
	for parameter in POST_PROCESS_PARAMETERS:
		if values.has(parameter):
			material.set_shader_parameter(parameter, values[parameter])
	# This value is deliberately runtime-only and is calculated from the active
	# player's speed/camera turn every frame.
	material.set_shader_parameter("motion_blur_amount", 0.0)
