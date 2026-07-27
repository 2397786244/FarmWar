extends Control
class_name PlayerBackpack

signal personal_slot_selected(slot_index: int, item: Dictionary)

@export var base_player_bag_slots := 12
@export var bag_slots_per_row := 6

const STANDALONE_WINDOW_OFFSETS := Rect2(-470.0, -340.0, 940.0, 680.0)
const COMPANION_WINDOW_OFFSETS := Rect2(-910.0, -340.0, 940.0, 680.0)
const PERSONAL_TAB := 0
const TEAM_STORAGE_TAB := 1
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")
const BAG_SLOT_SCENE := preload("res://ui/player_backpack_slot.tscn")

@onready var backpack_window: PanelContainer = $BackpackWindow
@onready var inventory_tabs: TabContainer = $BackpackWindow/Margin/VBox/InventoryTabs
@onready var bag_grid: GridContainer = $BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/BagGrid
@onready var weight_label: Label = $BackpackWindow/Margin/VBox/InventoryTabs/PersonalBackpack/WeightLabel
@onready var team_storage_list: VBoxContainer = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/ListPanel/Margin/Scroll/ItemList
@onready var team_storage_money: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/Header/Money
@onready var team_storage_total: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/Header/TotalWeight
@onready var team_storage_empty: Label = $BackpackWindow/Margin/VBox/InventoryTabs/TeamStorage/EmptyLabel
@onready var item_tooltip: Node = $PlayerBackpackTooltip

var player: GamePlayer
var bag_slots: Array[PlayerBackpackSlot] = []
var hotbar_slots: Array[PlayerBackpackSlot] = []
var equipment_slots: Dictionary = {}
var showing_as_companion := false
var companion_transfer_target: Node
var _active_drag_data: Dictionary = {}

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
	inventory_tabs.set_tab_title(TEAM_STORAGE_TAB, "队伍库存")
	inventory_tabs.tab_changed.connect(_on_inventory_tab_changed)
	if not GlobalVar.storage_changed.is_connected(_on_team_storage_changed):
		GlobalVar.storage_changed.connect(_on_team_storage_changed)
	backpack_window.visible = false


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
	if is_companion_display():
		return
	if is_open() and inventory_tabs.current_tab == TEAM_STORAGE_TAB:
		close()
	else:
		open_team_storage()

func open() -> void:
	open_personal()


func open_personal() -> void:
	_open_standalone_tab(PERSONAL_TAB)


func open_team_storage() -> void:
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
	var team_data: Dictionary = GlobalVar.team_storage[player.team]
	team_storage_money.text = "队伍金钱  %d" % int(round(GlobalVar.check_team_item_amount(player.team, "money")))
	team_storage_money.add_theme_color_override(
		"font_color", Color("#FF5656") if player.team == "red" else Color("#69A7FF")
	)
	var entries: Array[Dictionary] = []
	var total_weight := 0.0
	for item_id_value: Variant in team_data.keys():
		var item_id := str(item_id_value)
		var amount := float(team_data.get(item_id_value, 0.0))
		if item_id == "money" or amount <= 0.0001:
			continue
		var product := GlobalVar.get_shop_product(item_id)
		var unit := str(product.get("unit", "kg"))
		var display_name := str(product.get("name", ""))
		var ingredient := IngredientCatalog.get_definition(item_id)
		if not ingredient.is_empty():
			display_name = str(ingredient.get("display_name", display_name))
		if display_name.is_empty():
			display_name = item_id
		entries.append({
			"display_name": display_name,
			"item_id": item_id,
			"amount": amount,
			"unit": unit,
		})
		if unit == "kg":
			total_weight += amount
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)
	for entry: Dictionary in entries:
		_add_team_storage_row(entry)
	team_storage_empty.visible = entries.is_empty()
	team_storage_total.text = "总重量  %.2f kg" % total_weight


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


func _on_inventory_tab_changed(_tab: int) -> void:
	hide_item_tooltip()
	if is_open():
		refresh()


func _on_team_storage_changed(team: String, _item_name: String, _new_amount: float) -> void:
	if player != null and team == player.team and is_open():
		_refresh_team_storage()

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
