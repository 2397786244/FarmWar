extends Control
class_name PlayerBackpack

signal personal_slot_selected(slot_index: int, item: Dictionary)

@export var base_player_bag_slots := 12
@export var bag_slots_per_row := 6

const STANDALONE_WINDOW_OFFSETS := Rect2(-470.0, -340.0, 940.0, 680.0)
const COMPANION_WINDOW_OFFSETS := Rect2(-910.0, -340.0, 940.0, 680.0)
const PERSONAL_TAB := 0
const VEHICLE_GARAGE_TAB := 1
const TEAM_STORAGE_TAB := 2
const VEHICLE_GARAGE_REQUEST_TIMEOUT_SECONDS := 8.0
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")
const BAG_SLOT_SCENE := preload("res://ui/player_backpack_slot.tscn")
const VehicleColorCatalogScript = preload("res://src/vehicle_color_catalog.gd")

@onready var backpack_window: PanelContainer = $BackpackWindow
@onready var inventory_tabs: TabContainer = $BackpackWindow/Margin/VBox/InventoryTabs
@onready var bag_grid: GridContainer = $BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/BagGrid
@onready var weight_label: Label = $BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/WeightLabel
@onready var team_storage_list: VBoxContainer = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/ListPanel/Margin/Scroll/ItemList
@onready var team_storage_money: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/Header/Money
@onready var team_storage_total: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/Header/TotalWeight
@onready var team_storage_empty: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/EmptyLabel
@onready var vehicle_garage_list: VBoxContainer = $BackpackWindow/Margin/VBox/InventoryTabs/VehicleGarage/ListPanel/Margin/Scroll/VehicleList
@onready var vehicle_garage_money: Label = $BackpackWindow/Margin/VBox/InventoryTabs/VehicleGarage/Header/Money
@onready var vehicle_garage_empty: Label = $BackpackWindow/Margin/VBox/InventoryTabs/VehicleGarage/EmptyLabel
@onready var vehicle_garage_status: Label = $BackpackWindow/Margin/VBox/InventoryTabs/VehicleGarage/StatusLabel
@onready var item_tooltip: Node = $PlayerBackpackTooltip

var player: GamePlayer
var bag_slots: Array[PlayerBackpackSlot] = []
var hotbar_slots: Array[PlayerBackpackSlot] = []
var equipment_slots: Dictionary = {}
var showing_as_companion := false
var companion_transfer_target: Node
var _active_drag_data: Dictionary = {}
var _garage_repair_requests: Dictionary = {}
var _garage_repair_request_counter := 0
var _garage_status_message := ""
var _garage_status_color := Color(0.65, 0.72, 0.76)

