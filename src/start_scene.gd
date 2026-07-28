extends Node3D
class_name StartSceneShowcase

signal transition_alpha_changed(alpha: float)

const SHOWCASE_CHARACTER := preload("res://ui/showcase_character.tscn")
const HERO_TOOLS_PATH := "res://data/hero_special_tools.json"
const TOOL_DEFINITIONS_PATH := "res://data/tool_definitions.json"

const HERO_ORDER: Array[String] = [
	"farmer",
	"cook",
	"guard",
	"apothecary",
	"assistant",
	"engineer",
	"mage",
	"prospector",
	"rider",
	"trickster",
]

const CHARACTER_SCENES := {
	"farmer": "res://character/hero_skeleton/farmer_red.tscn",
	"cook": "res://character/hero_skeleton/cook_red.tscn",
	"guard": "res://character/hero_skeleton/guard_red.tscn",
	"apothecary": "res://character/hero_skeleton/apothecary_red.tscn",
	"assistant": "res://character/hero_skeleton/assistant_red.tscn",
	"engineer": "res://character/hero_skeleton/engineer_red.tscn",
	"mage": "res://character/hero_skeleton/mage_red.tscn",
	"prospector": "res://character/hero_skeleton/prospector_red.tscn",
	"rider": "res://character/hero_skeleton/rider_red.tscn",
	"trickster": "res://character/hero_skeleton/trickster_red.tscn",
}

# These tools are deployed into the world instead of being used from the hand.
const PLACED_TOOL_IDS := {
	"plant_protector": true,
	"anti_air": true,
	"normal_drone": true,
	"signal_jam": true,
	"signal_augment": true,
	"big_mouth": true,
}

const FLOOR_PROP_TRANSFORMS := {
	"plant_protector": {
		"position": Vector3(1.55, 0.0, 0.25),
		"rotation": Vector3(0.0, -18.0, 0.0),
		"scale": Vector3.ONE,
	},
	"anti_air": {
		"position": Vector3(1.65, 0.0, 0.2),
		"rotation": Vector3(0.0, -22.0, 0.0),
		"scale": Vector3.ONE,
	},
	"normal_drone": {
		"position": Vector3(1.5, 0.18, 0.3),
		"rotation": Vector3(0.0, -18.0, 0.0),
		"scale": Vector3.ONE,
	},
	"signal_jam": {
		"position": Vector3(1.65, 0.0, -0.25),
		"rotation": Vector3(0.0, -15.0, 0.0),
		"scale": Vector3.ONE * 0.82,
	},
	"signal_augment": {
		"position": Vector3(1.65, 0.0, -0.25),
		"rotation": Vector3(0.0, -15.0, 0.0),
		"scale": Vector3.ONE * 0.82,
	},
	"big_mouth": {
		"position": Vector3(1.45, 0.0, 0.3),
		"rotation": Vector3(0.0, 180.0, 0.0),
		"scale": Vector3.ONE * 0.5,
	},
}

const SHOWCASE_DURATION := 10
const FADE_DURATION := 1.0
const DARK_HOLD_DURATION := 2.0
const CAMERA_MOVE_DURATION := 6.0
const CAMERA_START := Vector3(5.2, 2.85, 9.4)
const CAMERA_END := Vector3(3.9, 2.35, 6.8)
const CAMERA_TARGET := Vector3(0.8, 1.35, 0.0)

@onready var showcase_anchor: Node3D = $ShowcaseAnchor
@onready var studio_camera: Camera3D = $StudioCamera
@onready var key_light: SpotLight3D = $Lights/KeyLight
@onready var fill_light: SpotLight3D = $Lights/FillLight
@onready var rim_light: SpotLight3D = $Lights/RimLight

var transition_alpha := 0.0:
	set(value):
		transition_alpha = clampf(value, 0.0, 1.0)
		transition_alpha_changed.emit(transition_alpha)

var _showcase_profiles: Array[Dictionary] = []
var _current_showcase: ShowcaseCharacter
var _current_profile_index := 0
var _camera_tween: Tween
var _light_time := 0.0
var _light_phase := 0.0


func _ready() -> void:
	_light_phase = randf_range(0.0, TAU)
	_showcase_profiles = _build_showcase_profiles()
	_aim_studio_nodes()
	studio_camera.current = true
	transition_alpha = 0.0
	if _showcase_profiles.is_empty():
		push_error("No valid main-menu showcase profiles were found.")
		return
	_show_profile(0)
	_run_showcase_cycle()


func _process(delta: float) -> void:
	_light_time += delta
	studio_camera.look_at(CAMERA_TARGET, Vector3.UP)
	var slow_wave := (sin(_light_time * 0.22 + _light_phase) + 1.0) * 0.5
	var rim_wave := (sin(_light_time * 0.17 + _light_phase + 1.7) + 1.0) * 0.5
	fill_light.light_color = Color("78a8ff").lerp(Color("79d8bc"), slow_wave)
	rim_light.light_color = Color("ffb45f").lerp(Color("f18ac5"), rim_wave)
	fill_light.light_energy = lerpf(2.6, 3.15, slow_wave)
	rim_light.light_energy = lerpf(3.8, 4.5, rim_wave)


