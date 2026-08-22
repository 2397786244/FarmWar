extends VehicleBase
class_name FarmBaseVehicle

## The imported model calls these nodes BrakeGlow, while the original vehicle
## setup notes used the spelling BakeGlow. Support both names so the vehicle
## remains usable if the imported scene is corrected later.
const BRAKE_GLOW_NAMES := [
	["BakeGlow_Left", "BrakeGlow_Left"],
	["BakeGlow_Right", "BrakeGlow_Right"],
]
const HEADLIGHT_GLOW_NAMES := [
	["HeadlightGlow_Left", ""],
	["HeadlightGlow_Right", ""],
]
const HEADLIGHT_MOUNT_NAMES := ["Headlamp_Left", "Headlamp_Right"]
const HEADLIGHT_LIGHT_NAMES := ["HeadlightLight_Left", "HeadlightLight_Right"]
const HEADLIGHT_ENERGY := 15.0
const HEADLIGHT_RANGE := 12.0
const HEADLIGHT_ANGLE := 60.0
const HEADLIGHT_ATTENUATION := 1.35
const ROOF_HEADLIGHTS_SCENE := preload("res://assets/vehicles/RoofHeadlights.glb")
const ROOF_HEADLIGHT_MOUNT_NODE_NAME := "RoofHeadlights"
const ROOF_HEADLIGHT_VISUAL_NODE_NAME := "RoofHeadlights"
const ROOF_HEADLIGHT_GLOW_NAMES := ["Glow_Left", "Glow_Right"]
const ROOF_HEADLIGHT_LIGHT_NAMES := ["RoofHeadlightLight_Left", "RoofHeadlightLight_Right"]
const ROOF_HEADLIGHT_ENERGY := HEADLIGHT_ENERGY * 1.6
const ROOF_HEADLIGHT_RANGE := 30.0
const ROOF_HEADLIGHT_ANGLE := 35.0
const BODY_MESH_NODE_NAME := "FTF_Vehicle_ModularFarmBase_Black_6_5m_Static"
const BASE_MESH_SCENE_PATH := "res://assets/vehicles/ModularFarmBaseVehicle.glb"
const REINFORCED_MESH_SCENE_PATH := "res://assets/vehicles/ModularFarmBaseVehicle_Defend.glb"
const REINFORCED_HP_MULTIPLIER := 1.5
const WHEEL_MESH_NODE_NAMES := [
	"Wheel_FL_Mesh",
	"Wheel_FR_Mesh",
	"Wheel_RL_Mesh",
	"Wheel_RR_Mesh",
]
const PLATFORM_MACHINE_GUN_SCENE := preload("res://vehicles/vehicle_base_machine_gun.tscn")
const PLATFORM_SEAT_SCENE := preload("res://assets/vehicles/PlatformSeat.glb")
const PLATFORM_INTERACTION_AREA_SCRIPT := preload("res://src/vehicle_platform_interaction_area.gd")
const HARVEST_REEL_SCENE := preload("res://vehicles/HarvestReel.tscn")
const HARVEST_REEL_MOUNT_NODE_NAME := "HarvestReelPos"
const HARVEST_REEL_NODE_NAME := "HarvestReel"
const PLATFORM_PASSENGER_SEAT_MARKER_NAMES := ["PlatformSeat1", "PlatformSeat2"]
const PLATFORM_PASSENGER_SEAT_POSITION_NODE_NAME := "SeatPos"
const PLATFORM_PASSENGER_SEAT_START_INDEX := 1
const MAX_PLATFORM_PASSENGER_SEATS := 2
const NITRO_BOOST_SCRIPT := preload("res://src/nitro_boost.gd")
const NITRO_BOOST_VISUAL_SCENE := preload("res://assets/vehicles/VehicleNitroBoost.glb")
const NITRO_BOOST_MAX_FORWARD_SPEED := 8.0
const NITRO_BOOST_SPEED_MULTIPLIER := 2.0
const NITRO_BOOST_MOUNT_NODE_NAME := "NitroBoostPos"
const NITRO_BOOST_CONTROLLER_NODE_NAME := "NitroBoostController"
const NITRO_BOOST_VISUAL_NODE_NAME := "VehicleNitroBoost"

## These are instance properties so two FarmBaseVehicle nodes can use
## different combinations when they share the same imported model scene.
@export var body_color := Color("000000")
@export var wheel_color := Color("000000")
@export var platform_machine_gun_installed := false
@export_range(0, 2, 1) var platform_passenger_seat_count := 0
@export var reinforced_variant := false
@export var nitro_boost_installed := false
@export var harvest_reel_installed := false
@export var roof_headlights_installed := false

var headlights_on := false
var brake_lights_on := false
var _brake_glows: Array[Node3D] = []
var _headlight_glows: Array[Node3D] = []
var _headlight_lights: Array[SpotLight3D] = []
var _roof_headlights_visual: Node3D
var _roof_headlight_glows: Array[Node3D] = []
var _roof_headlight_lights: Array[SpotLight3D] = []
var _platform_machine_gun: VehicleBaseMachineGun
var _platform_interaction_area: VehiclePlatformInteractionArea
var _platform_passenger_interaction_area: VehiclePlatformInteractionArea
var _platform_passenger_seat_definitions: Array[VehicleSeatConfig] = []
var _platform_passenger_seats_configured_count := -1
var _platform_passenger_seat_runtime_ready := false
var _nitro_boost: NitroBoost
var _harvest_reel: HarvestReel
var _base_vehicle_config: VehicleConfig


