extends CharacterBody3D
class_name GamePlayer

@onready var camera = $Head/Camera3D
@onready var Head = $Head
const SPEED := 5.0
const JUMP_VELOCITY := 3.0
const PRONE_SPEED_MULTIPLIER := 0.4
const PLAYER_MAX_HP := 200.0
const NETWORK_SIMULATION_DELTA := 1.0 / 60.0
const PLAYER_SOFT_CORRECTION_DISTANCE := 0.03
const PLAYER_HARD_CORRECTION_DISTANCE := 1.5
const PLAYER_CORRECTION_BLEND := 0.20
const PLAYER_AIRBORNE_VERTICAL_TOLERANCE := 0.35
const REMOTE_INTERPOLATION_DELAY_MSEC := 100
const REMOTE_MAX_EXTRAPOLATION_MSEC := 100
const REMOTE_CONTROL_LOST_EFFECTIVE_SIGNAL := 0.20
const MEDICINE_HEAL_AMOUNT := 50.0
const PLAYER_COLLISION_LAYER := 8
const PLAYER_COLLISION_MASK := 12943
const BASE_PLAYER_BAG_SLOTS := 12
const BAG_SLOT_ROWS := 2
const BAG_SLOTS_PER_ROW := 6
const HOTBAR_SLOT_COUNT := 6
const BASE_PERSONAL_BAG_WEIGHT_KG := 30.0
const CHEST_ARMOR_ATTACHMENT_OFFSET := Vector3(0.0, -0.16, -0.1)
const HANDHELD_INGREDIENT_PREFIX := "ingredient:"
const CROP_INTERACTION_DISTANCE := 4.0
const INTERACTION_MAX_DISTANCE := 4.0
const INTERACTION_MIN_FORWARD_DOT := -0.15
const INTERACTION_OCCLUSION_MASK := 2

const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"
const CooldownRingScene := preload("res://src/cooldown_ring.gd")
const HANDHELD_WEAPON_TOOL_IDS := {
	"sprout_blaster": true,
	"wreck": true,
	"eater": true,
}
const HIT_MARKER_SIZE := 52.0
const HIT_MARKER_HOLD_SECONDS := 0.08
const HIT_MARKER_FADE_SECONDS := 0.10
const TEAM_MARKER_HEIGHT := 3.15
const TEAM_VISIBILITY_UPDATE_INTERVAL := 0.10
const TEAM_VISIBILITY_RAY_MASK := 4099

var tool_definitions:Array[Dictionary] = []
var all_tool_definitions_by_id: Dictionary = {}
var pending_loadout_selection: Dictionary = {}
var authority_peer_id: int = 1
var input_sequence := 0
var remote_input_sequence := 0
var remote_jump_sequence := 0
var vehicle_input_sequence := 0
var jump_sequence := 0
var last_server_correction_seq := 0
var pending_input_frames: Array[Dictionary] = []
var pending_server_correction: Dictionary = {}
var is_remote_proxy := false
var remote_snapshot_buffer: Array[Dictionary] = []
var remote_locomotion_state := "idle"
var remote_grounded := true
var server_hp := PLAYER_MAX_HP
var respawn_left := 0.0
var is_respawning := false
var death_respawn_duration := 0.0
var flame_remaining := 0.0
var freeze_remaining := 0.0
var lightening_remaining := 0.0
var bug_remaining := 0.0
var labeled_remaining := 0.0
var spicy_remaining := 0.0
var spicy_dps := 0.0
var tranquilizer_remaining := 0.0
var tranquilizer_elapsed := 0.0

@export var team := "red"
@export var mouse_sensitivity := 0.0025
@export var max_look_angle := 50.0
@export var selected_hero:String = "farmer"
@export_group("Interaction Debug")
@export var debug_interaction_shapecasts := false
@export_group("First Person Punch")
@export var punch_hand_camera_offset := Vector3(0.24, 0.12, -1.10)
@export_range(0.0, 1.0, 0.01) var punch_hand_ik_weight := 1.0
@export_range(0.5, 2.0, 0.05) var punch_animation_speed := 1.25
@export_group("Two-Handed Weapons")
@export var left_hand_weapon_camera_offset := Vector3(-0.05, 0.12, -1.85)
@export_range(0.0, 1.0, 0.01) var left_hand_weapon_ik_weight := 1.0
@export_group("Handheld Items")
@export var handheld_item_position := Vector3(0.04, 0.0, 0.03)
# Food GLB assets share the same upside-down hand-socket orientation as dish assets.
@export var handheld_item_rotation_degrees := Vector3(180.0, 0.0, 0.0)
@export var handheld_item_scale := Vector3(0.5, 0.5, 0.5)
@export_group("Prone")
@export var prone_head_position := Vector3(0.0, 0.5, -2.9)
@export var prone_body_collision_position := Vector3(0.0, 0.5, -0.2)
@export var prone_hit_collision_position := Vector3(0.0, 0.5, -0.2)
var current_tool_index := 0
var tool_node: Node3D
var held_item_node: Node3D
var tool_cooldowns: Array[float] = []
var backpack_items: Array[Dictionary] = []
var suppress_backpack_layout_sync := false
var equipped_items: Dictionary = {
	"backpack": {},
	"chest_armor": {},
	"legwear": {},
}
var back_equipment_socket: BoneAttachment3D
var back_equipment_visual: Node3D
var chest_equipment_socket: BoneAttachment3D
var chest_equipment_visual: Node3D
var left_leg_equipment_socket: BoneAttachment3D
var right_leg_equipment_socket: BoneAttachment3D
var left_leg_equipment_visual: Node3D
var right_leg_equipment_visual: Node3D

var interact_hint: Label
var crosshair: Control
var hit_marker: Control
var hit_marker_tween: Tween
var last_hit_confirmation_id := 0
var cooldown_ring: Control
var health_root: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var ammo_label: Label
var control_status_root: PanelContainer
var control_status_title: Label
var control_status_primary_label: Label
var control_status_primary_bar: ProgressBar
var control_status_secondary_label: Label
var control_status_secondary_bar: ProgressBar
var cargo_car_storage_page: CargoCarStoragePage
var cargo_crate_storage_page: CargoCrateStoragePage
var cargo_delivery_page: CargoDeliveryPage
var government_notice_page: GovernmentNoticePage
var livestock_chop_page: LivestockChopPage
var control_status_detail_label: Label
var match_timer_label: Label
var respawn_overlay: ColorRect
var respawn_label: Label
var tranquilizer_overlay: ColorRect
var damage_flash_root: Control
var damage_flash_tween: Tween
var gameplay_notice: Label
var gameplay_notice_tween: Tween
var action_reward_feed: VBoxContainer
var action_reward_tweens: Dictionary = {}
var team_money_delta_feeds: Dictionary = {}
var team_money_delta_tweens: Dictionary = {}
var _cargo_crate_hold_target: CargoCrateGround
var _cargo_crate_hold_started_msec := 0
const CARGO_CRATE_PICKUP_HOLD_MSEC := 650
var team_marker: MeshInstance3D
var team_outline_material: StandardMaterial3D
var team_visibility_accumulator := 0.0
var team_reveal_visible := false
var team_outline_visible := false

var is_weapon_aiming := false
var is_prone := false
var standing_head_position := Vector3.ZERO
var standing_body_collision_transform := Transform3D.IDENTITY
var standing_hit_collision_transform := Transform3D.IDENTITY

var camera_rest_position := Vector3.ZERO
var camera_default_fov := 75.0
var rubber_knockback := Vector3.ZERO
var camera_shake_time := 0.0
var camera_shake_strength := 0.0
var camera_shake_duration := 0.22
var vehicle_camera_shake_time := 0.0
var vehicle_camera_shake_strength := 0.0
var vehicle_camera_shake_duration := 0.32
var vehicle_camera_rest_position := Vector3.ZERO
var remote_camera_shake_time := 0.0
var remote_camera_shake_strength := 0.0
var remote_camera_shake_duration := 0.2
var remote_camera_rest_position := Vector3.ZERO
var big_mouth_capture_remaining := 0.0
var big_mouth_pull_remaining := 0.0
var big_mouth_anchor := Vector3.ZERO

### 人物动画播放器
var appearance_player:AnimationPlayer 
var emotion_controller:EmotionController
var skeleton:Skeleton3D
@onready var hand_socket:BoneAttachment3D = $RightHandSocket
@onready var tool_pivot:Node3D = $RightHandSocket/ToolPivot
@onready var upper_body_look_target:Marker3D = $Head/UpperBodyLookTarget
@onready var right_hand_ik_target:Marker3D = $Head/RightHandIKTarget
@onready var left_hand_ik_target:Marker3D = $Head/LeftHandIKTarget
@onready var right_elbow_pole:Marker3D = $RightElbowPole
@onready var left_elbow_pole:Marker3D = $Head/LeftElbowPole
@onready var remote_effect:ColorRect
var action_anim_locked:bool = false
var was_on_floor:bool = true # 记录上一帧是不是在地面上
var landing_animation:bool = false
var upper_body_look_modifiers:Array[LookAtModifier3D] = []
var upper_body_look_weights:Array[float] = []
var right_arm_ik:TwoBoneIK3D
var left_arm_ik:TwoBoneIK3D
var hand_aim_look:LookAtModifier3D
var look_at_body:Node3D
var right_hand_ik_rest_position := Vector3.ZERO
var left_hand_ik_rest_position := Vector3.ZERO
## 当前正在远程操控
var remote_tool_node:Node3D = null  # NormalDrone,TechDrone,SmallMouse
var remote_is_active:bool = false
var remote_control_camera: Camera3D
var active_remote_device_id := ""
var pending_remote_device_id := ""
var owned_remote_devices: Dictionary = {}
var remote_device_buttons: Dictionary = {}

var active_vehicle: VehicleBase
var active_vehicle_id := ""
var active_vehicle_seat_index := -1
var vehicle_is_active := false

@onready var remote_device_panel: PanelContainer = $SubViewport/RemoteDevicePanel
@onready var remote_device_list: VBoxContainer = $SubViewport/RemoteDevicePanel/MarginContainer/VBoxContainer/ScrollContainer/DeviceList
@onready var player_backpack: PlayerBackpack = $SubViewport/PlayerBackpack
@onready var event_task_hud: EventTaskHud = $SubViewport/EventTaskHud
@onready var ingredient_pickup_page: Node = $SubViewport/IngredientPickupPage
@onready var plating_station_page: Node = $SubViewport/PlatingStationPage
@onready var oven_page: Node = $SubViewport/OvenPage
@onready var griddle_station_page: Node = $SubViewport/GriddleStationPage
@onready var induction_counter_page: Node = $SubViewport/InductionCounterPage
@onready var farm_smoker_page: Node = $SubViewport/FarmSmokerPage
@onready var freezer_page: Node = $SubViewport/FreezerPage
@onready var stand_mixer_page: Node = $SubViewport/StandMixerPage
@onready var ingredient_extractor_page: Node = $SubViewport/IngredientExtractorPage
@onready var auto_cooker_page: Node = $SubViewport/AutoCookerPage
@onready var vehicle_upgrade_page: Node = $SubViewport/VehicleUpgradePage
@onready var team_chat_panel: Node = $SubViewport/TeamChatPanel
@onready var game_exit_dialog: Node = $SubViewport/GameExitDialog

var _suppress_esc_mouse_release := false

func _load_tool_definitions() -> bool:
	tool_definitions.clear()
	all_tool_definitions_by_id.clear()
	if not FileAccess.file_exists(TOOL_CONFIG_PATH):
		push_error("Tool configuration not found: " + TOOL_CONFIG_PATH)
		return false

	var file := FileAccess.open(TOOL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open tool configuration: " + TOOL_CONFIG_PATH)
		return false

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_error(
			"Invalid tool JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false
	if not json.data is Dictionary:
		push_error("Tool JSON root must be an object.")
		return false

	var source_tools:Variant = json.data.get("tools", [])
	if not source_tools is Array:
		push_error("Tool JSON field 'tools' must be an array.")
		return false

	for source_tool:Variant in source_tools:
		if not source_tool is Dictionary:
			push_warning("Skipped a non-object entry in tool JSON.")
			continue
		var definition:Dictionary = source_tool.duplicate(true)
		var tool_id := str(definition.get("id", ""))
		if tool_id.is_empty() or not definition.has("name") or not definition.has("path"):
			push_warning("Skipped a tool without name or path.")
			continue

		definition["grip_position"] = _json_to_vector3(
			definition.get("grip_position", []),
			Vector3.ZERO
		)
		definition["grip_rotation"] = _json_to_vector3(
			definition.get("grip_rotation", []),
			Vector3.ZERO
		)
		definition["grip_scale"] = _json_to_vector3(
			definition.get("grip_scale", []),
			Vector3.ONE
		)
		if definition.has("left_hand_grip_offset"):
			definition["left_hand_grip_offset"] = _json_to_vector3(
				definition.get("left_hand_grip_offset", []),
				left_hand_weapon_camera_offset
			)
		definition["color"] = Color.from_string(
			str(definition.get("color", "#FFFFFF")),
			Color.WHITE
		)
		tool_definitions.append(definition)
		all_tool_definitions_by_id[tool_id] = definition

	if tool_definitions.is_empty():
		push_error("No valid tools were loaded from " + TOOL_CONFIG_PATH)
		return false

	print("Loaded %d tools from %s" % [
		tool_definitions.size(),
		TOOL_CONFIG_PATH,
	])
	return true


func apply_loadout_selection(selection: Dictionary) -> void:
	if not is_node_ready():
		pending_loadout_selection = selection.duplicate(true)
		return
	authority_peer_id = int(selection.get("peer_id", authority_peer_id))
	_apply_loadout_selection_now(selection, true)
	if not is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.make_current()

func _apply_loadout_selection_now(selection: Dictionary, rebuild_runtime: bool) -> void:
	var next_team := str(selection.get("team", team))
	if next_team in ["blue", "red"]:
		team = next_team

	var next_hero := str(selection.get("hero_id", selected_hero))
	if not next_hero.is_empty():
		selected_hero = _normalize_hero_id(next_hero)

	var selected_tool_ids := _tool_ids_from_loadout_selection(selection)
	var selected_definitions := _definitions_for_tool_ids(selected_tool_ids)
	if selected_definitions.is_empty():
		push_warning(
			"Loadout selection did not contain usable tools; keeping current tool list."
		)
	else:
		tool_definitions = selected_definitions

	_initialize_backpack(selected_definitions)
	_reset_tool_runtime()
	set_player_appearance(selected_hero, team)

	if rebuild_runtime:
		_rebuild_hotbar()
		# A remote proxy must wait for current_tool_id from the authoritative
		# snapshot. Its loadout describes inventory ownership, not what is held.
		if is_remote_proxy:
			_select_empty_hotbar_slot(-1)
		elif _has_any_equipped_tool():
			_select_tool(0, true)
		_update_crosshair_visibility()


func _tool_ids_from_loadout_selection(selection: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for field_name in ["primary_weapon_ids", "special_tool_ids"]:
		var source: Variant = selection.get(field_name, [])
		if not source is Array:
			continue
		for item: Variant in source:
			var tool_id := str(item)
			var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
			if tool_id.is_empty() or (result.has(tool_id) and not bool(definition.get("allow_multiple", false))):
				continue
			result.append(tool_id)
	return result


func _definitions_for_tool_ids(tool_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tool_id: String in tool_ids:
		if not all_tool_definitions_by_id.has(tool_id):
			push_warning("Selected tool is not in tool_definitions.json: " + tool_id)
			continue
		result.append((all_tool_definitions_by_id[tool_id] as Dictionary).duplicate(true))
	return result


func _reset_tool_runtime() -> void:
	_clear_tool_node()
	_clear_held_item_node()
	current_tool_index = _first_equipped_tool_slot()
	tool_cooldowns.clear()
	tool_cooldowns.resize(HOTBAR_SLOT_COUNT)
	tool_cooldowns.fill(0.0)


func _rebuild_hotbar() -> void:
	_create_hotbar()


func _create_hotbar() -> void:
	if is_instance_valid(player_backpack):
		player_backpack.bind_player(self)


func _initialize_backpack(selected_definitions: Array[Dictionary]) -> void:
	backpack_items.clear()
	backpack_items.resize(BASE_PLAYER_BAG_SLOTS)
	for index in range(BASE_PLAYER_BAG_SLOTS):
		backpack_items[index] = {}
	for index in range(mini(HOTBAR_SLOT_COUNT, selected_definitions.size())):
		var definition := selected_definitions[index]
		backpack_items[index] = _make_tool_backpack_item(str(definition.get("id", "")))
	_sync_equipped_tools_from_backpack()


func get_active_bag_slot_count() -> int:
	var backpack: Dictionary = equipped_items.get("backpack", {})
	var extra_slots := EquipmentCatalog.get_extra_slots(str(backpack.get("equipment_id", "")))
	if extra_slots % BAG_SLOTS_PER_ROW != 0:
		extra_slots = 0
	return BASE_PLAYER_BAG_SLOTS + extra_slots


func get_personal_bag_capacity_kg() -> float:
	var backpack: Dictionary = equipped_items.get("backpack", {})
	return BASE_PERSONAL_BAG_WEIGHT_KG + EquipmentCatalog.get_extra_weight_kg(
		str(backpack.get("equipment_id", ""))
	)


func _equipped_legwear_speed_multiplier() -> float:
	return EquipmentCatalog.get_movement_speed_multiplier(
		str(get_equipped_item("legwear").get("equipment_id", ""))
	)


func get_equipped_item(equipment_type: String) -> Dictionary:
	var value: Variant = equipped_items.get(equipment_type, {})
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var result := (value as Dictionary).duplicate(true)
	var definition := EquipmentCatalog.get_definition(str(result.get("equipment_id", "")))
	result["display_name"] = str(definition.get("name", "装备"))
	var max_hp := EquipmentCatalog.get_max_hp(str(result.get("equipment_id", "")))
	result["detail"] = "%.0f / %.0f HP" % [float(result.get("current_hp", max_hp)), max_hp] if max_hp > 0.0 else "装备"
	return result


func add_equipment_item(equipment_id: String, item_data: Dictionary = {}) -> bool:
	var definition := EquipmentCatalog.get_definition(equipment_id)
	if definition.is_empty() or str(definition.get("equipment_type", "")) not in ["backpack", "chest_armor", "legwear"]:
		return false
	for index in range(get_active_bag_slot_count()):
		if backpack_items[index].is_empty():
			backpack_items[index] = _make_equipment_backpack_item(equipment_id, item_data)
			_refresh_hotbar()
			_submit_backpack_layout_sync()
			return true
	return false


func request_equip_item(slot_index: int, equipment_type: String) -> void:
	if slot_index < 0 or slot_index >= get_active_bag_slot_count():
		return
	var item := backpack_items[slot_index]
	if str(item.get("kind", "")) != "equipment" or str(item.get("equipment_type", "")) != equipment_type:
		return
	var current := get_equipped_item(equipment_type)
	if slot_index >= BASE_PLAYER_BAG_SLOTS:
		show_gameplay_notice("扩展格中的装备必须先移到基础背包，才能装备或替换")
		return
	var action_name := "equip" if current.is_empty() else "swap"
	var overflow_items: Array[Dictionary] = []
	if action_name == "swap" and equipment_type == "backpack":
		var next_slots := EquipmentCatalog.get_extra_slots(str(item.get("equipment_id", "")))
		for index in range(BASE_PLAYER_BAG_SLOTS + next_slots, get_active_bag_slot_count()):
			if not backpack_items[index].is_empty():
				overflow_items.append(backpack_items[index].duplicate(true))
	_submit_equipment_action({
		"station_kind": "equipment",
		"action": action_name,
		"slot_index": slot_index,
		"equipment_id": str(item.get("equipment_id", "")),
		"equipment_type": equipment_type,
		"overflow_items": overflow_items,
	})


func request_unequip_item(equipment_type: String, target_slot_index: int) -> void:
	if target_slot_index < 0 or target_slot_index >= BASE_PLAYER_BAG_SLOTS \
			or not backpack_items[target_slot_index].is_empty() \
			or get_equipped_item(equipment_type).is_empty():
		return
	var overflow_items: Array[Dictionary] = []
	if equipment_type == "backpack":
		for index in range(BASE_PLAYER_BAG_SLOTS, get_active_bag_slot_count()):
			if not backpack_items[index].is_empty():
				overflow_items.append(backpack_items[index].duplicate(true))
	_submit_equipment_action({
		"station_kind": "equipment",
		"action": "unequip",
		"equipment_type": equipment_type,
		"target_slot_index": target_slot_index,
		"overflow_items": overflow_items,
	})


func _submit_equipment_action(action: Dictionary) -> void:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
	apply_authoritative_equipment_action_result(result)


func apply_authoritative_equipment_action_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		show_gameplay_notice("无法更换装备")
		return
	match str(result.get("action", "")):
		"equip":
			var slot_index := int(result.get("slot_index", -1))
			var equipment_id := str(result.get("equipment_id", ""))
			var equipment_type := str(result.get("equipment_type", ""))
			if slot_index >= 0 and slot_index < backpack_items.size():
				backpack_items[slot_index] = {}
			_set_equipped_item(equipment_type, equipment_id, result.get("equipment_item", {}))
		"swap":
			var slot_index := int(result.get("slot_index", -1))
			var equipment_type := str(result.get("equipment_type", ""))
			var old_equipment_id := str(result.get("old_equipment_id", ""))
			var equipment_id := str(result.get("equipment_id", ""))
			var next_capacity := get_active_bag_slot_count()
			if equipment_type == "backpack":
				next_capacity = BASE_PLAYER_BAG_SLOTS + EquipmentCatalog.get_extra_slots(equipment_id)
			for index in range(next_capacity, backpack_items.size()):
				backpack_items[index] = {}
			_set_equipped_item(equipment_type, equipment_id, result.get("equipment_item", {}))
			if slot_index >= 0 and slot_index < BASE_PLAYER_BAG_SLOTS:
				backpack_items[slot_index] = _make_equipment_backpack_item(old_equipment_id, result.get("old_equipment_item", {}))
		"unequip":
			var target_slot_index := int(result.get("target_slot_index", -1))
			var equipment_id := str(result.get("equipment_id", ""))
			var equipment_type := str(result.get("equipment_type", ""))
			if equipment_type == "backpack":
				for index in range(BASE_PLAYER_BAG_SLOTS, backpack_items.size()):
					backpack_items[index] = {}
			_set_equipped_item(equipment_type, "")
			if target_slot_index >= 0 and target_slot_index < BASE_PLAYER_BAG_SLOTS:
				backpack_items[target_slot_index] = _make_equipment_backpack_item(equipment_id, result.get("equipment_item", {}))
	_sync_equipped_tools_from_backpack()
	_refresh_hotbar()


func _submit_backpack_layout_sync() -> void:
	if suppress_backpack_layout_sync or is_remote_proxy or not is_node_ready():
		return
	var slots: Array[Dictionary] = []
	for item: Dictionary in backpack_items:
		slots.append(item.duplicate(true))
	var action := {
		"station_kind": "inventory_layout",
		"action": "sync",
		"slots": slots,
		"selected_slot": current_tool_index,
		"selected_id": _selected_tool_id(),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	elif GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
		GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)


func _make_equipment_backpack_item(equipment_id: String, source: Variant = {}) -> Dictionary:
	var definition := EquipmentCatalog.get_definition(equipment_id)
	var item := {
		"kind": "equipment",
		"equipment_id": equipment_id,
		"equipment_type": str(definition.get("equipment_type", "")),
	}
	var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
	if max_hp > 0.0:
		var source_item: Dictionary = source if source is Dictionary else {}
		item["current_hp"] = clampf(float(source_item.get("current_hp", max_hp)), 0.0, max_hp)
		item["max_hp"] = max_hp
	return item


func _set_equipped_item(equipment_type: String, equipment_id: String, item_state: Variant = {}) -> void:
	if equipment_type not in ["backpack", "chest_armor", "legwear"]:
		return
	var previous_id := str((equipped_items.get(equipment_type, {}) as Dictionary).get("equipment_id", ""))
	var definition := EquipmentCatalog.get_definition(equipment_id)
	if not equipment_id.is_empty() and str(definition.get("equipment_type", "")) != equipment_type:
		return
	var extra_slots := int(definition.get("extra_slots", 0))
	if equipment_type == "backpack" and not equipment_id.is_empty() and (extra_slots <= 0 or extra_slots % BAG_SLOTS_PER_ROW != 0):
		push_warning("Backpack extra_slots must be a positive multiple of %d: %s" % [BAG_SLOTS_PER_ROW, equipment_id])
		return
	equipped_items[equipment_type] = {} if equipment_id.is_empty() else _make_equipment_backpack_item(equipment_id, item_state)
	var next_size := get_active_bag_slot_count()
	if backpack_items.size() < next_size:
		var old_size := backpack_items.size()
		backpack_items.resize(next_size)
		for index in range(old_size, next_size):
			backpack_items[index] = {}
	elif backpack_items.size() > next_size:
		backpack_items.resize(next_size)
	if equipment_type == "backpack" and previous_id != equipment_id:
		_refresh_back_equipment_visual()
	elif equipment_type == "chest_armor" and previous_id != equipment_id:
		_refresh_chest_equipment_visual()
	elif equipment_type == "legwear" and previous_id != equipment_id:
		_refresh_leg_equipment_visuals()


func apply_equipped_backpack_snapshot(equipment_id: String) -> void:
	if str(get_equipped_item("backpack").get("equipment_id", "")) != equipment_id:
		_set_equipped_item("backpack", equipment_id)


func apply_equipped_items_snapshot(snapshot: Dictionary) -> void:
	for equipment_type in ["backpack", "chest_armor", "legwear"]:
		var item_value: Variant = snapshot.get(equipment_type, {})
		var item_state: Dictionary = item_value as Dictionary if item_value is Dictionary else {}
		var equipment_id := str(item_state.get("equipment_id", "")) if item_value is Dictionary else str(item_value)
		var current := get_equipped_item(equipment_type)
		if str(current.get("equipment_id", "")) != equipment_id \
				or not is_equal_approx(float(current.get("current_hp", -1.0)), float(item_state.get("current_hp", -1.0))):
			_set_equipped_item(equipment_type, equipment_id, item_state)
	_refresh_hotbar()


func apply_chest_armor_state(item_value: Variant) -> void:
	if not item_value is Dictionary:
		return
	var item := item_value as Dictionary
	var equipment_id := str(item.get("equipment_id", ""))
	if equipment_id.is_empty() or equipment_id != str(get_equipped_item("chest_armor").get("equipment_id", "")):
		return
	_set_equipped_item("chest_armor", equipment_id, item)
	_refresh_hotbar()


func apply_legwear_state(item_value: Variant) -> void:
	if not item_value is Dictionary:
		return
	var item := item_value as Dictionary
	var equipment_id := str(item.get("equipment_id", ""))
	if equipment_id.is_empty() or equipment_id != str(get_equipped_item("legwear").get("equipment_id", "")):
		return
	_set_equipped_item("legwear", equipment_id, item)
	_refresh_hotbar()


func _sync_equipped_tools_from_backpack() -> void:
	var previous_cooldowns: Dictionary = {}
	for index in range(mini(tool_definitions.size(), tool_cooldowns.size())):
		var previous_id := str(tool_definitions[index].get("id", ""))
		if not previous_id.is_empty():
			previous_cooldowns[previous_id] = tool_cooldowns[index]
	var selected_slot := current_tool_index
	tool_definitions.clear()
	tool_cooldowns.clear()
	for index in range(HOTBAR_SLOT_COUNT):
		var item := get_backpack_item(index)
		var definition: Dictionary = {}
		if str(item.get("kind", "")) == "tool":
			var tool_id := str(item.get("tool_id", ""))
			if all_tool_definitions_by_id.has(tool_id):
				definition = (all_tool_definitions_by_id[tool_id] as Dictionary).duplicate(true)
		tool_definitions.append(definition)
		tool_cooldowns.append(float(previous_cooldowns.get(str(definition.get("id", "")), 0.0)))
	var next_active := selected_slot if selected_slot >= 0 and selected_slot < HOTBAR_SLOT_COUNT else _first_equipped_tool_slot()
	if is_node_ready() and is_instance_valid(tool_pivot):
		if next_active >= 0:
			_select_tool(next_active, true)
		else:
			_select_empty_hotbar_slot(next_active)
	else:
		current_tool_index = next_active
	_refresh_hotbar()
	_submit_backpack_layout_sync()


func get_backpack_item(index: int) -> Dictionary:
	if index < 0 or index >= backpack_items.size():
		return {}
	var item := backpack_items[index]
	if item.is_empty():
		return {}
	var result := item.duplicate(true)
	if str(result.get("kind", "")) == "tool":
		var definition: Variant = all_tool_definitions_by_id.get(str(result.get("tool_id", "")), {})
		result["display_name"] = str((definition as Dictionary).get("short", "工具")) if definition is Dictionary else "工具"
		if str(result.get("tool_id", "")).begins_with("animal_"):
			result["detail"] = "%d%% | %d/%d HP | %.1f kg" % [
				roundi(float(result.get("growth_progress", 0.0))),
				roundi(float(result.get("current_hp", result.get("max_hp", 0.0)))),
				roundi(float(result.get("max_hp", 0.0))), float(result.get("weight_kg", 0.0)),
			]
		else:
			result["detail"] = "道具"
	elif str(result.get("kind", "")) == "ingredient":
		var ingredient_definition := IngredientCatalog.get_definition(str(result.get("ingredient_id", "")))
		var ingredient_name := str(ingredient_definition.get("display_name", result.get("display_name", result.get("ingredient_id", "食材"))))
		result["display_name"] = "切碎的" + ingredient_name if _is_chopped_ingredient_item(result) else ingredient_name
		result["detail"] = "%.2f kg" % float(result.get("weight_kg", 0.0))
	elif str(result.get("kind", "")) == "dish":
		var dish_definition := DishCatalog.get_definition(str(result.get("dish_id", "")))
		result["display_name"] = str(dish_definition.get("display_name", result.get("dish_id", "成品菜")))
		result["detail"] = "%d份 | %.2f kg" % [int(result.get("servings", 0)), float(result.get("weight_kg", 0.0))]
	elif str(result.get("kind", "")) == "equipment":
		var equipment_definition := EquipmentCatalog.get_definition(str(result.get("equipment_id", "")))
		result["display_name"] = str(equipment_definition.get("name", "装备"))
		result["detail"] = "装备"
	elif str(result.get("kind", "")) == "cargo_crate":
		result["display_name"] = str(result.get("display_name", "货运箱"))
		var quantity := float(result.get("content_quantity", 0.0))
		var unit := str(result.get("content_unit", "count"))
		var quantity_text := "%.2f kg" % quantity if unit == "kg" else "%d%s" % [roundi(quantity), "份" if unit == "serving" else "个"]
		result["detail"] = "%s | %.1f kg" % [quantity_text, float(result.get("total_weight_kg", 0.0))]
	return result


func get_backpack_slot_cooldown(index: int) -> float:
	return tool_cooldowns[index] if index >= 0 and index < tool_cooldowns.size() else 0.0


func move_backpack_item(from_index: int, to_index: int) -> void:
	if from_index < 0 or to_index < 0 or from_index >= backpack_items.size() or to_index >= backpack_items.size() or from_index == to_index:
		return
	var moved := backpack_items[from_index]
	backpack_items[from_index] = backpack_items[to_index]
	backpack_items[to_index] = moved
	_sync_equipped_tools_from_backpack()


func split_backpack_item_unit(from_index: int, to_index: int, requested_weight_kg: float) -> bool:
	if from_index < 0 or to_index < 0 or from_index >= backpack_items.size() \
			or to_index >= backpack_items.size() or from_index == to_index:
		return false
	var source := backpack_items[from_index]
	var target := backpack_items[to_index]
	var piece := UnitWeightItem.make_piece(source, requested_weight_kg)
	if piece.is_empty() or (not target.is_empty() and not UnitWeightItem.can_merge(target, piece)):
		return false
	backpack_items[from_index] = UnitWeightItem.subtract(source, piece)
	backpack_items[to_index] = UnitWeightItem.merge(target, piece)
	_sync_equipped_tools_from_backpack()
	_submit_backpack_layout_sync()
	return true


func add_personal_ingredient(ingredient_id: String, weight_kg: float, is_chopped := false) -> bool:
	if ingredient_id.is_empty() or weight_kg <= 0.0 or not can_add_personal_ingredient(ingredient_id, weight_kg, is_chopped):
		return false
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id \
				and bool(item.get("is_chopped", false)) == is_chopped:
			item["weight_kg"] = float(item.get("weight_kg", 0.0)) + weight_kg
			backpack_items[index] = item
			_refresh_selected_item_after_inventory_change()
			return true
	for index in range(backpack_items.size()):
		if backpack_items[index].is_empty():
			var definition := IngredientCatalog.get_definition(ingredient_id)
			backpack_items[index] = {
				"kind": "ingredient",
				"ingredient_id": ingredient_id,
				"display_name": str(definition.get("display_name", ingredient_id)),
				"weight_kg": weight_kg,
				"is_chopped": is_chopped,
			}
			_refresh_selected_item_after_inventory_change()
			return true
	return false


func add_personal_dish(dish_id: String, servings: int, weight_kg := -1.0) -> bool:
	var definition := DishCatalog.get_definition(dish_id)
	var serving_weight := float(definition.get("serving_weight_kg", 0.0))
	var added_weight := weight_kg if weight_kg > 0.0 else serving_weight * float(servings)
	if dish_id.is_empty() or servings <= 0 or added_weight <= 0.0 or not can_add_personal_dish(dish_id, servings, added_weight):
		return false
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		if str(item.get("kind", "")) == "dish" and str(item.get("dish_id", "")) == dish_id:
			item["servings"] = int(item.get("servings", 0)) + servings
			item["weight_kg"] = float(item.get("weight_kg", 0.0)) + added_weight
			backpack_items[index] = item
			_refresh_selected_item_after_inventory_change()
			return true
	for index in range(backpack_items.size()):
		if backpack_items[index].is_empty():
			backpack_items[index] = {"kind": "dish", "dish_id": dish_id, "servings": servings, "weight_kg": added_weight}
			_refresh_selected_item_after_inventory_change()
			return true
	return false


func add_backpack_tool(tool_id: String, item_data: Dictionary = {}) -> bool:
	if tool_id.is_empty() or not all_tool_definitions_by_id.has(tool_id):
		return false
	var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
	if not bool(definition.get("allow_multiple", false)):
		for item: Dictionary in backpack_items:
			if str(item.get("kind", "")) in ["tool", "weapon"] \
					and str(item.get("tool_id", "")) == tool_id:
				return false
	for index in range(backpack_items.size()):
		if backpack_items[index].is_empty():
			backpack_items[index] = _make_tool_backpack_item(tool_id, item_data)
			_sync_equipped_tools_from_backpack()
			return true
	return false


func _make_tool_backpack_item(tool_id: String, source: Dictionary = {}) -> Dictionary:
	var item := source.duplicate(true)
	item["kind"] = "tool"
	item["tool_id"] = tool_id
	var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
	item["weight_kg"] = float(item.get("weight_kg", definition.get("weight_kg", 0.0)))
	if definition.has("magazine_size"):
		var capacity := maxi(1, int(definition.get("magazine_size", 1)))
		item["ammo_in_mag"] = clampi(int(item.get("ammo_in_mag", capacity)), 0, capacity)
		item["reserve_ammo"] = maxi(0, int(item.get("reserve_ammo", definition.get("initial_reserve_ammo", 200))))
		item["reload_remaining"] = maxf(0.0, float(item.get("reload_remaining", 0.0)))
		item["reload_duration"] = maxf(0.0, float(item.get("reload_duration", 0.0)))
	return item


func apply_test_backpack_grant(entries: Array) -> void:
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		match str(entry.get("kind", "")):
			"tool":
				add_backpack_tool(str(entry.get("tool_id", entry.get("id", ""))), entry)
			"ingredient":
				add_personal_ingredient(
					str(entry.get("ingredient_id", entry.get("id", ""))),
					float(entry.get("weight_kg", 0.0)),
					bool(entry.get("is_chopped", false))
				)
			"dish":
				add_personal_dish(
					str(entry.get("dish_id", entry.get("id", ""))),
					int(entry.get("servings", 0)),
					float(entry.get("weight_kg", -1.0))
				)
			"equipment":
				add_equipment_item(str(entry.get("equipment_id", entry.get("id", ""))), entry)
			"cargo_crate":
				var crate := CargoCrateData.normalize(entry)
				for index in range(backpack_items.size()):
					if backpack_items[index].is_empty():
						backpack_items[index] = crate
						_refresh_selected_item_after_inventory_change()
						break


func _refresh_selected_item_after_inventory_change() -> void:
	if current_tool_index >= 0 and current_tool_index < backpack_items.size():
		var selected_item := backpack_items[current_tool_index]
		if not selected_item.is_empty() and str(selected_item.get("kind", "")) != "tool":
			_select_tool(current_tool_index, true)
			_submit_backpack_layout_sync()
			return
	_refresh_hotbar()
	_submit_backpack_layout_sync()


func get_selected_choppable_ingredient() -> Dictionary:
	if current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return {}
	var item := backpack_items[current_tool_index]
	if str(item.get("kind", "")) != "ingredient" or _is_chopped_ingredient_item(item):
		return {}
	var ingredient_id := str(item.get("ingredient_id", ""))
	if float(item.get("weight_kg", 0.0)) + 0.001 < IngredientCatalog.get_pickup_unit_kg(ingredient_id) \
			or IngredientCatalog.get_model_path(ingredient_id, "chopped_item").is_empty():
		return {}
	var result := item.duplicate(true)
	result["slot_index"] = current_tool_index
	return result


func remove_personal_ingredient_from_slot(
	slot_index: int,
	ingredient_id: String,
	weight_kg: float,
	is_chopped := false
) -> bool:
	if slot_index < 0 or slot_index >= backpack_items.size() or ingredient_id.is_empty() or weight_kg <= 0.0:
		return false
	var item := backpack_items[slot_index]
	if str(item.get("kind", "")) != "ingredient" \
			or str(item.get("ingredient_id", "")) != ingredient_id \
			or _is_chopped_ingredient_item(item) != is_chopped:
		return false
	var remaining_weight := float(item.get("weight_kg", 0.0)) - weight_kg
	if remaining_weight < -0.001:
		return false
	if remaining_weight <= 0.001:
		backpack_items[slot_index] = {}
	else:
		item["weight_kg"] = remaining_weight
		backpack_items[slot_index] = item
	_sync_equipped_tools_from_backpack()
	return true


func apply_authoritative_chopping_action_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	match str(result.get("action", "")):
		"place":
			remove_personal_ingredient_from_slot(
				int(result.get("slot_index", -1)),
				str(result.get("ingredient_id", "")),
				float(result.get("weight_kg", 0.0)),
				false
			)
		"take":
			var ingredient_value: Variant = result.get("ingredient", {})
			if ingredient_value is Dictionary:
				var ingredient := ingredient_value as Dictionary
				add_personal_ingredient(
					str(ingredient.get("ingredient_id", "")),
					float(ingredient.get("weight_kg", 0.0)),
					true
				)


func apply_authoritative_plating_station_action_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)) and str(result.get("action", "")) == "take":
		add_personal_dish(str(result.get("dish_id", "")), int(result.get("servings", 0)), float(result.get("weight_kg", -1.0)))
		if is_instance_valid(plating_station_page) and plating_station_page.has_method("refresh_if_open"):
			plating_station_page.call("refresh_if_open")


func apply_authoritative_oven_action_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)) and str(result.get("action", "")) == "take":
		add_personal_dish(str(result.get("dish_id", "")), int(result.get("servings", 0)), float(result.get("weight_kg", -1.0)))
		if is_instance_valid(oven_page) and oven_page.has_method("refresh_if_open"):
			oven_page.call("refresh_if_open")