func _ready() -> void:
	bag_grid.columns = bag_slots_per_row
	for index in range(base_player_bag_slots):
		var slot := get_node_or_null("BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/BagGrid/BagSlot%d" % index) as PlayerBackpackSlot
		if slot != null:
			bag_slots.append(slot)
	var backpack_slot := get_node_or_null("BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/Upper/Equipment/Margin/VBox/Grid/BackpackSlot") as PlayerBackpackSlot
	if backpack_slot != null:
		equipment_slots["backpack"] = backpack_slot
	var chest_armor_slot := get_node_or_null("BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/Upper/Equipment/Margin/VBox/Grid/ChestArmorSlot") as PlayerBackpackSlot
	if chest_armor_slot != null:
		equipment_slots["chest_armor"] = chest_armor_slot
	var legwear_slot := get_node_or_null("BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/Upper/Equipment/Margin/VBox/Grid/LegwearSlot") as PlayerBackpackSlot
	if legwear_slot != null:
		equipment_slots["legwear"] = legwear_slot
	for index in range(6):
		var slot := get_node_or_null("Hotbar/Margin/Slots/HotbarSlot%d" % index) as PlayerBackpackSlot
		if slot != null:
			hotbar_slots.append(slot)
	var configurable_slots: Array[PlayerBackpackSlot] = []
	for slot in bag_slots:
		configurable_slots.append(slot)
	for slot in hotbar_slots:
		configurable_slots.append(slot)
	for value: Variant in equipment_slots.values():
		if value is PlayerBackpackSlot:
			configurable_slots.append(value as PlayerBackpackSlot)
	for slot in configurable_slots:
		slot.configure(self)
	inventory_tabs.set_tab_title(PERSONAL_TAB, "玩家背包")
	inventory_tabs.set_tab_title(VEHICLE_GARAGE_TAB, "载具")
	inventory_tabs.set_tab_title(TEAM_STORAGE_TAB, "队伍物资")
	inventory_tabs.tab_changed.connect(_on_inventory_tab_changed)
	if not GlobalVar.storage_changed.is_connected(_on_team_storage_changed):
		GlobalVar.storage_changed.connect(_on_team_storage_changed)
	if is_instance_valid(GameAuthority) and GameAuthority.has_signal("team_garage_state_changed") \
			and not GameAuthority.team_garage_state_changed.is_connected(_on_team_garage_state_changed):
		GameAuthority.team_garage_state_changed.connect(_on_team_garage_state_changed)
	backpack_window.visible = false
	vehicle_garage_status.text = ""
	vehicle_garage_status.visible = false
	set_process(false)


func _process(delta: float) -> void:
	var has_active_request := false
	for garage_vehicle_id_value: Variant in _garage_repair_requests.keys():
		var garage_vehicle_id := str(garage_vehicle_id_value)
		var request_value: Variant = _garage_repair_requests.get(garage_vehicle_id, {})
		if not request_value is Dictionary:
			continue
		var request_state := request_value as Dictionary
		if bool(request_state.get("timed_out", false)):
			continue
		has_active_request = true
		request_state["elapsed"] = float(request_state.get("elapsed", 0.0)) + delta
		if float(request_state["elapsed"]) < VEHICLE_GARAGE_REQUEST_TIMEOUT_SECONDS:
			continue
		request_state["timed_out"] = true
		_garage_status_message = "请求超时，服务器可能仍在处理；可重试确认。"
		_garage_status_color = Color("ff8075")
		_garage_repair_requests[garage_vehicle_id] = request_state
		if is_open() and inventory_tabs.current_tab == VEHICLE_GARAGE_TAB:
			_refresh_vehicle_garage()
	set_process(has_active_request)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_value: Variant = get_viewport().gui_get_drag_data()
		_active_drag_data = (drag_value as Dictionary).duplicate(true) \
			if drag_value is Dictionary else {}
	elif what == NOTIFICATION_DRAG_END:
		var drag_data := _active_drag_data
		_active_drag_data = {}
		if drag_data.is_empty() or get_viewport().gui_is_drag_successful() \
				or _inventory_ui_contains_screen_point(get_viewport().get_mouse_position()):
			return
		if is_instance_valid(player):
			player.request_drop_dragged_inventory_item(drag_data)


func _inventory_ui_contains_screen_point(screen_point: Vector2) -> bool:
	if is_instance_valid(backpack_window) and backpack_window.visible \
			and backpack_window.get_global_rect().has_point(screen_point):
		return true
	var hotbar := get_node_or_null("Hotbar") as Control
	if hotbar != null and hotbar.visible and hotbar.get_global_rect().has_point(screen_point):
		return true
	return is_instance_valid(companion_transfer_target) \
		and companion_transfer_target.has_method("contains_storage_screen_point") \
		and bool(companion_transfer_target.call("contains_storage_screen_point", screen_point))

func bind_player(next_player: GamePlayer) -> void:
	player = next_player
	refresh()

func is_open() -> bool:
	return backpack_window.visible


func is_companion_display() -> bool:
	return backpack_window.visible and showing_as_companion

func toggle() -> void:
	toggle_personal()


