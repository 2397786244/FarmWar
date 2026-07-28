extends Control
class_name EventTaskHud

const MAX_VISIBLE_GLOBAL_EVENTS := 2
const MAX_VISIBLE_TEAM_TASKS := 2

@onready var global_event_list: RichTextLabel = $GlobalEvents/Margin/VBox/EventList
@onready var team_task_list: RichTextLabel = $TeamTasks/Margin/VBox/TaskList

var player: GamePlayer
var _countdown_accumulator := 0.0


func _ready() -> void:
	_set_mouse_passthrough(self)
	if not EventBoard.global_events_changed.is_connected(_on_global_events_changed):
		EventBoard.global_events_changed.connect(_on_global_events_changed)
	if not EventBoard.team_tasks_changed.is_connected(_on_team_tasks_changed):
		EventBoard.team_tasks_changed.connect(_on_team_tasks_changed)
	_refresh()


func _process(delta: float) -> void:
	_countdown_accumulator += delta
	if _countdown_accumulator < 0.25:
		return
	_countdown_accumulator = 0.0
	_refresh()


func _set_mouse_passthrough(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_passthrough(child)


func bind_player(next_player: GamePlayer) -> void:
	player = next_player
	_refresh()


func _on_global_events_changed(_events: Array[Dictionary]) -> void:
	_refresh()


func _on_team_tasks_changed(_team: String, _tasks: Array[Dictionary]) -> void:
	_refresh()


func _refresh() -> void:
	var global_lines: Array[String] = []
	var global_events := EventBoard.get_global_events()
	for index in range(mini(MAX_VISIBLE_GLOBAL_EVENTS, global_events.size())):
		var event: Dictionary = global_events[index]
		global_lines.append("%s\n%s" % [
			_escape(str(event.get("title", ""))),
			_escape(str(event.get("description", ""))),
		])
	global_event_list.text = "\n\n".join(global_lines) if not global_lines.is_empty() else "暂无公共事件"
	var team := player.team if is_instance_valid(player) else ""
	var task_lines: Array[String] = []
	if team in EventBoard.VALID_TEAMS:
		var team_tasks := EventBoard.get_team_tasks(team).filter(func(task: Dictionary) -> bool:
			return bool(task.get("active", true)) or bool(task.get("summary_visible", false))
		)
		for index in range(mini(MAX_VISIBLE_TEAM_TASKS, team_tasks.size())):
			var task: Dictionary = team_tasks[index]
			task_lines.append(_format_task(task))
	team_task_list.text = "\n\n".join(task_lines) if not task_lines.is_empty() else "暂无队伍任务"


func _format_task(task: Dictionary) -> String:
	if bool(task.get("summary_visible", false)):
		return "%s\n%s" % [
			_escape("任务总结：" + str(task.get("title", "队伍任务"))),
			_escape(str(task.get("result_summary", "任务已经结束。"))),
		]
	var lines: Array[String] = [_escape(str(task.get("title", "")))]
	if bool(task.get("is_timed", false)):
		var remaining := maxf(0.0, (
			float(task.get("deadline_unix_msec", 0)) \
			- Time.get_unix_time_from_system() * 1000.0
		) / 1000.0)
		lines.append("剩余时间：%02d:%02d" % [floori(remaining / 60.0), floori(remaining) % 60])
	var description := str(task.get("description", ""))
	if not description.is_empty():
		lines.append(_escape(description))
	var ingredients_value: Variant = task.get("required_ingredients", [])
	if ingredients_value is Array:
		var ingredient_lines: Array[String] = []
		for entry_value: Variant in ingredients_value:
			if entry_value is Dictionary:
				var entry := entry_value as Dictionary
				var display_name := str(entry.get("display_name", entry.get("ingredient_id", "")))
				if bool(entry.get("requires_chopping", false)):
					display_name = "切碎的" + display_name
				ingredient_lines.append("%s %.2fkg" % [
					_escape(display_name),
					float(entry.get("weight_kg", 0.0)),
				])
		if not ingredient_lines.is_empty():
			lines.append("原料：" + "、".join(ingredient_lines))
	var delivery_value: Variant = task.get("delivery_items", [])
	if delivery_value is Array:
		var delivery_lines: Array[String] = []
		var progress: Dictionary = task.get("delivery_progress", {}) as Dictionary \
			if task.get("delivery_progress", {}) is Dictionary else {}
		for value: Variant in delivery_value:
			if not value is Dictionary:
				continue
			var item := value as Dictionary
			var item_id := str(item.get("dish_id", item.get("ingredient_id", item.get("material_id", ""))))
			var name := _escape(str(item.get("display_name", item_id)))
			var current := float(progress.get(item_id, 0.0))
			if item.has("dish_id"):
				delivery_lines.append("%s %d/%d份" % [name, roundi(current), int(item.get("quantity", 0))])
			elif item.has("ingredient_id"):
				delivery_lines.append("%s %.2f/%.2fkg" % [name, current, float(item.get("weight_kg", 0.0))])
			else:
				delivery_lines.append("%s %d/%d个" % [name, roundi(current), int(item.get("quantity", 0))])
		if not delivery_lines.is_empty():
			lines.append("需求：" + "、".join(delivery_lines))
	var destination := str(task.get("delivery_location_name", ""))
	if not destination.is_empty():
		lines.append("交付：" + _escape(destination))
	var reward := int((task.get("rewards", {}) as Dictionary).get("money", 0))
	if reward > 0:
		lines.append("奖励：%d 队伍金钱，同时增加同额队伍得分" % reward)
	if bool(task.get("all_team_task", false)):
		var winner := str(task.get("race_winner_team", ""))
		lines.append("竞赛奖励：率先完成额外 +20%" if winner.is_empty() else "率先完成：%s队" % ("红" if winner == "red" else "蓝"))
	return "\n".join(lines)


func _escape(value: String) -> String:
	return value.replace("[", "\\[").replace("]", "\\]")
