extends PanelContainer
class_name AutoSalesPage

signal closed

const VehicleSalesCatalogScript = preload("res://src/vehicle_sales_catalog.gd")
const VehicleColorCatalogScript = preload("res://src/vehicle_color_catalog.gd")

const COLOR_BACKGROUND := Color("0b0d0f")
const COLOR_SURFACE := Color("15191d")
const COLOR_SURFACE_HIGHLIGHT := Color("22282e")
const COLOR_TEXT := Color("f2f4f5")
const COLOR_MUTED := Color("a6afb7")
const COLOR_ACCENT := Color("e45b4e")
const COLOR_ACCENT_DARK := Color("71302d")
const COLOR_SUCCESS := Color("6fd18a")
const COLOR_ERROR := Color("ff8075")
const PURCHASE_REQUEST_TIMEOUT_SECONDS := 8.0

var current_shop: Node
var current_team := ""
var current_player: Node
var selected_vehicle_id := ""
var selected_body_color_id := "black"
var selected_wheel_color_id := "black"
var purchase_pending := false
var _purchase_timed_out := false
var _purchase_wait_elapsed := 0.0
var _purchase_request_counter := 0
var _active_purchase_request_id := ""
var _active_purchase_request: Dictionary = {}
var _last_status_message := ""
var _last_status_color := COLOR_MUTED
var _show_last_status_on_open := false

var _title_label: Label
var _money_label: Label
var _price_label: Label
var _description_label: Label
var _status_label: Label
var _vehicle_list: VBoxContainer
var _body_color_grid: GridContainer
var _wheel_color_grid: GridContainer
var _purchase_button: Button
var _vehicle_buttons: Dictionary = {}
var _body_color_buttons: Dictionary = {}
var _wheel_color_buttons: Dictionary = {}

var _preview_viewport: SubViewport
var _preview_container: SubViewportContainer
var _preview_spin_root: Node3D
var _preview_model: Node3D
var _preview_camera: Camera3D


func _ready() -> void:
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	visible = false
	set_process(false)
	GlobalVar.storage_changed.connect(_on_storage_changed)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)


func is_open() -> bool:
	return visible