func toggle_personal() -> void:
	if is_companion_display():
		return
	if is_open() and inventory_tabs.current_tab == PERSONAL_TAB:
		close()
	else:
		open_personal()


func toggle_team_storage() -> void:
	toggle_vehicle_garage()


func toggle_vehicle_garage() -> void:
	if is_companion_display():
		return
	if is_open() and inventory_tabs.current_tab == VEHICLE_GARAGE_TAB:
		close()
	else:
		open_vehicle_garage()

func open() -> void:
	open_personal()


func open_personal() -> void:
	_open_standalone_tab(PERSONAL_TAB)


func open_team_storage() -> void:
	open_vehicle_garage()


func open_vehicle_garage() -> void:
	_open_standalone_tab(VEHICLE_GARAGE_TAB)


func open_team_materials() -> void:
	_open_standalone_tab(TEAM_STORAGE_TAB)


func _open_standalone_tab(tab_index: int) -> void:
	if player == null:
		return
	showing_as_companion = false
	companion_transfer_target = null
	_set_window_offsets(STANDALONE_WINDOW_OFFSETS)
	inventory_tabs.tabs_visible = true
	inventory_tabs.current_tab = tab_index
	backpack_window.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()


func show_companion(transfer_target: Node = null, window_offsets := COMPANION_WINDOW_OFFSETS) -> void:
	if player == null:
		return
	showing_as_companion = true
	companion_transfer_target = transfer_target
	_set_window_offsets(window_offsets)
	inventory_tabs.current_tab = PERSONAL_TAB
	inventory_tabs.tabs_visible = false
	backpack_window.visible = true
	refresh()


func hide_companion() -> void:
	if not showing_as_companion:
		return
	showing_as_companion = false
	companion_transfer_target = null
	backpack_window.visible = false
	inventory_tabs.tabs_visible = true
	hide_item_tooltip()
	_set_window_offsets(STANDALONE_WINDOW_OFFSETS)


func close() -> void:
	showing_as_companion = false
	companion_transfer_target = null
	backpack_window.visible = false
	inventory_tabs.tabs_visible = true
	hide_item_tooltip()
	_set_window_offsets(STANDALONE_WINDOW_OFFSETS)
	if player != null and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func can_drag_slot(slot_index: int, slot_kind := "inventory", equipment_type := "") -> bool:
	if player == null:
		return false
	if slot_kind == "equipment":
		return not player.get_equipped_item(equipment_type).is_empty()
	return not player.get_backpack_item(slot_index).is_empty()

func move_slot(from_index: int, to_index: int) -> void:
	if player == null:
		return
	player.move_backpack_item(from_index, to_index)
	hide_item_tooltip()
	refresh()


func select_personal_slot(slot_index: int) -> void:
	if player == null or slot_index < 0 or slot_index >= player.get_active_bag_slot_count():
		return
	personal_slot_selected.emit(slot_index, player.get_backpack_item(slot_index))


func make_unit_drag_data(slot_index: int) -> Dictionary:
	if player == null or slot_index < 0 or slot_index >= player.get_active_bag_slot_count():
		return {}
	var item := player.get_backpack_item(slot_index)
	var unit_weight := UnitWeightItem.get_unit_weight_kg(item)
	var piece := UnitWeightItem.make_piece(item, unit_weight)
	if piece.is_empty():
		return {}
	return {
		"unit_weight_transfer": true,
		"unit_weight_kg": UnitWeightItem.get_weight_kg(piece),
		"unit_item": piece,
		"backpack": self,
		"slot_index": slot_index,
		"slot_kind": "inventory",
	}