func _ready() -> void:
	_prepare_effective_vehicle_config()
	_ensure_mesh_variant()
	set_platform_passenger_seat_count(platform_passenger_seat_count)
	super()
	_cache_glow_nodes()
	_cache_headlight_lights()
	_set_headlights(false)
	_set_brake_lights(false)
	refresh_visuals()
	_ensure_platform_interaction_area()
	_ensure_platform_passenger_interaction_area()
	set_platform_machine_gun_installed(platform_machine_gun_installed)
	set_nitro_boost_installed(nitro_boost_installed)
	set_harvest_reel_installed(harvest_reel_installed)
	set_roof_headlights_installed(roof_headlights_installed)
	_platform_passenger_seat_runtime_ready = true


func refresh_visuals() -> void:
	_prepare_effective_vehicle_config()
	_ensure_mesh_variant()
	_configure_platform_passenger_seats()
	set_body_color(body_color)
	set_wheel_color(wheel_color)
	set_platform_machine_gun_installed(platform_machine_gun_installed)
	set_nitro_boost_installed(nitro_boost_installed)
	set_harvest_reel_installed(harvest_reel_installed)
	set_roof_headlights_installed(roof_headlights_installed)


func set_reinforced_variant(enabled: bool) -> void:
	var previous_max_hp := get_max_hp()
	var previous_hp := current_hp
	var was_initialized := is_inside_tree() and vehicle_config != null
	reinforced_variant = enabled
	_prepare_effective_vehicle_config()
	_ensure_mesh_variant()
	# Reapply both instance-level paints after the Mesh scene is swapped. The
	# reinforced DefenseNet keeps its authored GLB material because
	# set_body_color only targets BODY_MESH_NODE_NAME.
	set_body_color(body_color)
	set_wheel_color(wheel_color)
	if not was_initialized:
		return
	var next_max_hp := get_max_hp()
	if previous_max_hp > 0.0 and previous_hp > 0.0:
		current_hp = clampf(
			previous_hp / previous_max_hp * next_max_hp,
			0.0,
			next_max_hp
		)
	elif previous_max_hp <= 0.0 and previous_hp > 0.0:
		current_hp = next_max_hp
	else:
		current_hp = 0.0
	_last_available_cargo_slots = get_available_cargo_slot_count()
	_refresh_cargo_visuals()


## Add one or two rear platform seats.  The default scene has no passenger
## seats; map placement and a future vehicle upgrade platform can call this
## function to add the requested number.
func add_platform_passenger_seats(count: int = MAX_PLATFORM_PASSENGER_SEATS) -> int:
	return set_platform_passenger_seat_count(count)


func set_platform_passenger_seat_count(count: int) -> int:
	platform_passenger_seat_count = clampi(count, 0, MAX_PLATFORM_PASSENGER_SEATS)
	_configure_platform_passenger_seats()
	if _platform_passenger_seat_runtime_ready:
		_cache_seat_anchors()
		_ensure_platform_passenger_interaction_area()
	return _platform_passenger_seat_definitions.size()


func _configure_platform_passenger_seats() -> void:
	var requested_count := clampi(platform_passenger_seat_count, 0, MAX_PLATFORM_PASSENGER_SEATS)
	platform_passenger_seat_count = requested_count
	if _platform_passenger_seats_configured_count == requested_count:
		return
	_platform_passenger_seat_definitions.clear()
	var active_marker_count := 0
	for marker_index in range(PLATFORM_PASSENGER_SEAT_MARKER_NAMES.size()):
		var marker_name: String = PLATFORM_PASSENGER_SEAT_MARKER_NAMES[marker_index]
		var marker := find_child(marker_name, true, false) as Marker3D
		if marker == null:
			continue
		var is_active := active_marker_count < requested_count
		var visual_name := "PlatformSeatVisual%d" % (marker_index + 1)
		var visual := marker.find_child(visual_name, true, false) as Node3D
		if visual == null and is_active:
			visual = PLATFORM_SEAT_SCENE.instantiate() as Node3D
			if visual != null:
				visual.name = visual_name
				marker.add_child(visual)
				visual.transform = Transform3D.IDENTITY
		if visual != null:
			# The GLB is authored facing +Z. Keep its local transform unchanged so
			# the seat and the occupant both face the rear of the vehicle.
			visual.visible = is_active
		if is_active:
			var seat := VehicleSeatConfig.new()
			seat.seat_id = "platform_passenger_%d" % (active_marker_count + 1)
			seat.anchor_name = marker_name
			seat.can_drive = false
			seat.show_occupant = true
			seat.occupant_rotation_degrees = Vector3(0.0, 180.0, 0.0)
			# SeatPos is the authored seat contact marker. Keep the dynamic seat's
			# specific root-to-hip offset at zero; VehicleSeatConfig applies the
			# shared seated_position_offset to every driver and passenger seat.
			seat.occupant_offset = Vector3.ZERO
			_platform_passenger_seat_definitions.append(seat)
		active_marker_count += 1
	_platform_passenger_seats_configured_count = requested_count


