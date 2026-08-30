extends VehicleBase
class_name FirePickup

const MESH_NODE_NAME := "Mesh"
const HEADLIGHT_MOUNT_NODE_NAME := "HeadLightPos"
const HEADLIGHT_LIGHT_NODE_NAME := "Light3D"
const HEADLIGHT_GLOW_NAMES := ["HeadlightGlow_L", "HeadlightGlow_R"]
const BRAKE_GLOW_NAMES := ["TailLightGlow_L", "TailLightGlow_R"]

var headlights_on := false
var brake_lights_on := false

var _headlight_light: Light3D
var _headlight_glows: Array[Node3D] = []
var _brake_glows: Array[Node3D] = []


func _ready() -> void:
	super()
	_cache_fire_pickup_nodes()
	_set_headlights(false)
	_set_brake_lights(false)


func set_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
	super(throttle, steering, brake)
	# VehicleBase applies a full brake input to an empty vehicle so it stays
	# still. Only show the rear lamps when a driver is actually braking.
	_set_brake_lights(driver_peer_id > 0 and brake > 0.01)


func get_max_hp() -> float:
	return super()


func get_network_state() -> Dictionary:
	var state := super()
	state["max_hp"] = get_max_hp()
	state["headlights_on"] = headlights_on
	state["brake_lights_on"] = brake_lights_on
	return state


func apply_network_state(state: Dictionary) -> void:
	super(state)
	_set_headlights(bool(state.get("headlights_on", headlights_on)))
	_set_brake_lights(bool(state.get("brake_lights_on", brake_lights_on)))


func toggle_headlights() -> void:
	if GameAuthority.should_send_network_requests():
		return
	_set_headlights(not headlights_on)


func _cache_fire_pickup_nodes() -> void:
	_headlight_glows.clear()
	_brake_glows.clear()

	var mesh := get_node_or_null(MESH_NODE_NAME) as Node3D
	if mesh == null:
		push_error("FirePickup: missing direct Mesh visual node.")
		return

	for node_name: String in HEADLIGHT_GLOW_NAMES:
		var glow := mesh.find_child(node_name, true, false) as Node3D
		if glow != null:
			_headlight_glows.append(glow)
		else:
			push_warning("FirePickup: Mesh is missing %s." % node_name)

	for node_name: String in BRAKE_GLOW_NAMES:
		var glow := mesh.find_child(node_name, true, false) as Node3D
		if glow != null:
			_brake_glows.append(glow)
		else:
			push_warning("FirePickup: Mesh is missing %s." % node_name)

	var headlight_mount := find_child(HEADLIGHT_MOUNT_NODE_NAME, true, false) as Node3D
	if headlight_mount == null:
		push_error("FirePickup: missing recursive %s marker." % HEADLIGHT_MOUNT_NODE_NAME)
		return
	_headlight_light = headlight_mount.find_child(HEADLIGHT_LIGHT_NODE_NAME, true, false) as Light3D
	if _headlight_light == null:
		push_error("FirePickup: missing %s below %s." % [
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


func _set_glow_nodes_visible(glows: Array[Node3D], enabled: bool) -> void:
	for glow in glows:
		if is_instance_valid(glow):
			glow.visible = enabled