func can_drop_slot(target: PlayerBackpackSlot, data: Variant) -> bool:
	if player == null or not data is Dictionary:
		return false
	var transfer_data := data as Dictionary
	var source_page: Variant = transfer_data.get("companion_page", transfer_data.get("cargo_page", null))
	if source_page != null and source_page == companion_transfer_target:
		return showing_as_companion \
			and is_instance_valid(companion_transfer_target) \
			and target.slot_kind == "inventory" \
			and target.slot_index >= 0 \
			and target.slot_index < player.get_active_bag_slot_count() \
			and (
				player.get_backpack_item(target.slot_index).is_empty() \
				or UnitWeightItem.can_merge(
					player.get_backpack_item(target.slot_index),
					transfer_data.get("unit_item", {}) as Dictionary
				)
			) \
			and bool(companion_transfer_target.call(
				"can_drop", "player", target.slot_index, transfer_data
			))
	if transfer_data.get("backpack") != self:
		return false
	var source_kind := str(transfer_data.get("slot_kind", "inventory"))
	if bool(transfer_data.get("unit_weight_transfer", false)):
		if target.slot_kind != "inventory" or source_kind != "inventory" \
				or int(transfer_data.get("slot_index", -1)) == target.slot_index:
			return false
		var target_item := player.get_backpack_item(target.slot_index)
		return target_item.is_empty() or UnitWeightItem.can_merge(
			target_item, transfer_data.get("unit_item", {}) as Dictionary
		)
	if target.slot_kind == "equipment":
		if source_kind != "inventory":
			return false
		var source_index := int(data.get("slot_index", -1))
		if source_index < 0 or source_index >= GamePlayer.BASE_PLAYER_BAG_SLOTS:
			return false
		var item := player.get_backpack_item(source_index)
		return str(item.get("kind", "")) == "equipment" \
				and str(item.get("equipment_type", "")) == target.equipment_type
	if source_kind == "equipment":
		if target.slot_index < 0 or target.slot_index >= GamePlayer.BASE_PLAYER_BAG_SLOTS:
			return false
		var target_item := player.get_backpack_item(target.slot_index)
		return target_item.is_empty() or (
			str(target_item.get("kind", "")) == "equipment" \
			and str(target_item.get("equipment_type", "")) == str(data.get("equipment_type", ""))
		)
	return int(data.get("slot_index", -1)) != target.slot_index


func drop_on_slot(target: PlayerBackpackSlot, data: Variant) -> void:
	if not can_drop_slot(target, data):
		return
	var transfer_data := data as Dictionary
	var source_page: Variant = transfer_data.get("companion_page", transfer_data.get("cargo_page", null))
	if source_page != null and source_page == companion_transfer_target:
		companion_transfer_target.call("drop_item", "player", target.slot_index, data as Dictionary)
		hide_item_tooltip()
		return
	var source_kind := str(transfer_data.get("slot_kind", "inventory"))
	if bool(transfer_data.get("unit_weight_transfer", false)):
		player.split_backpack_item_unit(
			int(transfer_data.get("slot_index", -1)),
			target.slot_index,
			float(transfer_data.get("unit_weight_kg", 0.0))
		)
		refresh()
		hide_item_tooltip()
		return
	if target.slot_kind == "equipment":
		player.request_equip_item(int(data.get("slot_index", -1)), target.equipment_type)
	elif source_kind == "equipment":
		var equipment_type := str(data.get("equipment_type", ""))
		if player.get_backpack_item(target.slot_index).is_empty():
			player.request_unequip_item(equipment_type, target.slot_index)
		else:
			player.request_equip_item(target.slot_index, equipment_type)
	else:
		move_slot(int(data.get("slot_index", -1)), target.slot_index)
	hide_item_tooltip()


func show_item_tooltip(item: Dictionary, anchor_rect: Rect2) -> void:
	if not is_open():
		return
	if is_instance_valid(item_tooltip) and item_tooltip.has_method("show_for_item"):
		item_tooltip.call("show_for_item", item, anchor_rect)


func hide_item_tooltip() -> void:
	if is_instance_valid(item_tooltip) and item_tooltip.has_method("hide_tooltip"):
		item_tooltip.call("hide_tooltip")