func get_platform_passenger_seat_indices() -> Array[int]:
	_configure_platform_passenger_seats()
	var indices: Array[int] = []
	for offset in range(_platform_passenger_seat_definitions.size()):
		indices.append(PLATFORM_PASSENGER_SEAT_START_INDEX + offset)
	return indices


func is_platform_passenger_seat(seat_index: int) -> bool:
	_configure_platform_passenger_seats()
	return seat_index >= PLATFORM_PASSENGER_SEAT_START_INDEX \
			and seat_index < PLATFORM_PASSENGER_SEAT_START_INDEX + _platform_passenger_seat_definitions.size()


func get_available_platform_passenger_seat_index() -> int:
	for seat_index in get_platform_passenger_seat_indices():
		if not seat_occupants.has(seat_index):
			return seat_index
	return -1


func can_enter_platform_passenger(peer_id: int, requested_seat_index: int = -1) -> bool:
	var seat_index := get_available_platform_passenger_seat_index() \
			if requested_seat_index < 0 else requested_seat_index
	return is_platform_passenger_seat(seat_index) and can_enter_seat(peer_id, seat_index)


func get_max_hp() -> float:
	return vehicle_config.max_hp if vehicle_config != null else 0.0


func get_max_forward_speed() -> float:
	if nitro_boost_installed:
		return NITRO_BOOST_MAX_FORWARD_SPEED
	return super()


func get_max_reverse_speed() -> float:
	if nitro_boost_installed:
		return super() * NITRO_BOOST_SPEED_MULTIPLIER
	return super()


func _prepare_effective_vehicle_config() -> void:
	if vehicle_config == null:
		return
	if _base_vehicle_config == null:
		_base_vehicle_config = vehicle_config
	if not reinforced_variant:
		vehicle_config = _base_vehicle_config
		return
	var reinforced_config := _base_vehicle_config.duplicate(true) as VehicleConfig
	if reinforced_config == null:
		return
	reinforced_config.max_hp = _base_vehicle_config.max_hp * REINFORCED_HP_MULTIPLIER
	vehicle_config = reinforced_config


func _ensure_mesh_variant() -> void:
	var current_mesh := find_child("Mesh", true, false) as Node3D
	if current_mesh == null:
		push_warning("FarmBaseVehicle: missing recursive Mesh node.")
		return
	var requested_path := REINFORCED_MESH_SCENE_PATH if reinforced_variant else BASE_MESH_SCENE_PATH
	var current_path := str(current_mesh.get_meta("farm_base_mesh_scene_path", ""))
	if current_path.is_empty():
		current_path = BASE_MESH_SCENE_PATH
	if current_path == requested_path:
		current_mesh.set_meta("farm_base_mesh_scene_path", requested_path)
		return
	var packed := load(requested_path) as PackedScene
	if packed == null:
		push_error("FarmBaseVehicle: failed to load mesh variant %s." % requested_path)
		return
	var replacement := packed.instantiate() as Node3D
	if replacement == null:
		push_error("FarmBaseVehicle: mesh variant is not Node3D: %s" % requested_path)
		return
	var parent := current_mesh.get_parent()
	if parent == null:
		replacement.free()
		push_error("FarmBaseVehicle: Mesh node has no parent and cannot be replaced.")
		return
	var child_index := current_mesh.get_index()
	var mesh_transform := current_mesh.transform
	var mesh_visible := current_mesh.visible
	parent.remove_child(current_mesh)
	replacement.name = "Mesh"
	replacement.transform = mesh_transform
	replacement.visible = mesh_visible
	replacement.set_meta("farm_base_mesh_scene_path", requested_path)
	parent.add_child(replacement)
	parent.move_child(replacement, child_index)
	if current_mesh.is_inside_tree():
		current_mesh.queue_free()
	else:
		current_mesh.free()
	body_visual = replacement
	_cache_visual_nodes()
	_cache_glow_nodes()
	_cache_headlight_lights()
	_cache_roof_headlights()
	_set_headlights(headlights_on)
	_set_brake_lights(brake_lights_on)


func set_platform_machine_gun_installed(installed: bool) -> void:
	platform_machine_gun_installed = installed
	if not is_inside_tree():
		return
	if installed:
		install_platform_machine_gun(false)
	else:
		remove_platform_machine_gun()


