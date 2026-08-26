extends ChocolateOSAppBase
class_name ChocolateOSWeatherApp

const REFRESH_INTERVAL_SECONDS := 0.5
const BASE_TEMPERATURE_C := 18.0
const DAILY_TEMPERATURE_VARIATION_MIN_C := -5
const DAILY_TEMPERATURE_VARIATION_MAX_C := 5
const DAILY_HIGH_MIN_DELTA_C := 3
const DAILY_HIGH_MAX_DELTA_C := 9

var refresh_elapsed := 0.0
var current_label: Label
var time_label: Label
var status_label: Label
var forecast_row: HBoxContainer
var local_temperature_revision := -1
var local_temperatures: Dictionary = {}
var temperature_rng := RandomNumberGenerator.new()


func _ready() -> void:
	temperature_rng.randomize()
	_build_ui()


func on_launch(context: ChocolateOSAppContext) -> void:
	super.on_launch(context)
	_refresh_state()


func on_resume() -> void:
	_refresh_state()


func _process(delta: float) -> void:
	if app_context == null:
		return
	refresh_elapsed += delta
	if refresh_elapsed < REFRESH_INTERVAL_SECONDS:
		return
	refresh_elapsed = 0.0
	_refresh_state()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color("#d7d7d7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Weather is intentionally a single-page app.  Keep its complete page
	# centered so the seven-day forecast remains the visual focus at any window
	# size, without introducing page navigation.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 18.0
	center.offset_top = 10.0
	center.offset_right = -18.0
	center.offset_bottom = -10.0
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(700.0, 0.0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var heading := Label.new()
	heading.text = "天气预报"
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", Color("#262626"))
	root.add_child(heading)

	var current_panel := PanelContainer.new()
	current_panel.custom_minimum_size.y = 72.0
	current_panel.add_theme_stylebox_override(
		"panel", _stylebox(Color("#efefef"), Color("#8a8a8a"), 1, 3)
	)
	root.add_child(current_panel)
	var current_box := VBoxContainer.new()
	current_box.add_theme_constant_override("separation", 2)
	current_panel.add_child(current_box)
	current_label = Label.new()
	current_label.text = "当前天气：天气数据同步中…"
	current_label.add_theme_font_size_override("font_size", 20)
	current_label.add_theme_color_override("font_color", Color("#1f1f1f"))
	current_box.add_child(current_label)
	time_label = Label.new()
	time_label.text = "游戏时间 --:--"
	time_label.add_theme_color_override("font_color", Color("#4b4b4b"))
	current_box.add_child(time_label)

	var week_heading := Label.new()
	week_heading.text = "未来七天"
	week_heading.add_theme_font_size_override("font_size", 18)
	week_heading.add_theme_color_override("font_color", Color("#303030"))
	root.add_child(week_heading)

	var forecast_panel := PanelContainer.new()
	forecast_panel.custom_minimum_size.y = 226.0
	forecast_panel.add_theme_stylebox_override(
		"panel", _stylebox(Color("#e9e9e9"), Color("#969696"), 1, 3)
	)
	root.add_child(forecast_panel)
	var forecast_center := CenterContainer.new()
	forecast_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	forecast_panel.add_child(forecast_center)
	forecast_row = HBoxContainer.new()
	forecast_row.alignment = BoxContainer.ALIGNMENT_CENTER
	forecast_row.add_theme_constant_override("separation", 5)
	forecast_center.add_child(forecast_row)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("#555555"))
	root.add_child(status_label)


func _refresh_state() -> void:
	if app_context == null:
		return
	var result := app_context.query("weather.read")
	if not bool(result.get("ok", false)):
		status_label.text = "无法读取天气系统"
		return
	var state_value: Variant = result.get("state", {})
	if not state_value is Dictionary:
		status_label.text = "天气预报数据无效"
		return
	_render_state(state_value as Dictionary)


func _render_state(state: Dictionary) -> void:
	var current_type := str(state.get("current_weather_type", "clear"))
	var current_name := _weather_name(current_type)
	if bool(state.get("current_eclipse_active", false)):
		current_name = "日食进行中"
	var current_day := int(state.get("world_day", 0))
	var forecast_revision := int(state.get("forecast_revision", -1))
	if forecast_revision != local_temperature_revision:
		local_temperature_revision = forecast_revision
		local_temperatures.clear()
	var current_temperature := _temperature_for_day(current_day)
	current_label.text = "当前天气：%s · %d°C" % [
		current_name, int(current_temperature.get("current", BASE_TEMPERATURE_C))
	]
	var current_hour := float(state.get("current_hour", 0.0))
	var minutes := posmod(roundi(current_hour * 60.0), 24 * 60)
	time_label.text = "游戏时间 %02d:%02d · 世界第 %d 天" % [
		int(minutes / 60), minutes % 60, current_day + 1
	]

	for child: Node in forecast_row.get_children():
		child.queue_free()
	var forecast_value: Variant = state.get("forecast_days", [])
	if not forecast_value is Array or (forecast_value as Array).is_empty():
		status_label.text = "天气预报同步中…"
		return
	var forecast := forecast_value as Array
	for entry_value: Variant in forecast:
		if entry_value is Dictionary:
			forecast_row.add_child(_create_day_card(entry_value as Dictionary, current_day))
	status_label.text = "预报版本 %d · 每天更新一次" % int(state.get("forecast_revision", 0))


func _create_day_card(entry: Dictionary, current_day: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(90.0, 214.0)
	var day_index := int(entry.get("day_index", current_day))
	var is_today := bool(entry.get("is_today", day_index == current_day))
	var card_color := Color("#f5f5f5") if is_today else Color("#dedede")
	var border_color := Color("#b23a3a") if is_today else Color("#a0a0a0")
	card.add_theme_stylebox_override("panel", _stylebox(card_color, border_color, 2 if is_today else 1, 3))

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)
	var day_label := Label.new()
	day_label.text = _day_name(day_index, current_day)
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.add_theme_font_size_override("font_size", 16)
	day_label.add_theme_color_override("font_color", Color("#242424"))
	box.add_child(day_label)
	var symbol := Label.new()
	symbol.text = _weather_symbol(str(entry.get("weather_type", "clear")))
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.add_theme_font_size_override("font_size", 34)
	box.add_child(symbol)
	var type_label := Label.new()
	type_label.text = _weather_name(str(entry.get("weather_type", "clear")))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	type_label.add_theme_font_size_override("font_size", 16)
	type_label.add_theme_color_override("font_color", Color("#222222"))
	box.add_child(type_label)
	var temperature := _temperature_for_day(day_index)
	var temperature_label := Label.new()
	temperature_label.text = "气温 %d°C\n最高 %d°C" % [
		int(temperature.get("current", BASE_TEMPERATURE_C)),
		int(temperature.get("high", BASE_TEMPERATURE_C)),
	]
	temperature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	temperature_label.add_theme_font_size_override("font_size", 13)
	temperature_label.add_theme_color_override("font_color", Color("#333333"))
	box.add_child(temperature_label)
	var detail := Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color("#4b4b4b"))
	var eclipse_value: Variant = entry.get("eclipse", {})
	var eclipse := eclipse_value as Dictionary if eclipse_value is Dictionary else {}
	if bool(eclipse.get("enabled", false)):
		detail.text = "日食\n%s–%s" % [
			_format_hour(float(eclipse.get("start_hour", 0.0))),
			_format_hour(float(eclipse.get("end_hour", 0.0))),
		]
	else:
		detail.text = "全天%s" % ("有降雨" if str(entry.get("weather_type", "")) == "rain" else "晴朗")
	box.add_child(detail)
	return card