func refresh() -> void:
	if player == null:
		return
	_ensure_bag_slots(player.get_active_bag_slot_count())
	for index in range(bag_slots.size()):
		bag_slots[index].visible = index < player.get_active_bag_slot_count()
		if bag_slots[index].visible:
			bag_slots[index].set_item(player.get_backpack_item(index), index == player.current_tool_index, player.get_backpack_slot_cooldown(index))
	for equipment_type_value: Variant in equipment_slots.keys():
		var equipment_type := str(equipment_type_value)
		var equipment_slot := equipment_slots[equipment_type] as PlayerBackpackSlot
		equipment_slot.set_item(player.get_equipped_item(equipment_type))
	for index in range(hotbar_slots.size()):
		hotbar_slots[index].set_item(player.get_backpack_item(index), index == player.current_tool_index, player.get_backpack_slot_cooldown(index))
	weight_label.text = "重量  %.2f / %.2f kg" % [
		player.get_personal_bag_weight_kg(),
		player.get_personal_bag_capacity_kg(),
	]
	_refresh_vehicle_garage()
	_refresh_team_storage()


func _ensure_bag_slots(required_count: int) -> void:
	while bag_slots.size() < required_count:
		var slot := BAG_SLOT_SCENE.instantiate() as PlayerBackpackSlot
		if slot == null:
			return
		slot.name = "BagSlot%d" % bag_slots.size()
		slot.slot_index = bag_slots.size()
		bag_grid.add_child(slot)
		slot.configure(self)
		bag_slots.append(slot)


func _refresh_team_storage() -> void:
	for child in team_storage_list.get_children():
		team_storage_list.remove_child(child)
		child.queue_free()
	if player == null or not GlobalVar.team_storage.has(player.team):
		team_storage_empty.visible = true
		team_storage_money.text = "队伍金钱  0"
		team_storage_total.text = "总重量  0.00 kg"
		return
	var display_state := GlobalVar.get_team_storage_display_state(player.team)
	team_storage_money.text = "队伍金钱  %d" % int(round(float(display_state.get("team_money", 0.0))))
	team_storage_money.add_theme_color_override(
		"font_color", Color("#FF5656") if player.team == "red" else Color("#69A7FF")
	)
	var entries: Array[Dictionary] = display_state.get("entries", [])
	for entry: Dictionary in entries:
		_add_team_storage_row(entry)
	team_storage_empty.visible = entries.is_empty()
	team_storage_total.text = "总重量  %.2f kg" % float(display_state.get("total_weight_kg", 0.0))


func _add_team_storage_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 42.0)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemIcon
	icon.custom_minimum_size = Vector2(36.0, 36.0)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.text = str(entry.get("display_name", entry.get("item_id", "")))
	var amount_label := Label.new()
	amount_label.custom_minimum_size.x = 190.0
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.add_theme_font_size_override("font_size", 20)
	amount_label.add_theme_color_override("font_color", Color(0.68, 0.88, 0.94))
	if str(entry.get("unit", "kg")) == "kg":
		amount_label.text = "%.2f kg" % float(entry.get("amount", 0.0))
	else:
		amount_label.text = "%d 件" % roundi(float(entry.get("amount", 0.0)))
	row.add_child(icon)
	icon.set_item_id(str(entry.get("item_id", "")))
	row.add_child(name_label)
	row.add_child(amount_label)
	team_storage_list.add_child(row)