func install_platform_machine_gun(reset_health := true) -> VehicleBaseMachineGun:
	platform_machine_gun_installed = true
	if is_instance_valid(_platform_machine_gun):
		if reset_health and _platform_machine_gun.destroyed_state:
			_platform_machine_gun.current_hp = VehicleBaseMachineGun.MAX_HP
			_platform_machine_gun.set_destroyed_state(false)
		return _platform_machine_gun
	var existing := find_child("VehicleBaseMachineGun", true, false) as VehicleBaseMachineGun
	if existing != null:
		_platform_machine_gun = existing
		if reset_health and existing.destroyed_state:
			existing.current_hp = VehicleBaseMachineGun.MAX_HP
			existing.set_destroyed_state(false)
		return existing
	var mount := find_child("PlatformMachineGunPos", true, false) as Marker3D
	if mount == null:
		push_error("FarmBaseVehicle: missing recursive PlatformMachineGunPos marker.")
		return null
	var machine_gun := PLATFORM_MACHINE_GUN_SCENE.instantiate() as VehicleBaseMachineGun
	if machine_gun == null:
		push_error("FarmBaseVehicle: failed to instantiate platform machine gun.")
		return null
	machine_gun.name = "VehicleBaseMachineGun"
	mount.add_child(machine_gun)
	machine_gun.transform = Transform3D.IDENTITY
	_platform_machine_gun = machine_gun
	return machine_gun


