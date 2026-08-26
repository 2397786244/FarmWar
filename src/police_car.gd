extends VehicleBase
class_name PoliceCar

const MESH_NODE_NAME := "Mesh"
const HEADLIGHT_MOUNT_NODE_NAME := "HeadLightPos"
const HEADLIGHT_LIGHT_NODE_NAME := "Light3D"
const HEADLIGHT_GLOW_NAMES := ["HeadlightGlow_L", "HeadlightGlow_R"]
const BRAKE_GLOW_NAMES := ["TailLightGlow_L", "TailLightGlow_R"]
const POLICE_LIGHT_BLUE_NODE_NAME := "PoliceLightbarGlow_Blue"
const POLICE_LIGHT_RED_NODE_NAME := "PoliceLightbarGlow_Red"

## The roof bar starts flashing as soon as the vehicle enters the scene tree.
@export_range(0.05, 2.0, 0.05) var police_light_flash_interval := 0.35

var headlights_on := false
var brake_lights_on := false
var police_light_blue_on := true

var _headlight_light: Light3D
var _headlight_glows: Array[Node3D] = []
var _brake_glows: Array[Node3D] = []
var _police_light_blue: MeshInstance3D
var _police_light_red: MeshInstance3D
var _police_light_glow_materials: Dictionary = {}
var _police_light_elapsed := 0.0


func _ready() -> void:
	super()
	_cache_police_light_nodes()
	_set_headlights(false)
	_set_brake_lights(false)
	_set_police_light_state(true)


func _process(delta: float) -> void:
	var interval := maxf(police_light_flash_interval, 0.05)
	_police_light_elapsed += maxf(delta, 0.0)
	while _police_light_elapsed >= interval:
		_police_light_elapsed -= interval
		_set_police_light_state(not police_light_blue_on)


func set_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
	super(throttle, steering, brake)
	# VehicleBase applies a full brake input to an empty vehicle so it stays
	# still. Only show the rear lamps when a driver is actually braking.
	_set_brake_lights(driver_peer_id > 0 and brake > 0.01)


func get_max_hp() -> float:
	return vehicle_config.max_hp if vehicle_config != null else 0.0


func get_network_state() -> Dictionary:
	var state := super()
	state["max_hp"] = get_max_hp()
	state["headlights_on"] = headlights_on
	state["brake_lights_on"] = brake_lights_on
	state["police_light_blue_on"] = police_light_blue_on
	return state


func apply_network_state(state: Dictionary) -> void:
	super(state)
	_set_headlights(bool(state.get("headlights_on", headlights_on)))
	_set_brake_lights(bool(state.get("brake_lights_on", brake_lights_on)))
	if state.has("police_light_blue_on"):
		_set_police_light_state(bool(state.get("police_light_blue_on", police_light_blue_on)))


func toggle_headlights() -> void:
	if GameAuthority.should_send_network_requests():
		return
	_set_headlights(not headlights_on)