func _refresh_vehicle_garage() -> void:
	if vehicle_garage_list == null:
		return
	for child in vehicle_garage_list.get_children():
		vehicle_garage_list.remove_child(child)
		child.queue_free()
	if player == null:
		vehicle_garage_empty.visible = true
		vehicle_garage_money.text = "队伍金钱  0"
		vehicle_garage_status.text = _garage_status_message
		vehicle_garage_status.visible = not _garage_status_message.is_empty()
		vehicle_garage_status.add_theme_color_override("font_color", _garage_status_color)
		return
	var team := str(player.team)
	vehicle_garage_money.text = "队伍金钱  %d" % int(round(GlobalVar.check_team_item_amount(team, "money")))
	vehicle_garage_money.add_theme_color_override(
		"font_color", Color("ff5656") if team == "red" else Color("69a7ff")
	)
	var records: Array[Dictionary] = []
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_team_garage_records"):
		records = GameAuthority.get_team_garage_records(team)
		records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("garage_sequence", 0)) < int(right.get("garage_sequence", 0))
	)
	var active_garage_ids: Dictionary = {}
	for record: Dictionary in records:
		if str(record.get("status", "")) == "active" and not bool(record.get("delivery_pending", false)):
			active_garage_ids[str(record.get("garage_vehicle_id", ""))] = true
	var activated_request := false
	for garage_vehicle_id_value: Variant in _garage_repair_requests.keys():
		var garage_vehicle_id := str(garage_vehicle_id_value)
		if active_garage_ids.has(garage_vehicle_id):
			_garage_repair_requests.erase(garage_vehicle_id)
			activated_request = true
	if activated_request:
		_garage_status_message = ""
		_garage_status_color = Color("6fd18a")
	set_process(not _garage_repair_requests.is_empty())
	for record: Dictionary in records:
		_add_vehicle_garage_row(record)
	vehicle_garage_empty.visible = records.is_empty()
	vehicle_garage_status.text = _garage_status_message
	vehicle_garage_status.visible = not _garage_status_message.is_empty()
	vehicle_garage_status.add_theme_color_override("font_color", _garage_status_color)


func _add_vehicle_garage_row(record: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 72.0)
	row.add_theme_constant_override("separation", 12)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.text = _vehicle_garage_display_name(record)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(name_label)

	var garage_vehicle_id := str(record.get("garage_vehicle_id", ""))
	var delivery_pending := bool(record.get("delivery_pending", false))
	var status := str(record.get("status", "destroyed"))
	var request_state: Dictionary = _garage_repair_requests.get(garage_vehicle_id, {})
	var timed_out := bool(request_state.get("timed_out", false))
	var request_active := not request_state.is_empty() and not timed_out
	var quote: Dictionary = {}
	var quote_available := false
	if status == "destroyed" and not delivery_pending and not request_active:
		if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_vehicle_garage_service_quote"):
			quote = GameAuthority.get_vehicle_garage_service_quote(record)
		quote_available = bool(quote.get("available", false)) \
			and int(quote.get("repair_fee", -1)) >= 0 \
			and int(quote.get("delivery_fee", -1)) >= 0 \
			and int(quote.get("total_fee", -1)) >= 0
		var fee_label := Label.new()
		fee_label.add_theme_font_size_override("font_size", 15)
		fee_label.add_theme_color_override("font_color", Color("a6afb7"))
		fee_label.text = "修理费用不可用" if not quote_available else "修理费：%d + 运送费：%d = 总计：%d" % [
			int(quote.get("repair_fee", 0)),
			int(quote.get("delivery_fee", 0)),
			int(quote.get("total_fee", 0)),
		]
		details.add_child(fee_label)

	var status_label := Label.new()
	status_label.custom_minimum_size.x = 110.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 19)
	if delivery_pending:
		status_label.text = "运送中"
		status_label.add_theme_color_override("font_color", Color("f2b84b"))
	else:
		status_label.text = "可用" if status == "active" else "被摧毁"
		status_label.add_theme_color_override(
			"font_color", Color("6fd18a") if status == "active" else Color("ff8075")
		)
	var repair_button := Button.new()
	repair_button.custom_minimum_size = Vector2(160.0, 42.0)
	repair_button.add_theme_font_size_override("font_size", 16)
	if request_active:
		status_label.text = "运送中"
		status_label.add_theme_color_override("font_color", Color("f2b84b"))
		repair_button.text = "运送中"
		repair_button.disabled = true
		repair_button.visible = true
	elif status != "active" and not delivery_pending:
		repair_button.text = "重试确认" if timed_out else "修理并运送"
		repair_button.disabled = not quote_available
		repair_button.pressed.connect(_on_repair_delivery_pressed.bind(garage_vehicle_id))
	else:
		repair_button.text = "运送中" if delivery_pending else ""
		repair_button.disabled = true
		repair_button.visible = delivery_pending or status != "active"
	row.add_child(details)
	row.add_child(status_label)
	row.add_child(repair_button)
	vehicle_garage_list.add_child(row)