func remove_platform_machine_gun() -> void:
	platform_machine_gun_installed = false
	var machine_gun := get_platform_machine_gun()
	if machine_gun == null:
		return
	var former_operator := machine_gun.operator_peer_id
	machine_gun.operator_peer_id = 0
	if former_operator > 0 and (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		GameAuthority.force_release_mounted_machine_gun(former_operator, get_vehicle_id())
	var parent := machine_gun.get_parent()
	if parent != null:
		parent.remove_child(machine_gun)
	machine_gun.queue_free()
	_platform_machine_gun = null


func get_platform_machine_gun() -> VehicleBaseMachineGun:
	if is_instance_valid(_platform_machine_gun):
		return _platform_machine_gun
	_platform_machine_gun = find_child("VehicleBaseMachineGun", true, false) as VehicleBaseMachineGun
	return _platform_machine_gun


func on_platform_machine_gun_destroyed(former_operator_peer_id: int) -> void:
	if former_operator_peer_id > 0 and (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		GameAuthority.force_release_mounted_machine_gun(former_operator_peer_id, get_vehicle_id())


func set_harvest_reel_installed(installed: bool) -> void:
	harvest_reel_installed = installed
	if installed:
		install_harvest_reel()
	else:
		remove_harvest_reel()


func install_harvest_reel() -> HarvestReel:
	harvest_reel_installed = true
	if is_instance_valid(_harvest_reel):
		return _harvest_reel
	var existing := find_child(HARVEST_REEL_NODE_NAME, true, false) as HarvestReel
	if existing != null:
		_harvest_reel = existing
		return existing
	var mount := find_child(HARVEST_REEL_MOUNT_NODE_NAME, true, false) as Marker3D
	if mount == null:
		push_error("FarmBaseVehicle: missing recursive %s marker." % HARVEST_REEL_MOUNT_NODE_NAME)
		return null
	var reel := HARVEST_REEL_SCENE.instantiate() as HarvestReel
	if reel == null:
		push_error("FarmBaseVehicle: failed to instantiate HarvestReel.")
		return null
	reel.name = HARVEST_REEL_NODE_NAME
	mount.add_child(reel)
	reel.transform = Transform3D.IDENTITY
	_harvest_reel = reel
	return reel


func remove_harvest_reel() -> void:
	harvest_reel_installed = false
	var reel := get_harvest_reel()
	if reel == null:
		return
	var parent := reel.get_parent()
	if parent != null:
		parent.remove_child(reel)
	reel.queue_free()
	_harvest_reel = null


func get_harvest_reel() -> HarvestReel:
	if is_instance_valid(_harvest_reel):
		return _harvest_reel
	_harvest_reel = find_child(HARVEST_REEL_NODE_NAME, true, false) as HarvestReel
	return _harvest_reel


## RoofHeadlights is an optional FarmBaseVehicle upgrade. The authored
## visual is kept below the recursive RoofHeadlights marker and remains hidden
## until the upgrade is installed.
func set_roof_headlights_installed(installed: bool) -> void:
	roof_headlights_installed = installed
	var visual := _ensure_roof_headlights_visual()
	if visual == null:
		return
	_cache_roof_headlights()
	_set_roof_headlights_visuals(headlights_on)


func install_roof_headlights() -> Node3D:
	roof_headlights_installed = true
	var visual := _ensure_roof_headlights_visual()
	if visual == null:
		return null
	_cache_roof_headlights()
	_set_roof_headlights_visuals(headlights_on)
	return visual


func remove_roof_headlights() -> void:
	roof_headlights_installed = false
	_cache_roof_headlights()
	_set_roof_headlights_visuals(false)


func get_roof_headlights() -> Node3D:
	if is_instance_valid(_roof_headlights_visual):
		return _roof_headlights_visual
	var mount := find_child(ROOF_HEADLIGHT_MOUNT_NODE_NAME, true, false) as Marker3D
	if mount == null:
		return null
	_roof_headlights_visual = mount.find_child(
		ROOF_HEADLIGHT_VISUAL_NODE_NAME,
		true,
		false
	) as Node3D
	return _roof_headlights_visual


func _ensure_roof_headlights_visual() -> Node3D:
	var existing := get_roof_headlights()
	if existing != null:
		return existing
	var mount := find_child(ROOF_HEADLIGHT_MOUNT_NODE_NAME, true, false) as Marker3D
	if mount == null:
		push_error("FarmBaseVehicle: missing recursive %s marker." % ROOF_HEADLIGHT_MOUNT_NODE_NAME)
		return null
	var visual := ROOF_HEADLIGHTS_SCENE.instantiate() as Node3D
	if visual == null:
		push_error("FarmBaseVehicle: failed to instantiate RoofHeadlights visual.")
		return null
	visual.name = ROOF_HEADLIGHT_VISUAL_NODE_NAME
	mount.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	_roof_headlights_visual = visual
	return visual


func _cache_roof_headlights() -> void:
	_roof_headlight_glows.clear()
	_roof_headlight_lights.clear()
	var visual := get_roof_headlights()
	_roof_headlights_visual = visual
	if visual == null:
		return
	# Prefer the authored Mesh wrapper when one exists. The current imported
	# RoofHeadlights GLB has its model root directly below the scene root, so
	# use the visual as the recursive search root in that valid layout too.
	var mesh := visual.find_child("Mesh", true, false) as Node3D
	var glow_search_root: Node = mesh if mesh != null else visual
	for index in range(ROOF_HEADLIGHT_GLOW_NAMES.size()):
		var glow := glow_search_root.find_child(
			ROOF_HEADLIGHT_GLOW_NAMES[index],
			true,
			false
		) as Node3D
		if glow == null:
			push_warning("FarmBaseVehicle: missing RoofHeadlights glow %s." % ROOF_HEADLIGHT_GLOW_NAMES[index])
			continue
		_roof_headlight_glows.append(glow)
		var light_name: String = ROOF_HEADLIGHT_LIGHT_NAMES[index]
		var light := glow.find_child(light_name, true, false) as SpotLight3D
		if light == null:
			light = SpotLight3D.new()
			light.name = light_name
			glow.add_child(light)
		# SpotLight3D emits along local -Z. Place each light just in front of
		# its Glow, then explicitly aim that -Z axis at the vehicle's -Z front
		# direction instead of relying on the imported GLB's local orientation.
		if is_inside_tree() and glow.is_inside_tree():
			var vehicle_front := -global_transform.basis.z.normalized()
			light.global_position = glow.global_position + vehicle_front * 0.2
			light.global_basis = Basis.looking_at(vehicle_front, Vector3.UP)
		else:
			# The preview is configured before it enters the scene tree. Its
			# authored mount points +Z toward the vehicle's -Z front, and the
			# ready-time pass reapplies the explicit global orientation.
			light.position = Vector3(0.0, 0.0, 0.2)
			light.rotation = Vector3(0.0, PI, 0.0)
		light.light_color = Color(1.0, 0.97, 0.88, 1.0)
		light.light_energy = ROOF_HEADLIGHT_ENERGY
		light.light_indirect_energy = 0.0
		light.spot_range = ROOF_HEADLIGHT_RANGE
		light.spot_attenuation = HEADLIGHT_ATTENUATION
		light.spot_angle = ROOF_HEADLIGHT_ANGLE
		light.shadow_enabled = false
		light.visible = false
		_roof_headlight_lights.append(light)


func _set_roof_headlights_visuals(headlight_switch_enabled: bool) -> void:
	var visual := get_roof_headlights()
	if visual != null:
		visual.visible = roof_headlights_installed
	var enabled := roof_headlights_installed and headlight_switch_enabled
	_set_glow_nodes_visible(_roof_headlight_glows, enabled)
	for light in _roof_headlight_lights:
		if is_instance_valid(light):
			light.visible = enabled
			light.light_energy = ROOF_HEADLIGHT_ENERGY if enabled else 0.0


func set_nitro_boost_installed(installed: bool) -> void:
	nitro_boost_installed = installed
	if installed:
		_ensure_nitro_boost_visual()
	_set_nitro_boost_visual_visible(installed)
	if not is_inside_tree():
		return
	if installed:
		install_nitro_boost()
	else:
		remove_nitro_boost()


func install_nitro_boost() -> NitroBoost:
	nitro_boost_installed = true
	_ensure_nitro_boost_visual()
	_set_nitro_boost_visual_visible(true)
	if is_instance_valid(_nitro_boost):
		return _nitro_boost
	var existing := find_child(NITRO_BOOST_CONTROLLER_NODE_NAME, true, false) as NitroBoost
	if existing != null:
		_nitro_boost = existing
		return existing
	var mount := find_child(NITRO_BOOST_MOUNT_NODE_NAME, true, false) as Node3D
	if mount == null:
		push_error("FarmBaseVehicle: missing recursive NitroBoostPos marker.")
		return null
	var controller := Node3D.new()
	controller.name = NITRO_BOOST_CONTROLLER_NODE_NAME
	controller.set_script(NITRO_BOOST_SCRIPT)
	mount.add_child(controller)
	controller.transform = Transform3D.IDENTITY
	_nitro_boost = controller as NitroBoost
	return _nitro_boost


func remove_nitro_boost() -> void:
	nitro_boost_installed = false
	_set_nitro_boost_visual_visible(false)
	var nitro := get_nitro_boost()
	if nitro == null:
		return
	nitro.set_boost_active(false)
	var parent := nitro.get_parent()
	if parent != null:
		parent.remove_child(nitro)
	nitro.queue_free()
	_nitro_boost = null


func get_nitro_boost() -> NitroBoost:
	if is_instance_valid(_nitro_boost):
		return _nitro_boost
	_nitro_boost = find_child(NITRO_BOOST_CONTROLLER_NODE_NAME, true, false) as NitroBoost
	return _nitro_boost


func _set_nitro_boost_visual_visible(visible: bool) -> void:
	var visual := find_child(NITRO_BOOST_VISUAL_NODE_NAME, true, false) as Node3D
	if visual != null:
		visual.visible = visible


func _ensure_nitro_boost_visual() -> Node3D:
	var existing := find_child(NITRO_BOOST_VISUAL_NODE_NAME, true, false) as Node3D
	if existing != null:
		return existing
	var mount := find_child(NITRO_BOOST_MOUNT_NODE_NAME, true, false) as Node3D
	if mount == null:
		push_error("FarmBaseVehicle: missing recursive NitroBoostPos marker for visual.")
		return null
	var visual := NITRO_BOOST_VISUAL_SCENE.instantiate() as Node3D
	if visual == null:
		push_error("FarmBaseVehicle: failed to instantiate VehicleNitroBoost visual.")
		return null
	visual.name = NITRO_BOOST_VISUAL_NODE_NAME
	mount.add_child(visual)
	visual.transform = Transform3D.IDENTITY
	return visual


func _ensure_platform_interaction_area() -> void:
	_platform_interaction_area = find_child("PlatformInteractionArea", true, false) as VehiclePlatformInteractionArea
	if _platform_interaction_area != null:
		return
	var mount := find_child("PlatformMachineGunPos", true, false) as Marker3D
	if mount == null:
		return
	var area := Area3D.new()
	area.name = "PlatformInteractionArea"
	area.set_script(PLATFORM_INTERACTION_AREA_SCRIPT)
	area.interaction_kind = "machine_gun"
	mount.add_child(area)
	area.position = Vector3(0.0, 0.2, 0.65)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.2, 2.8)
	shape.shape = box
	area.add_child(shape)
	_platform_interaction_area = area as VehiclePlatformInteractionArea


func _ensure_platform_passenger_interaction_area() -> void:
	_configure_platform_passenger_seats()
	if _platform_passenger_seat_definitions.is_empty():
		if _platform_passenger_interaction_area != null:
			_platform_passenger_interaction_area.monitoring = false
			_platform_passenger_interaction_area.monitorable = false
		return
	_platform_passenger_interaction_area = find_child(
		"PlatformPassengerInteractionArea", true, false
	) as VehiclePlatformInteractionArea
	if _platform_passenger_interaction_area != null:
		_platform_passenger_interaction_area.interaction_kind = "passenger"
		_platform_passenger_interaction_area.monitoring = true
		_platform_passenger_interaction_area.monitorable = true
		return
	var first_marker := find_child(PLATFORM_PASSENGER_SEAT_MARKER_NAMES[0], true, false) as Marker3D
	var second_marker := find_child(PLATFORM_PASSENGER_SEAT_MARKER_NAMES[1], true, false) as Marker3D
	if first_marker == null:
		return
	var area := Area3D.new()
	area.name = "PlatformPassengerInteractionArea"
	area.set_script(PLATFORM_INTERACTION_AREA_SCRIPT)
	area.interaction_kind = "passenger"
	add_child(area)
	var center := to_local(first_marker.global_position)
	if second_marker != null:
		center = (to_local(first_marker.global_position) + to_local(second_marker.global_position)) * 0.5
	area.position = center + Vector3(0.0, 0.25, 0.35)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 2.3, 2.8)
	shape.shape = box
	area.add_child(shape)
	_platform_passenger_interaction_area = area as VehiclePlatformInteractionArea