func _run_showcase_cycle() -> void:
	while is_inside_tree():
		await get_tree().create_timer(SHOWCASE_DURATION).timeout
		if not is_inside_tree():
			return
		await _fade_to(1.0)
		if not is_inside_tree():
			return
		await get_tree().create_timer(DARK_HOLD_DURATION).timeout
		if not is_inside_tree():
			return
		_current_profile_index = (_current_profile_index + 1) % _showcase_profiles.size()
		_show_profile(_current_profile_index)
		await _fade_to(0.0)


func _fade_to(target_alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "transition_alpha", target_alpha, FADE_DURATION)
	await tween.finished


func _show_profile(profile_index: int) -> void:
	if is_instance_valid(_current_showcase):
		_current_showcase.free()
	var showcase := SHOWCASE_CHARACTER.instantiate() as ShowcaseCharacter
	showcase_anchor.add_child(showcase)
	_current_showcase = showcase
	showcase.setup(_showcase_profiles[profile_index])
	_start_camera_move()


func _start_camera_move() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	studio_camera.position = CAMERA_START
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(
		studio_camera,
		"position",
		CAMERA_END,
		CAMERA_MOVE_DURATION
	)


func _build_showcase_profiles() -> Array[Dictionary]:
	var hero_data := _load_json_dictionary(HERO_TOOLS_PATH)
	var definition_data := _load_json_dictionary(TOOL_DEFINITIONS_PATH)
	var heroes: Dictionary = hero_data.get("heroes", {}) as Dictionary
	var definitions_by_id := _tool_definitions_by_id(
		definition_data.get("tools", []) as Array
	)
	var profiles: Array[Dictionary] = []
	for hero_id in HERO_ORDER:
		var tool_ids: Array = heroes.get(hero_id, []) as Array
		if tool_ids.is_empty():
			push_warning("Showcase hero has no special tools: %s" % hero_id)
			continue
		var tool_id := str(tool_ids[0])
		var definition: Dictionary = definitions_by_id.get(tool_id, {}) as Dictionary
		var prop_path := str(definition.get("path", ""))
		var character_path := str(CHARACTER_SCENES.get(hero_id, ""))
		if character_path.is_empty() or prop_path.is_empty():
			push_warning("Showcase profile is incomplete: %s / %s" % [hero_id, tool_id])
			continue
		profiles.append(_make_showcase_profile(
			hero_id,
			tool_id,
			character_path,
			prop_path,
			definition
		))
	return profiles


func _make_showcase_profile(
		hero_id: String,
		tool_id: String,
		character_path: String,
		prop_path: String,
		definition: Dictionary
) -> Dictionary:
	var is_placed := PLACED_TOOL_IDS.has(tool_id)
	var profile := {
		"hero_id": hero_id,
		"tool_id": tool_id,
		"character": character_path,
		"prop": prop_path,
		"prop_mode": "floor" if is_placed else "hand",
	}
	if is_placed:
		var floor_transform: Dictionary = FLOOR_PROP_TRANSFORMS.get(
			tool_id,
			{}
		) as Dictionary
		profile["prop_position"] = floor_transform.get(
			"position",
			Vector3(1.5, 0.0, 0.25)
		)
		profile["prop_rotation"] = floor_transform.get("rotation", Vector3.ZERO)
		profile["prop_scale"] = floor_transform.get("scale", Vector3.ONE)
	else:
		profile["prop_position"] = _array_to_vector3(
			definition.get("grip_position", []),
			Vector3.ZERO
		)
		profile["prop_rotation"] = _array_to_vector3(
			definition.get("grip_rotation", []),
			Vector3.ZERO
		)
		profile["prop_scale"] = _array_to_vector3(
			definition.get("grip_scale", []),
			Vector3.ONE
		)
	return profile


func _tool_definitions_by_id(definitions: Array) -> Dictionary:
	var result := {}
	for value in definitions:
		if value is Dictionary:
			var definition := value as Dictionary
			var tool_id := str(definition.get("id", ""))
			if not tool_id.is_empty():
				result[tool_id] = definition
	return result


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Main-menu showcase data is missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open main-menu showcase data: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Invalid main-menu showcase JSON: %s" % path)
		return {}
	return parsed as Dictionary


func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var values := value as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


func _aim_studio_nodes() -> void:
	key_light.look_at(CAMERA_TARGET, Vector3.UP)
	fill_light.look_at(CAMERA_TARGET, Vector3.UP)
	rim_light.look_at(CAMERA_TARGET, Vector3.UP)