func _vehicle_garage_display_name(record: Dictionary) -> String:
	var body_color_id := str(record.get("body_color_id", "black"))
	var wheel_color_id := str(record.get("wheel_color_id", "black"))
	var body_label := VehicleColorCatalogScript.get_label(body_color_id)
	var wheel_label := VehicleColorCatalogScript.get_label(wheel_color_id)
	return "%s%s%s配色%d" % [
		str(record.get("display_name", record.get("vehicle_id", "载具"))),
		body_label,
		wheel_label,
		int(record.get("garage_sequence", 0)),
	]


func _on_repair_delivery_pressed(garage_vehicle_id: String) -> void:
	if player == null or garage_vehicle_id.is_empty():
		return
	var record := GameAuthority.get_team_garage_record(garage_vehicle_id) \
		if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_team_garage_record") else {}
	if record.is_empty() or str(record.get("status", "")) != "destroyed" \
			or bool(record.get("delivery_pending", false)):
		_refresh_vehicle_garage()
		return
	var request_state: Dictionary = _garage_repair_requests.get(garage_vehicle_id, {})
	var request: Dictionary = request_state.get("request", {}) if request_state is Dictionary else {}
	if request.is_empty():
		_garage_repair_request_counter += 1
		var peer_id := GameAuthority.get_local_interaction_peer_id() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_local_interaction_peer_id") \
			else GameAuthority.LOCAL_PLAYER_ID
		request = {
			"action": "repair_delivery",
			"shop_category": "vehicle_garage",
			"request_id": "garage_repair_%d_%d_%d" % [peer_id, Time.get_ticks_msec(), _garage_repair_request_counter],
			"garage_vehicle_id": garage_vehicle_id,
		}
	_garage_repair_requests[garage_vehicle_id] = {
		"request": request.duplicate(true),
		"elapsed": 0.0,
		"timed_out": false,
	}
	set_process(true)
	_garage_status_message = "正在确认队伍资金和载具交付位置……"
	_garage_status_color = Color("a6afb7")
	_refresh_vehicle_garage()
	if GameAuthority.should_send_network_requests():
		var sent := MultiplayerNetwork.submit_shop_transaction(request)
		if not sent:
			apply_vehicle_garage_transaction_result({
				"ok": false,
				"phase": "failed",
				"reason": "request_not_sent",
				"peer_id": GameAuthority.get_local_interaction_peer_id(),
				"shop_category": "vehicle_garage",
				"action": "repair_delivery",
				"request_id": str(request.get("request_id", "")),
				"garage_vehicle_id": garage_vehicle_id,
			})
		return
	if GameAuthority.is_local_interaction_authority():
		var local_peer_id := GameAuthority.LOCAL_PLAYER_ID
		if player != null:
			local_peer_id = int(player.authority_peer_id)
		apply_vehicle_garage_transaction_result(
			GameAuthority.local_shop_transaction(local_peer_id, request)
		)