func apply_authoritative_recipe_station_action_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)) and str(result.get("action", "")) == "take":
		add_personal_dish(str(result.get("dish_id", "")), int(result.get("servings", 0)), float(result.get("weight_kg", -1.0)))
		if is_instance_valid(griddle_station_page) and griddle_station_page.has_method("refresh_if_open"):
			griddle_station_page.call("refresh_if_open")
		if is_instance_valid(induction_counter_page) and induction_counter_page.has_method("refresh_if_open"):
			induction_counter_page.call("refresh_if_open")
		if is_instance_valid(farm_smoker_page) and farm_smoker_page.has_method("refresh_if_open"):
			farm_smoker_page.call("refresh_if_open")
		if is_instance_valid(freezer_page) and freezer_page.has_method("refresh_if_open"):
			freezer_page.call("refresh_if_open")
func apply_authoritative_extractor_action_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	match str(result.get("action", "")):
		"start":
			var inputs_value: Variant = result.get("personal_inputs", [])
			if inputs_value is Array:
				for input_value: Variant in inputs_value:
					if input_value is Dictionary:
						var input := input_value as Dictionary
						remove_personal_ingredient_by_type(
							str(input.get("ingredient_id", "")),
							float(input.get("weight_kg", 0.0)),
							false
						)
		"take":
			var ingredient_value: Variant = result.get("ingredient", {})
			if ingredient_value is Dictionary:
				var ingredient := ingredient_value as Dictionary
				add_personal_ingredient(
					str(ingredient.get("ingredient_id", "")),
					float(ingredient.get("weight_kg", 0.0))
				)


func apply_authoritative_mixer_action_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	match str(result.get("action", "")):
		"start":
			var inputs_value: Variant = result.get("personal_inputs", [])
			if inputs_value is Array:
				for input_value: Variant in inputs_value:
					if input_value is Dictionary:
						var input := input_value as Dictionary
						remove_personal_ingredient_by_type(
							str(input.get("ingredient_id", "")),
							float(input.get("weight_kg", 0.0)),
							false
						)
		"take":
			var ingredient_value: Variant = result.get("ingredient", {})
			if ingredient_value is Dictionary:
				var ingredient := ingredient_value as Dictionary
				add_personal_ingredient(
					str(ingredient.get("ingredient_id", "")),
					float(ingredient.get("weight_kg", 0.0))
				)


func apply_authoritative_dropped_item_action_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		match str(result.get("reason", "")):
			"personal_bag_full":
				show_gameplay_notice("背包已满或超重，无法加入新的物品")
			"unique_tool_already_owned":
				show_gameplay_notice("该道具只能持有一个")
		return
	var item_value: Variant = result.get("item", {})
	var item := item_value as Dictionary if item_value is Dictionary else {}
	match str(result.get("action", "")):
		"throw":
			var slots_value: Variant = result.get("player_slots", null)
			if slots_value is Array:
				apply_cargo_backpack_slots(slots_value as Array)
				return
			var slot_index := int(result.get("slot_index", -1))
			if slot_index >= 0 and slot_index < backpack_items.size() \
					and _backpack_items_match(backpack_items[slot_index], item):
				backpack_items[slot_index] = {}
				_sync_equipped_tools_from_backpack()
		"pickup":
			if str(item.get("kind", "")) == "tool" or str(item.get("kind", "")) == "weapon":
				add_backpack_tool(str(item.get("tool_id", "")), item)
			elif str(item.get("kind", "")) == "equipment":
				add_equipment_item(str(item.get("equipment_id", "")), item)
			elif str(item.get("kind", "")) == "ingredient":
				add_personal_ingredient(
					str(item.get("ingredient_id", "")),
					float(item.get("weight_kg", 0.0)),
					bool(item.get("is_chopped", false))
				)
			elif str(item.get("kind", "")) == "dish":
				add_personal_dish(
					str(item.get("dish_id", "")),
					int(item.get("servings", 0)),
					float(item.get("weight_kg", 0.0))
				)
			elif str(item.get("kind", "")) == "cargo_crate":
				for index in range(backpack_items.size()):
					if backpack_items[index].is_empty():
						backpack_items[index] = item.duplicate(true)
						_refresh_selected_item_after_inventory_change()
						break


func apply_death_inventory_drop(items_value: Variant) -> void:
	if not items_value is Array:
		return
	suppress_backpack_layout_sync = true
	for item_value: Variant in items_value:
		if not item_value is Dictionary:
			continue
		var item := item_value as Dictionary
		match str(item.get("kind", "")):
			"tool", "weapon":
				for index in range(backpack_items.size()):
					if (str(backpack_items[index].get("kind", "")) == "tool" or str(backpack_items[index].get("kind", "")) == "weapon") \
							and str(backpack_items[index].get("tool_id", "")) == str(item.get("tool_id", "")):
						backpack_items[index] = {}
						break
			"ingredient":
				remove_personal_ingredient_by_type(
					str(item.get("ingredient_id", "")),
					float(item.get("weight_kg", 0.0)),
					bool(item.get("is_chopped", false))
				)
			"dish":
				_remove_personal_dish_by_type(
					str(item.get("dish_id", "")),
					int(item.get("servings", 0)),
					float(item.get("weight_kg", 0.0))
				)
			"equipment":
				if bool(item.get("was_equipped", false)):
					_set_equipped_item(str(item.get("equipment_type", "")), "")
				else:
					for index in range(backpack_items.size()):
						if str(backpack_items[index].get("kind", "")) == "equipment" \
								and str(backpack_items[index].get("equipment_id", "")) == str(item.get("equipment_id", "")):
							backpack_items[index] = {}
							break
			"cargo_crate":
				for index in range(backpack_items.size()):
					if str(backpack_items[index].get("kind", "")) == "cargo_crate" \
							and str(backpack_items[index].get("crate_instance_id", "")) == str(item.get("crate_instance_id", "")):
						backpack_items[index] = {}
						break
	suppress_backpack_layout_sync = false
	_sync_equipped_tools_from_backpack()


func request_pickup_item(pickup: PickupItem) -> bool:
	if not is_instance_valid(pickup) or not pickup.landed:
		return false
	var rejection_notice := _dropped_item_rejection_notice(pickup.item_data)
	if not rejection_notice.is_empty():
		show_gameplay_notice(rejection_notice)
		return false
	var action := {"station_kind": "dropped_item", "action": "pickup", "item_id": pickup.item_id}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return true
	var result := GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
	apply_authoritative_dropped_item_action_result(result)
	return bool(result.get("ok", false))


func _request_throw_current_item() -> void:
	if is_prone or vehicle_is_active or remote_is_active or current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return
	var item := backpack_items[current_tool_index]
	var kind := str(item.get("kind", ""))
	if kind != "tool" and kind != "weapon" and kind != "ingredient" and kind != "dish" and kind != "equipment" and kind != "cargo_crate":
		return
	var direction: Vector3 = -Head.global_transform.basis.z
	if direction.length_squared() <= 0.001:
		direction = -global_transform.basis.z
	var action := {
		"station_kind": "dropped_item",
		"action": "throw",
		"slot_index": current_tool_index,
		"item": item.duplicate(true),
		"direction": direction.normalized(),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
	apply_authoritative_dropped_item_action_result(result)


func request_drop_dragged_inventory_item(data: Dictionary) -> void:
	if is_respawning or vehicle_is_active or remote_is_active:
		return
	var direction: Vector3 = -Head.global_transform.basis.z
	if direction.length_squared() <= 0.001:
		direction = -global_transform.basis.z
	direction = direction.normalized()
	if data.get("backpack", null) == player_backpack:
		if str(data.get("slot_kind", "")) != "inventory":
			return
		var slot_index := int(data.get("slot_index", -1))
		var item := data.get("unit_item", {}) as Dictionary \
			if bool(data.get("unit_weight_transfer", false)) else get_backpack_item(slot_index)
		if item.is_empty():
			return
		var action := {
			"station_kind": "dropped_item",
			"action": "throw",
			"slot_index": slot_index,
			"item": item.duplicate(true),
			"direction": direction,
		}
		if GameAuthority.should_send_network_requests():
			MultiplayerNetwork.submit_ingredient_pickup_action(action)
		else:
			apply_authoritative_dropped_item_action_result(
				GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
			)
		return
	var source_page: Variant = data.get("companion_page", data.get("cargo_page", null))
	if is_instance_valid(source_page) and source_page.has_method("drop_dragged_item_outside"):
		source_page.call("drop_dragged_item_outside", data, direction)


func _can_accept_dropped_item(item: Dictionary) -> bool:
	return _dropped_item_rejection_notice(item).is_empty()


func _dropped_item_rejection_notice(item: Dictionary) -> String:
	var kind := str(item.get("kind", ""))
	if kind in ["tool", "weapon"]:
		var tool_id := str(item.get("tool_id", ""))
		var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
		if not bool(definition.get("allow_multiple", false)):
			for slot: Dictionary in backpack_items:
				if str(slot.get("kind", "")) in ["tool", "weapon"] \
						and str(slot.get("tool_id", "")) == tool_id:
					return "该道具只能持有一个"
		for slot: Dictionary in backpack_items:
			if slot.is_empty():
				return "" if get_personal_bag_weight_kg() + float(item.get("weight_kg", definition.get("weight_kg", 0.0))) <= get_personal_bag_capacity_kg() + 0.001 else "背包已超重"
		return "背包已满或超重，无法加入新的物品"
	if kind == "equipment":
		for slot: Dictionary in backpack_items:
			if slot.is_empty():
				return ""
		return "背包已满或超重，无法加入新的物品"
	if kind == "ingredient":
		return "" if can_add_personal_ingredient(
			str(item.get("ingredient_id", "")),
			float(item.get("weight_kg", 0.0)),
			bool(item.get("is_chopped", false))
		) else "背包已满或超重，无法加入新的物品"
	if kind == "dish":
		return "" if can_add_personal_dish(
			str(item.get("dish_id", "")),
			int(item.get("servings", 0)),
			float(item.get("weight_kg", 0.0))
		) else "背包已满或超重，无法加入新的物品"
	if kind == "cargo_crate":
		for slot: Dictionary in backpack_items:
			if slot.is_empty():
				return "" if get_personal_bag_weight_kg() + float(item.get("total_weight_kg", 0.0)) <= get_personal_bag_capacity_kg() + 0.001 else "背包已超重"
		return "背包已满"
	return "无法拾取该物品"


func _backpack_items_match(first: Dictionary, second: Dictionary) -> bool:
	var kind := str(first.get("kind", ""))
	if kind != str(second.get("kind", "")):
		return false
	if kind == "tool" or kind == "weapon":
		return str(first.get("tool_id", "")) == str(second.get("tool_id", ""))
	if kind == "ingredient":
		return str(first.get("ingredient_id", "")) == str(second.get("ingredient_id", "")) \
				and _is_chopped_ingredient_item(first) == bool(second.get("is_chopped", false)) \
				and is_equal_approx(float(first.get("weight_kg", 0.0)), float(second.get("weight_kg", 0.0)))
	if kind == "dish":
		return str(first.get("dish_id", "")) == str(second.get("dish_id", "")) \
				and int(first.get("servings", 0)) == int(second.get("servings", 0)) \
				and is_equal_approx(float(first.get("weight_kg", 0.0)), float(second.get("weight_kg", 0.0)))
	if kind == "equipment":
		return str(first.get("equipment_id", "")) == str(second.get("equipment_id", ""))
	if kind == "cargo_crate":
		return str(first.get("crate_instance_id", "")) == str(second.get("crate_instance_id", ""))
	return false


func _remove_personal_dish_by_type(dish_id: String, servings: int, weight_kg: float) -> bool:
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		if str(item.get("kind", "")) != "dish" or str(item.get("dish_id", "")) != dish_id:
			continue
		var remaining_servings := int(item.get("servings", 0)) - servings
		var remaining_weight := float(item.get("weight_kg", 0.0)) - weight_kg
		if remaining_servings < 0 or remaining_weight < -0.001:
			return false
		if remaining_servings <= 0 or remaining_weight <= 0.001:
			backpack_items[index] = {}
		else:
			item["servings"] = remaining_servings
			item["weight_kg"] = remaining_weight
			backpack_items[index] = item
		_submit_backpack_layout_sync()
		return true
	return false


func remove_personal_ingredient_by_type(ingredient_id: String, weight_kg: float, is_chopped := false) -> bool:
	var remaining_weight := weight_kg
	for index in range(backpack_items.size()):
		var item := get_backpack_item(index)
		if str(item.get("kind", "")) != "ingredient" or str(item.get("ingredient_id", "")) != ingredient_id \
				or _is_chopped_ingredient_item(item) != is_chopped:
			continue
		var removed_weight := minf(float(item.get("weight_kg", 0.0)), remaining_weight)
		if removed_weight > 0.0:
			remove_personal_ingredient_from_slot(index, ingredient_id, removed_weight, is_chopped)
			remaining_weight -= removed_weight
			if remaining_weight <= 0.001:
				return true
	return false


func can_add_personal_ingredient(ingredient_id: String, weight_kg: float, is_chopped := false) -> bool:
	if ingredient_id.is_empty() or weight_kg <= 0.0:
		return false
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id \
				and bool(item.get("is_chopped", false)) == is_chopped:
			return get_personal_bag_weight_kg() + weight_kg <= get_personal_bag_capacity_kg() + 0.001
	for index in range(backpack_items.size()):
		if backpack_items[index].is_empty():
			return get_personal_bag_weight_kg() + weight_kg <= get_personal_bag_capacity_kg() + 0.001
	return false


func can_add_personal_dish(dish_id: String, servings: int, weight_kg := -1.0) -> bool:
	var definition := DishCatalog.get_definition(dish_id)
	var added_weight := weight_kg if weight_kg > 0.0 else float(definition.get("serving_weight_kg", 0.0)) * float(servings)
	if dish_id.is_empty() or servings <= 0 or added_weight <= 0.0:
		return false
	for item: Dictionary in backpack_items:
		if str(item.get("kind", "")) == "dish" and str(item.get("dish_id", "")) == dish_id:
			return get_personal_bag_weight_kg() + added_weight <= get_personal_bag_capacity_kg() + 0.001
	for item: Dictionary in backpack_items:
		if item.is_empty():
			return get_personal_bag_weight_kg() + added_weight <= get_personal_bag_capacity_kg() + 0.001
	return false


func get_personal_bag_weight_kg() -> float:
	var total_weight := 0.0
	for item: Dictionary in backpack_items:
		total_weight += maxf(0.0, float(item.get(
			"total_weight_kg" if str(item.get("kind", "")) == "cargo_crate" else "weight_kg",
			0.0
		)))
	return total_weight


func clear_personal_backpack_items() -> void:
	for index in range(backpack_items.size()):
		if str(backpack_items[index].get("kind", "")) != "tool":
			backpack_items[index] = {}
	_sync_equipped_tools_from_backpack()


func _has_equipped_tool(index: int) -> bool:
	return index >= 0 and index < tool_definitions.size() and not tool_definitions[index].is_empty()


func _has_any_equipped_tool() -> bool:
	for index in range(tool_definitions.size()):
		if _has_equipped_tool(index):
			return true
	return false


func _first_equipped_tool_slot() -> int:
	for index in range(tool_definitions.size()):
		if _has_equipped_tool(index):
			return index
	return -1


func _tool_slot_for_id(tool_id: String) -> int:
	if tool_id.is_empty():
		return _first_equipped_tool_slot()
	for index in range(tool_definitions.size()):
		if str(tool_definitions[index].get("id", "")) == tool_id:
			return index
	return -1


func _normalize_hero_id(hero_id: String) -> String:
	return hero_id


func _json_to_vector3(value:Variant, fallback:Vector3) -> Vector3:
	if not value is Array or value.size() < 3:
		return fallback
	return Vector3(
		float(value[0]),
		float(value[1]),
		float(value[2])
	)

func _ready() -> void:
	add_to_group("human_players")
	if not is_remote_proxy and not GameAuthority.player_correction_ready.is_connected(_on_authority_player_correction):
		GameAuthority.player_correction_ready.connect(_on_authority_player_correction)
	if not is_remote_proxy and not GameAuthority.reliable_world_event_ready.is_connected(_on_authority_world_event):
		GameAuthority.reliable_world_event_ready.connect(_on_authority_world_event)
	if not is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_rest_position = camera.position
	camera_default_fov = camera.fov
	standing_head_position = Head.position
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		standing_body_collision_transform = body_shape.transform
	var hit_shape := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
	if hit_shape != null:
		standing_hit_collision_transform = hit_shape.transform
	right_hand_ik_rest_position = right_hand_ik_target.position
	left_hand_ik_rest_position = left_hand_ik_target.position

	if not _load_tool_definitions():
		set_process(false)
		set_physics_process(false)
		return

	if pending_loadout_selection.is_empty():
		_initialize_backpack(tool_definitions.slice(0, HOTBAR_SLOT_COUNT))
		_reset_tool_runtime()
		set_player_appearance(selected_hero, team)
		if not is_remote_proxy:
			camera.make_current()
	else:
		authority_peer_id = int(pending_loadout_selection.get("peer_id", authority_peer_id))
		_apply_loadout_selection_now(pending_loadout_selection, false)
		pending_loadout_selection.clear()
	_ensure_team_marker_visual()
	_update_team_reveal_visual(true)

	if is_remote_proxy:
		_disable_remote_proxy_runtime()
	else:
		_disable_legacy_tool_ui()
		_create_hotbar()
		if is_instance_valid(event_task_hud):
			event_task_hud.bind_player(self)
		_create_health_ui()
		_create_control_status_ui()
		_create_match_timer_ui()
		_create_crosshair()
		_create_interact_hint()
		_create_gameplay_notice()
		_create_damage_feedback_ui()
		_create_action_reward_feed()
		_create_team_money_delta_feeds()
		cargo_car_storage_page = CargoCarStoragePage.new()
		cargo_car_storage_page.name = "CargoCarStoragePage"
		$SubViewport.add_child(cargo_car_storage_page)
		cargo_crate_storage_page = CargoCrateStoragePage.new()
		cargo_crate_storage_page.name = "CargoCrateStoragePage"
		$SubViewport.add_child(cargo_crate_storage_page)
		cargo_delivery_page = CargoDeliveryPage.new()
		cargo_delivery_page.name = "CargoDeliveryPage"
		$SubViewport.add_child(cargo_delivery_page)
		cargo_delivery_page.bind_player(self)
		government_notice_page = GovernmentNoticePage.new()
		government_notice_page.name = "GovernmentNoticePage"
		$SubViewport.add_child(government_notice_page)
		government_notice_page.closed.connect(_on_government_notice_closed)
		livestock_chop_page = LivestockChopPage.new()
		livestock_chop_page.name = "LivestockChopPage"
		$SubViewport.add_child(livestock_chop_page)
		_ensure_tranquilizer_overlay()
		team_chat_panel.bind_player(self)
		game_exit_dialog.resume_requested.connect(_close_game_exit_dialog)
		game_exit_dialog.exit_requested.connect(_exit_game)
		remote_device_panel.visible = false
		$SubViewport/ShopPage.closed.connect(_on_shop_page_closed)
		if _has_any_equipped_tool():
			_select_tool(0, true)


func configure_remote_proxy(peer_id: int, selection: Dictionary) -> void:
	is_remote_proxy = true
	authority_peer_id = peer_id
	apply_loadout_selection(selection)
	_disable_remote_proxy_runtime()


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	if not is_remote_proxy:
		return
	var position: Variant = snapshot.get("position", Vector3.ZERO)
	if not position is Vector3:
		return
	var sample := snapshot.duplicate(true)
	sample["received_at_msec"] = Time.get_ticks_msec()
	var snapshot_tick := int(sample.get("tick", -1))
	if not remote_snapshot_buffer.is_empty() and snapshot_tick >= 0:
		var last_tick := int(remote_snapshot_buffer.back().get("tick", -1))
		if snapshot_tick < last_tick:
			return
		if snapshot_tick == last_tick:
			remote_snapshot_buffer[remote_snapshot_buffer.size() - 1] = sample
			return
	remote_snapshot_buffer.append(sample)
	if remote_snapshot_buffer.size() > 32:
		remote_snapshot_buffer.pop_front()
	if remote_snapshot_buffer.size() == 1:
		_apply_remote_render_state(sample)


func _update_remote_interpolation() -> void:
	if remote_snapshot_buffer.is_empty():
		return
	var target_time := Time.get_ticks_msec() - REMOTE_INTERPOLATION_DELAY_MSEC
	var previous: Dictionary = remote_snapshot_buffer.front()
	var following: Dictionary = {}
	for sample in remote_snapshot_buffer:
		if int(sample.get("received_at_msec", 0)) <= target_time:
			previous = sample
			continue
		following = sample
		break
	if following.is_empty():
		var latest_time := int(previous.get("received_at_msec", target_time))
		var extrapolation_msec := clampi(target_time - latest_time, 0, REMOTE_MAX_EXTRAPOLATION_MSEC)
		var extrapolated := previous.duplicate(true)
		var position: Variant = extrapolated.get("position", global_position)
		var velocity: Variant = extrapolated.get("velocity", Vector3.ZERO)
		if position is Vector3 and velocity is Vector3:
			extrapolated["position"] = position + velocity * (float(extrapolation_msec) / 1000.0)
		_apply_remote_render_state(extrapolated)
		return
	var from_time := int(previous.get("received_at_msec", target_time))
	var to_time := int(following.get("received_at_msec", from_time + 1))
	var blend := clampf(float(target_time - from_time) / maxf(1.0, float(to_time - from_time)), 0.0, 1.0)
	var blended := previous.duplicate(true)
	var from_position: Variant = previous.get("position", global_position)
	var to_position: Variant = following.get("position", from_position)
	if from_position is Vector3 and to_position is Vector3:
		blended["position"] = from_position.lerp(to_position, blend)
	blended["yaw"] = lerp_angle(
		float(previous.get("yaw", rotation.y)),
		float(following.get("yaw", rotation.y)),
		blend
	)
	blended["pitch"] = lerpf(
		float(previous.get("pitch", Head.rotation.x)),
		float(following.get("pitch", Head.rotation.x)),
		blend
	)
	if blend >= 0.5:
		blended["current_tool_index"] = following.get("current_tool_index", current_tool_index)
		blended["current_tool_id"] = following.get("current_tool_id", "")
	_apply_remote_render_state(blended)


func _apply_remote_render_state(snapshot: Dictionary) -> void:
	apply_respawn_state(float(snapshot.get("respawn_left", 0.0)))
	labeled_remaining = maxf(0.0, float(snapshot.get("labeled_remaining", 0.0)))
	apply_vehicle_snapshot(
		str(snapshot.get("vehicle_id", "")),
		int(snapshot.get("vehicle_seat_index", -1))
	)
	var target_position: Variant = snapshot.get("position", global_position)
	if target_position is Vector3:
		global_position = target_position
	rotation.y = float(snapshot.get("yaw", rotation.y))
	if is_instance_valid(Head):
		Head.rotation.x = float(snapshot.get("pitch", Head.rotation.x))
	_set_prone_state(bool(snapshot.get("prone", str(snapshot.get("locomotion_state", "")) == "prone")))
	var equipped_snapshot: Variant = snapshot.get("equipped_items", {})
	if equipped_snapshot is Dictionary:
		apply_equipped_items_snapshot(equipped_snapshot as Dictionary)
	else:
		apply_equipped_backpack_snapshot(str(snapshot.get("equipped_backpack_id", "")))
	var next_tool_index := int(snapshot.get("current_tool_index", current_tool_index))
	var next_tool_id := str(snapshot.get("current_tool_id", _selected_tool_id()))
	if next_tool_index != current_tool_index or next_tool_id != _selected_tool_id():
		apply_remote_tool_selection(next_tool_index, next_tool_id)
	var previous_locomotion_state := remote_locomotion_state
	remote_grounded = bool(snapshot.get("grounded", remote_grounded))
	remote_locomotion_state = str(snapshot.get("locomotion_state", remote_locomotion_state))
	_update_remote_locomotion_animation(previous_locomotion_state)


func apply_remote_tool_selection(tool_index: int, tool_id := "") -> void:
	if not is_remote_proxy:
		return
	var ingredient_item := _ingredient_item_from_replication_id(tool_id)
	if not ingredient_item.is_empty():
		_select_handheld_item(tool_index, ingredient_item, true)
		return
	if tool_index < 0 or tool_id.is_empty():
		_select_empty_hotbar_slot(tool_index)
		return
	if tool_index >= HOTBAR_SLOT_COUNT:
		return
	if not tool_id.is_empty() and all_tool_definitions_by_id.has(tool_id):
		tool_definitions[tool_index] = (all_tool_definitions_by_id[tool_id] as Dictionary).duplicate(true)
	_select_tool(tool_index, true)
	# Remote snapshots can update the proxy's skeleton/pivot transform in the
	# same frame as the tool swap. Reapply the global-up correction after the
	# instantiated model has entered the remote hand socket.
	if is_instance_valid(tool_node) \
			and not _definition_uses_weapon_orientation(tool_definitions[tool_index]):
		_schedule_held_model_upright(tool_node)


func play_remote_tool_action(action_name: String) -> void:
	if not is_remote_proxy or is_prone or not is_instance_valid(appearance_player):
		return
	action_anim_locked = true
	match action_name:
		"shooting":
			appearance_player.play(&"ShootOneHand", 0.05)
		"melee":
			appearance_player.play(&"PunchRight", 0.05,punch_animation_speed)
		_:
			appearance_player.play(&"ToolUseRight", 0.05)


func _update_remote_locomotion_animation(previous_state: String) -> void:
	if not is_remote_proxy or not is_instance_valid(appearance_player) or action_anim_locked:
		return
	if remote_locomotion_state == "air":
		if previous_state != "air":
			appearance_player.play(&"JumpStart", 0.05)
		elif appearance_player.current_animation != &"JumpStart":
			_play_body_animation(&"JumpLoop", 0.05)
		return
	if previous_state == "air":
		landing_animation = true
		appearance_player.play(&"JumpLand", 0.05)
		return
	if landing_animation:
		return
	match remote_locomotion_state:
		"prone":
			_play_body_animation(&"ProneCrawl", 0.10)
		"walk":
			_play_body_animation(&"Carry" if _selected_item_uses_carry_pose() else &"Walk", 0.08)
		"idle_tool":
			_play_body_animation(&"Carry" if _selected_item_uses_carry_pose() else &"IdleTool", 0.12)
		_:
			_play_body_animation(&"Idle", 0.12)


func _disable_remote_proxy_runtime() -> void:
	# Remote proxies have no gameplay loop, but do render from their snapshot buffer.
	set_process(true)
	set_physics_process(false)
	set_process_input(false)
	# Snapshot-driven remote players are presentation only on this client. Their
	# collision exists exclusively in the server-side PlayerPhysicsBody proxy.
	collision_layer = 0
	collision_mask = 0
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)
	_set_interaction_detectors_enabled(false)
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null:
		hit_area.set_deferred("monitoring", false)
		hit_area.set_deferred("monitorable", false)
	if is_instance_valid(camera):
		# A remote player never owns a viewport on this client. Remove its camera
		# entirely so Godot cannot promote it if the current local camera exits.
		var proxy_camera := camera as Camera3D
		proxy_camera.current = false
		var camera_parent := proxy_camera.get_parent()
		if camera_parent != null:
			camera_parent.remove_child(proxy_camera)
		proxy_camera.free()
		camera = null
	var ui := get_node_or_null("SubViewport")
	if ui is CanvasLayer:
		ui.visible = false