func _cache_police_light_nodes() -> void:
	_headlight_glows.clear()
	_brake_glows.clear()
	_police_light_blue = null
	_police_light_red = null

	var mesh := get_node_or_null(MESH_NODE_NAME) as Node3D
	if mesh == null:
		push_error("PoliceCar: missing direct Mesh visual node.")
		return

	for node_name: String in HEADLIGHT_GLOW_NAMES:
		var glow := mesh.find_child(node_name, true, false) as Node3D
		if glow != null:
			_headlight_glows.append(glow)
		else:
			push_warning("PoliceCar: Mesh is missing %s." % node_name)

	for node_name: String in BRAKE_GLOW_NAMES:
		var glow := mesh.find_child(node_name, true, false) as Node3D
		if glow != null:
			_brake_glows.append(glow)
		else:
			push_warning("PoliceCar: Mesh is missing %s." % node_name)

	_police_light_blue = mesh.find_child(POLICE_LIGHT_BLUE_NODE_NAME, true, false) as MeshInstance3D
	_police_light_red = mesh.find_child(POLICE_LIGHT_RED_NODE_NAME, true, false) as MeshInstance3D
	if _police_light_blue == null:
		push_warning("PoliceCar: Mesh is missing %s." % POLICE_LIGHT_BLUE_NODE_NAME)
	if _police_light_red == null:
		push_warning("PoliceCar: Mesh is missing %s." % POLICE_LIGHT_RED_NODE_NAME)
	_cache_police_light_glow_materials(_police_light_blue)
	_cache_police_light_glow_materials(_police_light_red)

	_headlight_light = get_node_or_null(
		"%s/%s" % [HEADLIGHT_MOUNT_NODE_NAME, HEADLIGHT_LIGHT_NODE_NAME]
	) as Light3D
	if _headlight_light == null:
		push_warning("PoliceCar: missing %s below %s." % [
			HEADLIGHT_LIGHT_NODE_NAME,
			HEADLIGHT_MOUNT_NODE_NAME,
		])


func _set_headlights(enabled: bool) -> void:
	headlights_on = enabled
	_set_glow_nodes_visible(_headlight_glows, enabled)
	if is_instance_valid(_headlight_light):
		_headlight_light.visible = enabled


func _set_brake_lights(enabled: bool) -> void:
	brake_lights_on = enabled
	_set_glow_nodes_visible(_brake_glows, enabled)


func _set_police_light_state(blue_on: bool) -> void:
	police_light_blue_on = blue_on
	if is_instance_valid(_police_light_blue):
		# Keep the authored blue lens visible at all times. Only its emission
		# (the imported Glow effect) participates in the alternating flash.
		_police_light_blue.visible = true
		_set_police_light_glow(_police_light_blue, blue_on)
	if is_instance_valid(_police_light_red):
		# The inactive red lens keeps its base red albedo instead of disappearing.
		_police_light_red.visible = true
		_set_police_light_glow(_police_light_red, not blue_on)


func _cache_police_light_glow_materials(light: MeshInstance3D) -> void:
	if not is_instance_valid(light) or light.mesh == null:
		return
	var material_states: Array[Dictionary] = []
	var mesh_resource := light.mesh as Mesh
	if mesh_resource == null:
		return
	for surface_index in range(mesh_resource.get_surface_count()):
		var source_material := mesh_resource.surface_get_material(surface_index) as BaseMaterial3D
		if source_material == null:
			continue
		var unique_material := source_material.duplicate() as BaseMaterial3D
		if unique_material == null:
			continue
		light.set_surface_override_material(surface_index, unique_material)
		material_states.append({
			"material": unique_material,
			"emission_enabled": source_material.emission_enabled,
			"emission": source_material.emission,
			"emission_energy_multiplier": source_material.emission_energy_multiplier,
		})
	_police_light_glow_materials[light.get_instance_id()] = material_states


func _set_police_light_glow(light: MeshInstance3D, enabled: bool) -> void:
	if not is_instance_valid(light):
		return
	var material_states: Variant = _police_light_glow_materials.get(light.get_instance_id(), [])
	if not material_states is Array:
		return
	for state_value: Variant in material_states:
		var state := state_value as Dictionary
		var material := state.get("material") as BaseMaterial3D
		if material == null:
			continue
		var authored_emission_enabled := bool(state.get("emission_enabled", true))
		material.emission_enabled = enabled and authored_emission_enabled
		if enabled and authored_emission_enabled:
			var emission_value: Variant = state.get("emission", Color.WHITE)
			if emission_value is Color:
				material.emission = emission_value as Color
			material.emission_energy_multiplier = float(
				state.get("emission_energy_multiplier", 1.0)
			)


func _set_glow_nodes_visible(glows: Array[Node3D], enabled: bool) -> void:
	for glow in glows:
		if is_instance_valid(glow):
			glow.visible = enabled