func apply_vehicle_garage_transaction_result(result: Dictionary) -> void:
	if str(result.get("shop_category", "")) != "vehicle_garage":
		return
	var request_id := str(result.get("request_id", ""))
	var garage_vehicle_id := str(result.get("garage_vehicle_id", ""))
	if garage_vehicle_id.is_empty():
		for id_value: Variant in _garage_repair_requests.keys():
			var value: Variant = _garage_repair_requests.get(id_value, {})
			if not value is Dictionary:
				continue
			var stored_request: Variant = (value as Dictionary).get("request", {})
			if stored_request is Dictionary and str((stored_request as Dictionary).get("request_id", "")) == request_id:
				garage_vehicle_id = str(id_value)
				break
	if garage_vehicle_id.is_empty() or not _garage_repair_requests.has(garage_vehicle_id):
		return
	var stored_state_value: Variant = _garage_repair_requests.get(garage_vehicle_id, {})
	if not stored_state_value is Dictionary:
		return
	var stored_state := stored_state_value as Dictionary
	var stored_request_value: Variant = stored_state.get("request", {})
	if not stored_request_value is Dictionary \
			or str((stored_request_value as Dictionary).get("request_id", "")) != request_id:
		# A late result for a previous request must not close a newer request for
		# the same garage record.
		return
	var phase := str(result.get("phase", "failed"))
	if phase == "pending":
		var pending_state: Dictionary = stored_state
		pending_state["elapsed"] = 0.0
		pending_state["timed_out"] = false
		_garage_repair_requests[garage_vehicle_id] = pending_state
		_garage_status_message = "载具正在空投运送中……"
		_garage_status_color = Color("f2b84b")
		_refresh_vehicle_garage()
		set_process(true)
		return
	_garage_repair_requests.erase(garage_vehicle_id)
	set_process(false if _garage_repair_requests.is_empty() else true)
	var reason := str(result.get("reason", ""))
	if bool(result.get("ok", false)) and phase == "completed":
		# The active garage row is the confirmation. Do not leave the old
		# "checking funds"/delivery message below the list after it is usable.
		_garage_status_message = ""
		_garage_status_color = Color("6fd18a")
	else:
		_garage_status_message = _vehicle_garage_result_message(reason, bool(result.get("refunded", false)))
		_garage_status_color = Color("ff8075")
	_refresh_vehicle_garage()


func _vehicle_garage_result_message(reason: String, refunded: bool) -> String:
	match reason:
		"garage_vehicle_busy":
			return "其他队员正在修理并运送。"
		"garage_vehicle_already_active":
			return "该载具已被其他队员获得。"
		"insufficient_money":
			return "队伍资金不足。"
		"no_vehicle_spawn_point", "placement_missing_world", "placement_missing_scene", \
		"placement_invalid_scene", "placement_no_collision", "placement_no_ground", \
		"placement_too_steep", "placement_in_water", "placement_blocked":
			return "玩家附近没有合法的载具交付点。" + ("费用已全额退款。" if refunded else "")
		"vehicle_spawn_failed", "missing_vehicle_scene":
			return "载具交付失败。" + ("费用已全额退款。" if refunded else "")
		"invalid_service_fee":
			return "载具维修费用不可用，无法免费维修。"
		"request_not_sent":
			return "网络未连接，修理请求未发送。"
		_:
			return "载具交付失败：%s%s" % [reason, "（费用已全额退款）" if refunded else ""]


func _on_inventory_tab_changed(_tab: int) -> void:
	hide_item_tooltip()
	if is_open():
		refresh()


func _on_team_storage_changed(team: String, _item_name: String, _new_amount: float) -> void:
	if player != null and team == player.team and is_open():
		_refresh_team_storage()
		_refresh_vehicle_garage()


func _on_team_garage_state_changed(team: String) -> void:
	if player != null and team == player.team and is_open():
		_refresh_vehicle_garage()

func flash_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return
	var slot := hotbar_slots[slot_index]
	var tween := create_tween()
	tween.tween_property(slot, "modulate", Color("#FF9D9D"), 0.06)
	tween.tween_property(slot, "modulate", Color.WHITE, 0.12)


func _set_window_offsets(offsets: Rect2) -> void:
	backpack_window.offset_left = offsets.position.x
	backpack_window.offset_top = offsets.position.y
	backpack_window.offset_right = offsets.position.x + offsets.size.x
	backpack_window.offset_bottom = offsets.position.y + offsets.size.y