func _close_active_ui_for_escape() -> bool:
	if is_instance_valid(livestock_chop_page) and livestock_chop_page.is_open():
		livestock_chop_page.close()
		_update_crosshair_visibility()
		return true
	if is_instance_valid(government_notice_page) and government_notice_page.is_open():
		government_notice_page.close()
		_update_crosshair_visibility()
		return true
	if is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open():
		cargo_delivery_page.close()
		_update_crosshair_visibility()
		return true
	if is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open():
		cargo_car_storage_page.close()
		_update_crosshair_visibility()
		return true
	if is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open():
		cargo_crate_storage_page.close()
		_update_crosshair_visibility()
		return true
	if $SubViewport/ShopPage.visible:
		$SubViewport/ShopPage.close_shop()
		return true
	if is_instance_valid(team_chat_panel) and team_chat_panel.is_chat_open():
		team_chat_panel.close_chat()
		return true
	if player_backpack.is_open() and not player_backpack.is_companion_display():
		player_backpack.close()
		_update_crosshair_visibility()
		return true
	var closable_pages: Array[Node] = [
		vehicle_upgrade_page,
		ingredient_pickup_page,
		plating_station_page,
		oven_page,
		griddle_station_page,
		induction_counter_page,
		farm_smoker_page,
		freezer_page,
		stand_mixer_page,
		ingredient_extractor_page,
		auto_cooker_page,
	]
	for page: Node in closable_pages:
		if is_instance_valid(page) and page.has_method("is_open") \
				and bool(page.call("is_open")):
			page.call("close")
			_update_crosshair_visibility()
			return true
	return false


func _inventory_ui_blocks_gameplay_actions() -> bool:
	return (is_instance_valid(player_backpack) and player_backpack.is_open()) \
		or (is_instance_valid(livestock_chop_page) and livestock_chop_page.is_open()) \
		or (is_instance_valid(government_notice_page) and government_notice_page.is_open()) \
		or (is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open()) \
		or (is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open()) \
		or (is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open())