func _cache_seat_anchors() -> void:
	## VehicleBase searches anchors below Mesh because that is where the
	## imported driver's DriverSeatPoint lives. FarmBase's passenger markers are
	## root-level nodes, so resolve them recursively here as well.
	seat_anchors.clear()
	var definitions := _seat_definitions()
	for seat_index in range(definitions.size()):
		var seat := definitions[seat_index]
		var anchor: Node3D = null
		if vehicle_config.open_cabin:
			var default_anchor_name := "DriverSeatPoint" if seat_index == 0 else "SeatPoint_%d" % seat_index
			var anchor_name := default_anchor_name if seat.anchor_name.is_empty() else seat.anchor_name
			if seat_index >= PLATFORM_PASSENGER_SEAT_START_INDEX:
				var platform_seat := find_child(anchor_name, true, false) as Node3D
				if platform_seat != null:
					# Each PlatformSeat marker owns its own SeatPos. Resolve it
					# recursively so the visual/marker hierarchy can be nested.
					anchor = platform_seat.find_child(
						PLATFORM_PASSENGER_SEAT_POSITION_NODE_NAME, true, false
					) as Node3D
					if anchor == null:
						push_warning(
							"Platform passenger seat %s is missing recursive %s anchor."
							% [anchor_name, PLATFORM_PASSENGER_SEAT_POSITION_NODE_NAME]
						)
				else:
					push_warning("Open vehicle is missing platform passenger seat %s." % anchor_name)
			else:
				anchor = _find_visual_node(anchor_name)
			if anchor == null:
				push_warning("Open vehicle is missing seat anchor %s." % anchor_name)
		seat_anchors.append(anchor)