func show_shop(shop: Node, team: String, player: Node = null) -> void:
	if not is_instance_valid(shop):
		return
	current_shop = shop
	current_team = team
	current_player = player
	if not _active_purchase_request.is_empty():
		selected_vehicle_id = str(_active_purchase_request.get("vehicle_id", selected_vehicle_id))
		selected_body_color_id = str(_active_purchase_request.get("body_color_id", selected_body_color_id))
		selected_wheel_color_id = str(_active_purchase_request.get("wheel_color_id", selected_wheel_color_id))
	visible = true
	set_process(true)
	_layout_panel()
	_build_vehicle_list()
	_build_color_grids()
	_refresh_money()
	if selected_vehicle_id.is_empty() or VehicleSalesCatalogScript.get_product(selected_vehicle_id).is_empty():
		var products := VehicleSalesCatalogScript.get_products()
		selected_vehicle_id = str(products[0].get("vehicle_id", "")) if not products.is_empty() else ""
	_refresh_selection()
	_load_preview()
	if purchase_pending:
		_update_status("正在等待服务器确认交付结果……", COLOR_MUTED)
	elif _purchase_timed_out:
		_update_status("请求超时，服务器可能仍在处理；可重试确认。", COLOR_ERROR)
	elif _show_last_status_on_open:
		_update_status(_last_status_message, _last_status_color)
		_show_last_status_on_open = false
	else:
		_update_status("选择载具、车身颜色和轮毂颜色后购买。", COLOR_MUTED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop() -> void:
	if not visible:
		return
	visible = false
	set_process(purchase_pending or _purchase_timed_out)
	_clear_preview()
	current_shop = null
	current_team = ""
	current_player = null
	closed.emit()


func close() -> void:
	close_shop()


func _process(delta: float) -> void:
	if purchase_pending:
		_purchase_wait_elapsed += maxf(0.0, delta)
		if _purchase_wait_elapsed >= PURCHASE_REQUEST_TIMEOUT_SECONDS:
			purchase_pending = false
			_purchase_timed_out = true
			_update_status("请求超时，服务器可能仍在处理；可重试确认。", COLOR_ERROR)
			_refresh_selection()
	if not visible:
		return
	if is_instance_valid(_preview_spin_root):
		_preview_spin_root.rotate_y(0.32 * delta)
	_refresh_money()
	_update_preview_viewport_size()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_stylebox_override("panel", _style_box(COLOR_BACKGROUND, 12))
	clip_contents = true

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	_title_label = Label.new()
	_title_label.text = "AutoSales 载具商店"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(_title_label)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 20)
	_money_label.add_theme_color_override("font_color", Color("e8b45a"))
	header.add_child(_money_label)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "关闭（Esc）"
	close_button.custom_minimum_size = Vector2(44, 40)
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.pressed.connect(close_shop)
	header.add_child(close_button)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	root.add_child(content)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, 10))
	content.add_child(preview_panel)
	_preview_container = SubViewportContainer.new()
	_preview_container.stretch = true
	_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_container.custom_minimum_size = Vector2(480, 380)
	preview_panel.add_child(_preview_container)
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "VehiclePreviewViewport"
	_preview_viewport.transparent_bg = false
	_preview_viewport.gui_disable_input = true
	_preview_viewport.handle_input_locally = false
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_preview_viewport.size = Vector2i(640, 480)
	_preview_viewport.world_3d = World3D.new()
	_preview_container.add_child(_preview_viewport)
	_create_preview_world()

	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size.x = 330.0
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, 10))
	content.add_child(right_panel)
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 18)
	right_margin.add_theme_constant_override("margin_top", 16)
	right_margin.add_theme_constant_override("margin_right", 18)
	right_margin.add_theme_constant_override("margin_bottom", 16)
	right_panel.add_child(right_margin)
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right)

	var vehicle_heading := Label.new()
	vehicle_heading.text = "选择载具"
	vehicle_heading.add_theme_font_size_override("font_size", 19)
	vehicle_heading.add_theme_color_override("font_color", COLOR_TEXT)
	right.add_child(vehicle_heading)
	var vehicle_scroll := ScrollContainer.new()
	vehicle_scroll.name = "VehicleListScroll"
	vehicle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vehicle_scroll.custom_minimum_size.y = 205.0
	right.add_child(vehicle_scroll)
	_vehicle_list = VBoxContainer.new()
	_vehicle_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_list.add_theme_constant_override("separation", 6)
	vehicle_scroll.add_child(_vehicle_list)

	var selection_heading := Label.new()
	selection_heading.text = "外观"
	selection_heading.add_theme_font_size_override("font_size", 18)
	selection_heading.add_theme_color_override("font_color", COLOR_TEXT)
	right.add_child(selection_heading)
	var body_heading := Label.new()
	body_heading.text = "车身颜色"
	body_heading.add_theme_color_override("font_color", COLOR_MUTED)
	right.add_child(body_heading)
	_body_color_grid = GridContainer.new()
	_body_color_grid.columns = 3
	_body_color_grid.add_theme_constant_override("h_separation", 6)
	_body_color_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_body_color_grid)
	var wheel_heading := Label.new()
	wheel_heading.text = "轮毂颜色"
	wheel_heading.add_theme_color_override("font_color", COLOR_MUTED)
	right.add_child(wheel_heading)
	_wheel_color_grid = GridContainer.new()
	_wheel_color_grid.columns = 3
	_wheel_color_grid.add_theme_constant_override("h_separation", 6)
	_wheel_color_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_wheel_color_grid)

	_price_label = Label.new()
	_price_label.add_theme_font_size_override("font_size", 20)
	_price_label.add_theme_color_override("font_color", Color("e8b45a"))
	right.add_child(_price_label)
	_description_label = Label.new()
	_description_label.custom_minimum_size.y = 38.0
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.add_theme_color_override("font_color", COLOR_MUTED)
	right.add_child(_description_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 30.0
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	right.add_child(_status_label)
	_purchase_button = Button.new()
	_purchase_button.text = "购买载具"
	_purchase_button.custom_minimum_size.y = 48.0
	_purchase_button.add_theme_font_size_override("font_size", 20)
	_purchase_button.add_theme_stylebox_override("normal", _style_box(COLOR_ACCENT_DARK, 7))
	_purchase_button.add_theme_stylebox_override("hover", _style_box(Color("91403b"), 7))
	_purchase_button.pressed.connect(_on_purchase_pressed)
	right.add_child(_purchase_button)


func _create_preview_world() -> void:
	_preview_spin_root = Node3D.new()
	_preview_spin_root.name = "PreviewSpinRoot"
	_preview_viewport.add_child(_preview_spin_root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101317")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9aa7b2")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_preview_viewport.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.name = "PreviewKeyLight"
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	_preview_viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "PreviewFillLight"
	fill_light.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	fill_light.light_energy = 0.45
	_preview_viewport.add_child(fill_light)
	_preview_camera = Camera3D.new()
	_preview_camera.name = "PreviewCamera"
	_preview_camera.current = true
	_preview_camera.fov = 42.0
	_preview_camera.near = 0.05
	_preview_camera.far = 100.0
	_preview_viewport.add_child(_preview_camera)


func _build_vehicle_list() -> void:
	if not is_instance_valid(_vehicle_list):
		return
	for child in _vehicle_list.get_children():
		_vehicle_list.remove_child(child)
		child.queue_free()
	_vehicle_buttons.clear()
	for product_value: Variant in VehicleSalesCatalogScript.get_products():
		if not product_value is Dictionary:
			continue
		var product := product_value as Dictionary
		var vehicle_id := str(product.get("vehicle_id", ""))
		var button := Button.new()
		button.text = "%s    $%s" % [str(product.get("name", vehicle_id)), _format_money(int(product.get("price", 0)))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_vehicle_selected.bind(vehicle_id))
		_vehicle_list.add_child(button)
		_vehicle_buttons[vehicle_id] = button


func _build_color_grids() -> void:
	if not is_instance_valid(_body_color_grid) or not is_instance_valid(_wheel_color_grid):
		return
	for child in _body_color_grid.get_children():
		_body_color_grid.remove_child(child)
		child.queue_free()
	for child in _wheel_color_grid.get_children():
		_wheel_color_grid.remove_child(child)
		child.queue_free()
	_body_color_buttons.clear()
	_wheel_color_buttons.clear()
	for option_value: Variant in VehicleColorCatalogScript.get_options():
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var color_id := str(option.get("id", "black"))
		var color_value: Variant = option.get("color", Color.BLACK)
		var color := color_value as Color if color_value is Color else Color.BLACK
		var body_button := _make_color_button(option, color)
		body_button.pressed.connect(_on_body_color_selected.bind(color_id))
		_body_color_grid.add_child(body_button)
		_body_color_buttons[color_id] = body_button
		var wheel_button := _make_color_button(option, color)
		wheel_button.pressed.connect(_on_wheel_color_selected.bind(color_id))
		_wheel_color_grid.add_child(wheel_button)
		_wheel_color_buttons[color_id] = wheel_button
	_refresh_color_button_styles()


func _make_color_button(option: Dictionary, color: Color) -> Button:
	var button := Button.new()
	button.text = str(option.get("label", "颜色"))
	button.tooltip_text = str(option.get("label", "颜色"))
	button.custom_minimum_size = Vector2(91.0, 32.0)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", _contrast_text(color))
	return button


func _on_vehicle_selected(vehicle_id: String) -> void:
	if _purchase_input_locked() or VehicleSalesCatalogScript.get_product(vehicle_id).is_empty():
		return
	selected_vehicle_id = vehicle_id
	_refresh_selection()
	_load_preview()


func _on_body_color_selected(color_id: String) -> void:
	if _purchase_input_locked() or not VehicleColorCatalogScript.has_color(color_id):
		return
	selected_body_color_id = color_id
	_refresh_color_button_styles()
	_load_preview()


func _on_wheel_color_selected(color_id: String) -> void:
	if _purchase_input_locked() or not VehicleColorCatalogScript.has_color(color_id):
		return
	selected_wheel_color_id = color_id
	_refresh_color_button_styles()
	_load_preview()


func _refresh_selection() -> void:
	var product := VehicleSalesCatalogScript.get_product(selected_vehicle_id)
	if product.is_empty():
		return
	var locked := _purchase_input_locked()
	for vehicle_id_value: Variant in _vehicle_buttons.keys():
		var vehicle_id := str(vehicle_id_value)
		var button := _vehicle_buttons[vehicle_id] as Button
		if button != null:
			button.disabled = locked
			button.add_theme_stylebox_override(
				"normal",
				_style_box(COLOR_ACCENT_DARK if vehicle_id == selected_vehicle_id else COLOR_SURFACE_HIGHLIGHT, 6)
			)
	_price_label.text = "参考售价：$%s" % _format_money(int(product.get("price", 0)))
	_description_label.text = str(product.get("description", ""))
	_purchase_button.disabled = purchase_pending
	_purchase_button.text = "处理中…" if purchase_pending else "重试确认" if _purchase_timed_out else "购买载具"
	_refresh_color_button_styles()


func _refresh_color_button_styles() -> void:
	for color_id_value: Variant in _body_color_buttons.keys():
		var color_id := str(color_id_value)
		var button := _body_color_buttons[color_id] as Button
		if button != null:
			button.disabled = _purchase_input_locked()
			var color := VehicleColorCatalogScript.get_color(color_id)
			button.add_theme_stylebox_override(
				"normal",
				_style_box(color.lightened(0.14) if color_id == selected_body_color_id else color, 5)
			)
	for color_id_value: Variant in _wheel_color_buttons.keys():
		var color_id := str(color_id_value)
		var button := _wheel_color_buttons[color_id] as Button
		if button != null:
			button.disabled = _purchase_input_locked()
			var color := VehicleColorCatalogScript.get_color(color_id)
			button.add_theme_stylebox_override(
				"normal",
				_style_box(color.lightened(0.14) if color_id == selected_wheel_color_id else color, 5)
			)


func _purchase_input_locked() -> bool:
	return purchase_pending or _purchase_timed_out


func _load_preview() -> void:
	if not is_instance_valid(_preview_spin_root):
		return
	_clear_preview()
	var product := VehicleSalesCatalogScript.get_product(selected_vehicle_id)
	var scene_path := str(product.get("scene_path", ""))
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_update_status("载具展示模型暂时不可用。", COLOR_ERROR)
		return
	var source := packed.instantiate() as Node3D
	if source == null:
		return
	var body_color := VehicleColorCatalogScript.get_color(selected_body_color_id)
	var wheel_color := VehicleColorCatalogScript.get_color(selected_wheel_color_id)
	if source.has_method("set_body_color"):
		source.call("set_body_color", body_color)
	if source.has_method("set_wheel_color"):
		source.call("set_wheel_color", wheel_color)
	var source_visual := source.get_node_or_null("Mesh") as Node3D
	if source_visual == null:
		source_visual = source.get_node_or_null("BodyVisual") as Node3D
	if source_visual == null:
		var config_value: Variant = source.get("vehicle_config")
		if config_value is Resource:
			var visual_scene_value: Variant = (config_value as Resource).get("visual_scene")
			if visual_scene_value is PackedScene:
				source_visual = (visual_scene_value as PackedScene).instantiate() as Node3D
	if source_visual == null:
		source.free()
		return
	var visual_copy := source_visual.duplicate() as Node3D
	source.free()
	if visual_copy == null:
		return
	_preview_model = visual_copy
	_preview_spin_root.add_child(_preview_model)
	var bounds := _calculate_visual_bounds(_preview_model, Transform3D.IDENTITY)
	if bounds.size.length_squared() > 0.001:
		var center := bounds.position + bounds.size * 0.5
		_preview_model.position -= center
		var horizontal_size := maxf(bounds.size.x, bounds.size.z)
		var vehicle_height := maxf(bounds.size.y, 1.0)
		var camera_distance := maxf(6.5, horizontal_size * 1.9 + 2.0)
		_preview_camera.position = Vector3(horizontal_size * 0.55, vehicle_height * 0.58, camera_distance)
		_preview_camera.look_at(Vector3(0.0, vehicle_height * 0.18, 0.0), Vector3.UP)
	else:
		_preview_camera.position = Vector3(4.0, 2.5, 7.0)
		_preview_camera.look_at(Vector3.ZERO, Vector3.UP)
	_preview_spin_root.rotation.y = 0.0


func _clear_preview() -> void:
	if is_instance_valid(_preview_model):
		_preview_model.queue_free()
	_preview_model = null


func _calculate_visual_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	var node_transform := parent_transform * node.transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var local_bounds := mesh_node.get_aabb()
		for x: float in [local_bounds.position.x, local_bounds.end.x]:
			for y: float in [local_bounds.position.y, local_bounds.end.y]:
				for z: float in [local_bounds.position.z, local_bounds.end.z]:
					var point := node_transform * Vector3(x, y, z)
					if not found:
						result = AABB(point, Vector3.ZERO)
						found = true
					else:
						result = result.expand(point)
	for child_value: Variant in node.get_children():
		if not child_value is Node3D:
			continue
		var child_bounds := _calculate_visual_bounds(child_value as Node3D, node_transform)
		if child_bounds.size.length_squared() <= 0.0001:
			continue
		if not found:
			result = child_bounds
			found = true
		else:
			result = result.merge(child_bounds)
	return result


func _on_purchase_pressed() -> void:
	var retrying := _purchase_timed_out and not _active_purchase_request.is_empty()
	if purchase_pending or (not retrying and not is_instance_valid(current_shop)):
		return
	var request: Dictionary = {}
	if retrying:
		request = _active_purchase_request.duplicate(true)
	else:
		var product := VehicleSalesCatalogScript.get_product(selected_vehicle_id)
		if product.is_empty():
			return
		_purchase_request_counter += 1
		var peer_id := GameAuthority.get_local_interaction_peer_id() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_local_interaction_peer_id") \
			else GameAuthority.LOCAL_PLAYER_ID
		request = {
			"action": "vehicle_purchase",
			"shop_category": "vehicle_sales",
			"request_id": "autosales_%d_%d_%d" % [peer_id, Time.get_ticks_msec(), _purchase_request_counter],
			"vehicle_id": selected_vehicle_id,
			"body_color_id": selected_body_color_id,
			"wheel_color_id": selected_wheel_color_id,
			"shop_path": str(current_shop.get_path()),
			"shop_position": current_shop.get_interaction_position() \
				if current_shop.has_method("get_interaction_position") else current_shop.global_position,
		}
		_active_purchase_request = request.duplicate(true)
		_active_purchase_request_id = str(request.get("request_id", ""))
	purchase_pending = true
	_purchase_timed_out = false
	_purchase_wait_elapsed = 0.0
	set_process(true)
	_refresh_selection()
	_update_status("正在确认队伍金钱和交付位置……", COLOR_MUTED)
	if GameAuthority.should_send_network_requests():
		var sent := MultiplayerNetwork.submit_shop_transaction(request)
		if not sent:
			apply_transaction_result({
				"ok": false,
				"phase": "failed",
				"reason": "request_not_sent",
				"peer_id": GameAuthority.get_local_interaction_peer_id(),
				"shop_category": "vehicle_sales",
				"action": "vehicle_purchase",
				"request_id": _active_purchase_request_id,
				"charged": false,
				"refunded": false,
			})
		return
	if GameAuthority.is_local_interaction_authority():
		var peer_id := GameAuthority.LOCAL_PLAYER_ID
		if is_instance_valid(current_player):
			peer_id = int(current_player.get("authority_peer_id"))
		var result := GameAuthority.local_shop_transaction(peer_id, request)
		apply_transaction_result(result)
		return
	apply_transaction_result({
		"ok": false,
		"phase": "failed",
		"reason": "request_not_sent",
		"peer_id": GameAuthority.LOCAL_PLAYER_ID,
		"shop_category": "vehicle_sales",
		"action": "vehicle_purchase",
		"request_id": _active_purchase_request_id,
		"charged": false,
		"refunded": false,
	})


func apply_transaction_result(result: Dictionary) -> void:
	if str(result.get("shop_category", "")) != "vehicle_sales":
		return
	var result_request_id := str(result.get("request_id", ""))
	if _active_purchase_request_id.is_empty() or result_request_id != _active_purchase_request_id:
		return
	var phase := str(result.get("phase", ""))
	if phase == "pending":
		purchase_pending = true
		_purchase_timed_out = false
		_purchase_wait_elapsed = 0.0
		_update_status("购买已受理，载具正在空投；若生成失败服务器会自动退款。", COLOR_MUTED)
		_refresh_selection()
		return
	var succeeded := bool(result.get("ok", false)) and phase != "failed"
	purchase_pending = false
	_purchase_timed_out = false
	_purchase_wait_elapsed = 0.0
	_active_purchase_request.clear()
	_active_purchase_request_id = ""
	set_process(visible)
	if succeeded:
		var product := VehicleSalesCatalogScript.get_product(str(result.get("vehicle_id", selected_vehicle_id)))
		var vehicle_name := str(product.get("name", result.get("vehicle_id", selected_vehicle_id)))
		_update_status(
			"购买成功：%s 已送到你所属队伍的出生点附近。" % vehicle_name,
			COLOR_SUCCESS
		)
		_refresh_money()
		_refresh_selection()
		if not visible:
			_show_last_status_on_open = true
		return
	_update_status(
		"购买失败：%s" % _failure_message(
			str(result.get("reason", "")), bool(result.get("refunded", false))
		),
		COLOR_ERROR
	)
	_refresh_money()
	_refresh_selection()
	if not visible:
		_show_last_status_on_open = true


func _failure_message(reason: String, refunded := false) -> String:
	match reason:
		"vehicle_shop_out_of_range": return "距离载具商店过远"
		"vehicle_shop_not_found": return "载具商店不可用"
		"vehicle_not_available": return "该载具不在销售目录中"
		"invalid_vehicle_color": return "颜色选项无效"
		"insufficient_money": return "队伍金钱不足"
		"no_team_spawn_point": return "当前队伍没有可用出生点"
		"no_vehicle_spawn_point": return "队伍出生点附近没有合法落点"
		"missing_request_id": return "购买请求缺少唯一标识，请重试"
		"missing_vehicle_scene": return "载具场景不可用"
		"vehicle_spawn_failed", "vehicle_spawn_drop_failed":
			return "载具生成失败，已退款" if refunded else "载具生成失败，未扣款"
		"request_not_sent": return "当前网络未连接，购买请求未发出"
		_: return "请求未通过权威端检查"


func _refresh_money() -> void:
	if is_instance_valid(_money_label) and not current_team.is_empty():
		_money_label.text = "队伍金钱  $%s" % _format_money(roundi(GlobalVar.check_team_item_amount(current_team, "money")))


func _on_storage_changed(team: String, _item_name: String, _new_amount: float) -> void:
	if visible and team == current_team:
		_refresh_money()


func _update_status(message: String, color: Color) -> void:
	_last_status_message = message
	_last_status_color = color
	if not is_instance_valid(_status_label):
		return
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", color)


func _format_money(value: int) -> String:
	return _format_grouped_integer(value)


func _format_grouped_integer(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(abs(value))
	var groups: Array[String] = []
	while not digits.is_empty():
		var start := maxi(0, digits.length() - 3)
		groups.push_front(digits.substr(start))
		digits = digits.substr(0, start)
	return sign + ",".join(groups)


func _contrast_text(color: Color) -> Color:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return Color("111111") if luminance > 0.58 else COLOR_TEXT


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _on_viewport_size_changed() -> void:
	if visible:
		_layout_panel()


func _layout_panel() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	var panel_width := clampf(viewport_size.x * 0.86, 760.0, 1320.0)
	var panel_height := clampf(viewport_size.y * 0.84, 500.0, 820.0)
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -panel_width * 0.5
	offset_top = -panel_height * 0.5
	offset_right = panel_width * 0.5
	offset_bottom = panel_height * 0.5


func _update_preview_viewport_size() -> void:
	if not is_instance_valid(_preview_viewport) or not is_instance_valid(_preview_container):
		return
	var size := _preview_container.size
	if size.x > 1.0 and size.y > 1.0:
		var desired := Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
		if _preview_viewport.size != desired:
			_preview_viewport.size = desired