func _input(event: InputEvent) -> void:
	if is_remote_proxy:
		return
	if game_exit_dialog.is_open():
		if event.is_action_pressed("esc", false):
			_close_game_exit_dialog()
			_suppress_esc_mouse_release = true
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("esc", false):
		if _close_active_ui_for_escape():
			_suppress_esc_mouse_release = true
		elif remote_is_active:
			remote_device_close()
			_suppress_esc_mouse_release = true
		elif vehicle_is_active:
			_request_vehicle_exit()
			_suppress_esc_mouse_release = true
		else:
			_open_game_exit_dialog()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(government_notice_page) and government_notice_page.is_open():
		if event.is_action_pressed("interact", false):
			government_notice_page.close()
			get_viewport().set_input_as_handled()
		return
	var text_input_focused := bool(team_chat_panel.call("is_text_input_focused"))
	var modified_talk := bool(team_chat_panel.call("is_modified_talk_event", event))
	if modified_talk or (event.is_action_pressed("talk", false) and not text_input_focused):
		team_chat_panel.toggle_chat()
		_update_crosshair_visibility()
		get_viewport().set_input_as_handled()
		return
	if team_chat_panel.is_chat_open():
		if event.is_action_pressed("enter", false):
			team_chat_panel.submit_current_text()
			get_viewport().set_input_as_handled()
		return
	if is_respawning:
		return
	if is_instance_valid(vehicle_upgrade_page) and vehicle_upgrade_page.has_method("is_open") \
			and bool(vehicle_upgrade_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			vehicle_upgrade_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("bag", false) and not vehicle_is_active and not remote_is_active:
		player_backpack.toggle_personal()
		_update_crosshair_visibility()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("team_storage", false) and not vehicle_is_active and not remote_is_active:
		player_backpack.toggle_team_storage()
		_update_crosshair_visibility()
		get_viewport().set_input_as_handled()
		return
	if player_backpack.is_open() and not player_backpack.is_companion_display():
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			player_backpack.close()
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(ingredient_pickup_page) and ingredient_pickup_page.has_method("is_open") \
			and bool(ingredient_pickup_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			ingredient_pickup_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(plating_station_page) and plating_station_page.has_method("is_open") \
			and bool(plating_station_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			plating_station_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(oven_page) and oven_page.has_method("is_open") \
			and bool(oven_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			oven_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(griddle_station_page) and griddle_station_page.has_method("is_open") \
			and bool(griddle_station_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			griddle_station_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(induction_counter_page) and induction_counter_page.has_method("is_open") \
			and bool(induction_counter_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			induction_counter_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(farm_smoker_page) and farm_smoker_page.has_method("is_open") \
			and bool(farm_smoker_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			farm_smoker_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(freezer_page) and freezer_page.has_method("is_open") \
			and bool(freezer_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			freezer_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(stand_mixer_page) and stand_mixer_page.has_method("is_open") \
			and bool(stand_mixer_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			stand_mixer_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(ingredient_extractor_page) and ingredient_extractor_page.has_method("is_open") \
			and bool(ingredient_extractor_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			ingredient_extractor_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(auto_cooker_page) and auto_cooker_page.has_method("is_open") \
			and bool(auto_cooker_page.call("is_open")):
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			auto_cooker_page.call("close")
			_suppress_esc_mouse_release = true
			_update_crosshair_visibility()
			get_viewport().set_input_as_handled()
		return
	if $SubViewport/ShopPage.visible:
		return
	# _input runs before Control GUI handling. Stop gameplay actions here without
	# marking the event handled, so inventory slots can still receive mouse input.
	if _inventory_ui_blocks_gameplay_actions():
		_set_weapon_aiming(false)
		return
	
	if vehicle_is_active:
		if event.is_action_pressed("interact", false):
			_request_vehicle_exit()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and is_instance_valid(active_vehicle):
			active_vehicle.rotate_driving_camera(event.relative, mouse_sensitivity)
		return
	if remote_is_active:
		return
	if event.is_action_pressed("second_action", false) and not player_backpack.is_open():
		if _cycle_sprout_blaster_seed():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("prone", false) and not player_backpack.is_open():
		_set_prone_state(not is_prone)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reload", false) and not player_backpack.is_open():
		_request_reload_current_weapon()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("throw", false) and not player_backpack.is_open():
		_request_throw_current_item()
		get_viewport().set_input_as_handled()
		return
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:

		var sensitivity_scale := 0.62 if is_weapon_aiming else 1.0
		var horizontal_scale := sensitivity_scale / 3.0 if is_prone else sensitivity_scale
		rotate_y(-event.relative.x * mouse_sensitivity * horizontal_scale)
		# 瞄准期间锁定俯仰角，准心不会因鼠标上下移动而离开枪口轴线。
		#if not is_weapon_aiming:
			#print("ROTATION HEAD")
		Head.rotation.x -= \
			event.relative.y * mouse_sensitivity * sensitivity_scale
		Head.rotation.x = clamp(
				Head.rotation.x,
				deg_to_rad(-_current_look_angle_limit()),
				deg_to_rad(_current_look_angle_limit())
			)
			#tool_node.rotation.x = -Head.rotation.x
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var direct_index := _tool_index_from_key(event.physical_keycode)
		if direct_index >= 0:
			_select_tool(direct_index)
			get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton

	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
		_select_tool(wrapi(current_tool_index + 1, 0, tool_definitions.size()))
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
		_select_tool(wrapi(current_tool_index - 1, 0, tool_definitions.size()))
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_set_weapon_aiming(mouse_event.pressed)
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_use_current_tool()


func _tool_index_from_key(key: Key) -> int:
	match key:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
	return -1


func _submit_authority_input(input_direction: Vector2, jumped: bool, delta: float) -> void:
	input_sequence += 1
	if jumped:
		jump_sequence += 1
	var submitted_move := Vector2.ZERO if remote_is_active else input_direction
	var frame := {
		"input_seq": input_sequence,
		"client_time_msec": Time.get_ticks_msec(),
		"move": submitted_move,
		"jump_seq": jump_sequence,
		"yaw": rotation.y,
		"pitch": Head.rotation.x,
		"prone": is_prone,
	}
	if GameAuthority.should_send_network_requests():
		var prediction_frame := frame.duplicate(true)
		prediction_frame["jumped"] = jumped
		prediction_frame["delta"] = delta
		pending_input_frames.append(prediction_frame)
		if pending_input_frames.size() > 120:
			pending_input_frames.pop_front()
		MultiplayerNetwork.submit_player_input(frame)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_receive_player_input(authority_peer_id, frame)


func _make_tool_request() -> Dictionary:
	var tool_id := ""
	if current_tool_index >= 0 and current_tool_index < tool_definitions.size():
		tool_id = str(tool_definitions[current_tool_index].get("id", ""))
	var origin := global_position
	var direction := -global_transform.basis.z
	if is_instance_valid(camera):
		origin = camera.global_position
		direction = -camera.global_transform.basis.z
	var muzzle: Node3D = null
	if is_instance_valid(tool_node):
		muzzle = tool_node.get_node_or_null("Muzzle") as Node3D
	if muzzle != null:
		origin = muzzle.global_position
	var target_tile_path := ""
	var target_position := Vector3.ZERO
	var look_raycast := find_child("LookAtTarget", true, false) as RayCast3D
	if look_raycast != null:
		look_raycast.force_raycast_update()
		if look_raycast.is_colliding():
			target_position = look_raycast.get_collision_point()
			var tile := Farmlandmanager.resolve_raycast_tile(look_raycast)
			if tile != null:
				target_tile_path = str(tile.get_path())
	if tool_id == "fertilizer" and is_instance_valid(tool_node) and tool_node.has_method("get_fertilizer_targeting_request"):
		var targeting: Variant = tool_node.call("get_fertilizer_targeting_request")
		if targeting is Dictionary:
			var targeting_data := targeting as Dictionary
			origin = targeting_data.get("origin", origin)
			direction = targeting_data.get("direction", direction)
			target_position = targeting_data.get("target_position", target_position)
			target_tile_path = str(targeting_data.get("target_tile_path", target_tile_path))
	var request := {
		"input_seq": input_sequence,
		"client_time_msec": Time.get_ticks_msec(),
		"tool_id": tool_id,
		"tool_index": current_tool_index,
		"origin": origin,
		"direction": direction.normalized(),
		"target_tile_path": target_tile_path,
		"target_position": target_position,
		"player_position": global_position,
		"yaw": rotation.y,
		"pitch": Head.rotation.x,
	}
	if tool_id == "sprout_blaster":
		request["seed_id"] = _get_selected_sprout_seed_id()
	return request


func _plantable_seed_ids() -> Array[String]:
	return IngredientCatalog.get_plantable_ids()


func _default_sprout_seed_id() -> String:
	var seed_ids := _plantable_seed_ids()
	if seed_ids.has("potato"):
		return "potato"
	return seed_ids[0] if not seed_ids.is_empty() else ""


func _get_selected_sprout_seed_id() -> String:
	if current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return _default_sprout_seed_id()
	var item := backpack_items[current_tool_index]
	var seed_id := str(item.get("selected_seed_id", ""))
	return seed_id if IngredientCatalog.is_plantable(seed_id) else _default_sprout_seed_id()


func _cycle_sprout_blaster_seed() -> bool:
	if is_prone or vehicle_is_active or remote_is_active or is_respawning \
			or current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return false
	var item := backpack_items[current_tool_index]
	if str(item.get("kind", "")) != "tool" \
			or str(item.get("tool_id", "")) != "sprout_blaster":
		return false
	var seed_ids := _plantable_seed_ids()
	if seed_ids.is_empty():
		return false
	var current_seed := _get_selected_sprout_seed_id()
	var current_index := seed_ids.find(current_seed)
	var next_seed := seed_ids[wrapi(current_index + 1, 0, seed_ids.size())]
	item["selected_seed_id"] = next_seed
	backpack_items[current_tool_index] = item
	if is_instance_valid(tool_node):
		tool_node.set("selected_seed_id", next_seed)
	_update_ammo_ui()
	return true


func _submit_remote_control_frame() -> void:
	if not is_instance_valid(remote_tool_node):
		return
	var device_id := _remote_device_id(remote_tool_node)
	if device_id.is_empty():
		return
	remote_input_sequence += 1
	if _remote_jump_just_pressed():
		remote_jump_sequence += 1
	var frame := {
		"device_id": device_id,
		"device_path": device_id,
		"device_type": _remote_device_type(remote_tool_node),
		"client_time_msec": Time.get_ticks_msec(),
		"input_seq": remote_input_sequence,
		"move": Input.get_vector("remote_left", "remote_right", "remote_forward", "remote_backward"),
		"vertical": Input.get_axis("remote_descend", "remote_ascend"),
		"jump_seq": remote_jump_sequence,
		"primary": Input.is_action_pressed("remote_primary_action"),
		"second": Input.is_action_pressed("remote_second_action"),
		"interact": Input.is_action_pressed("remote_interact"),
		"position": remote_tool_node.global_position,
		"velocity": remote_tool_node.get("velocity") if remote_tool_node is CharacterBody3D else Vector3.ZERO,
		"yaw": remote_tool_node.rotation.y,
	}
	if remote_tool_node.has_method("record_network_prediction"):
		remote_tool_node.call("record_network_prediction", frame)
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_remote_control_input(frame)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_remote_control_input(authority_peer_id, frame)


func _submit_vehicle_control_frame() -> void:
	if not is_instance_valid(active_vehicle) or active_vehicle_id.is_empty():
		return
	vehicle_input_sequence += 1
	var ui_blocks_drive := is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open()
	var frame := {
		"vehicle_id": active_vehicle_id,
		"input_seq": vehicle_input_sequence,
		"throttle": 0.0 if ui_blocks_drive else Input.get_axis("backward", "forward"),
		"steering": 0.0 if ui_blocks_drive else Input.get_axis("left", "right"),
		"brake": 1.0 if ui_blocks_drive or Input.is_action_pressed("jump") else 0.0,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_vehicle_input(frame)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_vehicle_input(authority_peer_id, frame)


func _request_vehicle_enter(vehicle: VehicleBase) -> void:
	if vehicle_is_active or vehicle == null or vehicle.is_full() or not vehicle.can_team_enter(team):
		return
	_set_prone_state(false)
	var vehicle_id := vehicle.get_vehicle_id()
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_vehicle_session(vehicle_id, true)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_vehicle_session(authority_peer_id, vehicle_id, true)
	else:
		var seat_index := vehicle.get_available_seat_index(true)
		if vehicle.enter_seat(authority_peer_id, seat_index):
			apply_vehicle_session_result({
				"ok": true,
				"connected": true,
				"vehicle_id": vehicle_id,
				"seat_index": seat_index,
			}, vehicle)


func _request_vehicle_exit() -> void:
	if not vehicle_is_active or active_vehicle_id.is_empty():
		return
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_vehicle_session(active_vehicle_id, false)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_vehicle_session(authority_peer_id, active_vehicle_id, false)
	elif is_instance_valid(active_vehicle):
		var seat_index := active_vehicle.exit_seat(authority_peer_id)
		apply_vehicle_session_result({
			"ok": seat_index >= 0,
			"connected": false,
			"vehicle_id": active_vehicle_id,
			"seat_index": seat_index,
			"exit_position": active_vehicle.get_exit_position(seat_index),
		}, active_vehicle)


func apply_vehicle_session_result(result: Dictionary, vehicle: VehicleBase = null) -> void:
	if int(result.get("peer_id", authority_peer_id)) != authority_peer_id:
		return
	if not bool(result.get("ok", false)):
		print("[VehicleSession] local request rejected: %s" % str(result.get("reason", "unknown")))
		return
	var connected := bool(result.get("connected", false))
	if connected:
		_disconnect_active_vehicle_damage_signal()
		active_vehicle = vehicle if is_instance_valid(vehicle) else _find_vehicle_by_id(str(result.get("vehicle_id", "")))
		if not is_instance_valid(active_vehicle):
			return
		active_vehicle_id = active_vehicle.get_vehicle_id()
		active_vehicle_seat_index = int(result.get("seat_index", -1))
		vehicle_is_active = active_vehicle_seat_index >= 0
		_connect_active_vehicle_damage_signal()
		_set_vehicle_player_runtime(true)
		active_vehicle.reset_driving_camera_orbit()
		_ensure_vehicle_camera()
		_update_vehicle_occupant_presentation()
	else:
		_disconnect_active_vehicle_damage_signal()
		var exit_position: Variant = result.get("exit_position", Vector3.ZERO)
		vehicle_is_active = false
		active_vehicle_id = ""
		active_vehicle_seat_index = -1
		active_vehicle = null
		_set_vehicle_player_runtime(false)
		if exit_position is Vector3:
			global_position = exit_position
			velocity = Vector3.ZERO
		if is_instance_valid(camera):
			camera.make_current()


func apply_vehicle_snapshot(vehicle_id: String, seat_index: int) -> void:
	if vehicle_id.is_empty() or seat_index < 0:
		if vehicle_is_active:
			apply_vehicle_session_result({"ok": true, "connected": false, "exit_position": global_position})
		return
	var vehicle := _find_vehicle_by_id(vehicle_id)
	if vehicle == null:
		return
	if is_remote_proxy:
		active_vehicle = vehicle
		active_vehicle_id = vehicle_id
		active_vehicle_seat_index = seat_index
		vehicle_is_active = true
		_set_vehicle_player_runtime(true)
		_update_vehicle_occupant_presentation()
	elif not vehicle_is_active and authority_peer_id == MultiplayerNetwork.get_unique_peer_id():
		apply_vehicle_session_result({
			"ok": true,
			"connected": true,
			"vehicle_id": vehicle_id,
			"seat_index": seat_index,
		}, vehicle)


func _find_vehicle_by_id(vehicle_id: String) -> VehicleBase:
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).get_vehicle_id() == vehicle_id:
			return node as VehicleBase
	return null


func _ensure_vehicle_camera() -> void:
	if not vehicle_is_active or not is_instance_valid(active_vehicle):
		return
	var vehicle_camera := active_vehicle.get_driving_camera()
	if is_instance_valid(vehicle_camera):
		if is_instance_valid(camera):
			camera.current = false
		vehicle_camera.make_current()


func _update_vehicle_occupant_presentation() -> void:
	if not vehicle_is_active or not is_instance_valid(active_vehicle):
		return
	global_transform = active_vehicle.get_occupant_world_transform(active_vehicle_seat_index)
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	var show_occupant := active_vehicle.should_show_occupant(active_vehicle_seat_index)
	if appearance != null:
		appearance.visible = show_occupant
	if is_instance_valid(tool_node):
		tool_node.visible = false
	if is_instance_valid(held_item_node):
		held_item_node.visible = false
	if show_occupant and is_instance_valid(appearance_player):
		appearance_player.play(&"Idle")


func _set_vehicle_player_runtime(seated: bool) -> void:
	_set_weapon_aiming(false)
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance != null:
		appearance.visible = not seated or (is_instance_valid(active_vehicle) and active_vehicle.should_show_occupant(active_vehicle_seat_index))
	if is_instance_valid(tool_node):
		tool_node.visible = not seated and not is_respawning and not is_prone
	if is_instance_valid(held_item_node):
		held_item_node.visible = not seated and not is_respawning and not is_prone
	if is_instance_valid(crosshair):
		crosshair.visible = not seated
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", seated or is_respawning or is_remote_proxy)
	collision_layer = 0 if seated or is_respawning or is_remote_proxy else PLAYER_COLLISION_LAYER
	collision_mask = 0 if seated or is_respawning or is_remote_proxy else PLAYER_COLLISION_MASK
	_set_interaction_detectors_enabled(not seated and not is_respawning and not is_remote_proxy)
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null:
		hit_area.set_deferred("monitoring", not seated and not is_respawning and not is_remote_proxy)
		hit_area.set_deferred("monitorable", not seated and not is_respawning and not is_remote_proxy)


func _remote_jump_just_pressed() -> bool:
	var action_name := "remote_jump" if InputMap.has_action("remote_jump") else "remote_ascend"
	return InputMap.has_action(action_name) and Input.is_action_just_pressed(action_name)


func _remote_device_type(node: Node) -> String:
	if node is ActionDrone:
		return "action_drone"
	if node is TechDrone:
		return "tech_drone"
	if node is NormalDrone:
		return "normal_drone"
	if node is BoomBuggy:
		return "boom_buggy"
	if node is SmallMouse:
		return "small_mouse"
	return str(node.get_meta("device_type", "remote"))


func _on_authority_player_correction(peer_id: int, correction: Dictionary) -> void:
	if peer_id != authority_peer_id:
		return
	var acknowledged_seq := int(correction.get("input_seq", 0))
	if acknowledged_seq < last_server_correction_seq:
		return
	last_server_correction_seq = acknowledged_seq
	if not GameAuthority.should_send_network_requests():
		return
	pending_server_correction = correction.duplicate(true)


func _apply_server_correction() -> void:
	if pending_server_correction.is_empty():
		return
	var correction := pending_server_correction
	pending_server_correction = {}
	var server_position: Variant = correction.get("position", global_position)
	var server_velocity: Variant = correction.get("velocity", velocity)
	if not server_position is Vector3 or not server_velocity is Vector3:
		return
	if is_respawning:
		_update_cooldown_ring()
		# A dead player must never replay buffered input. Keep its presentation
		# anchored to the authoritative state until the respawn event arrives.
		pending_input_frames.clear()
		global_position = server_position
		velocity = Vector3.ZERO
		return
	var acknowledged_seq := int(correction.get("input_seq", 0))
	while not pending_input_frames.is_empty() and int(pending_input_frames.front().get("input_seq", 0)) <= acknowledged_seq:
		pending_input_frames.pop_front()
	var rendered_position := global_position
	var rendered_velocity := velocity
	var rendered_grounded := is_on_floor()
	global_position = server_position
	velocity = server_velocity
	# Replaying unacknowledged input keeps the local player responsive while the
	# server remains the sole source of truth for the baseline state.
	for frame in pending_input_frames:
		_replay_predicted_input(frame)
	var reconciled_position := global_position
	var reconciled_velocity := velocity
	var correction_distance := rendered_position.distance_to(reconciled_position)
	if correction_distance >= PLAYER_HARD_CORRECTION_DISTANCE:
		global_position = reconciled_position
		velocity = reconciled_velocity
	elif correction_distance >= PLAYER_SOFT_CORRECTION_DISTANCE:
		var blended_position := rendered_position.lerp(reconciled_position, PLAYER_CORRECTION_BLEND)
		var blended_velocity := rendered_velocity.lerp(reconciled_velocity, PLAYER_CORRECTION_BLEND)
		var server_grounded := bool(correction.get("grounded", false))
		var vertical_error := absf(rendered_position.y - reconciled_position.y)
		if not rendered_grounded and not server_grounded \
				and vertical_error <= PLAYER_AIRBORNE_VERTICAL_TOLERANCE:
			# Horizontal prediction still reconciles normally. Small vertical timing
			# differences must not flatten the jump arc for a frame.
			blended_position.y = rendered_position.y
			blended_velocity.y = rendered_velocity.y
		global_position = blended_position
		velocity = blended_velocity
	else:
		global_position = rendered_position
		velocity = rendered_velocity


func _replay_predicted_input(frame: Dictionary) -> void:
	var input_direction := _vector2_from_input(frame.get("move", Vector2.ZERO))
	_simulate_predicted_movement(
		NETWORK_SIMULATION_DELTA,
		input_direction,
		bool(frame.get("jumped", false)),
		float(frame.get("yaw", rotation.y)),
		bool(frame.get("prone", is_prone))
	)


func _vector2_from_input(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _simulate_predicted_movement(
	delta: float,
	input_direction: Vector2,
	jumped: bool,
	movement_yaw := rotation.y,
	prone_state := is_prone
) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if jumped and not prone_state and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var basis := Basis(Vector3.UP, movement_yaw)
	var direction := (basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	var move_speed := SPEED * _equipped_legwear_speed_multiplier()
	move_speed *= PRONE_SPEED_MULTIPLIER if prone_state else 1.0
	velocity.x = direction.x * move_speed + rubber_knockback.x
	velocity.z = direction.z * move_speed + rubber_knockback.z
	rubber_knockback = rubber_knockback.move_toward(Vector3.ZERO, 18.0 * delta)
	move_and_slide()


func _select_tool(new_index: int, force := false) -> void:
	if new_index < 0 or new_index >= tool_definitions.size():
		return
	var selected_item := get_backpack_item(new_index)
	if str(selected_item.get("kind", "")) != "tool":
		_select_handheld_item(new_index, selected_item, force)
		return
	if not force and new_index == current_tool_index and is_instance_valid(tool_node):
		return

	_set_weapon_aiming(false)
	_clear_tool_node()
	_clear_held_item_node()

	current_tool_index = new_index
	var definition: Dictionary = tool_definitions[current_tool_index]
	if definition.is_empty():
		_select_empty_hotbar_slot(current_tool_index)
		return
	var packed_scene := load(str(definition["path"])) as PackedScene
	if packed_scene == null:
		push_error("无法加载工具场景：" + str(definition["path"]))
		_refresh_hotbar()
		return

	tool_node = packed_scene.instantiate() as Node3D
	if tool_node is VehicleBase:
		(tool_node as VehicleBase).vehicle_deployed = false
	tool_pivot.add_child(tool_node)
	tool_node.set("tool_owner", team)
	if str(definition.get("id", "")) == "sprout_blaster":
		var seed_id := _get_selected_sprout_seed_id()
		backpack_items[current_tool_index]["selected_seed_id"] = seed_id
		tool_node.set("selected_seed_id", seed_id)
	tool_node.visible = not is_prone and not vehicle_is_active and not is_respawning
	
	var is_shooting_tool := _definition_uses_weapon_orientation(definition)
	# Non-weapon tools use the hand socket's neutral transform. Their imported
	# model is corrected upright below; only scale remains data-driven.
	tool_node.position = definition.get("grip_position", Vector3.ZERO) if is_shooting_tool else Vector3.ZERO
	tool_node.rotation_degrees = definition.get("grip_rotation", Vector3.ZERO) if is_shooting_tool else Vector3.ZERO
	tool_node.scale = definition.get(
		"grip_scale",
		Vector3.ONE
	)
	var left_hand_grip := tool_node.get_node_or_null("LeftHandGrip") as Marker3D
	if left_hand_grip != null and bool(definition.get("two_handed", false)):
		left_hand_grip.position = definition.get(
			"left_hand_grip_offset",
			left_hand_grip.position
		)
	# Utility tools are displayed as held objects rather than aimed weapons.
	# Normalize their model's local Y axis so imported GLB axis differences do
	# not make the object appear upside down or lying on its side.
	if not is_shooting_tool:
		_schedule_held_model_upright(tool_node)

	_refresh_hotbar()
	if is_remote_proxy:
		return
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_select_tool(current_tool_index, _selected_tool_id())
	elif GameAuthority.is_local_authority():
		GameAuthority.local_select_tool(authority_peer_id, current_tool_index, _selected_tool_id())


func _select_handheld_item(new_index: int, item: Dictionary, force := false) -> void:
	if item.is_empty():
		_select_empty_hotbar_slot(new_index)
		return
	if not force and new_index == current_tool_index and is_instance_valid(held_item_node):
		return
	var model_path := _get_handheld_item_model_path(item)
	if model_path.is_empty():
		_select_empty_hotbar_slot(new_index)
		return
	var packed_scene := load(model_path) as PackedScene
	if packed_scene == null:
		push_warning("无法加载手持物品模型：" + model_path)
		_select_empty_hotbar_slot(new_index)
		return
	_set_weapon_aiming(false)
	_clear_tool_node()
	_clear_held_item_node()
	current_tool_index = new_index
	held_item_node = packed_scene.instantiate() as Node3D
	if held_item_node == null:
		_select_empty_hotbar_slot(new_index)
		return
	if str(item.get("kind", "")) == "cargo_crate" and held_item_node is CargoCrateGround:
		held_item_node.set_meta("held_preview", true)
		(held_item_node as CargoCrateGround).setup_crate(item)
	tool_pivot.add_child(held_item_node)
	held_item_node.visible = not is_prone and not vehicle_is_active and not is_respawning
	_disable_handheld_item_collision(held_item_node)
	held_item_node.position = item.get("handheld_position", handheld_item_position)
	held_item_node.rotation_degrees = _get_handheld_item_rotation_degrees(item)
	held_item_node.scale = item.get("handheld_scale", handheld_item_scale)
	_schedule_held_model_upright(held_item_node)
	held_item_node.set_meta("selection_replication_id", _handheld_item_replication_id(item))
	_refresh_hotbar()
	if is_remote_proxy:
		return
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_select_tool(current_tool_index, _selected_tool_id())
	elif GameAuthority.is_local_authority():
		GameAuthority.local_select_tool(authority_peer_id, current_tool_index, _selected_tool_id())


func _get_handheld_item_model_path(item: Dictionary) -> String:
	var explicit_path := str(item.get("handheld_model_path", item.get("model_path", "")))
	if not explicit_path.is_empty():
		return explicit_path
	if str(item.get("kind", "")) != "ingredient":
		return DishCatalog.get_model_path(str(item.get("dish_id", ""))) if str(item.get("kind", "")) == "dish" else ""
	var ingredient_id := str(item.get("ingredient_id", ""))
	var is_chopped := _is_chopped_ingredient_item(item)
	if is_chopped:
		var chopped_path := IngredientCatalog.get_model_path(ingredient_id, "chopped_item")
		if not chopped_path.is_empty():
			return chopped_path
	var whole_path := IngredientCatalog.get_model_path(ingredient_id, "whole_item")
	return whole_path if not whole_path.is_empty() else IngredientCatalog.get_harvest_drop_scene_path(ingredient_id)


func _get_handheld_item_rotation_degrees(item: Dictionary) -> Vector3:
	var rotation_value: Variant = item.get("handheld_rotation_degrees", null)
	if rotation_value == null and str(item.get("kind", "")) == "dish":
		rotation_value = DishCatalog.get_definition(str(item.get("dish_id", ""))).get(
			"handheld_rotation_degrees",
			[180.0, 0.0, 0.0]
		)
	if rotation_value is Vector3:
		return rotation_value as Vector3
	if rotation_value is Array and (rotation_value as Array).size() >= 3:
		var values := rotation_value as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return handheld_item_rotation_degrees


func _upright_held_model(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var world_basis := node.global_transform.basis.orthonormalized()
	var model_world_up := world_basis.y.normalized()
	var mesh := _find_first_mesh_instance(node)
	if mesh != null:
		# Read the imported mesh's actual world-space local Y axis. The hand
		# socket may be rotated with the character, but the desired up direction
		# is always the map's global Vector3.UP.
		model_world_up = mesh.global_transform.basis.y.normalized()
	if model_world_up.length_squared() < 0.001 \
			or model_world_up.is_equal_approx(Vector3.UP):
		return
	var correction := Quaternion(model_world_up, Vector3.UP)
	if absf(correction.w) > 0.99999:
		return
	var corrected_world_basis := Basis(correction) * world_basis
	var parent := node.get_parent() as Node3D
	var parent_basis := parent.global_transform.basis.orthonormalized() \
			if parent != null else Basis.IDENTITY
	# Convert the corrected world orientation back to the node's local
	# rotation without changing its configured position or scale.
	node.rotation = (parent_basis.inverse() * corrected_world_basis).get_euler()


func _schedule_held_model_upright(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	_upright_held_model(node)
	# Imported GLB scene transforms can settle after the initial add_child.
	# Reapply once on the next idle frame whenever the inventory slot changes.
	call_deferred("_upright_held_model_deferred", node)


func _upright_held_model_deferred(node: Node3D) -> void:
	if is_instance_valid(node) and node.get_parent() == tool_pivot:
		_upright_held_model(node)


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested := _find_first_mesh_instance(child)
		if nested != null:
			return nested
	return null


func _is_chopped_ingredient_item(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) \
		or str(item.get("preparation", "")) == "chopped" \
		or str(item.get("model_state", "")) == "chopped"


func _handheld_item_replication_id(item: Dictionary) -> String:
	if str(item.get("kind", "")) == "cargo_crate":
		return "cargo_crate:" + str(item.get("crate_size", "medium"))
	if str(item.get("kind", "")) == "dish":
		return "dish:" + str(item.get("dish_id", ""))
	if str(item.get("kind", "")) != "ingredient":
		return ""
	var ingredient_id := str(item.get("ingredient_id", ""))
	if ingredient_id.is_empty():
		return ""
	return HANDHELD_INGREDIENT_PREFIX + ingredient_id + (":chopped" if _is_chopped_ingredient_item(item) else ":whole")


func _ingredient_item_from_replication_id(replication_id: String) -> Dictionary:
	if replication_id.begins_with("cargo_crate:"):
		return CargoCrateData.create_empty(replication_id.trim_prefix("cargo_crate:"), "remote_visual")
	if replication_id.begins_with("dish:"):
		var dish_id := replication_id.trim_prefix("dish:")
		return {"kind": "dish", "dish_id": dish_id, "servings": 0, "weight_kg": 0.0} if not DishCatalog.get_definition(dish_id).is_empty() else {}
	if not replication_id.begins_with(HANDHELD_INGREDIENT_PREFIX):
		return {}
	var parts := replication_id.split(":", false)
	if parts.size() != 3 or parts[1].is_empty() or IngredientCatalog.get_definition(parts[1]).is_empty():
		return {}
	return {
		"kind": "ingredient",
		"ingredient_id": parts[1],
		"is_chopped": parts[2] == "chopped",
	}


func _clear_tool_node() -> void:
	if is_instance_valid(tool_node):
		tool_pivot.remove_child(tool_node)
		tool_node.queue_free()
		tool_node = null


func _clear_held_item_node() -> void:
	if is_instance_valid(held_item_node):
		tool_pivot.remove_child(held_item_node)
		held_item_node.queue_free()
		held_item_node = null


func _disable_handheld_item_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	for child in node.get_children():
		_disable_handheld_item_collision(child)


func _select_empty_hotbar_slot(selected_slot := -1) -> void:
	_set_weapon_aiming(false)
	_clear_tool_node()
	_clear_held_item_node()
	current_tool_index = selected_slot
	_refresh_hotbar()
	if is_remote_proxy:
		return
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_select_tool(current_tool_index, "")
	elif GameAuthority.is_local_authority():
		GameAuthority.local_select_tool(authority_peer_id, current_tool_index, "")


func _selected_tool_id() -> String:
	if is_instance_valid(tool_node) and _has_equipped_tool(current_tool_index):
		return str(tool_definitions[current_tool_index].get("id", ""))
	if is_instance_valid(held_item_node):
		return str(held_item_node.get_meta("selection_replication_id", ""))
	return ""


func _selected_item_uses_carry_pose() -> bool:
	var selection_id := _selected_tool_id()
	return selection_id.begins_with("animal_") or selection_id.begins_with("cargo_crate:")


func _use_current_tool() -> void:
	#emotion_controller.set_expression(EmotionController.EmotionType.FUNNY)
	if is_respawning or is_prone or _inventory_ui_blocks_gameplay_actions():
		return
	var selected_inventory_item := get_backpack_item(current_tool_index)
	if str(selected_inventory_item.get("kind", "")) == "cargo_crate":
		_request_place_carried_cargo_crate(selected_inventory_item)
		return
	if not _has_equipped_tool(current_tool_index) or not is_instance_valid(tool_node):
		_use_fist()
		return
	# RiftBook's cooldown limits placing the next anchor. A landed anchor can
	# always be used for teleportation immediately, so let the authoritative
	# request decide whether this click is a teleport or a new launch.
	var selected_tool_id := str(tool_definitions[current_tool_index].get("id", ""))
	if _selected_weapon_uses_ammo():
		var selected_item := backpack_items[current_tool_index]
		if float(selected_item.get("reload_remaining", 0.0)) > 0.0:
			show_gameplay_notice("正在换弹")
			return
		if int(selected_item.get("ammo_in_mag", 0)) <= 0:
			show_gameplay_notice("弹匣为空，按装弹键换弹")
			return
	if tool_cooldowns[current_tool_index] > 0.0 and selected_tool_id != "rift_book":
		_flash_cooldown_slot(current_tool_index)
		return
	var definition: Dictionary = tool_definitions[current_tool_index]
	var category := str(definition.get("category", "utility"))
	if not tool_node.has_method("emit") \
			and not bool(definition.get("free_placement", false)) \
			and category != "throwable":
		return

	var ret = null
	if GameAuthority.should_send_network_requests():
		_consume_predicted_ammo()
		MultiplayerNetwork.submit_use_tool(_make_tool_request())
		_play_local_tool_visual()
	elif GameAuthority.is_local_authority():
		# 单人模式也走 GameAuthority 的本地权威入口。
		# 不能先调用旧 emit() 再调用 local_try_use_tool()，否则 FarmRunner/放置类工具会执行两次。
		ret = GameAuthority.local_try_use_tool(authority_peer_id, _make_tool_request())
		if not (ret is Dictionary) or bool((ret as Dictionary).get("ok", false)):
			_play_local_tool_visual(ret)
	else:
		# 兼容没有启用 GameAuthority 的旧测试场景。
		ret = tool_node.call("emit")
		_consume_predicted_ammo()
	## 这里要更新工具的安装位置
	
	## 处理工具的类别，如果是remote要特殊处理
	var tool_category = str(tool_definitions[current_tool_index].get("category", "utility"))
	match tool_category:
		"remote":
			if ret is Dictionary:
				var node = ret.get("remote_node",null)
				remote_device_reset(node)
				remote_device_start()
		_:
			pass
	## END
	
	_set_tool_action()
	# Local authority returns the placement rejection immediately. Do not consume a
	# long placement cooldown when slope or clearance validation fails.
	var action_accepted := not (ret is Dictionary and not bool((ret as Dictionary).get("ok", false)))
	var starts_tool_cooldown := action_accepted
	if selected_tool_id == "rift_book" and ret is Dictionary:
		starts_tool_cooldown = str((ret as Dictionary).get("rift_action", "")) == "launch"
	if ret is Dictionary and not str((ret as Dictionary).get("consumed_tool_id", "")).is_empty():
		starts_tool_cooldown = false
	if starts_tool_cooldown:
		tool_cooldowns[current_tool_index] = float(
			tool_definitions[current_tool_index]["cooldown"]
		)
	_refresh_hotbar()
	_update_ammo_ui()


func _selected_weapon_uses_ammo() -> bool:
	if current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return false
	var item := backpack_items[current_tool_index]
	if str(item.get("kind", "")) != "tool":
		return false
	var definition: Dictionary = all_tool_definitions_by_id.get(str(item.get("tool_id", "")), {})
	return definition.has("magazine_size")


func _consume_predicted_ammo() -> void:
	if not _selected_weapon_uses_ammo():
		return
	var item := backpack_items[current_tool_index]
	item["ammo_in_mag"] = maxi(0, int(item.get("ammo_in_mag", 0)) - 1)
	backpack_items[current_tool_index] = item


func _request_reload_current_weapon() -> void:
	if is_prone or vehicle_is_active or remote_is_active or is_respawning or not _selected_weapon_uses_ammo():
		return
	var item := backpack_items[current_tool_index]
	var tool_id := str(item.get("tool_id", ""))
	var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
	if float(item.get("reload_remaining", 0.0)) > 0.0:
		return
	if int(item.get("ammo_in_mag", 0)) >= int(definition.get("magazine_size", 1)):
		return
	if int(item.get("reserve_ammo", 0)) <= 0:
		show_gameplay_notice("没有备用弹药")
		return
	if GameAuthority.should_send_network_requests():
		var reload_time := maxf(0.05, float(definition.get("reload_time", 1.0)))
		item["reload_remaining"] = reload_time
		item["reload_duration"] = reload_time
		backpack_items[current_tool_index] = item
		MultiplayerNetwork.submit_reload_weapon(tool_id)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_reload_weapon(authority_peer_id, tool_id)
	else:
		var needed := maxi(0, int(definition.get("magazine_size", 1)) - int(item.get("ammo_in_mag", 0)))
		var transferred := mini(needed, int(item.get("reserve_ammo", 0)))
		item["ammo_in_mag"] = int(item.get("ammo_in_mag", 0)) + transferred
		item["reserve_ammo"] = int(item.get("reserve_ammo", 0)) - transferred
		backpack_items[current_tool_index] = item
	_update_ammo_ui()


func _play_local_tool_visual(authoritative_result: Variant = null) -> void:
	if not is_instance_valid(tool_node) or not tool_node.has_method("emit"):
		return
	var definition: Dictionary = tool_definitions[current_tool_index]
	var tool_id := str(definition.get("id", ""))
	var category := str(definition.get("category", "utility"))
	# Wreck and BugCannon use server-simulated projectile visuals in multiplayer.
	# Running their legacy local projectile scripts there creates a second, divergent
	# cannonball. Single-player has no client replicator, so BugCannon still needs
	# its local flight visual.
	if tool_id == "sprout_blaster" and tool_node.has_method("play_muzzle_visual"):
		tool_node.call("play_muzzle_visual")
	elif tool_id == "fertilizer" and tool_node.has_method("play_muzzle_visual"):
		tool_node.call("play_muzzle_visual")
	elif tool_id == "spicy_blaster":
		# Network clients render the server-snapshotted projectile. Local mode has
		# no replicator, so it still needs the flight-only projectile here.
		if GameAuthority.is_local_authority():
			tool_node.call("emit")
		elif tool_node.has_method("play_muzzle_visual"):
			tool_node.call("play_muzzle_visual")
	elif tool_id == "wand":
		# Multiplayer renders the confirmed server lightning event, including for
		# its owner. Local authority can use the immediate confirmed hit position.
		if authoritative_result is Dictionary \
				and str((authoritative_result as Dictionary).get("hit_kind", "none")) != "none" \
				and tool_node.has_method("play_lightning_at"):
			var hit_position: Variant = (authoritative_result as Dictionary).get(
				"hit_position", Vector3.ZERO
			)
			if hit_position is Vector3:
				tool_node.call("play_lightning_at", hit_position as Vector3)
	elif category == "shooting":
		# Authoritative shooting is resolved immediately by GameAuthority hitscan.
		# Local projectiles are presentation only and must never apply a second hit.
		if tool_node.has_method("emit_visual_only"):
			tool_node.call("emit_visual_only")
		else:
			tool_node.call("emit")
	elif tool_id == "bug_cannon" and GameAuthority.is_local_authority():
		tool_node.call("emit")
	elif tool_id == "medicine_cannon" and GameAuthority.is_local_authority():
		tool_node.call("emit")


func play_remote_tool_visual(tool_id: String, tool_index: int) -> void:
	if not is_remote_proxy:
		return
	if tool_index >= 0 and tool_index < tool_definitions.size() and tool_index != current_tool_index:
		_select_tool(tool_index, true)
	if tool_id == "sprout_blaster" and is_instance_valid(tool_node) and tool_node.has_method("play_muzzle_visual"):
		tool_node.call("play_muzzle_visual")
	elif tool_id == "fertilizer" and is_instance_valid(tool_node) and tool_node.has_method("play_muzzle_visual"):
		tool_node.call("play_muzzle_visual")
	elif tool_id == "spicy_blaster" and is_instance_valid(tool_node) and tool_node.has_method("play_muzzle_visual"):
		tool_node.call("play_muzzle_visual")
	elif is_instance_valid(tool_node) and tool_node.has_method("play_muzzle_visual") \
			and current_tool_index >= 0 and current_tool_index < tool_definitions.size() \
			and str(tool_definitions[current_tool_index].get("category", "")) == "shooting":
		tool_node.call("play_muzzle_visual")

func _process_user_key():
	if Input.is_action_just_pressed("esc"):
		if _suppress_esc_mouse_release:
			_suppress_esc_mouse_release = false
			return
		if player_backpack.is_open():
			player_backpack.close()
			_update_crosshair_visibility()
		elif vehicle_is_active:
			_request_vehicle_exit()
		elif remote_is_active:
			remote_device_close()
		elif remote_device_panel.visible:
			_hide_remote_device_panel()
		else:
			_open_game_exit_dialog()
	elif Input.is_action_just_pressed("remote") and not remote_is_active and not owned_remote_devices.is_empty():
		if remote_device_panel.visible:
			_hide_remote_device_panel()
		else:
			_show_remote_device_panel()


func _open_game_exit_dialog() -> void:
	if remote_is_active:
		remote_device_close()
		_suppress_esc_mouse_release = true
		return
	if vehicle_is_active:
		_request_vehicle_exit()
		return
	if team_chat_panel.is_chat_open():
		team_chat_panel.close_chat()
	_set_weapon_aiming(false)
	game_exit_dialog.open_dialog()
	_update_crosshair_visibility()


func _close_game_exit_dialog() -> void:
	game_exit_dialog.close_dialog()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if $SubViewport/ShopPage.visible \
			else Input.MOUSE_MODE_CAPTURED
	_update_crosshair_visibility()


func _exit_game() -> void:
	if MultiplayerNetwork.is_connected_to_game_server() \
			or MultiplayerNetwork.is_connecting_to_game_server():
		MultiplayerNetwork.disconnect_from_game_server(false)
	get_tree().quit()


func _set_prone_state(value: bool) -> void:
	var next_prone := value and not vehicle_is_active and not remote_is_active and not is_respawning
	if is_prone == next_prone:
		return
	is_prone = next_prone
	_update_prone_collision_shapes()
	_set_weapon_aiming(false)
	if is_prone:
		action_anim_locked = false
		landing_animation = false
		Head.rotation.x = clampf(
			Head.rotation.x,
			deg_to_rad(-_current_look_angle_limit()),
			deg_to_rad(_current_look_angle_limit())
		)
	if is_instance_valid(tool_node):
		tool_node.visible = not is_prone and not vehicle_is_active and not is_respawning
	if is_instance_valid(held_item_node):
		held_item_node.visible = not is_prone and not vehicle_is_active and not is_respawning
	_update_crosshair_visibility()


func _current_look_angle_limit() -> float:
	return float(floori(max_look_angle / 3.0)) if is_prone else max_look_angle


func _update_prone_collision_shapes() -> void:
	# Keep the existing capsule resources and dimensions; only their transforms
	# change to follow the horizontal prone body.
	var prone_basis := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		var body_transform := standing_body_collision_transform
		if is_prone:
			body_transform = Transform3D(prone_basis, prone_body_collision_position)
		body_shape.set_deferred("transform", body_transform)
	var hit_shape := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
	if hit_shape != null:
		var hit_transform := standing_hit_collision_transform
		if is_prone:
			hit_transform = Transform3D(prone_basis, prone_hit_collision_position)
		hit_shape.set_deferred("transform", hit_transform)


func _update_prone_presentation(delta: float) -> void:
	if not is_instance_valid(Head):
		return
	var target := standing_head_position
	if is_prone:
		target = prone_head_position
	Head.position = Head.position.lerp(target, 1.0 - exp(-12.0 * delta))
		
			
	
func _process(delta: float) -> void:
	if is_remote_proxy:
		_update_remote_interpolation()
		_update_prone_presentation(delta)
		_update_team_visibility_timer(delta)
		if vehicle_is_active:
			_update_vehicle_occupant_presentation()
		_update_upper_body_aim(delta)
		return
	_ensure_local_camera_ownership()
	_update_prone_presentation(delta)
	_tick_status_effects(delta)
	_update_health_ui()
	_update_control_status_ui()
	_update_match_timer_ui()
	_update_global_score_ui()
	if game_exit_dialog.is_open():
		_set_weapon_aiming(false)
		_update_cooldown_ring()
		_update_crosshair_visibility()
		return
	if team_chat_panel.is_chat_open():
		_set_weapon_aiming(false)
		_update_cooldown_ring()
		_update_crosshair_visibility()
		return
	if (is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open()) \
			or (is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open()) \
			or (is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open()) \
			or (is_instance_valid(government_notice_page) and government_notice_page.is_open()) \
			or (is_instance_valid(livestock_chop_page) and livestock_chop_page.is_open()):
		_set_weapon_aiming(false)
		_update_cooldown_ring()
		_update_crosshair_visibility()
		return
	if is_respawning:
		if GameAuthority.is_local_authority():
			respawn_left = maxf(0.0, respawn_left - delta)
		_update_death_appearance_visibility()
		_update_cooldown_ring()
		_update_respawn_overlay()
		return
	if remote_is_active:
		_ensure_remote_device_camera()
		_update_remote_camera_shake(delta)
		_process_user_key()
		if not remote_is_active or not is_instance_valid(remote_tool_node):
			return
		var signal_power := _get_active_remote_signal_strength()
		if signal_power < REMOTE_CONTROL_LOST_EFFECTIVE_SIGNAL:
			remote_device_close()
			return
		# Electronic disable corrupts only the video feed. The real link quality
		# above remains authoritative for the existing signal-loss disconnect rule.
		var display_signal_power := signal_power
		if remote_tool_node.has_method("is_electronics_disabled") \
				and bool(remote_tool_node.call("is_electronics_disabled")):
			display_signal_power = 0.0
		_set_remote_effect_signal_strength(remote_effect, display_signal_power)
		_update_cooldown_ring()
		return
	if vehicle_is_active:
		_ensure_vehicle_camera()
		_update_vehicle_occupant_presentation()
		_update_vehicle_camera_shake(delta)
		_process_user_key()
		_update_cooldown_ring()
		return
	if remote_device_panel.visible:
		_update_remote_device_panel()
		
	var cooldown_changed := false
	for index in range(tool_cooldowns.size()):
		if tool_cooldowns[index] > 0.0:
			tool_cooldowns[index] = maxf(0.0, tool_cooldowns[index] - delta)
			cooldown_changed = true
	if cooldown_changed:
		_refresh_hotbar()
	_tick_local_reload_displays(delta)
	_update_continuous_tool_use()


	_update_cooldown_ring()
	
	_process_user_key()
	_update_weapon_aim(delta)
	_update_upper_body_aim(delta)
	_update_tool_camera_alignment()
	_update_crosshair_visibility()
	_update_camera_shake(delta)
	_update_interaction()
	_refresh_interact_hint()


func _update_continuous_tool_use() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if _selected_tool_id() != "repair_welder" \
			or current_tool_index < 0 or current_tool_index >= tool_cooldowns.size():
		return
	if tool_cooldowns[current_tool_index] <= 0.0:
		_use_current_tool()


func _ensure_local_camera_ownership() -> void:
	if remote_is_active or vehicle_is_active or not is_instance_valid(camera):
		return
	if not camera.current:
		print("[CameraOwnership] Restoring local player camera for peer=%d" % authority_peer_id)
		camera.make_current()


func _use_fist() -> void:
	if is_prone or current_tool_index < 0 or current_tool_index >= HOTBAR_SLOT_COUNT:
		return
	if is_instance_valid(appearance_player):
		action_anim_locked = true
		appearance_player.play(&"PunchRight", 0.05)
	var request := _make_tool_request()
	request["tool_id"] = "fist"
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_use_tool(request)
	elif GameAuthority.is_local_authority():
		GameAuthority.local_try_use_tool(authority_peer_id, request)


func _update_global_score_ui() -> void:
	var title := $SubViewport/GlobalStats as Label
	var value := $SubViewport/GlobalStatsValue as RichTextLabel
	if title != null:
		title.visible = false
	if value != null:
		value.text = "[center][color=#FF5656]%d[/color]             [color=#69A7FF]%d[/color][/center]" % [
			GlobalVar.get_team_score("red"),
			GlobalVar.get_team_score("blue"),
		]


func _physics_process(delta: float) -> void:
	if is_remote_proxy:
		return
	if GameAuthority.should_send_network_requests():
		_apply_server_correction()
	if is_respawning:
		velocity = Vector3.ZERO
		return
	if game_exit_dialog.is_open():
		_simulate_predicted_movement(NETWORK_SIMULATION_DELTA, Vector2.ZERO, false)
		_submit_authority_input(Vector2.ZERO, false, NETWORK_SIMULATION_DELTA)
		_update_player_action_animation(Vector2.ZERO)
		return
	if team_chat_panel.is_chat_open():
		_simulate_predicted_movement(NETWORK_SIMULATION_DELTA, Vector2.ZERO, false)
		_submit_authority_input(Vector2.ZERO, false, NETWORK_SIMULATION_DELTA)
		_update_player_action_animation(Vector2.ZERO)
		return
	if big_mouth_capture_remaining > 0.0:
		_update_big_mouth_capture(delta)
		_submit_authority_input(Vector2.ZERO, false, NETWORK_SIMULATION_DELTA)
		_update_player_action_animation(Vector2.ZERO)
		return
	var vehicle_upgrade_open := is_instance_valid(vehicle_upgrade_page) \
		and vehicle_upgrade_page.has_method("is_open") \
		and bool(vehicle_upgrade_page.call("is_open"))
	var cargo_ui_open := (is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open()) \
		or (is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open()) \
		or (is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open()) \
		or (is_instance_valid(livestock_chop_page) and livestock_chop_page.is_open())
	var government_notice_open := is_instance_valid(government_notice_page) \
		and government_notice_page.is_open()
	if player_backpack.is_open() or vehicle_upgrade_open or cargo_ui_open or government_notice_open:
		# UI blocks player input, but gravity, knockback, and collision must continue.
		_simulate_predicted_movement(NETWORK_SIMULATION_DELTA, Vector2.ZERO, false)
		_submit_authority_input(Vector2.ZERO, false, NETWORK_SIMULATION_DELTA)
		_update_player_action_animation(Vector2.ZERO)
		return
	if remote_is_active:
		_submit_remote_control_frame()
		# One shared input owner keeps armed remote devices from double-submitting.
		if (remote_tool_node is SmallMouse or remote_tool_node is NormalDrone or remote_tool_node is TechDrone) and Input.is_action_just_pressed("remote_primary_action") and remote_tool_node.has_method("request_primary_action"):
			remote_tool_node.call("request_primary_action")
		if remote_tool_node is ActionDrone and Input.is_action_just_pressed("remote_second_action") and remote_tool_node.has_method("request_secondary_action"):
			remote_tool_node.call("request_secondary_action")
		return
	if vehicle_is_active:
		_submit_vehicle_control_frame()
		_update_vehicle_occupant_presentation()
		return
	var jump_pressed := Input.is_action_just_pressed("jump")
	var stood_from_prone := is_prone and jump_pressed
	if stood_from_prone:
		_set_prone_state(false)
	var jumped = not stood_from_prone and not is_prone and not remote_is_active and jump_pressed and is_on_floor() and \
		not $SubViewport/ShopPage.visible
	if jumped:
		appearance_player.play("JumpStart",0.05)
	
	 
	var input_direction = Vector2.ZERO
	if remote_is_active == false or (remote_is_active and rubber_knockback.length() > 0):
		input_direction = Vector2.ZERO if $SubViewport/ShopPage.visible else \
			Input.get_vector("left", "right", "forward", "backward")
	_simulate_predicted_movement(NETWORK_SIMULATION_DELTA, input_direction, jumped)
	_submit_authority_input(input_direction, jumped, NETWORK_SIMULATION_DELTA)
	_update_player_action_animation(input_direction)


func apply_big_mouth_capture(anchor_position: Vector3, duration: float, pull_seconds: float) -> void:
	big_mouth_anchor = anchor_position
	big_mouth_capture_remaining = maxf(big_mouth_capture_remaining, duration)
	big_mouth_pull_remaining = maxf(big_mouth_pull_remaining, pull_seconds)
	velocity = Vector3.ZERO
	rubber_knockback = Vector3.ZERO
	pending_input_frames.clear()


func apply_big_mouth_capture_snapshot(remaining: float, anchor_position: Vector3) -> void:
	if remaining <= 0.0:
		release_big_mouth_capture()
		return
	if big_mouth_capture_remaining <= 0.0:
		apply_big_mouth_capture(anchor_position, remaining, 0.28)
	else:
		big_mouth_capture_remaining = remaining
		big_mouth_anchor = anchor_position


func _update_big_mouth_capture(delta: float) -> void:
	big_mouth_capture_remaining = maxf(0.0, big_mouth_capture_remaining - delta)
	big_mouth_pull_remaining = maxf(0.0, big_mouth_pull_remaining - delta)
	if big_mouth_pull_remaining > 0.0:
		global_position = global_position.lerp(big_mouth_anchor, clampf(delta * 16.0, 0.0, 1.0))
	else:
		global_position = big_mouth_anchor
	velocity = Vector3.ZERO


func release_big_mouth_capture() -> void:
	big_mouth_capture_remaining = 0.0
	big_mouth_pull_remaining = 0.0
	velocity = Vector3.ZERO
	pending_input_frames.clear()
	
	
func _play_body_animation(
	anim_name: StringName,
	blend_time := 0.12
) -> void:
	if anim_name == null:
		return

	if appearance_player.current_animation == anim_name \
			and appearance_player.is_playing():
		return

	appearance_player.play(anim_name, blend_time)

func _set_tool_action():
	var definition: Dictionary = tool_definitions[current_tool_index]

	var category := str(
		definition.get("category", "utility")
	)
	action_anim_locked = true
	match category:
		"shooting":
			appearance_player.play(&"ShootOneHand", 0.05)
		"melee":
			appearance_player.play(&"PunchRight", 0.05)
		_:
			appearance_player.play(&"ToolUseRight", 0.05)


func get_rift_book_request() -> Dictionary:
	var direction := -global_transform.basis.z
	if is_instance_valid(camera):
		direction = -camera.global_transform.basis.z
	return {
		"tool_id": "rift_book",
		"tool_index": current_tool_index,
		"origin": camera.global_position if is_instance_valid(camera) else global_position + Vector3.UP * 1.4,
		"direction": direction.normalized(),
		"player_position": global_position,
		"carrying_item": is_instance_valid(held_item_node) and held_item_node.visible,
		"in_vehicle": vehicle_is_active,
	}
		
func _update_player_action_animation(direction_strength:Vector2):
	if appearance_player==null:
		return
	if action_anim_locked:
		return
	
	var ground = is_on_floor()
	if is_prone and ground:
		action_anim_locked = false
		landing_animation = false
		_play_body_animation(&"ProneCrawl", 0.10)
		was_on_floor = true
		return
	#print("CURRENT:",ground)
	if ground and not was_on_floor:
		#print("JumpLand")
		appearance_player.play("JumpLand",0.05)
		landing_animation = true
		was_on_floor = true
		return
		
	if landing_animation:
		was_on_floor = ground
		return
			
	if not ground:
		if appearance_player.current_animation != &"JumpStart":
			#print("JumpLOOP")
			_play_body_animation(&"JumpLoop", 0.05)
	
	elif direction_strength.length() > 0.001:
		#print("WALK")
		appearance_player.play(&"Carry" if _selected_item_uses_carry_pose() else &"Walk")
	else:
		if is_instance_valid(tool_node) or is_instance_valid(held_item_node):
			#print("IDLETOOL")
			appearance_player.play(&"Carry" if _selected_item_uses_carry_pose() else &"IdleTool")
			#_set_tool_action()
		else:
			#print("IDLE")
			appearance_player.play(&"Idle")
	was_on_floor = ground
		
func _create_crosshair() -> void:
	crosshair = Control.new()
	crosshair.name = "ShootingCrosshair"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -22.0
	crosshair.offset_top = -22.0
	crosshair.offset_right = 22.0
	crosshair.offset_bottom = 22.0
	$SubViewport.add_child(crosshair)
	_create_cooldown_ring()

	var line_color := Color("#F7FBFFFF")
	_add_crosshair_line(Vector2(20.0, 5.0), Vector2(4.0, 11.0), line_color)
	_add_crosshair_line(Vector2(20.0, 28.0), Vector2(4.0, 11.0), line_color)
	_add_crosshair_line(Vector2(5.0, 20.0), Vector2(11.0, 4.0), line_color)
	_add_crosshair_line(Vector2(28.0, 20.0), Vector2(11.0, 4.0), line_color)
	_add_crosshair_line(Vector2(20.0, 20.0), Vector2(4.0, 4.0), Color("#FFAD66"))
	_create_hit_marker()
	_update_crosshair_visibility()


func _create_gameplay_notice() -> void:
	if is_instance_valid(gameplay_notice):
		return
	gameplay_notice = Label.new()
	gameplay_notice.name = "GameplayNotice"
	gameplay_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	gameplay_notice.offset_left = -430.0
	gameplay_notice.offset_top = -210.0
	gameplay_notice.offset_right = 430.0
	gameplay_notice.offset_bottom = -160.0
	gameplay_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameplay_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gameplay_notice.add_theme_color_override("font_color", Color("#FFD84A"))
	gameplay_notice.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.01, 0.95))
	gameplay_notice.add_theme_constant_override("outline_size", 7)
	gameplay_notice.add_theme_font_size_override("font_size", 28)
	gameplay_notice.visible = false
	$SubViewport.add_child(gameplay_notice)


func show_gameplay_notice(message: String, duration := 2.2) -> void:
	if message.strip_edges().is_empty():
		return
	if not is_instance_valid(gameplay_notice):
		_create_gameplay_notice()
	if is_instance_valid(gameplay_notice_tween):
		gameplay_notice_tween.kill()
	gameplay_notice.text = message
	gameplay_notice.modulate = Color.WHITE
	gameplay_notice.visible = true
	gameplay_notice_tween = create_tween()
	gameplay_notice_tween.tween_interval(maxf(0.2, duration))
	gameplay_notice_tween.tween_property(gameplay_notice, "modulate:a", 0.0, 0.25)
	gameplay_notice_tween.tween_callback(func() -> void: gameplay_notice.visible = false)


func _create_action_reward_feed() -> void:
	if is_instance_valid(action_reward_feed):
		return
	action_reward_feed = VBoxContainer.new()
	action_reward_feed.name = "ActionRewardFeed"
	action_reward_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_reward_feed.set_anchors_preset(Control.PRESET_CENTER)
	action_reward_feed.offset_left = 58.0
	action_reward_feed.offset_top = -42.0
	action_reward_feed.offset_right = 500.0
	action_reward_feed.offset_bottom = 250.0
	action_reward_feed.add_theme_constant_override("separation", 4)
	$SubViewport.add_child(action_reward_feed)


func show_action_reward(amount: int, description: String) -> void:
	if amount <= 0 or description.strip_edges().is_empty():
		return
	if not is_instance_valid(action_reward_feed):
		_create_action_reward_feed()
	# A new reward supersedes older entries visually. This keeps rapid harvest
	# and multi-kill rewards readable without leaving a tall persistent list.
	for child in action_reward_feed.get_children():
		if child is Label:
			_fade_action_reward_entry(child as Label, 0.22, 0.0)
	var entry := Label.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.text = "+%d  %s" % [amount, description]
	entry.custom_minimum_size = Vector2(400.0, 34.0)
	entry.add_theme_color_override("font_color", Color("#FF3F4D"))
	entry.add_theme_color_override("font_outline_color", Color(0.04, 0.01, 0.01, 0.96))
	entry.add_theme_constant_override("outline_size", 6)
	entry.add_theme_font_size_override("font_size", 24)
	action_reward_feed.add_child(entry)
	_fade_action_reward_entry(entry, 0.32, 1.35)


func _fade_action_reward_entry(entry: Label, fade_seconds: float, delay_seconds: float) -> void:
	if not is_instance_valid(entry):
		return
	var entry_id := entry.get_instance_id()
	var existing: Tween = action_reward_tweens.get(entry_id, null)
	if is_instance_valid(existing):
		existing.kill()
	var tween := create_tween()
	action_reward_tweens[entry_id] = tween
	if delay_seconds > 0.0:
		tween.tween_interval(delay_seconds)
	tween.tween_property(entry, "modulate:a", 0.0, maxf(0.05, fade_seconds))
	tween.tween_callback(func() -> void:
		action_reward_tweens.erase(entry_id)
		if is_instance_valid(entry):
			entry.queue_free()
	)


func _create_team_money_delta_feeds() -> void:
	if not team_money_delta_feeds.is_empty():
		return
	var root := Control.new()
	root.name = "TeamMoneyDeltaFeeds"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_left = -220.0
	root.offset_top = 56.0
	root.offset_right = 220.0
	root.offset_bottom = 170.0
	$SubViewport.add_child(root)
	for team_id in ["red", "blue"]:
		var feed := VBoxContainer.new()
		feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		feed.position = Vector2(0.0 if team_id == "red" else 240.0, 0.0)
		feed.size = Vector2(200.0, 110.0)
		feed.alignment = BoxContainer.ALIGNMENT_BEGIN
		feed.add_theme_constant_override("separation", 2)
		root.add_child(feed)
		team_money_delta_feeds[team_id] = feed


func show_team_money_delta(changed_team: String, delta: float) -> void:
	if changed_team != team or is_zero_approx(delta):
		return
	if team_money_delta_feeds.is_empty():
		_create_team_money_delta_feeds()
	var feed := team_money_delta_feeds.get(changed_team, null) as VBoxContainer
	if not is_instance_valid(feed):
		return
	for child in feed.get_children():
		if child is Label:
			_fade_team_money_delta_entry(child as Label, 0.18, 0.0)
	var entry := Label.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.custom_minimum_size = Vector2(200.0, 30.0)
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.text = "%s%d" % ["+" if delta > 0.0 else "-", int(round(absf(delta)))]
	var color := Color("#42D67A") if delta < 0.0 else (
		Color("#FF5656") if changed_team == "red" else Color("#69A7FF")
	)
	entry.add_theme_color_override("font_color", color)
	entry.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.96))
	entry.add_theme_constant_override("outline_size", 5)
	entry.add_theme_font_size_override("font_size", 22)
	feed.add_child(entry)
	_fade_team_money_delta_entry(entry, 0.3, 1.15)


func _fade_team_money_delta_entry(entry: Label, fade_seconds: float, delay_seconds: float) -> void:
	if not is_instance_valid(entry):
		return
	var entry_id := entry.get_instance_id()
	var existing: Tween = team_money_delta_tweens.get(entry_id, null)
	if is_instance_valid(existing):
		existing.kill()
	var tween := create_tween()
	team_money_delta_tweens[entry_id] = tween
	if delay_seconds > 0.0:
		tween.tween_interval(delay_seconds)
	tween.tween_property(entry, "modulate:a", 0.0, maxf(0.05, fade_seconds))
	tween.tween_callback(func() -> void:
		team_money_delta_tweens.erase(entry_id)
		if is_instance_valid(entry):
			entry.queue_free()
	)


func _create_hit_marker() -> void:
	if is_instance_valid(hit_marker):
		return
	hit_marker = Control.new()
	hit_marker.name = "HitMarker"
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	hit_marker.offset_left = -HIT_MARKER_SIZE * 0.5
	hit_marker.offset_top = -HIT_MARKER_SIZE * 0.5
	hit_marker.offset_right = HIT_MARKER_SIZE * 0.5
	hit_marker.offset_bottom = HIT_MARKER_SIZE * 0.5
	hit_marker.pivot_offset = Vector2.ONE * HIT_MARKER_SIZE * 0.5
	hit_marker.rotation = deg_to_rad(45.0)
	hit_marker.visible = false
	$SubViewport.add_child(hit_marker)

	var marker_color := Color("#FF3F4D")
	_add_hit_marker_line(Vector2(24.0, 3.0), Vector2(4.0, 16.0), marker_color)
	_add_hit_marker_line(Vector2(24.0, 33.0), Vector2(4.0, 16.0), marker_color)
	_add_hit_marker_line(Vector2(3.0, 24.0), Vector2(16.0, 4.0), marker_color)
	_add_hit_marker_line(Vector2(33.0, 24.0), Vector2(16.0, 4.0), marker_color)


func _add_hit_marker_line(position: Vector2, size: Vector2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = position
	line.size = size
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_marker.add_child(line)


func _on_authority_world_event(event: Dictionary) -> void:
	if is_remote_proxy:
		return
	var event_type := str(event.get("type", ""))
	if event_type == "personal_inventory_grant":
		if int(event.get("peer_id", 0)) == authority_peer_id:
			var entries: Variant = event.get("entries", [])
			if entries is Array:
				apply_test_backpack_grant(entries as Array)
		return
	if event_type == "gameplay_notice":
		if int(event.get("peer_id", 0)) == authority_peer_id:
			show_gameplay_notice(str(event.get("text", "")))
		return
	if event_type == "cargo_delivery_preview" and int(event.get("peer_id", 0)) == authority_peer_id:
		var preview_value: Variant = event.get("data", {})
		if preview_value is Dictionary:
			show_cargo_delivery_preview(preview_value as Dictionary)
		return
	if event_type == "cargo_car_action_result":
		var cargo_result: Variant = event.get("data", {})
		if cargo_result is Dictionary and int((cargo_result as Dictionary).get("peer_id", 0)) == authority_peer_id:
			apply_cargo_car_action_result(cargo_result as Dictionary)
		return
	if event_type == "cargo_crate_action_result":
		var crate_result: Variant = event.get("data", {})
		if crate_result is Dictionary and int((crate_result as Dictionary).get("peer_id", 0)) == authority_peer_id:
			apply_cargo_crate_action_result(crate_result as Dictionary)
		return
	if event_type == "cargo_delivery_result":
		var delivery_result: Variant = event.get("data", {})
		if delivery_result is Dictionary and int((delivery_result as Dictionary).get("peer_id", 0)) == authority_peer_id:
			apply_cargo_delivery_result(delivery_result as Dictionary)
		return
	if event_type == "action_reward":
		if int(event.get("peer_id", 0)) == authority_peer_id:
			show_action_reward(
				int(event.get("amount", 0)),
				str(event.get("description", ""))
			)
		return
	if event_type == "team_money_changed":
		show_team_money_delta(
			str(event.get("team", "")),
			float(event.get("delta", 0.0))
		)
		return
	if event_type == "shop_transaction":
		var shop_result: Variant = event.get("data", {})
		if shop_result is Dictionary:
			var result := shop_result as Dictionary
			apply_authoritative_shop_dish_transaction(result)
			if int(result.get("peer_id", 0)) == authority_peer_id:
				var shop_page := get_node_or_null("SubViewport/ShopPage")
				if shop_page != null and shop_page.has_method("apply_transaction_result"):
					shop_page.call("apply_transaction_result", result)
		return
	if event_type == "tool_used":
		var data_value: Variant = event.get("data", {})
		if data_value is Dictionary:
			var data := data_value as Dictionary
			if int(data.get("peer_id", 0)) == authority_peer_id:
				var consumed_tool_id := str(data.get("consumed_tool_id", ""))
				if not consumed_tool_id.is_empty():
					_apply_consumed_tool(consumed_tool_id, int(data.get("consumed_tool_index", -1)))
		return
	if event_type == "projectile_exploded" and str(event.get("projectile_type", "")) == "grenade":
		var explosion_position: Variant = event.get("position", Vector3.ZERO)
		if explosion_position is Vector3:
			apply_explosion_camera_shake(
				explosion_position as Vector3,
				float(event.get("shake_radius", CombatBalance.get_float("grenade", "shake_radius")))
			)
		return
	if event_type == "weapon_ammo_state":
		if int(event.get("peer_id", 0)) == authority_peer_id:
			var ammo_value: Variant = event.get("ammo_state", {})
			if ammo_value is Dictionary:
				apply_weapon_ammo_state(str(event.get("tool_id", "")), ammo_value as Dictionary)
		return
	if event_type == "player_damaged":
		if int(event.get("peer_id", 0)) == authority_peer_id:
			server_hp = float(event.get("hp", server_hp))
			apply_chest_armor_state(event.get("chest_armor", {}))
			apply_legwear_state(event.get("legwear", {}))
			if float(event.get("incoming_damage", event.get("damage", 0.0))) > 0.0 \
					and (float(event.get("damage", 0.0)) > 0.0 \
					or float(event.get("absorbed_damage", 0.0)) > 0.0):
				_show_player_damage_feedback()
			var effect := str(event.get("effect", "")).to_lower()
			if effect == TranquilizerBullet.EFFECT_TRANQUILIZER:
				apply_tranquilizer_effect()
			elif effect in ["labeled", "labelled"]:
				labeled_remaining = maxf(labeled_remaining, CombatBalance.get_float("small_mouse", "labeled_duration"))
			_update_health_ui()
		return
	if event_type == "vehicle_damaged":
		if vehicle_is_active and str(event.get("vehicle_id", "")) == active_vehicle_id:
			_trigger_vehicle_damage_shake()
		return
	if event_type == "remote_device_damaged":
		if remote_is_active and str(event.get("device_id", "")) == active_remote_device_id:
			_trigger_remote_damage_shake()
		return
	if event_type != "hit_confirmed":
		return
	if int(event.get("attacker_peer_id", 0)) != authority_peer_id:
		return
	var confirmation_id := int(event.get("confirmation_id", 0))
	if confirmation_id > 0:
		if confirmation_id <= last_hit_confirmation_id:
			return
		last_hit_confirmation_id = confirmation_id
	show_hit_marker()


func apply_authoritative_shop_dish_transaction(result: Dictionary) -> void:
	if not bool(result.get("ok", false)) \
			or int(result.get("peer_id", 0)) != authority_peer_id:
		return
	if str(result.get("kind", "")) == "livestock":
		var slots_value: Variant = result.get("player_slots", [])
		if slots_value is Array:
			apply_cargo_backpack_slots(slots_value as Array)
		return
	if str(result.get("kind", "")) != "dish":
		return
	var dish_id := str(result.get("item_id", ""))
	var servings := int(result.get("amount", 0))
	var total_weight := float(result.get("total_weight_kg", 0.0))
	if dish_id.is_empty() or servings <= 0 or total_weight <= 0.0:
		return
	suppress_backpack_layout_sync = true
	if bool(result.get("is_buy", true)):
		add_personal_dish(dish_id, servings, total_weight)
	else:
		_remove_personal_dish_by_type(dish_id, servings, total_weight)
	suppress_backpack_layout_sync = false
	_submit_backpack_layout_sync()


func _apply_consumed_tool(tool_id: String, preferred_slot: int) -> void:
	var slot_index := preferred_slot
	if slot_index < 0 or slot_index >= backpack_items.size() \
			or str(backpack_items[slot_index].get("tool_id", "")) != tool_id:
		slot_index = -1
		for index in range(backpack_items.size()):
			if str(backpack_items[index].get("tool_id", "")) == tool_id:
				slot_index = index
				break
	if slot_index < 0:
		return
	suppress_backpack_layout_sync = true
	backpack_items[slot_index] = {}
	_sync_equipped_tools_from_backpack()
	suppress_backpack_layout_sync = false
	_refresh_hotbar()


func show_hit_marker() -> void:
	if not is_instance_valid(hit_marker):
		return
	if is_instance_valid(hit_marker_tween):
		hit_marker_tween.kill()
	hit_marker.visible = true
	hit_marker.modulate = Color.WHITE
	hit_marker.scale = Vector2(1.12, 1.12)
	hit_marker_tween = create_tween()
	hit_marker_tween.set_parallel(false)
	hit_marker_tween.tween_property(hit_marker, "scale", Vector2.ONE, 0.05)
	hit_marker_tween.tween_interval(HIT_MARKER_HOLD_SECONDS)
	hit_marker_tween.tween_property(hit_marker, "modulate:a", 0.0, HIT_MARKER_FADE_SECONDS)
	hit_marker_tween.tween_callback(func() -> void: hit_marker.visible = false)


func _hide_hit_marker() -> void:
	if is_instance_valid(hit_marker_tween):
		hit_marker_tween.kill()
	if is_instance_valid(hit_marker):
		hit_marker.visible = false


func _create_cooldown_ring() -> void:
	if is_instance_valid(cooldown_ring):
		return
	cooldown_ring = CooldownRingScene.new()
	cooldown_ring.name = "CooldownRing"
	cooldown_ring.set_anchors_preset(Control.PRESET_CENTER)
	cooldown_ring.offset_left = -86.0
	cooldown_ring.offset_top = -26.0
	cooldown_ring.offset_right = -34.0
	cooldown_ring.offset_bottom = 26.0
	cooldown_ring.visible = false
	$SubViewport.add_child(cooldown_ring)


func _update_cooldown_ring() -> void:
	if not is_instance_valid(cooldown_ring):
		return
	if is_respawning or is_prone or $SubViewport/ShopPage.visible:
		cooldown_ring.call("set_cooldown", 0.0, 0.0)
		return
	var remaining := 0.0
	var duration := 0.0
	if _selected_weapon_uses_ammo() \
			and float(backpack_items[current_tool_index].get("reload_remaining", 0.0)) > 0.0:
		var item := backpack_items[current_tool_index]
		remaining = float(item.get("reload_remaining", 0.0))
		duration = float(item.get("reload_duration", 0.0))
	elif remote_is_active and is_instance_valid(remote_tool_node):
		if remote_tool_node.has_method("get_primary_action_cooldown_remaining"):
			remaining = float(remote_tool_node.call("get_primary_action_cooldown_remaining"))
		if remote_tool_node.has_method("get_primary_action_cooldown_duration"):
			duration = float(remote_tool_node.call("get_primary_action_cooldown_duration"))
	elif current_tool_index >= 0 and current_tool_index < tool_cooldowns.size():
		remaining = tool_cooldowns[current_tool_index]
		if current_tool_index < tool_definitions.size():
			duration = float(tool_definitions[current_tool_index].get("cooldown", 0.0))
	cooldown_ring.call("set_cooldown", remaining, duration)


func _create_health_ui() -> void:
	if is_instance_valid(health_root):
		return
	health_root = PanelContainer.new()
	health_root.name = "HealthPanel"
	health_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_root.offset_left = 24.0
	health_root.offset_top = -164.0
	health_root.offset_right = 284.0
	health_root.offset_bottom = -24.0
	health_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_root.add_theme_stylebox_override("panel", _make_panel_style(Color("#080A08F2"), Color("#E98624"), 2))
	$SubViewport.add_child(health_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	health_root.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)

	ammo_label = Label.new()
	ammo_label.text = ""
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ammo_label.add_theme_font_size_override("font_size", 22)
	ammo_label.add_theme_color_override("font_color", Color("#E98624"))
	content.add_child(ammo_label)

	health_label = Label.new()
	health_label.text = "HP 200 / 200"
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	health_label.add_theme_font_size_override("font_size", 18)
	health_label.add_theme_color_override("font_color", Color("#63D487"))
	content.add_child(health_label)

	health_bar = ProgressBar.new()
	health_bar.max_value = PLAYER_MAX_HP
	health_bar.value = PLAYER_MAX_HP
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(230.0, 12.0)
	health_bar.add_theme_stylebox_override("background", _make_bar_style(Color("#080A08")))
	health_bar.add_theme_stylebox_override("fill", _make_bar_style(Color("#63D487")))
	content.add_child(health_bar)
	_update_health_ui()
	_update_ammo_ui()


func _create_control_status_ui() -> void:
	if is_instance_valid(control_status_root):
		return
	control_status_root = PanelContainer.new()
	control_status_root.name = "ControlStatusPanel"
	control_status_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	control_status_root.offset_left = 24.0
	control_status_root.offset_top = -168.0
	control_status_root.offset_right = 324.0
	control_status_root.offset_bottom = -24.0
	control_status_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_status_root.add_theme_stylebox_override(
		"panel", _make_panel_style(Color("#080A08F2"), Color("#E98624"), 2)
	)
	$SubViewport.add_child(control_status_root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	control_status_root.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	control_status_title = Label.new()
	control_status_title.add_theme_font_size_override("font_size", 17)
	control_status_title.add_theme_color_override("font_color", Color("#E98624"))
	content.add_child(control_status_title)

	control_status_primary_label = Label.new()
	control_status_primary_label.add_theme_font_size_override("font_size", 14)
	control_status_primary_label.add_theme_color_override("font_color", Color("#63D487"))
	content.add_child(control_status_primary_label)
	control_status_primary_bar = _create_control_status_bar(Color("#63D487"))
	content.add_child(control_status_primary_bar)

	control_status_secondary_label = Label.new()
	control_status_secondary_label.add_theme_font_size_override("font_size", 14)
	control_status_secondary_label.add_theme_color_override("font_color", Color("#E98624"))
	content.add_child(control_status_secondary_label)
	control_status_secondary_bar = _create_control_status_bar(Color("#E98624"))
	content.add_child(control_status_secondary_bar)

	control_status_detail_label = Label.new()
	control_status_detail_label.add_theme_font_size_override("font_size", 14)
	control_status_detail_label.add_theme_color_override("font_color", Color("#63D487"))
	content.add_child(control_status_detail_label)
	control_status_root.visible = false


func _create_control_status_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(270.0, 10.0)
	bar.add_theme_stylebox_override("background", _make_bar_style(Color("#080A08")))
	bar.add_theme_stylebox_override("fill", _make_bar_style(fill_color))
	return bar


func _create_match_timer_ui() -> void:
	if is_instance_valid(match_timer_label):
		return
	match_timer_label = Label.new()
	match_timer_label.name = "MatchTimerLabel"
	match_timer_label.text = "20:00"
	match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_timer_label.add_theme_font_size_override("font_size", 28)
	match_timer_label.add_theme_color_override("font_color", Color("#FFF4C2"))
	match_timer_label.add_theme_color_override("font_shadow_color", Color("#000000A0"))
	match_timer_label.add_theme_constant_override("shadow_offset_x", 2)
	match_timer_label.add_theme_constant_override("shadow_offset_y", 2)
	match_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_timer_label.offset_left = -120.0
	match_timer_label.offset_top = 12.0
	match_timer_label.offset_right = 120.0
	match_timer_label.offset_bottom = 48.0
	match_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SubViewport.add_child(match_timer_label)
	_update_match_timer_ui()


func _ensure_respawn_overlay() -> void:
	if is_remote_proxy or is_instance_valid(respawn_overlay):
		return
	respawn_overlay = ColorRect.new()
	respawn_overlay.name = "RespawnOverlay"
	respawn_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	respawn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	respawn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_overlay.z_index = 100
	$SubViewport.add_child(respawn_overlay)
	respawn_label = Label.new()
	respawn_label.name = "RespawnLabel"
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	respawn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	respawn_label.add_theme_font_size_override("font_size", 32)
	respawn_label.add_theme_color_override("font_color", Color("#FFF4F4"))
	respawn_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	respawn_label.add_theme_constant_override("shadow_offset_x", 2)
	respawn_label.add_theme_constant_override("shadow_offset_y", 2)
	respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	respawn_label.offset_left = -220.0
	respawn_label.offset_top = -34.0
	respawn_label.offset_right = 220.0
	respawn_label.offset_bottom = 34.0
	respawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_label.z_index = 101
	$SubViewport.add_child(respawn_label)


func _ensure_tranquilizer_overlay() -> void:
	if is_remote_proxy or is_instance_valid(tranquilizer_overlay):
		return
	tranquilizer_overlay = ColorRect.new()
	tranquilizer_overlay.name = "TranquilizerOverlay"
	tranquilizer_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	tranquilizer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	tranquilizer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tranquilizer_overlay.z_index = 90
	$SubViewport.add_child(tranquilizer_overlay)


func apply_tranquilizer_effect() -> void:
	if is_remote_proxy or is_respawning:
		return
	_ensure_tranquilizer_overlay()
	tranquilizer_remaining = CombatBalance.get_float("tranquilizer_pistol", "effect_duration")
	tranquilizer_elapsed = 0.0
	_update_tranquilizer_overlay()


func _update_tranquilizer_overlay() -> void:
	if not is_instance_valid(tranquilizer_overlay):
		return
	if tranquilizer_remaining <= 0.0:
		tranquilizer_overlay.color.a = 0.0
		return
	var cycle := maxf(0.1, CombatBalance.get_float("tranquilizer_pistol", "flash_cycle"))
	var wave := 0.5 - 0.5 * cos(TAU * tranquilizer_elapsed / cycle)
	tranquilizer_overlay.color.a = wave * CombatBalance.get_float("tranquilizer_pistol", "darkness_alpha")


func apply_respawn_state(next_respawn_left: float, spawn_position: Variant = null) -> void:
	if spawn_position is Vector3 and next_respawn_left <= 0.0:
		global_position = spawn_position
		velocity = Vector3.ZERO
		pending_input_frames.clear()
	respawn_left = maxf(0.0, next_respawn_left)
	var next_is_respawning := respawn_left > 0.0
	var started_respawning := next_is_respawning and not is_respawning
	if next_is_respawning:
		_set_prone_state(false)
		spicy_remaining = 0.0
		spicy_dps = 0.0
		tranquilizer_remaining = 0.0
		_update_tranquilizer_overlay()
		if started_respawning:
			death_respawn_duration = respawn_left
			_play_death_animation()
		else:
			# The reliable death event can arrive after an earlier snapshot. Keep the
			# full authoritative duration so hiding still occurs at its exact midpoint.
			death_respawn_duration = maxf(death_respawn_duration, respawn_left)
		_update_death_appearance_visibility()
	if is_respawning == next_is_respawning:
		if next_is_respawning:
			_update_respawn_overlay()
		return
	is_respawning = next_is_respawning
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance != null:
		appearance.visible = not is_respawning or respawn_left > death_respawn_duration * 0.5
	if is_instance_valid(tool_node):
		tool_node.visible = not is_respawning and not is_prone
	if is_instance_valid(held_item_node):
		held_item_node.visible = not is_respawning and not is_prone
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", is_respawning or is_remote_proxy)
	# The body, interaction ShapeCasts, and legacy local hit trigger must all leave
	# the physics world together. Remote proxies use the same presentation state.
	collision_layer = 0 if is_respawning or is_remote_proxy else PLAYER_COLLISION_LAYER
	collision_mask = 0 if is_respawning or is_remote_proxy else PLAYER_COLLISION_MASK
	_set_interaction_detectors_enabled(not is_respawning and not is_remote_proxy)
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null:
		hit_area.set_deferred("monitoring", not is_respawning and not is_remote_proxy)
		hit_area.set_deferred("monitorable", not is_respawning and not is_remote_proxy)
	if is_respawning:
		velocity = Vector3.ZERO
		if remote_is_active:
			remote_device_close(false)
		if not is_remote_proxy:
			_ensure_respawn_overlay()
			var fade := create_tween()
			fade.tween_property(respawn_overlay, "color:a", 0.88, 0.65)
			_update_respawn_overlay()
	else:
		death_respawn_duration = 0.0
		action_anim_locked = false
		landing_animation = false
		if is_instance_valid(appearance_player):
			appearance_player.play(&"Idle", 0.05)
		if not is_remote_proxy and is_instance_valid(respawn_overlay):
			var fade := create_tween()
			fade.tween_property(respawn_overlay, "color:a", 0.0, 0.35)
		if is_instance_valid(respawn_label):
			respawn_label.visible = false


func _play_death_animation() -> void:
	action_anim_locked = true
	landing_animation = false
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance != null:
		appearance.visible = true
	if not is_instance_valid(appearance_player):
		return
	if not appearance_player.has_animation(&"DeathFallForward"):
		push_warning("Character appearance is missing DeathFallForward: %s" % selected_hero)
		return
	appearance_player.play(&"DeathFallForward", 0.08)


func _update_death_appearance_visibility() -> void:
	if not is_respawning and respawn_left <= 0.0:
		return
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance == null:
		return
	var hide_at_remaining := death_respawn_duration * 0.5
	appearance.visible = respawn_left > hide_at_remaining


func _update_respawn_overlay() -> void:
	if not is_instance_valid(respawn_label):
		return
	respawn_label.visible = is_respawning
	if is_respawning:
		respawn_label.text = "复活中... %d" % maxf(1.0, ceilf(respawn_left))


func _update_match_timer_ui() -> void:
	if not is_instance_valid(match_timer_label):
		return
	var remaining := -1
	if GameAuthority.last_snapshot.has("remaining_time_seconds"):
		remaining = int(GameAuthority.last_snapshot.get("remaining_time_seconds", -1))
	if remaining < 0:
		match_timer_label.visible = false
		return
	match_timer_label.visible = true
	var minutes := int(remaining / 60)
	var seconds := int(remaining % 60)
	match_timer_label.text = "%02d:%02d" % [minutes, seconds]
	if remaining <= 30:
		match_timer_label.add_theme_color_override("font_color", Color("#FF6565"))
	elif remaining <= 120:
		match_timer_label.add_theme_color_override("font_color", Color("#FFB45D"))
	else:
		match_timer_label.add_theme_color_override("font_color", Color("#FFF4C2"))


func _update_health_ui() -> void:
	if not is_instance_valid(health_bar) or not is_instance_valid(health_label):
		return
	if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
		var state: Dictionary = GameAuthority.player_states[authority_peer_id]
		server_hp = float(state.get("hp", PLAYER_MAX_HP))
	var hp := clampf(server_hp, 0.0, PLAYER_MAX_HP)
	health_bar.value = hp
	health_label.text = "HP %d / %d" % [roundi(hp), roundi(PLAYER_MAX_HP)]
	var ratio := hp / PLAYER_MAX_HP
	var fill_color := Color("#E98624")
	if ratio > 0.6:
		fill_color = Color("#63D487")
	health_bar.add_theme_stylebox_override("fill", _make_bar_style(fill_color))
	_update_ammo_ui()


func _update_ammo_ui() -> void:
	if not is_instance_valid(ammo_label):
		return
	var text := _get_selected_item_info_text()
	ammo_label.visible = not text.is_empty()
	ammo_label.text = text


func _get_selected_item_info_text() -> String:
	if current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return ""
	var item := backpack_items[current_tool_index]
	if item.is_empty():
		return ""
	var kind := str(item.get("kind", ""))
	if kind == "tool":
		var tool_id := str(item.get("tool_id", ""))
		var definition: Dictionary = all_tool_definitions_by_id.get(tool_id, {})
		var tool_name := str(definition.get("name", definition.get("short", tool_id)))
		if is_instance_valid(tool_node) and tool_node.has_method("get_held_item_info_text"):
			return str(tool_node.call("get_held_item_info_text", item, definition))
		if definition.has("magazine_size"):
			return "%s\n%d / %d" % [
				tool_name,
				int(item.get("ammo_in_mag", 0)),
				int(item.get("reserve_ammo", 0)),
			]
		return tool_name
	return str(get_backpack_item(current_tool_index).get("display_name", ""))


func _tick_local_reload_displays(delta: float) -> void:
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		var remaining := float(item.get("reload_remaining", 0.0))
		if remaining <= 0.0:
			continue
		item["reload_remaining"] = maxf(0.0, remaining - delta)
		backpack_items[index] = item


func apply_weapon_ammo_state(tool_id: String, ammo_state: Dictionary) -> void:
	for index in range(backpack_items.size()):
		var item := backpack_items[index]
		if str(item.get("kind", "")) != "tool" or str(item.get("tool_id", "")) != tool_id:
			continue
		item["ammo_in_mag"] = maxi(0, int(ammo_state.get("ammo_in_mag", item.get("ammo_in_mag", 0))))
		item["reserve_ammo"] = maxi(0, int(ammo_state.get("reserve_ammo", item.get("reserve_ammo", 0))))
		item["reload_remaining"] = maxf(0.0, float(ammo_state.get("reload_remaining", 0.0)))
		item["reload_duration"] = maxf(0.0, float(ammo_state.get("reload_duration", 0.0)))
		backpack_items[index] = item
		break
	_update_ammo_ui()
	_update_cooldown_ring()


func _update_control_status_ui() -> void:
	if not is_instance_valid(control_status_root):
		return
	if remote_is_active and is_instance_valid(remote_tool_node):
		if is_instance_valid(health_root):
			health_root.visible = false
		_update_remote_control_status_ui()
		control_status_root.visible = true
		return
	if vehicle_is_active and is_instance_valid(active_vehicle):
		if is_instance_valid(health_root):
			health_root.visible = false
		_update_vehicle_control_status_ui()
		control_status_root.visible = true
		return
	control_status_root.visible = false
	if is_instance_valid(health_root):
		health_root.visible = true


func _update_vehicle_control_status_ui() -> void:
	var max_hp := active_vehicle.vehicle_config.max_hp if active_vehicle.vehicle_config != null else 0.0
	var hp := clampf(active_vehicle.current_hp, 0.0, max_hp)
	control_status_title.text = "VEHICLE"
	control_status_primary_label.text = "Vehicle HP  %d / %d" % [roundi(hp), roundi(max_hp)]
	control_status_primary_bar.max_value = maxf(max_hp, 1.0)
	control_status_primary_bar.value = hp
	control_status_primary_bar.add_theme_stylebox_override(
		"fill", _make_bar_style(_status_health_color(hp, max_hp))
	)

	var cargo_weight := active_vehicle.get_cargo_weight_kg()
	var cargo_capacity := active_vehicle.get_cargo_capacity_kg()
	var displays_cargo := active_vehicle.supports_cargo()
	control_status_secondary_label.visible = displays_cargo
	control_status_secondary_bar.visible = displays_cargo
	if displays_cargo:
		control_status_secondary_label.text = "Crates  %d / 12    Cargo  %d / %d kg" % [
			active_vehicle.get_cargo_crate_count(), roundi(cargo_weight), roundi(cargo_capacity)
		]
		control_status_secondary_bar.max_value = maxf(cargo_capacity, 1.0)
		control_status_secondary_bar.value = cargo_weight
		control_status_secondary_bar.add_theme_stylebox_override("fill", _make_bar_style(Color("#E98624")))

	var speed := absf(active_vehicle.current_speed)
	var displayed_speed := 0.0 if is_zero_approx(speed) else maxf(speed, 0.1)
	control_status_detail_label.visible = true
	control_status_detail_label.text = "Speed  %.1f m/s" % displayed_speed


func _update_remote_control_status_ui() -> void:
	var current_hp := _node_numeric_property(remote_tool_node, ["current_hp"], 0.0)
	var max_hp := _node_numeric_property(remote_tool_node, ["max_hp", "SET_HP", "set_hp"], current_hp)
	current_hp = clampf(current_hp, 0.0, maxf(max_hp, 0.0))
	var signal_strength := _get_active_remote_signal_strength()
	control_status_title.text = "REMOTE  " + _remote_device_display_name(remote_tool_node)
	control_status_primary_label.text = "Device HP  %d / %d" % [roundi(current_hp), roundi(max_hp)]
	control_status_primary_bar.max_value = maxf(max_hp, 1.0)
	control_status_primary_bar.value = current_hp
	control_status_primary_bar.add_theme_stylebox_override(
		"fill", _make_bar_style(_status_health_color(current_hp, max_hp))
	)
	control_status_secondary_label.text = "Signal  %d%%" % roundi(signal_strength * 100.0)
	control_status_secondary_label.visible = true
	control_status_secondary_bar.visible = true
	control_status_secondary_bar.max_value = 100.0
	control_status_secondary_bar.value = signal_strength * 100.0
	control_status_secondary_bar.add_theme_stylebox_override("fill", _make_bar_style(Color("#63D487")))
	control_status_detail_label.visible = false


func _get_active_remote_signal_strength() -> float:
	if not is_instance_valid(remote_tool_node):
		return 0.0
	# Multiplayer must display the server's authoritative effective signal.
	if remote_tool_node.has_meta("network_effective_signal"):
		return clampf(float(remote_tool_node.get_meta("network_effective_signal")), 0.0, 1.0)
	if remote_tool_node.has_method("get_effective_signal_strength"):
		return clampf(float(remote_tool_node.call("get_effective_signal_strength", self)), 0.0, 1.0)
	if remote_tool_node.has_method("get_signal_strength"):
		return clampf(float(remote_tool_node.call("get_signal_strength", self)), 0.0, 1.0)
	return 0.0


func _node_numeric_property(node: Object, property_names: Array[String], fallback: float) -> float:
	if node == null:
		return fallback
	for property_name in property_names:
		for property_info in node.get_property_list():
			if str(property_info.get("name", "")) == property_name:
				var value: Variant = node.get(property_name)
				if value is float or value is int:
					return float(value)
	return fallback


func _status_health_color(value: float, maximum: float) -> Color:
	var ratio := value / maxf(maximum, 0.01)
	if ratio > 0.6:
		return Color("#63D487")
	return Color("#E98624")


func _add_crosshair_line(position: Vector2, size: Vector2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = position
	line.size = size
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(line)


func _update_crosshair_visibility() -> void:
	if not is_instance_valid(crosshair):
		return
	if not _has_equipped_tool(current_tool_index):
		crosshair.visible = false
		_hide_hit_marker()
		return
	var definition: Dictionary = tool_definitions[current_tool_index]
	var ingredient_page_open := is_instance_valid(ingredient_pickup_page) \
		and ingredient_pickup_page.has_method("is_open") \
		and bool(ingredient_pickup_page.call("is_open"))
	var plating_page_open := is_instance_valid(plating_station_page) \
		and plating_station_page.has_method("is_open") \
		and bool(plating_station_page.call("is_open"))
	var oven_page_open := is_instance_valid(oven_page) \
		and oven_page.has_method("is_open") \
		and bool(oven_page.call("is_open"))
	var griddle_page_open := is_instance_valid(griddle_station_page) \
		and griddle_station_page.has_method("is_open") \
		and bool(griddle_station_page.call("is_open"))
	var induction_page_open := is_instance_valid(induction_counter_page) \
		and induction_counter_page.has_method("is_open") \
		and bool(induction_counter_page.call("is_open"))
	var smoker_page_open := is_instance_valid(farm_smoker_page) \
		and farm_smoker_page.has_method("is_open") \
		and bool(farm_smoker_page.call("is_open"))
	var freezer_page_open := is_instance_valid(freezer_page) \
		and freezer_page.has_method("is_open") \
		and bool(freezer_page.call("is_open"))
	var mixer_page_open := is_instance_valid(stand_mixer_page) \
		and stand_mixer_page.has_method("is_open") \
		and bool(stand_mixer_page.call("is_open"))
	var extractor_page_open := is_instance_valid(ingredient_extractor_page) \
		and ingredient_extractor_page.has_method("is_open") \
		and bool(ingredient_extractor_page.call("is_open"))
	var auto_cooker_page_open := is_instance_valid(auto_cooker_page) \
		and auto_cooker_page.has_method("is_open") \
		and bool(auto_cooker_page.call("is_open"))
	var vehicle_upgrade_page_open := is_instance_valid(vehicle_upgrade_page) \
		and vehicle_upgrade_page.has_method("is_open") \
		and bool(vehicle_upgrade_page.call("is_open"))
	var cargo_page_open := (is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open()) \
		or (is_instance_valid(cargo_delivery_page) and cargo_delivery_page.is_open()) \
		or (is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open())
	var government_notice_open := is_instance_valid(government_notice_page) \
		and government_notice_page.is_open()
	var livestock_chop_open := is_instance_valid(livestock_chop_page) \
		and livestock_chop_page.is_open()
	crosshair.visible = not is_prone and not is_respawning and not vehicle_is_active and not remote_is_active and (bool(definition.get("show_crosshair", false)) or _current_tool_is_shooting() and \
		bool(definition.get("show_crosshair", false))) and \
		not $SubViewport/ShopPage.visible and not player_backpack.is_open() and not team_chat_panel.is_chat_open() and not game_exit_dialog.is_open() and not ingredient_page_open and not plating_page_open and not oven_page_open and not griddle_page_open and not induction_page_open and not smoker_page_open and not freezer_page_open and not mixer_page_open and not extractor_page_open and not auto_cooker_page_open and not vehicle_upgrade_page_open and not cargo_page_open and not government_notice_open and not livestock_chop_open
	if not crosshair.visible:
		_hide_hit_marker()


func _refresh_hotbar() -> void:
	if is_instance_valid(player_backpack):
		player_backpack.refresh()
	_update_ammo_ui()
	_update_cooldown_ring()


func _flash_cooldown_slot(index: int) -> void:
	if is_instance_valid(player_backpack):
		player_backpack.flash_hotbar_slot(index)


func _make_panel_style(
	background: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	return style


func _make_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _disable_legacy_tool_ui() -> void:
	$SubViewport/Label.visible = false
	$SubViewport/cooler.visible = false


func _update_interaction() -> void:
	if remote_is_active or vehicle_is_active:
		return
	if _cargo_crate_hold_target != null and not is_instance_valid(_cargo_crate_hold_target):
		_cargo_crate_hold_target = null
	if is_instance_valid(_cargo_crate_hold_target):
		if Input.is_action_pressed("interact"):
			if Time.get_ticks_msec() - _cargo_crate_hold_started_msec >= CARGO_CRATE_PICKUP_HOLD_MSEC:
				_request_ground_cargo_crate_pickup(_cargo_crate_hold_target)
				_cargo_crate_hold_target = null
			return
		if Input.is_action_just_released("interact"):
			cargo_crate_storage_page.open_for(_cargo_crate_hold_target, self)
			_update_crosshair_visibility()
		_cargo_crate_hold_target = null
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if is_instance_valid(government_notice_page) and government_notice_page.is_open():
		government_notice_page.close()
		_update_crosshair_visibility()
		return
	if is_instance_valid(livestock_chop_page) and livestock_chop_page.is_open():
		livestock_chop_page.close()
		_update_crosshair_visibility()
		return
	if $SubViewport/ShopPage.visible:
		$SubViewport/ShopPage.close_shop()
		return
	if is_instance_valid(vehicle_upgrade_page) and vehicle_upgrade_page.has_method("is_open") \
			and bool(vehicle_upgrade_page.call("is_open")):
		vehicle_upgrade_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(ingredient_pickup_page) and ingredient_pickup_page.has_method("is_open") \
			and bool(ingredient_pickup_page.call("is_open")):
		ingredient_pickup_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(plating_station_page) and plating_station_page.has_method("is_open") \
			and bool(plating_station_page.call("is_open")):
		if plating_station_page.has_method("try_take_completed_output") \
				and bool(plating_station_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		plating_station_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(oven_page) and oven_page.has_method("is_open") \
			and bool(oven_page.call("is_open")):
		if oven_page.has_method("try_take_completed_output") \
				and bool(oven_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		oven_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(griddle_station_page) and griddle_station_page.has_method("is_open") \
			and bool(griddle_station_page.call("is_open")):
		if griddle_station_page.has_method("try_take_completed_output") \
				and bool(griddle_station_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		griddle_station_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(induction_counter_page) and induction_counter_page.has_method("is_open") \
			and bool(induction_counter_page.call("is_open")):
		if induction_counter_page.has_method("try_take_completed_output") \
				and bool(induction_counter_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		induction_counter_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(farm_smoker_page) and farm_smoker_page.has_method("is_open") \
			and bool(farm_smoker_page.call("is_open")):
		if farm_smoker_page.has_method("try_take_completed_output") \
				and bool(farm_smoker_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		farm_smoker_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(freezer_page) and freezer_page.has_method("is_open") \
			and bool(freezer_page.call("is_open")):
		if freezer_page.has_method("try_take_completed_output") \
				and bool(freezer_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		freezer_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(stand_mixer_page) and stand_mixer_page.has_method("is_open") \
			and bool(stand_mixer_page.call("is_open")):
		if stand_mixer_page.has_method("try_take_completed_output") \
				and bool(stand_mixer_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		stand_mixer_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(ingredient_extractor_page) and ingredient_extractor_page.has_method("is_open") \
			and bool(ingredient_extractor_page.call("is_open")):
		if ingredient_extractor_page.has_method("try_take_completed_output") \
				and bool(ingredient_extractor_page.call("try_take_completed_output")):
			_update_crosshair_visibility()
			return
		ingredient_extractor_page.call("close")
		_update_crosshair_visibility()
		return
	if is_instance_valid(auto_cooker_page) and auto_cooker_page.has_method("is_open") \
			and bool(auto_cooker_page.call("is_open")):
		auto_cooker_page.call("close")
		_update_crosshair_visibility()
		return
	var target := _get_best_interaction_target(true)
	match str(target.get("kind", "")):
		"crop":
			_request_single_crop_harvest(target.get("tile") as FarmTile, target.get("body") as Node3D)
		"livestock":
			_request_livestock_pickup(target.get("body") as FarmLivestock)
		"livestock_chop":
			livestock_chop_page.open_for(target.get("body") as LivestockChop, self)
			_update_crosshair_visibility()
		"vehicle":
			_request_vehicle_enter(target.get("vehicle", target.get("body")) as VehicleBase)
		"cargo_car_storage":
			var cargo_vehicle := target.get("vehicle") as VehicleBase
			if is_instance_valid(cargo_vehicle):
				cargo_car_storage_page.open_for(cargo_vehicle, self)
				_update_crosshair_visibility()
		"cargo_crate":
			_cargo_crate_hold_target = target.get("body") as CargoCrateGround
			_cargo_crate_hold_started_msec = Time.get_ticks_msec()
		"garage_upgrade":
			(target.get("body") as GarageUpgradeTerminal).interact(self)
			_update_crosshair_visibility()
		"ingredient_pickup":
			ingredient_pickup_page.call("open_for", target.get("body") as IngredientPickup, self)
			_update_crosshair_visibility()
		"plating_station":
			var station := target.get("body") as PlatingStation
			if station.complete:
				_request_plating_station_take(station)
			elif not station.cooking and not station.is_in_use_by_other(authority_peer_id):
				plating_station_page.call("open_for", station, self)
				_update_crosshair_visibility()
		"oven":
			var oven := target.get("body") as Oven
			if oven.complete:
				_request_oven_take(oven)
			elif not oven.cooking and not oven.is_in_use_by_other(authority_peer_id):
				oven_page.call("open_for", oven, self)
				_update_crosshair_visibility()
		"griddle":
			var griddle := target.get("body") as GriddleStation
			_interact_recipe_cooking_station(griddle, griddle_station_page)
		"induction":
			var induction := target.get("body") as InductionCounter
			_interact_recipe_cooking_station(induction, induction_counter_page)
		"smoker":
			var smoker := target.get("body") as RecipeCookingStation
			_interact_recipe_cooking_station(smoker, farm_smoker_page)
		"freezer":
			var freezer := target.get("body") as RecipeCookingStation
			_interact_recipe_cooking_station(freezer, freezer_page)
		"mixer":
			(target.get("body") as StandMixer).interact(self)
			_update_crosshair_visibility()
		"pickup_item":
			(target.get("body") as PickupItem).interact(self)
		"auto_cooker":
			(target.get("body") as AutoCooker).interact(self)
		"kitchen":
			(target.get("body") as KitchenAppliance).interact(self)
		"shop":
			_set_weapon_aiming(false)
			if is_instance_valid(team_chat_panel):
				team_chat_panel.call("close_chat")
				team_chat_panel.visible = false
			player_backpack.show_companion()
			$SubViewport/ShopPage.show_shop(target.get("body") as Shop, team, self)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		"government_board":
			_set_weapon_aiming(false)
			government_notice_page.open_for(target.get("body") as GovernmentBoard)
			interact_hint.visible = false
			_update_crosshair_visibility()


func _on_shop_page_closed() -> void:
	player_backpack.hide_companion()
	if is_instance_valid(team_chat_panel):
		team_chat_panel.visible = true
	_suppress_esc_mouse_release = Input.is_action_pressed("esc")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_government_notice_closed() -> void:
	_suppress_esc_mouse_release = Input.is_action_pressed("esc")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_crosshair_visibility()


func apply_cargo_backpack_slots(slots_value: Array) -> void:
	suppress_backpack_layout_sync = true
	backpack_items.clear()
	for value: Variant in slots_value:
		backpack_items.append((value as Dictionary).duplicate(true) if value is Dictionary else {})
	_sync_equipped_tools_from_backpack()
	suppress_backpack_layout_sync = false
	_refresh_hotbar()


func apply_cargo_car_action_result(result: Dictionary) -> void:
	if is_instance_valid(cargo_car_storage_page):
		cargo_car_storage_page.apply_authoritative_result(result)


func _request_place_carried_cargo_crate(item: Dictionary) -> void:
	if current_tool_index < 0 or current_tool_index >= backpack_items.size():
		return
	var direction := -global_transform.basis.z
	var target_position := global_position + direction * 2.5
	var look_raycast := find_child("LookAtTarget", true, false) as RayCast3D
	if look_raycast != null:
		look_raycast.force_raycast_update()
		if look_raycast.is_colliding():
			target_position = look_raycast.get_collision_point()
	var action := {
		"station_kind": "cargo_crate", "action": "place",
		"slot_index": current_tool_index, "item": item.duplicate(true),
		"target_position": target_position, "yaw": rotation.y,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_cargo_crate_action_result(GameAuthority.local_ingredient_pickup_action(authority_peer_id, action))


func _request_ground_cargo_crate_pickup(target_crate: CargoCrateGround) -> void:
	if not is_instance_valid(target_crate):
		return
	var action := {
		"station_kind": "cargo_crate", "action": "pickup",
		"crate_id": str(target_crate.get_meta("network_device_id", target_crate.get_path())),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_cargo_crate_action_result(GameAuthority.local_ingredient_pickup_action(authority_peer_id, action))


func apply_cargo_crate_action_result(result: Dictionary) -> void:
	if int(result.get("peer_id", 0)) != authority_peer_id:
		return
	var slots_value: Variant = result.get("player_slots", null)
	if bool(result.get("ok", false)) and slots_value is Array:
		apply_cargo_backpack_slots(slots_value as Array)
	if is_instance_valid(cargo_crate_storage_page) and cargo_crate_storage_page.is_open():
		cargo_crate_storage_page.apply_authoritative_result(result)
	elif not bool(result.get("ok", false)):
		show_gameplay_notice("货运箱操作失败：%s" % str(result.get("reason", "rejected")))


func show_cargo_delivery_preview(preview: Dictionary) -> void:
	if is_instance_valid(cargo_car_storage_page) and cargo_car_storage_page.is_open():
		cargo_car_storage_page.close()
	if is_instance_valid(cargo_delivery_page):
		cargo_delivery_page.show_preview(preview, self)


func apply_cargo_delivery_result(result: Dictionary) -> void:
	var slots_value: Variant = result.get("player_slots", null)
	if slots_value is Array:
		apply_cargo_backpack_slots(slots_value as Array)
	if is_instance_valid(cargo_delivery_page):
		cargo_delivery_page.apply_result(result)


func _request_plating_station_take(station: PlatingStation) -> void:
	if not is_instance_valid(station):
		return
	var action := {
		"station_kind": "plating",
		"action": "take",
		"station_path": str(station.get_path()),
		"station_position": station.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	if GameAuthority.is_local_authority():
		var result := GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
		if bool(result.get("ok", false)):
			add_personal_dish(str(result.get("dish_id", "")), int(result.get("servings", 0)), float(result.get("weight_kg", -1.0)))


func _request_oven_take(oven: Oven) -> void:
	if not is_instance_valid(oven):
		return
	var action := {
		"station_kind": "oven",
		"action": "take",
		"station_path": str(oven.get_path()),
		"station_position": oven.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	if GameAuthority.is_local_authority():
		apply_authoritative_oven_action_result(
			GameAuthority.local_ingredient_pickup_action(authority_peer_id, action)
		)


func _interact_recipe_cooking_station(station: RecipeCookingStation, page: Node) -> void:
	if not is_instance_valid(station):
		return
	if station.complete:
		_request_recipe_cooking_station_take(station)
	elif not station.cooking and not station.is_in_use_by_other(authority_peer_id) and page != null and page.has_method("open_for"):
		page.call("open_for", station, self)
		_update_crosshair_visibility()


func _request_recipe_cooking_station_take(station: RecipeCookingStation) -> void:
	if not is_instance_valid(station):
		return
	var station_kind := "griddle" if station is GriddleStation else "induction" if station is InductionCounter else "smoker" if station.is_in_group("smoker_stations") else "freezer" if station.is_in_group("freezer_stations") else ""
	if station_kind.is_empty():
		return
	var action := {"station_kind": station_kind, "action": "take", "station_path": str(station.get_path()), "station_position": station.global_position}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	if GameAuthority.is_local_authority():
		apply_authoritative_recipe_station_action_result(GameAuthority.local_ingredient_pickup_action(authority_peer_id, action))


func _create_interact_hint() -> void:
	interact_hint = Label.new()
	interact_hint.text = "[E] 交互"
	interact_hint.visible = false
	interact_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_hint.add_theme_font_size_override("font_size", 22)
	interact_hint.add_theme_color_override("font_color", Color("#FFF1A8"))
	interact_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interact_hint.position = Vector2(-120.0, -205.0)
	interact_hint.size = Vector2(240.0, 38.0)
	$SubViewport.add_child(interact_hint)


func _get_interactable_crop_tile(body: Node3D) -> FarmTile:
	if not is_instance_valid(body):
		return null
	var parent := body.get_parent()
	if not parent is FarmTile:
		return null
	var tile := parent as FarmTile
	return tile if tile.plant_children.has(body) else null


func _get_interaction_detectors() -> Array[ShapeCast3D]:
	var detectors: Array[ShapeCast3D] = []
	for detector_path in [NodePath("Head/InteractDetect"), NodePath("SODArea")]:
		var detector := get_node_or_null(detector_path) as ShapeCast3D
		if detector != null:
			detectors.append(detector)
	return detectors


func _set_interaction_detectors_enabled(value: bool) -> void:
	for detector: ShapeCast3D in _get_interaction_detectors():
		detector.enabled = value


func _debug_interaction_shapecast_hits(detector: ShapeCast3D) -> void:
	if not debug_interaction_shapecasts or not GameAuthority.is_local_authority():
		return
	var detected_nodes: Array[String] = []
	for collision_index in detector.get_collision_count():
		var collider := detector.get_collider(collision_index) as Node
		if is_instance_valid(collider):
			detected_nodes.append("%s (%s)" % [collider.name, collider.get_path()])
	detected_nodes.sort()
	var next_hits := "[无]" if detected_nodes.is_empty() else ", ".join(detected_nodes)
	print("[交互 ShapeCast][E] %s -> %s" % [detector.name, next_hits])


func _get_best_interaction_target(print_shape_cast_debug := false) -> Dictionary:
	var candidate_bodies: Dictionary = {}
	for area_value: Variant in get_tree().get_nodes_in_group("livestock_interaction_areas"):
		if area_value is Area3D:
			var livestock_area := area_value as Area3D
			if is_instance_valid(livestock_area) and livestock_area.overlaps_body(self):
				candidate_bodies[livestock_area.get_instance_id()] = livestock_area
	for area_value: Variant in get_tree().get_nodes_in_group("livestock_chop_interaction_areas"):
		if area_value is Area3D:
			var chop_area := area_value as Area3D
			if is_instance_valid(chop_area) and chop_area.overlaps_body(self):
				candidate_bodies[chop_area.get_instance_id()] = chop_area
	for area_value: Variant in get_tree().get_nodes_in_group("shop_interaction_areas"):
		if area_value is Area3D:
			var shop_area := area_value as Area3D
			if is_instance_valid(shop_area) and shop_area.overlaps_body(self):
				candidate_bodies[shop_area.get_instance_id()] = shop_area
	for area_value: Variant in get_tree().get_nodes_in_group("government_board_interaction_areas"):
		if area_value is Area3D:
			var board_area := area_value as Area3D
			if is_instance_valid(board_area) and board_area.overlaps_body(self):
				candidate_bodies[board_area.get_instance_id()] = board_area
	for area_value: Variant in get_tree().get_nodes_in_group("cargo_car_interaction_areas"):
		if area_value is Area3D:
			var cargo_area := area_value as Area3D
			if is_instance_valid(cargo_area) and cargo_area.overlaps_body(self):
				candidate_bodies[cargo_area.get_instance_id()] = cargo_area
	for detector: ShapeCast3D in _get_interaction_detectors():
		if not detector.enabled:
			continue
		detector.force_shapecast_update()
		if print_shape_cast_debug:
			_debug_interaction_shapecast_hits(detector)
		for collision_index in detector.get_collision_count():
			var body_value := detector.get_collider(collision_index) as Node3D
			if is_instance_valid(body_value):
				candidate_bodies[body_value.get_instance_id()] = body_value
	var best_target: Dictionary = {}
	var best_score := INF
	var player_forward := -global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	for body_value: Node3D in candidate_bodies.values():
		var target := _build_interaction_target(body_value)
		if target.is_empty():
			if print_shape_cast_debug:
				_debug_interaction_rejected_body(body_value)
			continue
		var body := target.get("body") as Node3D
		if body == null:
			continue
		var inside_shop_area := body is Area3D \
				and body.is_in_group("shop_interaction_areas") \
				and (body as Area3D).overlaps_body(self)
		var inside_cargo_area := body is Area3D \
				and body.is_in_group("cargo_car_interaction_areas") \
				and (body as Area3D).overlaps_body(self)
		var inside_board_area := body is Area3D \
				and body.is_in_group("government_board_interaction_areas") \
				and (body as Area3D).overlaps_body(self)
		var inside_interaction_area := inside_shop_area or inside_cargo_area or inside_board_area
		var interaction_position: Vector3 = global_position if inside_interaction_area \
				else target.get("interaction_position", body.global_position)
		var to_target := interaction_position - global_position
		var horizontal_offset := Vector3(to_target.x, 0.0, to_target.z)
		var distance := horizontal_offset.length()
		var max_distance := CROP_INTERACTION_DISTANCE if str(target.get("kind", "")) == "crop" else INTERACTION_MAX_DISTANCE
		if distance > max_distance:
			if print_shape_cast_debug:
				print("[交互筛选][E] %s -> 超出距离 %.2fm / %.2fm" % [body.name, distance, max_distance])
			continue
		var front_alignment := 1.0 if distance <= 0.001 else player_forward.dot(horizontal_offset / distance)
		if front_alignment < INTERACTION_MIN_FORWARD_DOT:
			if print_shape_cast_debug:
				print("[交互筛选][E] %s -> 不在玩家前方 (dot=%.2f)" % [body.name, front_alignment])
			continue
		if not inside_interaction_area and _is_interaction_occluded(interaction_position):
			if print_shape_cast_debug:
				print("[交互筛选][E] %s -> 被墙体遮挡" % body.name)
			continue
		var score := distance + (1.0 - front_alignment) * 1.4
		if score < best_score:
			best_score = score
			best_target = target
	if print_shape_cast_debug:
		if best_target.is_empty():
			print("[交互选择][E] -> [无可响应目标]")
		else:
			var selected_body := best_target.get("body") as Node3D
			print("[交互选择][E] -> %s: %s" % [str(best_target.get("kind", "")), selected_body.get_path()])
	return best_target


func _build_interaction_target(body: Node3D) -> Dictionary:
	var chop := body as LivestockChop
	var chop_parent := body.get_parent()
	while chop == null and chop_parent is Node3D:
		chop = chop_parent as LivestockChop
		chop_parent = chop_parent.get_parent()
	if chop != null and chop.can_player_interact(self):
		return {
			"kind": "livestock_chop", "body": chop,
			"interaction_position": chop.global_position,
			"hint": chop.get_interaction_hint(self),
		}
	var livestock := body as FarmLivestock
	var livestock_parent := body.get_parent()
	while livestock == null and livestock_parent is Node3D:
		livestock = livestock_parent as FarmLivestock
		livestock_parent = livestock_parent.get_parent()
	if livestock != null and livestock.can_player_pick_up(self):
		return {
			"kind": "livestock", "body": livestock,
			"interaction_position": livestock.global_position,
			"hint": livestock.get_interaction_hint(self),
		}
	var crate_body := body as CargoCrateGround
	if crate_body == null and body.get_parent() is CargoCrateGround:
		crate_body = body.get_parent() as CargoCrateGround
	if crate_body != null and crate_body.current_hp > 0.0:
		return {
			"kind": "cargo_crate", "body": crate_body,
			"interaction_position": crate_body.global_position,
			"hint": crate_body.get_interaction_hint(self),
		}
	if body is CargoCarInteractionArea:
		var interaction_area := body as CargoCarInteractionArea
		var cargo_vehicle := interaction_area.get_cargo_car()
		if not is_instance_valid(cargo_vehicle):
			return {}
		if interaction_area.interaction_kind == "cargo":
			return {
				"kind": "cargo_car_storage",
				"body": interaction_area,
				"vehicle": cargo_vehicle,
				"hint": "[E] 打开货运库",
			}
		if not cargo_vehicle.can_team_enter(team):
			return {"kind": "vehicle_locked", "body": interaction_area, "hint": "敌方载具，无法驾驶"}
		return {
			"kind": "vehicle",
			"body": interaction_area,
			"vehicle": cargo_vehicle,
			"interaction_position": interaction_area.global_position,
			"hint": "载具已满员" if cargo_vehicle.is_full() else "[E] 进入载具",
		}
	var crop_tile := _get_interactable_crop_tile(body)
	if crop_tile != null:
		var crop_index := crop_tile.plant_children.find(body)
		if crop_index >= 0 and crop_tile.get_harvestable_crop(crop_index) != null:
			return {"kind": "crop", "body": body, "tile": crop_tile, "hint": "[E] 收获"}
	if body is VehicleBase:
		var vehicle := body as VehicleBase
		# CargoCar interaction is intentionally restricted to its two cab-side
		# driver areas and three cargo-bed areas.
		if vehicle.supports_cargo():
			return {}
		if not vehicle.can_team_enter(team):
			return {
				"kind": "vehicle_locked",
				"body": vehicle,
				"hint": "敌方载具，无法驾驶",
			}
		return {
			"kind": "vehicle",
			"body": vehicle,
			"hint": "载具已满员" if vehicle.is_full() else "[E] 进入载具",
		}
	if body is GarageUpgradeTerminal:
		var terminal := body as GarageUpgradeTerminal
		if terminal.can_player_interact(self):
			return {"kind": "garage_upgrade", "body": terminal, "hint": terminal.get_interaction_hint(self)}
	if body is IngredientPickup:
		var pickup := body as IngredientPickup
		if pickup.can_player_interact(self):
			return {"kind": "ingredient_pickup", "body": pickup, "hint": pickup.get_interaction_hint(self)}
	if body is PickupItem:
		var dropped_item := body as PickupItem
		if dropped_item.landed:
			return {"kind": "pickup_item", "body": dropped_item, "hint": dropped_item.get_interaction_hint(self)}
	if body is Oven:
		var oven := body as Oven
		if oven.can_player_interact(self):
			return {"kind": "oven", "body": oven, "hint": oven.get_interaction_hint(self)}
	if body is Freezer:
		var freezer := body as Freezer
		if freezer.can_player_interact(self):
			return {"kind": "freezer", "body": freezer, "hint": freezer.get_interaction_hint(self)}
	if body is StandMixer:
		var mixer := body as StandMixer
		if mixer.can_player_interact(self):
			return {"kind": "mixer", "body": mixer, "hint": mixer.get_interaction_hint(self)}
	if body is GriddleStation:
		var griddle := body as GriddleStation
		if griddle.can_player_interact(self):
			return {"kind": "griddle", "body": griddle, "hint": griddle.get_interaction_hint(self)}
	if body is InductionCounter:
		var induction := body as InductionCounter
		if induction.can_player_interact(self):
			return {"kind": "induction", "body": induction, "hint": induction.get_interaction_hint(self)}
	if body is RecipeCookingStation and body.is_in_group("smoker_stations"):
		var smoker := body as RecipeCookingStation
		if smoker.can_player_interact(self):
			return {"kind": "smoker", "body": smoker, "hint": smoker.get_interaction_hint(self)}
	if body is PlatingStation:
		var plating_station := body as PlatingStation
		if plating_station.can_player_interact(self):
			return {"kind": "plating_station", "body": plating_station, "hint": plating_station.get_interaction_hint(self)}
	if body is AutoCooker:
		var auto_cooker := body as AutoCooker
		if auto_cooker.can_player_interact(self):
			return {"kind": "auto_cooker", "body": auto_cooker, "hint": auto_cooker.get_interaction_hint(self)}
	if body is KitchenAppliance:
		var appliance := body as KitchenAppliance
		if appliance.can_player_interact(self):
			return {"kind": "kitchen", "body": appliance, "hint": appliance.get_interaction_hint(self)}
	if body is Shop:
		var shop := body as Shop
		return {"kind": "shop", "body": shop, "hint": shop.get_interaction_hint(self)}
	if body is Area3D and body.name == "ShopArea" and body.get_parent() is Shop:
		var area_shop := body.get_parent() as Shop
		return {
			"kind": "shop",
			"body": area_shop,
			"interaction_position": body.global_position,
			"hint": area_shop.get_interaction_hint(self),
		}
	if body is GovernmentBoard:
		var board := body as GovernmentBoard
		return {"kind": "government_board", "body": board, "hint": board.get_interaction_hint(self)}
	if body is Area3D and body.get_parent() is GovernmentBoard:
		var area_board := body.get_parent() as GovernmentBoard
		return {
			"kind": "government_board",
			"body": area_board,
			"interaction_position": body.global_position,
			"hint": area_board.get_interaction_hint(self),
		}
	return {}


func _debug_interaction_rejected_body(body: Node3D) -> void:
	if not debug_interaction_shapecasts or not GameAuthority.is_local_authority():
		return
	var crop_tile := _get_interactable_crop_tile(body)
	if crop_tile == null:
		return
	var crop_index := crop_tile.plant_children.find(body)
	print(
		"[交互筛选][E] %s -> 作物不可收获 (seed=%s, growth=%d, can_harvest=%s, index=%d)"
		% [body.name, crop_tile.seed_record, crop_tile.growth_value, crop_tile.can_harvest, crop_index]
	)


func _is_interaction_occluded(target_position: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var origin := global_position + Vector3.UP * 1.2
	var target := target_position + Vector3.UP * 0.5
	if origin.distance_squared_to(target) <= 0.04:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target, INTERACTION_OCCLUSION_MASK, [get_rid()])
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _request_single_crop_harvest(tile: FarmTile, crop: Node3D) -> void:
	if not is_instance_valid(crop):
		return
	var crop_index := tile.plant_children.find(crop)
	if crop_index < 0 or tile.get_harvestable_crop(crop_index) == null:
		return
	var action := {
		"type": "harvest_one",
		"tile_path": str(tile.get_path()),
		"tile_position": tile.global_position,
		"crop_index": crop_index,
		"crop_position": crop.global_position,
		"absorb_source": global_position + Vector3.UP * 0.9,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_farm_action(action)
	elif GameAuthority.is_local_authority():
		var result := GameAuthority.local_farm_action(authority_peer_id, action)
		if debug_interaction_shapecasts:
			print(
				"[交互收获][E] %s -> ok=%s, reason=%s"
				% [crop.name, bool(result.get("ok", false)), str(result.get("reason", ""))]
			)
	else:
		tile.harvest_one(global_position + Vector3.UP * 0.9, crop_index)


func _request_livestock_pickup(livestock: FarmLivestock) -> void:
	if not is_instance_valid(livestock):
		return
	var action := {
		"station_kind": "livestock",
		"action": "pickup",
		"animal_id": livestock.animal_id,
		"animal_position": livestock.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	elif GameAuthority.is_local_authority():
		var result := GameAuthority.server_ingredient_pickup_action(authority_peer_id, action)
		if not bool(result.get("ok", false)):
			show_gameplay_notice(str(result.get("message", "无法抱起这只动物")))


func _refresh_interact_hint() -> void:
	if not is_instance_valid(interact_hint):
		return
	var vehicle_upgrade_open := is_instance_valid(vehicle_upgrade_page) \
		and vehicle_upgrade_page.has_method("is_open") \
		and bool(vehicle_upgrade_page.call("is_open"))
	var government_notice_open := is_instance_valid(government_notice_page) \
		and government_notice_page.is_open()
	if $SubViewport/ShopPage.visible or vehicle_upgrade_open or government_notice_open:
		interact_hint.visible = false
		return
	var target := _get_best_interaction_target()
	interact_hint.visible = not target.is_empty()
	if interact_hint.visible:
		interact_hint.text = str(target.get("hint", "[E] 交互"))


func _set_weapon_aiming(value: bool) -> void:
	is_weapon_aiming = value and not is_prone and _current_tool_can_aim() and \
		is_instance_valid(tool_node)
	if is_instance_valid(tool_node) and tool_node.has_method("set_aiming"):
		tool_node.call("set_aiming", is_weapon_aiming)


func _update_weapon_aim(delta: float) -> void:
	if not _has_equipped_tool(current_tool_index):
		camera.fov = lerpf(camera.fov, camera_default_fov, 1.0 - exp(-12.0 * delta))
		return
	var definition: Dictionary = tool_definitions[current_tool_index]
	var aim_speed := float(definition.get("aim_speed", 12.0))
	var blend := 1.0 - exp(-aim_speed * delta)

	var target_fov := float(definition.get("aim_fov", camera_default_fov)) \
		if is_weapon_aiming else camera_default_fov
	camera.fov = lerpf(
		camera.fov,
		target_fov,
		blend
	)
	#print("CORSSHAIR??")
	_update_crosshair_visibility()

func _update_tool_camera_alignment() -> void:
	# This compensates the local first-person model against the local camera.
	# Remote visual proxies deliberately remove Camera3D and use snapshot aim.
	if is_remote_proxy or not is_instance_valid(camera) \
			or not is_instance_valid(tool_pivot) \
			or (not is_instance_valid(tool_node) and not is_instance_valid(held_item_node)):
		return
	# Weapon aiming owns the pivot orientation. Utility tools and held items do
	# not need camera alignment; keep the pivot neutral and continuously enforce
	# the model's world-up correction, including immediately after a weapon swap.
	if not _current_tool_is_shooting():
		tool_pivot.transform = Transform3D.IDENTITY
		_upright_held_model(tool_node)
		if is_instance_valid(held_item_node):
			_upright_held_model(held_item_node)
		return

	# A Muzzle or RayCast3D is the authoritative forward frame. The arm IK
	# controls where the hand is, while this compensation keeps the visible
	# tool and its gameplay ray aligned with the camera despite the imported
	# hand bone's changing orientation.
	var muzzle := tool_node.get_node_or_null("Muzzle") as Node3D
	var aim_basis: Basis
	if muzzle != null:
		aim_basis = muzzle.global_transform.basis.orthonormalized()
	else:
		var aim_ray := tool_node.find_child(
			"RayCast3D",
			true,
			false
		) as RayCast3D
		if aim_ray == null or aim_ray.target_position.is_zero_approx():
			tool_pivot.transform = Transform3D.IDENTITY
			return

		var ray_direction := (
			aim_ray.to_global(aim_ray.target_position)
			- aim_ray.global_position
		).normalized()
		var preferred_up := \
			tool_node.global_transform.basis.y.normalized()
		if absf(ray_direction.dot(preferred_up)) > 0.98:
			preferred_up = camera.global_transform.basis.x.normalized()
		aim_basis = Basis.looking_at(
			ray_direction,
			preferred_up
		).orthonormalized()

	if aim_basis.determinant() == 0.0:
		tool_pivot.transform = Transform3D.IDENTITY
		return

	var pivot_basis: Basis = \
		tool_pivot.global_transform.basis.orthonormalized()
	var aim_from_pivot: Basis = (
		pivot_basis.inverse() * aim_basis
	).orthonormalized()
	var desired_pivot_basis: Basis = (
		camera.global_transform.basis.orthonormalized()
		* aim_from_pivot.inverse()
	).orthonormalized()
	tool_pivot.global_transform = Transform3D(
		desired_pivot_basis,
		tool_pivot.global_position
	)


func _current_tool_is_shooting() -> bool:
	if not _has_equipped_tool(current_tool_index):
		return false
	return _definition_uses_weapon_orientation(tool_definitions[current_tool_index])


func _definition_uses_weapon_orientation(definition: Dictionary) -> bool:
	var tool_id := str(definition.get("id", ""))
	return str(definition.get("category", "utility")) == "shooting" \
			or str(definition.get("category", "utility")) == "throwable" \
			or HANDHELD_WEAPON_TOOL_IDS.has(tool_id)


func _current_tool_can_aim() -> bool:
	if not _has_equipped_tool(current_tool_index):
		return false
	return _current_tool_is_shooting() and bool(
		tool_definitions[current_tool_index].get("aimable", false)
	)


func get_combat_team() -> String:
	return team


func receive_bullet_hit(
	hit_direction: Vector3,
	force: float,
	shooter_team: String
) -> void:
	if shooter_team == team:
		return
	var horizontal_direction := Vector3(
		hit_direction.x, 0.0, hit_direction.z
	).normalized()
	rubber_knockback = horizontal_direction * force
	camera_shake_time = 0.22
	camera_shake_duration = 0.22
	camera_shake_strength = 0.075


func apply_explosion_camera_shake(explosion_position: Vector3, radius: float) -> void:
	if is_remote_proxy or radius <= 0.0:
		return
	var observer_position := global_position + Vector3.UP
	if vehicle_is_active and is_instance_valid(active_vehicle):
		observer_position = active_vehicle.global_position
	var ratio := clampf(1.0 - observer_position.distance_to(explosion_position) / radius, 0.0, 1.0)
	if ratio <= 0.0:
		return
	if vehicle_is_active:
		vehicle_camera_shake_duration = 0.72
		vehicle_camera_shake_time = maxf(vehicle_camera_shake_time, vehicle_camera_shake_duration)
		vehicle_camera_shake_strength = maxf(vehicle_camera_shake_strength, lerpf(0.04, 0.30, ratio))
	else:
		camera_shake_duration = 0.72
		camera_shake_time = maxf(camera_shake_time, camera_shake_duration)
		camera_shake_strength = maxf(camera_shake_strength, lerpf(0.035, 0.26, ratio))


func _create_damage_feedback_ui() -> void:
	if is_instance_valid(damage_flash_root):
		return
	damage_flash_root = Control.new()
	damage_flash_root.name = "DamageEdgeFlash"
	damage_flash_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_flash_root.modulate.a = 0.0
	damage_flash_root.visible = false
	$EffectLayer.add_child(damage_flash_root)
	var top_edge := ColorRect.new()
	top_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_edge.color = Color(0.82, 0.025, 0.025, 0.72)
	top_edge.anchor_right = 1.0
	top_edge.offset_bottom = 72.0
	damage_flash_root.add_child(top_edge)
	var bottom_edge := ColorRect.new()
	bottom_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_edge.color = Color(0.82, 0.025, 0.025, 0.72)
	bottom_edge.anchor_top = 1.0
	bottom_edge.anchor_right = 1.0
	bottom_edge.anchor_bottom = 1.0
	bottom_edge.offset_top = -72.0
	damage_flash_root.add_child(bottom_edge)


func _show_player_damage_feedback() -> void:
	if not is_instance_valid(damage_flash_root):
		_create_damage_feedback_ui()
	if is_instance_valid(damage_flash_tween):
		damage_flash_tween.kill()
	damage_flash_root.visible = true
	damage_flash_root.modulate.a = 0.34
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(damage_flash_root, "modulate:a", 0.0, 0.28)
	damage_flash_tween.tween_callback(func() -> void:
		if is_instance_valid(damage_flash_root):
			damage_flash_root.visible = false
	)
	if remote_is_active:
		_trigger_remote_damage_shake()
	elif vehicle_is_active:
		_trigger_vehicle_damage_shake()
	else:
		camera_shake_duration = 0.2
		camera_shake_time = camera_shake_duration
		camera_shake_strength = 0.055


func _tick_status_effects(delta: float) -> void:
	flame_remaining = maxf(0.0, flame_remaining - delta)
	freeze_remaining = maxf(0.0, freeze_remaining - delta)
	lightening_remaining = maxf(0.0, lightening_remaining - delta)
	bug_remaining = maxf(0.0, bug_remaining - delta)
	labeled_remaining = maxf(0.0, labeled_remaining - delta)
	if tranquilizer_remaining > 0.0:
		tranquilizer_remaining = maxf(0.0, tranquilizer_remaining - delta)
		tranquilizer_elapsed += delta
		_update_tranquilizer_overlay()
	# Local matches own their player bodies, while dedicated servers own only
	# player_states. Keeping this branch local prevents the two simulators from
	# applying the same DoT twice.
	if not GameAuthority.is_local_authority() or spicy_remaining <= 0.0 or is_respawning:
		return
	var spicy_tick := minf(delta, spicy_remaining)
	spicy_remaining = maxf(0.0, spicy_remaining - delta)
	var damage := maxf(0.0, spicy_dps) * spicy_tick
	server_hp = maxf(0.0, server_hp - damage)
	if GameAuthority.player_states.has(authority_peer_id):
		var state: Dictionary = GameAuthority.player_states[authority_peer_id]
		state["hp"] = server_hp
		state["spicy_remaining"] = spicy_remaining
		state["spicy_dps"] = spicy_dps
		GameAuthority.player_states[authority_peer_id] = state
		if damage > 0.0 and server_hp <= 0.0:
			GameAuthority._begin_player_respawn(authority_peer_id)
	if damage > 0.0:
		_update_health_ui()

func _update_camera_shake(delta: float) -> void:
	if camera_shake_time > 0.0:
		camera_shake_time -= delta
		var fade := clampf(camera_shake_time / maxf(camera_shake_duration, 0.01), 0.0, 1.0)
		camera.position = camera_rest_position + Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * camera_shake_strength * fade
	else:
		camera.position = camera_rest_position


func _connect_active_vehicle_damage_signal() -> void:
	if not is_instance_valid(active_vehicle) or is_remote_proxy:
		return
	if not active_vehicle.vehicle_damaged.is_connected(_on_active_vehicle_damaged):
		active_vehicle.vehicle_damaged.connect(_on_active_vehicle_damaged)
	var driving_camera := active_vehicle.get_driving_camera()
	if is_instance_valid(driving_camera):
		vehicle_camera_rest_position = driving_camera.position


func _disconnect_active_vehicle_damage_signal() -> void:
	if is_instance_valid(active_vehicle) \
			and active_vehicle.vehicle_damaged.is_connected(_on_active_vehicle_damaged):
		active_vehicle.vehicle_damaged.disconnect(_on_active_vehicle_damaged)
	_reset_vehicle_camera_shake()


func _on_active_vehicle_damaged(current_hp: float, max_hp: float) -> void:
	if not vehicle_is_active or not is_instance_valid(active_vehicle):
		return
	_trigger_vehicle_damage_shake()


func _trigger_vehicle_damage_shake() -> void:
	vehicle_camera_shake_duration = 0.22
	vehicle_camera_shake_time = vehicle_camera_shake_duration
	vehicle_camera_shake_strength = 0.09


func _update_vehicle_camera_shake(delta: float) -> void:
	if not is_instance_valid(active_vehicle):
		return
	var driving_camera := active_vehicle.get_driving_camera()
	if not is_instance_valid(driving_camera):
		return
	if vehicle_camera_shake_time > 0.0:
		vehicle_camera_shake_time = maxf(0.0, vehicle_camera_shake_time - delta)
		var fade := vehicle_camera_shake_time / maxf(vehicle_camera_shake_duration, 0.01)
		driving_camera.position = vehicle_camera_rest_position + Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * vehicle_camera_shake_strength * fade
	else:
		driving_camera.position = vehicle_camera_rest_position


func _reset_vehicle_camera_shake() -> void:
	if is_instance_valid(active_vehicle):
		var driving_camera := active_vehicle.get_driving_camera()
		if is_instance_valid(driving_camera):
			driving_camera.position = vehicle_camera_rest_position
	vehicle_camera_shake_time = 0.0
	vehicle_camera_shake_strength = 0.0
	vehicle_camera_shake_duration = 0.32


func _trigger_remote_damage_shake() -> void:
	if not remote_is_active or not is_instance_valid(remote_control_camera):
		return
	remote_camera_shake_duration = 0.2
	remote_camera_shake_time = remote_camera_shake_duration
	remote_camera_shake_strength = 0.065


func _update_remote_camera_shake(delta: float) -> void:
	if not is_instance_valid(remote_control_camera):
		return
	if remote_camera_shake_time > 0.0:
		remote_camera_shake_time = maxf(0.0, remote_camera_shake_time - delta)
		var fade := remote_camera_shake_time / maxf(remote_camera_shake_duration, 0.01)
		remote_control_camera.position = remote_camera_rest_position + Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * remote_camera_shake_strength * fade
	else:
		remote_control_camera.position = remote_camera_rest_position


func _reset_remote_camera_shake() -> void:
	if is_instance_valid(remote_control_camera):
		remote_control_camera.position = remote_camera_rest_position
	remote_camera_shake_time = 0.0
	remote_camera_shake_strength = 0.0
	remote_camera_shake_duration = 0.2


## 更新人物的外观
func set_player_appearance(hero_name:String,team_name:String):
	# 载入这个外观
	hero_name = _normalize_hero_id(hero_name)
	if hero_name not in ["cook","farmer","guard","mage","engineer","apothecary","assistant","trickster","prospector","rider"]:
		return
	#if hero_name 	
	if team_name not in ["blue","red"]:
		return
	var load_appearance_path = "res://character/hero_skeleton/" + hero_name + "_" + team_name + ".tscn"
	if not ResourceLoader.exists(load_appearance_path):
		push_warning("Player appearance scene missing: " + load_appearance_path)
		return
	var old_appearance := get_node_or_null("AppearanceNode")
	if old_appearance != null:
		hand_socket.use_external_skeleton = false
		hand_socket.external_skeleton = NodePath("")
		if is_instance_valid(back_equipment_socket):
			back_equipment_socket.use_external_skeleton = false
			back_equipment_socket.external_skeleton = NodePath("")
		if is_instance_valid(chest_equipment_socket):
			chest_equipment_socket.use_external_skeleton = false
			chest_equipment_socket.external_skeleton = NodePath("")
		if is_instance_valid(left_leg_equipment_socket):
			left_leg_equipment_socket.use_external_skeleton = false
			left_leg_equipment_socket.external_skeleton = NodePath("")
		if is_instance_valid(right_leg_equipment_socket):
			right_leg_equipment_socket.use_external_skeleton = false
			right_leg_equipment_socket.external_skeleton = NodePath("")
		back_equipment_socket = null
		back_equipment_visual = null
		chest_equipment_socket = null
		chest_equipment_visual = null
		left_leg_equipment_socket = null
		right_leg_equipment_socket = null
		left_leg_equipment_visual = null
		right_leg_equipment_visual = null
		remove_child(old_appearance)
		old_appearance.free()
	var appearance_node = load(load_appearance_path).instantiate()
	add_child(appearance_node)
	appearance_node.rotation.y = deg_to_rad(180)
	appearance_node.name = "AppearanceNode"
	appearance_player = appearance_node.find_child("AnimationPlayer",true)
	skeleton = appearance_node.find_child("Skeleton3D",true) as Skeleton3D
	if appearance_player == null or skeleton == null:
		push_error("Unable to initialize the animated character skeleton.")
		return
	if appearance_player.has_animation(&"ProneCrawl"):
		var prone_animation := appearance_player.get_animation(&"ProneCrawl")
		if prone_animation != null:
			prone_animation.loop_mode = Animation.LOOP_LINEAR
	else:
		push_warning("Character appearance is missing ProneCrawl: %s" % hero_name)
	
	appearance_player.play("Idle")
	emotion_controller = appearance_node.find_child("EmotionController",true)
	
	hand_socket.use_external_skeleton = true
	hand_socket.external_skeleton = hand_socket.get_path_to(skeleton)
	hand_socket.bone_name = "Hand.R"
	hand_socket.override_pose = false
	_ensure_back_equipment_socket()
	_refresh_back_equipment_visual()
	_ensure_chest_equipment_socket()
	_refresh_chest_equipment_visual()
	_ensure_leg_equipment_sockets()
	_refresh_leg_equipment_visuals()
	
	if not appearance_player.animation_finished.is_connected(
		_skeleton_animation_finished
	):
		appearance_player.animation_finished.connect(
			_skeleton_animation_finished
		)
	
	_setup_upper_body_aim()
	# Appearance scenes are replaced when a hero/team changes, so the x-ray
	# overlay must be rebound to the newly instanced character meshes.
	team_outline_visible = false
	_update_team_reveal_visual(true)


func _ensure_back_equipment_socket() -> void:
	if not is_instance_valid(skeleton):
		return
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance == null:
		return
	if not is_instance_valid(back_equipment_socket):
		back_equipment_socket = BoneAttachment3D.new()
		back_equipment_socket.name = "BackEquipmentSocket"
		appearance.add_child(back_equipment_socket)
	back_equipment_socket.use_external_skeleton = true
	back_equipment_socket.external_skeleton = back_equipment_socket.get_path_to(skeleton)
	back_equipment_socket.bone_name = "Chest"
	back_equipment_socket.override_pose = false


func _refresh_back_equipment_visual() -> void:
	if is_instance_valid(back_equipment_visual):
		back_equipment_visual.queue_free()
		back_equipment_visual = null
	if not is_instance_valid(skeleton):
		return
	_ensure_back_equipment_socket()
	var equipment_id := str(get_equipped_item("backpack").get("equipment_id", ""))
	var scene_path := EquipmentCatalog.get_scene_path(equipment_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("Unable to load back equipment: %s" % scene_path)
		return
	back_equipment_visual = packed.instantiate() as Node3D
	if back_equipment_visual != null:
		back_equipment_socket.add_child(back_equipment_visual)


func _ensure_chest_equipment_socket() -> void:
	if not is_instance_valid(skeleton):
		return
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance == null:
		return
	if not is_instance_valid(chest_equipment_socket):
		chest_equipment_socket = BoneAttachment3D.new()
		chest_equipment_socket.name = "ChestEquipmentSocket"
		appearance.add_child(chest_equipment_socket)
	chest_equipment_socket.use_external_skeleton = true
	chest_equipment_socket.external_skeleton = chest_equipment_socket.get_path_to(skeleton)
	chest_equipment_socket.bone_name = "Chest"
	chest_equipment_socket.override_pose = false


func _refresh_chest_equipment_visual() -> void:
	if is_instance_valid(chest_equipment_visual):
		chest_equipment_visual.queue_free()
		chest_equipment_visual = null
	if not is_instance_valid(skeleton):
		return
	_ensure_chest_equipment_socket()
	var equipment_id := str(get_equipped_item("chest_armor").get("equipment_id", ""))
	var scene_path := EquipmentCatalog.get_scene_path(equipment_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("Unable to load chest equipment: %s" % scene_path)
		return
	chest_equipment_visual = packed.instantiate() as Node3D
	if chest_equipment_visual != null:
		chest_equipment_socket.add_child(chest_equipment_visual)
		chest_equipment_visual.position += CHEST_ARMOR_ATTACHMENT_OFFSET


func _ensure_leg_equipment_sockets() -> void:
	if not is_instance_valid(skeleton):
		return
	var appearance := get_node_or_null("AppearanceNode") as Node3D
	if appearance == null:
		return
	if not is_instance_valid(left_leg_equipment_socket):
		left_leg_equipment_socket = BoneAttachment3D.new()
		left_leg_equipment_socket.name = "LeftLegEquipmentSocket"
		appearance.add_child(left_leg_equipment_socket)
	if not is_instance_valid(right_leg_equipment_socket):
		right_leg_equipment_socket = BoneAttachment3D.new()
		right_leg_equipment_socket.name = "RightLegEquipmentSocket"
		appearance.add_child(right_leg_equipment_socket)
	left_leg_equipment_socket.use_external_skeleton = true
	left_leg_equipment_socket.external_skeleton = left_leg_equipment_socket.get_path_to(skeleton)
	left_leg_equipment_socket.bone_name = "Thigh.L"
	left_leg_equipment_socket.override_pose = false
	left_leg_equipment_socket.position = Vector3(0.0, -0.05, -0.13)
	right_leg_equipment_socket.use_external_skeleton = true
	right_leg_equipment_socket.external_skeleton = right_leg_equipment_socket.get_path_to(skeleton)
	right_leg_equipment_socket.bone_name = "Thigh.R"
	right_leg_equipment_socket.override_pose = false
	right_leg_equipment_socket.position = Vector3(0.0, -0.05, -0.13)


func _refresh_leg_equipment_visuals() -> void:
	if is_instance_valid(left_leg_equipment_visual):
		left_leg_equipment_visual.queue_free()
		left_leg_equipment_visual = null
	if is_instance_valid(right_leg_equipment_visual):
		right_leg_equipment_visual.queue_free()
		right_leg_equipment_visual = null
	if not is_instance_valid(skeleton):
		return
	_ensure_leg_equipment_sockets()
	var equipment_id := str(get_equipped_item("legwear").get("equipment_id", ""))
	if equipment_id.is_empty():
		return
	left_leg_equipment_visual = _instantiate_leg_equipment_visual(
		EquipmentCatalog.get_leg_scene_path(equipment_id, false),
		left_leg_equipment_socket
	)
	right_leg_equipment_visual = _instantiate_leg_equipment_visual(
		EquipmentCatalog.get_leg_scene_path(equipment_id, true),
		right_leg_equipment_socket
	)


func _instantiate_leg_equipment_visual(scene_path: String, socket: BoneAttachment3D) -> Node3D:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path) or not is_instance_valid(socket):
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("Unable to load leg equipment: %s" % scene_path)
		return null
	var visual := packed.instantiate() as Node3D
	if visual != null:
		socket.add_child(visual)
	return visual


func _ensure_team_marker_visual() -> void:
	if is_instance_valid(team_marker):
		return
	team_marker = MeshInstance3D.new()
	team_marker.name = "TeamMarker"
	team_marker.position = Vector3.UP * TEAM_MARKER_HEIGHT
	team_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_marker.ignore_occlusion_culling = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 16
	sphere.rings = 8
	team_marker.mesh = sphere
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.no_depth_test = true
	marker_material.albedo_color = _team_marker_color()
	marker_material.emission_enabled = true
	marker_material.emission = _team_marker_color()
	marker_material.emission_energy_multiplier = 2.5
	marker_material.render_priority = 120
	team_marker.material_override = marker_material
	add_child(team_marker)
	team_marker.visible = false


func _team_marker_color() -> Color:
	return Color("#F04455") if team == "red" else Color("#398CFF")


func _local_viewer_team() -> String:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			return str((node as GamePlayer).team)
	return ""


func _update_team_visibility_timer(delta: float) -> void:
	team_visibility_accumulator += delta
	if team_visibility_accumulator < TEAM_VISIBILITY_UPDATE_INTERVAL:
		return
	team_visibility_accumulator = 0.0
	_update_team_reveal_visual()


func _update_team_reveal_visual(force := false) -> void:
	_ensure_team_marker_visual()
	# The first-person owner does not need a marker over their own head. Every
	# remote teammate is always revealed; an enemy is revealed only while labeled.
	var viewer_team := _local_viewer_team()
	var enemy_is_labeled := is_remote_proxy and not viewer_team.is_empty() \
		and viewer_team != team and labeled_remaining > 0.0
	var should_reveal := is_remote_proxy and not viewer_team.is_empty() and (
		viewer_team == team or enemy_is_labeled
	)
	if force or should_reveal != team_reveal_visible:
		team_reveal_visible = should_reveal
		var marker_material := team_marker.material_override as StandardMaterial3D
		if marker_material != null:
			marker_material.albedo_color = _team_marker_color()
			marker_material.emission = _team_marker_color()
		if is_instance_valid(team_outline_material):
			var outline_color := _team_marker_color()
			outline_color.a = 0.92
			team_outline_material.albedo_color = outline_color
			team_outline_material.emission = _team_marker_color()
	team_marker.visible = should_reveal and not is_respawning
	var should_outline := should_reveal and not is_respawning and (
		enemy_is_labeled or _is_occluded_from_local_camera()
	)
	if force or should_outline != team_outline_visible:
		_set_team_outline_visible(should_outline)


func _is_occluded_from_local_camera() -> bool:
	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null or get_world_3d() == null:
		return false
	var origin := active_camera.global_position
	var target := global_position + Vector3.UP * 1.35
	if origin.distance_squared_to(target) <= 0.01:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target, TEAM_VISIBILITY_RAY_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var exclusions: Array[RID] = []
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is CollisionObject3D and not (node as GamePlayer).is_remote_proxy:
			exclusions.append((node as CollisionObject3D).get_rid())
	query.exclude = exclusions
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _get_team_outline_material() -> StandardMaterial3D:
	if is_instance_valid(team_outline_material):
		return team_outline_material
	team_outline_material = StandardMaterial3D.new()
	team_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	team_outline_material.no_depth_test = true
	team_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var outline_color := _team_marker_color()
	outline_color.a = 0.92
	team_outline_material.albedo_color = outline_color
	team_outline_material.emission_enabled = true
	team_outline_material.emission = _team_marker_color()
	team_outline_material.emission_energy_multiplier = 1.8
	team_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	team_outline_material.grow = true
	team_outline_material.grow_amount = 0.045
	team_outline_material.render_priority = 119
	return team_outline_material


func _set_team_outline_visible(value: bool) -> void:
	team_outline_visible = value
	var appearance := get_node_or_null("AppearanceNode")
	if appearance == null:
		return
	var overlay := _get_team_outline_material() if value else null
	for mesh_node in appearance.find_children("*", "MeshInstance3D", true, false):
		var character_mesh := mesh_node as MeshInstance3D
		character_mesh.material_overlay = overlay
		character_mesh.ignore_occlusion_culling = value


func _setup_upper_body_aim() -> void:
	upper_body_look_modifiers.clear()
	upper_body_look_weights.clear()

	_add_upper_body_look("SpineLook", "Spine", 0.10, 20.0)
	_add_upper_body_look("ChestLook", "Chest", 0.22, 30.0)
	_add_upper_body_look("NeckLook", "Neck", 0.16, 35.0)
	_add_upper_body_look("HeadLook", "Head_2", 0.28, 50.0)

	right_arm_ik = skeleton.find_child(
		"RightArmIK",
		false,
		false
	) as TwoBoneIK3D
	if right_arm_ik == null:
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)

	right_arm_ik.setting_count = 1
	right_arm_ik.set_root_bone_name(0, "UpperArm.R")
	right_arm_ik.set_middle_bone_name(0, "Forearm.R")
	right_arm_ik.set_end_bone_name(0, "Hand.R")
	right_arm_ik.set_use_virtual_end(0, false)
	right_arm_ik.set_extend_end_bone(0, false)
	right_arm_ik.set_pole_direction(
		0,
		SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X
	)
	right_arm_ik.set_target_node(
		0,
		right_arm_ik.get_path_to(right_hand_ik_target)
	)
	right_arm_ik.set_pole_node(
		0,
		right_arm_ik.get_path_to(right_elbow_pole)
	)
	right_arm_ik.active = true
	right_arm_ik.influence = 0.0

	left_arm_ik = skeleton.find_child(
		"LeftArmIK",
		false,
		false
	) as TwoBoneIK3D
	if left_arm_ik == null:
		left_arm_ik = TwoBoneIK3D.new()
		left_arm_ik.name = "LeftArmIK"
		skeleton.add_child(left_arm_ik)
	left_arm_ik.setting_count = 1
	left_arm_ik.set_root_bone_name(0, "UpperArm.L")
	left_arm_ik.set_middle_bone_name(0, "Forearm.L")
	left_arm_ik.set_end_bone_name(0, "Hand.L")
	left_arm_ik.set_use_virtual_end(0, false)
	left_arm_ik.set_extend_end_bone(0, false)
	left_arm_ik.set_pole_direction(
		0,
		SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_X
	)
	left_arm_ik.set_target_node(
		0,
		left_arm_ik.get_path_to(left_hand_ik_target)
	)
	left_arm_ik.set_pole_node(
		0,
		left_arm_ik.get_path_to(left_elbow_pole)
	)
	left_arm_ik.active = true
	left_arm_ik.influence = 0.0

	# TwoBoneIK solves the wrist position but does not guarantee the final
	# Hand.R rotation. This modifier runs after IK and constrains wrist pitch
	# to the camera-facing target so the attached tool no longer rolls wildly.
	hand_aim_look = skeleton.find_child(
		"HandAimLook",
		false,
		false
	) as LookAtModifier3D
	if hand_aim_look == null:
		hand_aim_look = LookAtModifier3D.new()
		hand_aim_look.name = "HandAimLook"
		skeleton.add_child(hand_aim_look)

	hand_aim_look.bone_name = "Hand.R"
	hand_aim_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y
	hand_aim_look.primary_rotation_axis = Vector3.AXIS_X
	hand_aim_look.use_secondary_rotation = false
	hand_aim_look.relative = false
	hand_aim_look.use_angle_limitation = true
	hand_aim_look.symmetry_limitation = true
	hand_aim_look.primary_limit_angle = deg_to_rad(55.0)
	hand_aim_look.primary_damp_threshold = 1.0
	hand_aim_look.target_node = hand_aim_look.get_path_to(
		upper_body_look_target
	)
	# ToolPivot now performs full camera-frame alignment. The old single-axis
	# wrist LookAt could flip near the pitch limits, so it remains disabled.
	hand_aim_look.active = false
	hand_aim_look.influence = 0.0


func _add_upper_body_look(
	node_name:String,
	bone_name:String,
	base_weight:float,
	limit_degrees:float
) -> void:
	var modifier := skeleton.find_child(
		node_name,
		false,
		false
	) as LookAtModifier3D
	if modifier == null:
		modifier = LookAtModifier3D.new()
		modifier.name = node_name
		skeleton.add_child(modifier)

	modifier.bone_name = bone_name
	modifier.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	modifier.primary_rotation_axis = Vector3.AXIS_X
	modifier.use_secondary_rotation = false
	modifier.relative = true
	modifier.use_angle_limitation = true
	modifier.symmetry_limitation = true
	modifier.primary_limit_angle = deg_to_rad(limit_degrees)
	modifier.primary_damp_threshold = 1.0
	modifier.target_node = modifier.get_path_to(
		upper_body_look_target
	)
	modifier.active = true
	modifier.influence = 0.0

	upper_body_look_modifiers.append(modifier)
	upper_body_look_weights.append(base_weight)


func _update_upper_body_aim(delta:float) -> void:
	if skeleton == null:
		return

	var is_punching := action_anim_locked \
		and appearance_player.current_animation == &"PunchRight"
	var is_holding_any_item := (
			is_instance_valid(tool_node) and tool_node.visible
		) or (
			is_instance_valid(held_item_node) and held_item_node.visible
		)
	# All held objects use the same camera-space hand position reached by the
	# punch pose, so the complete model stays clearly visible in first person.
	var hand_in_camera_space := is_punching or is_holding_any_item
	var hand_target := punch_hand_camera_offset if hand_in_camera_space \
		else right_hand_ik_rest_position
	if hand_in_camera_space:
		# Held tools, food, dishes and the punch all use this visible hand target.
		right_hand_ik_target.position = hand_target
	else:
		right_hand_ik_target.position = right_hand_ik_target.position.lerp(
			hand_target,
			minf(delta * 18.0, 1.0)
		)

	var equipped_scale := 1.0 if is_holding_any_item else 0.0
	var action_scale := 0.70 if action_anim_locked else 1.0
	var uses_two_handed_grip := _current_tool_uses_two_handed_grip()
	var left_hand_target := left_hand_ik_rest_position
	if uses_two_handed_grip:
		var weapon_grip := tool_node.get_node_or_null("LeftHandGrip") as Marker3D
		if weapon_grip != null:
			left_hand_target = Head.to_local(weapon_grip.global_position)
		else:
			left_hand_target = left_hand_weapon_camera_offset
	left_hand_ik_target.position = left_hand_ik_target.position.lerp(
		left_hand_target,
		minf(delta * 18.0, 1.0)
	)

	for index in range(upper_body_look_modifiers.size()):
		var modifier := upper_body_look_modifiers[index]
		if not is_instance_valid(modifier):
			continue
		var desired := \
			upper_body_look_weights[index] \
			* equipped_scale \
			* action_scale
		modifier.influence = move_toward(
			modifier.influence,
			desired,
			delta * 3.5
		)

	if is_instance_valid(right_arm_ik):
		# Keep the punch hand in the camera frame so the forearm visibly extends
		# toward the target, regardless of the imported character's punch pose.
		var desired_ik := punch_hand_ik_weight if hand_in_camera_space \
			else 0.88 * equipped_scale * action_scale
		right_arm_ik.influence = move_toward(
			right_arm_ik.influence,
			desired_ik,
			delta * (28.0 if hand_in_camera_space else 5.0)
		)
	if is_instance_valid(left_arm_ik):
		var desired_left_ik := left_hand_weapon_ik_weight * action_scale \
			if uses_two_handed_grip else 0.0
		left_arm_ik.influence = move_toward(
			left_arm_ik.influence,
			desired_left_ik,
			delta * 12.0
		)

	if is_instance_valid(hand_aim_look):
		hand_aim_look.influence = 0.0


func _current_tool_uses_two_handed_grip() -> bool:
	if not _current_tool_is_shooting() or not is_instance_valid(tool_node) \
			or not tool_node.visible:
		return false
	return bool(tool_definitions[current_tool_index].get("two_handed", false))

func _skeleton_animation_finished(
	anim_name:String
):
	match anim_name:
		&"JumpStart":
			if not is_on_floor():
				_play_body_animation(&"JumpLoop", 0.05)

		&"JumpLand":
			landing_animation = false

		&"ShootOneHand", &"PunchRight", &"ToolUseRight":
			action_anim_locked = false


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if is_respawning or GameAuthority.should_send_network_requests():
		return
	if not (
			body is RubberBullet
			or body is NailBullet
			or body is ColorBullet
			or body is DetectLaserBullet
			or body is MedicineBullet
			or body is TranquilizerBullet
		):
			return

	var shooter_team := str(body.call("get_bullet_owner"))
	if shooter_team == team and not body is MedicineBullet:
		return

	var hit_direction := Vector3.ZERO
	var knockback_force := 0.0
	var effect := "None"
	var strength := 0.0
	if body is RubberBullet:
		var bullet := body as RubberBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		strength = float(bullet.bullet_strength)
	elif body is NailBullet:
		var bullet := body as NailBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		strength = float(bullet.bullet_strength)
	elif body is ColorBullet:
		var bullet := body as ColorBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		effect = str(bullet.bullet_effect)
		strength = float(bullet.bullet_strength)
	elif body is DetectLaserBullet:
		var bullet := body as DetectLaserBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		effect = str(bullet.bullet_effect)
		strength = float(bullet.bullet_strength)
	elif body is MedicineBullet:
		var bullet := body as MedicineBullet
		if not bullet.gameplay_effect_enabled:
			body.queue_free()
			return
		effect = MedicineBullet.EFFECT_HEALING
		strength = float(bullet.bullet_strength)
	elif body is TranquilizerBullet:
		var bullet := body as TranquilizerBullet
		if not bullet.gameplay_effect_enabled:
			body.queue_free()
			return
		hit_direction = bullet.direction
		effect = TranquilizerBullet.EFFECT_TRANQUILIZER
		strength = float(bullet.bullet_strength)
	if not body is MedicineBullet:
		receive_bullet_hit(hit_direction, knockback_force, shooter_team)
	body.queue_free()
	impact(effect, strength, shooter_team)
		
func impact(effect: String, strength: float, shooter: String) -> bool:
	if is_respawning or GameAuthority.should_send_network_requests():
		return false
	var normalized_effect := effect.strip_edges().to_lower()
	if normalized_effect == MedicineBullet.EFFECT_HEALING:
		server_hp = minf(PLAYER_MAX_HP, server_hp + MEDICINE_HEAL_AMOUNT)
		if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
			var healed_state: Dictionary = GameAuthority.player_states[authority_peer_id]
			healed_state["hp"] = server_hp
			GameAuthority.player_states[authority_peer_id] = healed_state
		_update_health_ui()
		return true
	if normalized_effect == "medicine_storm":
		var amount := maxf(0.0, strength)
		if shooter == team:
			print("GET HP!")
			server_hp = minf(PLAYER_MAX_HP, server_hp + amount)
		else:
			server_hp = maxf(0.0, server_hp - amount)
		if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
			var medicine_state: Dictionary = GameAuthority.player_states[authority_peer_id]
			medicine_state["hp"] = server_hp
			GameAuthority.player_states[authority_peer_id] = medicine_state
			if server_hp <= 0.0:
				GameAuthority._begin_player_respawn(authority_peer_id)
		_update_health_ui()
		return true
	if shooter == team:
		return false
	if normalized_effect == "spicy":
		spicy_remaining = maxf(0.0, CombatBalance.get_float("spicy_blaster", "spicy_duration"))
		spicy_dps = maxf(0.0, maxf(strength, CombatBalance.get_float("spicy_blaster", "spicy_dps")))
		if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
			var spicy_state: Dictionary = GameAuthority.player_states[authority_peer_id]
			spicy_state["spicy_remaining"] = spicy_remaining
			spicy_state["spicy_dps"] = spicy_dps
			GameAuthority.player_states[authority_peer_id] = spicy_state
		return true
	match normalized_effect:
		TranquilizerBullet.EFFECT_TRANQUILIZER:
			apply_tranquilizer_effect()
		"lightening", "lightning":
			lightening_remaining = maxf(lightening_remaining, 1.0)
		"flame", "fire":
			flame_remaining = maxf(flame_remaining, 3.0)
		"freeze", "ice":
			freeze_remaining = maxf(freeze_remaining, 2.0)
		"bug":
			bug_remaining = maxf(bug_remaining, 4.0)
		"labeled", "labelled":
			labeled_remaining = maxf(
				labeled_remaining,
				CombatBalance.get_float("small_mouse", "labeled_duration")
			)
		_:
			pass
	var damage := maxf(0.0, strength)
	if damage <= 0.0:
		return true
	if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
		var attacker_peer_id := GameAuthority.resolve_attacker_peer_id(shooter)
		var applied := GameAuthority._damage_player(
			authority_peer_id, damage, 0.0, Vector3.ZERO, shooter, effect, attacker_peer_id
		)
		var authoritative_state: Dictionary = GameAuthority.player_states.get(authority_peer_id, {})
		server_hp = float(authoritative_state.get("hp", server_hp))
		var armor_id := str(authoritative_state.get("equipped_chest_armor_id", ""))
		if not armor_id.is_empty():
			apply_chest_armor_state(GameAuthority._server_equipment_item(authoritative_state, armor_id))
		var legwear_id := str(authoritative_state.get("equipped_legwear_id", ""))
		if not legwear_id.is_empty():
			apply_legwear_state(GameAuthority._server_equipment_item(authoritative_state, legwear_id))
		_update_health_ui()
		return applied
	server_hp = maxf(0.0, server_hp - damage)
	if GameAuthority.is_local_authority() and GameAuthority.player_states.has(authority_peer_id):
		var state: Dictionary = GameAuthority.player_states[authority_peer_id]
		state["hp"] = server_hp
		GameAuthority.player_states[authority_peer_id] = state
		if server_hp <= 0.0:
			GameAuthority._begin_player_respawn(authority_peer_id)
	_update_health_ui()
	return true


func remote_device_reset(new_tool:Node3D):
	if not is_instance_valid(new_tool):
		return
	if is_instance_valid(remote_tool_node) and remote_tool_node != new_tool:
		# Switching control targets must leave the previously deployed device in
		# the world. It can be controlled again later or destroyed by gameplay.
		remote_device_close()
	remote_tool_node = new_tool
	remote_control_camera = remote_tool_node.find_child("Camera3D", true, false) as Camera3D
	_register_remote_device(remote_tool_node)
	var quality := _remote_device_quality(remote_tool_node)
	if quality == "NONE":
		if is_instance_valid(remote_effect):
			remote_effect.visible = false
		remote_effect = null
	elif quality == "HQ":
		remote_effect = $EffectLayer/RemoteEffect	
	else:
		remote_effect = $EffectLayer/RemoteLQEffect	
func remote_device_start():
	if not is_instance_valid(remote_tool_node) or not remote_tool_node.has_method("begin_remote_control"):
		remote_tool_node = null
		remote_control_camera = null
		return
	if remote_tool_node.has_method("set_remote_receiver"):
		remote_tool_node.call("set_remote_receiver", self)
	remote_tool_node.begin_remote_control()
	if remote_control_camera == null:
		remote_control_camera = remote_tool_node.find_child("Camera3D", true, false) as Camera3D
	if is_instance_valid(remote_control_camera):
		remote_camera_rest_position = remote_control_camera.position
	remote_is_active = true
	active_remote_device_id = _remote_device_id(remote_tool_node)
	pending_remote_device_id = ""
	_update_control_status_ui()
	_ensure_remote_device_camera()
	call_deferred("_ensure_remote_device_camera")
	if is_instance_valid(remote_effect):
		_set_remote_effect_signal_strength(remote_effect, 1.0)
		remote_effect.visible = true
	_hide_remote_device_panel()


func _ensure_remote_device_camera() -> void:
	if not remote_is_active or not is_instance_valid(remote_control_camera):
		return
	if is_instance_valid(camera):
		camera.current = false
	remote_control_camera.make_current()
	
func remote_device_close(notify_authority := true):
	var closed_device_id := active_remote_device_id
	if closed_device_id.is_empty() and is_instance_valid(remote_tool_node):
		closed_device_id = _remote_device_id(remote_tool_node)
	if is_instance_valid(remote_tool_node) and remote_tool_node.has_method("end_remote_control"):
		remote_tool_node.end_remote_control()
	if is_instance_valid(remote_effect):
		_set_remote_effect_signal_strength(remote_effect, 1.0)
		remote_effect.visible = false
	_reset_remote_camera_shake()
	remote_is_active = false
	active_remote_device_id = ""
	remote_control_camera = null
	_update_control_status_ui()
	if is_instance_valid(camera):
		camera.make_current()
	if notify_authority and not closed_device_id.is_empty():
		if GameAuthority.should_send_network_requests():
			MultiplayerNetwork.submit_remote_control_session(closed_device_id, false)
		elif GameAuthority.is_local_authority():
			GameAuthority.local_remote_control_session(authority_peer_id, closed_device_id, false)
	
func remote_destoryed():
	if is_instance_valid(remote_effect):
		_set_remote_effect_signal_strength(remote_effect, 1.0)
		remote_effect.visible = false
	remote_tool_node = null
	remote_is_active = false
	remote_control_camera = null
	_update_control_status_ui()
	camera.make_current()


func _set_remote_effect_signal_strength(effect: ColorRect, signal_power: float) -> void:
	if not is_instance_valid(effect):
		return
	var shader_material := effect.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("signal_strength", clampf(signal_power, 0.0, 1.0))


func _register_remote_device(device: Node3D) -> void:
	if not is_instance_valid(device):
		return
	var device_id := _remote_device_id(device)
	owned_remote_devices[device_id] = {
		"node": device,
		"type": _remote_device_type(device),
	}
	var lost_callback := Callable(self, "_on_remote_device_signal_lost").bind(device_id)
	if device.has_signal(&"remote_signal_lost") and not device.is_connected(&"remote_signal_lost", lost_callback):
		device.connect(&"remote_signal_lost", lost_callback)
	var exit_callback := Callable(self, "_on_remote_device_tree_exited").bind(device_id)
	if not device.tree_exited.is_connected(exit_callback):
		device.tree_exited.connect(exit_callback)
	_refresh_remote_device_panel()


func _remote_device_id(device: Node3D) -> String:
	if not is_instance_valid(device):
		return ""
	if device.has_meta("network_device_id"):
		return str(device.get_meta("network_device_id"))
	# get_meta's default argument is evaluated eagerly by GDScript. Do not place
	# get_path() there: this helper is also called from tree_exited callbacks.
	if device.is_inside_tree():
		return str(device.get_path())
	return ""


func _remote_device_quality(device: Node3D) -> String:
	if device is ActionDrone:
		return "NONE"
	return "HQ" if device is NormalDrone or device is TechDrone else "LQ"


func _remote_device_display_name(device: Node3D) -> String:
	if device is ActionDrone:
		return "ActionDrone"
	if device is TechDrone:
		return "TechDrone"
	if device is SmallMouse:
		return "SmallMouse"
	if device is NormalDrone:
		return "NormalDrone"
	if device is BoomBuggy:
		return "BoomBuggy"
	return str(device.name)


func _show_remote_device_panel() -> void:
	_refresh_remote_device_panel()
	if owned_remote_devices.is_empty():
		return
	remote_device_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_remote_device_panel() -> void:
	remote_device_panel.visible = false
	if not remote_is_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_remote_device_panel() -> void:
	for child in remote_device_list.get_children():
		child.queue_free()
	remote_device_buttons.clear()
	for device_id_value in owned_remote_devices.keys():
		var device_id := str(device_id_value)
		var entry: Dictionary = owned_remote_devices[device_id]
		var device: Node3D = entry.get("node", null)
		if not is_instance_valid(device):
			owned_remote_devices.erase(device_id)
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(290, 54)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _remote_device_status_text(device)
		button.gui_input.connect(_on_remote_device_item_gui_input.bind(device_id))
		remote_device_list.add_child(button)
		remote_device_buttons[device_id] = button


func _update_remote_device_panel() -> void:
	var stale_ids: Array[String] = []
	for device_id_value in owned_remote_devices.keys():
		var device_id := str(device_id_value)
		var entry: Dictionary = owned_remote_devices[device_id]
		var device: Node3D = entry.get("node", null)
		if not is_instance_valid(device):
			stale_ids.append(device_id)
			continue
		var button: Button = remote_device_buttons.get(device_id, null)
		if is_instance_valid(button):
			button.text = _remote_device_status_text(device)
	for device_id in stale_ids:
		owned_remote_devices.erase(device_id)
	if not stale_ids.is_empty():
		_refresh_remote_device_panel()
	if owned_remote_devices.is_empty():
		remote_device_panel.visible = false


func _remote_device_status_text(device: Node3D) -> String:
	var signal_strength := 0.0
	if device.has_meta("network_effective_signal"):
		signal_strength = clampf(float(device.get_meta("network_effective_signal")), 0.0, 1.0)
	elif device.has_method("get_signal_strength"):
		signal_strength = clampf(float(device.call("get_signal_strength", self)), 0.0, 1.0)
	return "%s\nSignal %d%%" % [_remote_device_display_name(device), roundi(signal_strength * 100.0)]


func _on_remote_device_item_gui_input(event: InputEvent, device_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and mouse_event.double_click:
		_reconnect_remote_device(device_id)


func _reconnect_remote_device(device_id: String) -> void:
	var entry: Dictionary = owned_remote_devices.get(device_id, {})
	var device: Node3D = entry.get("node", null)
	if not is_instance_valid(device):
		owned_remote_devices.erase(device_id)
		_refresh_remote_device_panel()
		return
	if GameAuthority.should_send_network_requests():
		pending_remote_device_id = device_id
		MultiplayerNetwork.submit_remote_control_session(device_id, true)
		return
	if GameAuthority.is_local_authority():
		var result: Dictionary = GameAuthority.local_remote_control_session(authority_peer_id, device_id, true)
		if not bool(result.get("ok", false)):
			return
	remote_device_reset(device)
	remote_device_start()


func apply_remote_control_session_result(data: Dictionary, device: Node3D) -> void:
	var device_id := str(data.get("device_id", ""))
	if device_id.is_empty():
		return
	if not bool(data.get("connected", false)):
		if active_remote_device_id == device_id:
			remote_device_close(false)
		return
	if device_id != pending_remote_device_id:
		return
	pending_remote_device_id = ""
	if not bool(data.get("ok", false)) or not bool(data.get("connected", false)):
		return
	if not is_instance_valid(device):
		return
	remote_device_reset(device)
	remote_device_start()


func _on_remote_device_signal_lost(device_id: String) -> void:
	if active_remote_device_id == device_id:
		remote_device_close()


func _on_remote_device_tree_exited(device_id: String) -> void:
	owned_remote_devices.erase(device_id)
	remote_device_buttons.erase(device_id)
	# The authoritative destroy path frees the device before the next snapshot.
	# Drop the selected-device reference even when it is not actively controlled.
	if (
		is_instance_valid(remote_tool_node)
		and _remote_device_id(remote_tool_node) == device_id
	):
		remote_tool_node = null
		remote_control_camera = null
	elif not is_instance_valid(remote_tool_node):
		remote_tool_node = null
	if active_remote_device_id == device_id:
		remote_is_active = false
		active_remote_device_id = ""
		remote_control_camera = null
		_update_control_status_ui()
		if is_instance_valid(remote_effect):
			_set_remote_effect_signal_strength(remote_effect, 1.0)
			remote_effect.visible = false
		if is_instance_valid(camera):
			camera.make_current()
	_refresh_remote_device_panel()