func _seat_definitions() -> Array[VehicleSeatConfig]:
	var definitions: Array[VehicleSeatConfig] = []
	var base_definitions := super()
	for definition: VehicleSeatConfig in base_definitions:
		definitions.append(definition)
	_configure_platform_passenger_seats()
	for definition: VehicleSeatConfig in _platform_passenger_seat_definitions:
		definitions.append(definition)
	return definitions


func set_body_color(color: Color) -> void:
	body_color = Color(color.r, color.g, color.b, 1.0)
	# Apply the map paint only to the named chassis mesh. The reinforced
	# DefenseNet meshes intentionally keep the material authored in the GLB.
	var body_mesh := find_child(BODY_MESH_NODE_NAME, true, false) as MeshInstance3D
	if body_mesh == null:
		return
	body_mesh.material_override = _make_color_material(body_color)


func set_wheel_color(color: Color) -> void:
	wheel_color = Color(color.r, color.g, color.b, 1.0)
	var material := _make_color_material(wheel_color)
	for node_name: String in WHEEL_MESH_NODE_NAMES:
		var wheel_mesh := find_child(node_name, true, false) as MeshInstance3D
		if wheel_mesh != null:
			wheel_mesh.material_override = material


func _make_color_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 1.0)
	material.metallic = 0.25
	material.roughness = 0.42
	return material


func set_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
	super(throttle, steering, brake)
	# The authority uses a full brake input to keep an empty vehicle stopped;
	# that should not make its rear lamps glow.
	_set_brake_lights(driver_peer_id > 0 and brake > 0.01)


func simulate_authority(delta: float) -> void:
	super(delta)
	var nitro := get_nitro_boost()
	if nitro == null:
		return
	# Nitro is an always-available speed module. The visible exhaust starts only
	# while an occupied vehicle is being driven forward, and never while braking
	# or reversing.
	nitro.set_boost_active(
		nitro_boost_installed
			and driver_peer_id > 0
			and drive_throttle > 0.01
			and drive_brake <= 0.01
	)


func get_network_state() -> Dictionary:
	var state := super()
	state["reinforced_variant"] = reinforced_variant
	state["max_hp"] = get_max_hp()
	state["headlights_on"] = headlights_on
	state["brake_lights_on"] = brake_lights_on
	state["body_color"] = body_color
	state["wheel_color"] = wheel_color
	state["platform_machine_gun_installed"] = platform_machine_gun_installed
	state["platform_passenger_seat_count"] = platform_passenger_seat_count
	state["nitro_boost_installed"] = nitro_boost_installed
	state["harvest_reel_installed"] = harvest_reel_installed
	state["roof_headlights_installed"] = roof_headlights_installed
	var nitro := get_nitro_boost()
	state["nitro_boost_active"] = nitro != null and nitro.is_boost_active()
	state["nitro_boost"] = {
		"installed": nitro_boost_installed,
		"active": state["nitro_boost_active"],
	}
	var machine_gun := get_platform_machine_gun()
	state["platform_machine_gun"] = machine_gun.get_network_state() if machine_gun != null else {
		"installed": platform_machine_gun_installed,
		"hp": 0.0,
		"destroyed": platform_machine_gun_installed,
		"yaw": 0.0,
		"elevation": 0.0,
		"operator_peer_id": 0,
	}
	return state


func apply_network_state(state: Dictionary) -> void:
	var next_reinforced_variant := bool(state.get("reinforced_variant", reinforced_variant))
	if next_reinforced_variant != reinforced_variant:
		set_reinforced_variant(next_reinforced_variant)
	var next_passenger_seat_count := clampi(
		int(state.get("platform_passenger_seat_count", platform_passenger_seat_count)),
		0,
		MAX_PLATFORM_PASSENGER_SEATS
	)
	if next_passenger_seat_count != platform_passenger_seat_count:
		set_platform_passenger_seat_count(next_passenger_seat_count)
	var normalized_state := _normalize_legacy_hp_state(state)
	super(normalized_state)
	_set_headlights(bool(state.get("headlights_on", headlights_on)))
	_set_brake_lights(bool(state.get("brake_lights_on", brake_lights_on)))
	var next_body_color: Variant = state.get("body_color", null)
	if next_body_color is Color:
		set_body_color(next_body_color as Color)
	var next_wheel_color: Variant = state.get("wheel_color", null)
	if next_wheel_color is Color:
		set_wheel_color(next_wheel_color as Color)
	var nitro_installed := bool(state.get("nitro_boost_installed", false))
	var nitro_value: Variant = state.get("nitro_boost", {})
	if nitro_value is Dictionary:
		nitro_installed = bool((nitro_value as Dictionary).get("installed", nitro_installed))
	set_nitro_boost_installed(nitro_installed)
	var nitro := get_nitro_boost()
	if nitro != null:
		var nitro_active := bool(state.get("nitro_boost_active", false))
		if nitro_value is Dictionary:
			nitro_active = bool((nitro_value as Dictionary).get("active", nitro_active))
		nitro.set_boost_active(nitro_active)
	var installed := bool(state.get("platform_machine_gun_installed", false))
	var machine_gun_value: Variant = state.get("platform_machine_gun", {})
	if machine_gun_value is Dictionary:
		installed = bool((machine_gun_value as Dictionary).get("installed", installed))
	set_platform_machine_gun_installed(installed)
	var machine_gun := get_platform_machine_gun()
	if machine_gun != null and machine_gun_value is Dictionary:
		machine_gun.apply_network_state(machine_gun_value as Dictionary)
	set_harvest_reel_installed(bool(state.get("harvest_reel_installed", harvest_reel_installed)))
	set_roof_headlights_installed(bool(state.get("roof_headlights_installed", roof_headlights_installed)))