func _temperature_for_day(day_index: int) -> Dictionary:
	if local_temperatures.has(day_index):
		return local_temperatures[day_index] as Dictionary
	var current_temperature := int(round(BASE_TEMPERATURE_C)) + temperature_rng.randi_range(
		DAILY_TEMPERATURE_VARIATION_MIN_C, DAILY_TEMPERATURE_VARIATION_MAX_C
	)
	var high_temperature := current_temperature + temperature_rng.randi_range(
		DAILY_HIGH_MIN_DELTA_C, DAILY_HIGH_MAX_DELTA_C
	)
	var value := {
		"current": current_temperature,
		"high": high_temperature,
	}
	local_temperatures[day_index] = value
	return value


func _day_name(day_index: int, current_day: int) -> String:
	var offset := day_index - current_day
	match offset:
		0: return "今天"
		1: return "明天"
		2: return "后天"
		_: return "第 %d 天" % (day_index + 1)


func _weather_name(weather_type: String) -> String:
	match weather_type:
		"rain": return "雨天"
		"eclipse": return "日食"
		_: return "晴天"


func _weather_symbol(weather_type: String) -> String:
	match weather_type:
		"rain": return "雨"
		"eclipse": return "食"
		_: return "晴"


func _format_hour(hour: float) -> String:
	var minutes := posmod(roundi(hour * 60.0), 24 * 60)
	return "%02d:%02d" % [int(minutes / 60), minutes % 60]


func _stylebox(color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8.0
	box.content_margin_top = 8.0
	box.content_margin_right = 8.0
	box.content_margin_bottom = 8.0
	return box