func _normalize_legacy_hp_state(state: Dictionary) -> Dictionary:
	var normalized := state.duplicate(true)
	if not normalized.has("hp"):
		return normalized
	var target_max_hp := get_max_hp()
	if target_max_hp <= 0.0:
		return normalized
	var source_max_hp := float(normalized.get("max_hp", 0.0))
	if source_max_hp <= 0.0:
		# Older FarmBaseVehicle snapshots did not include max_hp and used 300 HP
		# (450 HP for the old reinforced variant).
		source_max_hp = 450.0 if reinforced_variant else 300.0
	if source_max_hp < target_max_hp:
		var source_hp := float(normalized.get("hp", 0.0))
		normalized["hp"] = clampf(
			source_hp / source_max_hp * target_max_hp,
			0.0,
			target_max_hp
	)
	return normalized


func toggle_headlights() -> void:
	if GameAuthority.should_send_network_requests():
		return
	_set_headlights(not headlights_on)


func _cache_glow_nodes() -> void:
	_brake_glows.clear()
	_headlight_glows.clear()
	for names: Array in BRAKE_GLOW_NAMES:
		var glow := _find_mesh_child(str(names[0]), str(names[1]))
		if glow != null:
			_brake_glows.append(glow)
	for names: Array in HEADLIGHT_GLOW_NAMES:
		var glow := _find_mesh_child(str(names[0]), str(names[1]))
		if glow != null:
			_headlight_glows.append(glow)


func _cache_headlight_lights() -> void:
	_headlight_lights.clear()
	for index in range(HEADLIGHT_MOUNT_NAMES.size()):
		var mount := find_child(HEADLIGHT_MOUNT_NAMES[index], true, false) as Node3D
		if mount == null:
			push_warning("FarmBaseVehicle: missing headlight mount %s." % HEADLIGHT_MOUNT_NAMES[index])
			continue
		var light_name: String = HEADLIGHT_LIGHT_NAMES[index]
		var light := mount.find_child(light_name, true, false) as SpotLight3D
		if light == null:
			light = SpotLight3D.new()
			light.name = light_name
			mount.add_child(light)
		# The imported headlamp points along local +Z. SpotLight3D emits along
		# local -Z, so rotate it 180 degrees to project through the lamp face.
		light.position = Vector3(0.0, 0.0, 0.15)
		light.rotation = Vector3(0.0, PI, 0.0)
		light.light_color = Color(1.0, 0.95, 0.85, 1.0)
		light.light_energy = HEADLIGHT_ENERGY
		light.light_indirect_energy = 0.0
		light.spot_range = HEADLIGHT_RANGE
		light.spot_attenuation = HEADLIGHT_ATTENUATION
		light.spot_angle = HEADLIGHT_ANGLE
		light.shadow_enabled = false
		light.visible = false
		_headlight_lights.append(light)


func _find_mesh_child(primary_name: String, fallback_name: String) -> Node3D:
	var mesh_node := find_child("Mesh", true, false)
	if mesh_node != null:
		var glow := mesh_node.find_child(primary_name, true, false) as Node3D
		if glow != null:
			return glow
		if not fallback_name.is_empty():
			glow = mesh_node.find_child(fallback_name, true, false) as Node3D
			if glow != null:
				return glow
	# Keep the lookup recursive even if the visual wrapper is renamed in a later
	# revision of the scene.
	var glow := find_child(primary_name, true, false) as Node3D
	if glow != null:
		return glow
	return find_child(fallback_name, true, false) as Node3D if not fallback_name.is_empty() else null


func _set_headlights(enabled: bool) -> void:
	headlights_on = enabled
	_set_glow_nodes_visible(_headlight_glows, enabled)
	for light in _headlight_lights:
		if is_instance_valid(light):
			light.visible = enabled
			light.light_energy = HEADLIGHT_ENERGY if enabled else 0.0
	_set_roof_headlights_visuals(enabled)


func _set_brake_lights(enabled: bool) -> void:
	brake_lights_on = enabled
	_set_glow_nodes_visible(_brake_glows, enabled)


func _set_glow_nodes_visible(nodes: Array[Node3D], enabled: bool) -> void:
	for glow in nodes:
		if is_instance_valid(glow):
			glow.visible = enabled
