extends Camera3D
## 导播观察相机。支持第三人称跟随选中的 NPC（电竞导播风格），
## 鼠标右键环绕旋转，滚轮调距离，数字键1-6快捷切换，0=自由模式。
## 自由模式下回退到 WASD 自由移动（同 test_observer_camera）。

# --- 自由模式参数 ---
const FREE_MOVE_SPEED := 40.0
const FREE_FAST_SPEED := 90.0
const LOOK_SENSITIVITY := 0.0025

# --- 跟随模式参数 ---
const FOLLOW_SPEED := 6.0
const DEFAULT_ORBIT_DISTANCE := 7.0
const MIN_ORBIT_DISTANCE := 3.0
const MAX_ORBIT_DISTANCE := 15.0
const ORBIT_HEIGHT := 3.5
const TARGET_HEIGHT_OFFSET := 1.6  # 看向胸部高度
const SMOOTH_ROTATE_SPEED := 8.0

# --- UI 配色 ---
const COLOR_BLUE := Color(0.23, 0.51, 0.96, 1)
const COLOR_RED := Color(0.94, 0.27, 0.27, 1)
const COLOR_PANEL_BG := Color(0.08, 0.09, 0.12, 0.82)
const COLOR_PANEL_BORDER := Color(0.25, 0.27, 0.33, 0.9)
const COLOR_TEXT := Color(0.92, 0.93, 0.96, 1)
const COLOR_TEXT_DIM := Color(0.62, 0.64, 0.70, 1)
const COLOR_HP_BG := Color(0.15, 0.16, 0.20, 0.9)
const COLOR_HP_FULL := Color(0.30, 0.85, 0.39, 1)
const COLOR_HP_LOW := Color(0.94, 0.35, 0.27, 1)
const COLOR_SELECTED := Color(1.0, 0.84, 0.0, 1)

# --- 中文映射 ---
const PROFESSION_CN := {
	"farmer": "农夫", "cook": "厨师", "guard": "守卫", "mage": "法师",
	"engineer": "工程师", "apothecary": "药剂师", "assistant": "助手",
	"trickster": "诡术师", "prospector": "探矿者", "rider": "骑手",
}
const ENEMY_TYPE_CN := {
	"bandit": "盗匪", "bruiser_rider": "重装骑兵", "future_warrior": "未来战士",
}
const STATE_CN := {
	0: "思考", 1: "前往播种", 2: "播种中", 3: "前往收获", 4: "收获中",
	5: "前往攻击", 6: "攻击中", 7: "前往放置", 8: "放置中", 9: "吸能中",
	10: "射击玩家", 11: "施法中", 12: "支援队友", 13: "眩晕中", 14: "巡逻中",
	15: "侦查进攻", 16: "防御农田",
}
const DECISION_CN := {
	0: "收获", 1: "放盾", 2: "放炮塔", 3: "放防空", 4: "播种",
	5: "破坏农田", 6: "射击玩家", 7: "雷击", 8: "支援", 9: "侦查",
	10: "巡逻", 11: "防御农田",
}

# --- 状态 ---
var targets: Array = []  # Array[AIPlayerv2]
var current_index: int = -1  # -1 = 自由模式
var orbit_yaw: float = 0.0
var orbit_pitch: float = -0.35
var orbit_distance: float = DEFAULT_ORBIT_DISTANCE
var is_looking: bool = false

# 自由模式相机欧拉角
var free_yaw: float = 0.0
var free_pitch: float = -0.6

# UI 引用
var ui_layer: CanvasLayer
var button_container: HBoxContainer
var info_label: RichTextLabel
var hint_label: Label
var target_buttons: Array = []  # Array[Button]

# 平滑过渡
var is_transitioning: bool = false
var transition_from_pos: Vector3
var transition_from_look: Vector3
var transition_time: float = 0.0
const TRANSITION_DURATION := 0.6


func _ready() -> void:
	current = true
	rotation = Vector3(free_pitch, free_yaw, 0.0)
	# 延迟收集目标，确保所有 AI 已 _ready
	call_deferred("_collect_targets")
	call_deferred("_build_ui")


func _process(delta: float) -> void:
	if is_transitioning:
		_update_transition(delta)
	elif current_index >= 0 and current_index < targets.size():
		_follow_target(delta)
	else:
		_handle_free_movement(delta)
	_update_ui()


# ===========================================================================
# 目标收集
# ===========================================================================

func _collect_targets() -> void:
	targets.clear()
	var nodes := get_tree().get_nodes_in_group("ai_players")
	# 按 team 排序：blue 在前，red 在后；同队按 profession 排序
	nodes.sort_custom(_sort_targets)
	for n in nodes:
		if n is CharacterBody3D and is_instance_valid(n):
			targets.append(n)
	# 重建按钮（如果 UI 已创建）
	if button_container != null:
		_rebuild_buttons()


func _sort_targets(a, b) -> bool:
	var ta: String = a.team_id if "team_id" in a else ""
	var tb: String = b.team_id if "team_id" in b else ""
	if ta != tb:
		return ta < tb
	var pa: String = a.profession if "profession" in a else ""
	var pb: String = b.profession if "profession" in b else ""
	return pa < pb


# ===========================================================================
# 自由模式（WASD 移动）
# ===========================================================================

func _handle_free_movement(delta: float) -> void:
	var speed := FREE_FAST_SPEED if Input.is_key_pressed(KEY_SHIFT) else FREE_MOVE_SPEED
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir += -global_transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir += -global_transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		input_dir += Vector3.DOWN
	if Input.is_key_pressed(KEY_E):
		input_dir += Vector3.UP
	if input_dir.length_squared() > 0.001:
		global_position += input_dir.normalized() * speed * delta


# ===========================================================================
# 第三人称跟随
# ===========================================================================

func _follow_target(delta: float) -> void:
	var target := targets[current_index] as CharacterBody3D
	if target == null or not is_instance_valid(target):
		switch_to_free()
		return

	var target_pos := target.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	# 环绕偏移
	var h_dist := cos(orbit_pitch) * orbit_distance
	var v_dist := sin(-orbit_pitch) * orbit_distance
	var offset := Vector3(
		sin(orbit_yaw) * h_dist,
		v_dist + ORBIT_HEIGHT,
		cos(orbit_yaw) * h_dist
	)
	var desired_pos := target_pos + offset
	var lerp_weight := 1.0 - exp(-FOLLOW_SPEED * delta)
	global_position = global_position.lerp(desired_pos, lerp_weight)
	look_at(target_pos, Vector3.UP)


# ===========================================================================
# 平滑过渡（切换目标时）
# ===========================================================================

func _start_transition(target_pos: Vector3, look_pos: Vector3) -> void:
	is_transitioning = true
	transition_from_pos = global_position
	transition_from_look = _get_current_look_target()
	transition_time = 0.0
	# 存储目标位置到元数据
	set_meta("trans_target_pos", target_pos)
	set_meta("trans_look_pos", look_pos)


func _update_transition(delta: float) -> void:
	transition_time += delta
	var t := clampf(transition_time / TRANSITION_DURATION, 0.0, 1.0)
	# ease out cubic
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var target_pos := get_meta("trans_target_pos") as Vector3
	var look_pos := get_meta("trans_look_pos") as Vector3
	global_position = transition_from_pos.lerp(target_pos, eased)
	var current_look := transition_from_look.lerp(look_pos, eased)
	look_at(current_look, Vector3.UP)
	if t >= 1.0:
		is_transitioning = false


func _get_current_look_target() -> Vector3:
	if current_index >= 0 and current_index < targets.size():
		var t := targets[current_index] as CharacterBody3D
		if t != null and is_instance_valid(t):
			return t.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	return global_position - global_transform.basis.z * 10.0


# ===========================================================================
# 切换目标
# ===========================================================================

func switch_to_target(index: int) -> void:
	if index < 0 or index >= targets.size():
		return
	var target := targets[index] as CharacterBody3D
	if target == null or not is_instance_valid(target):
		return
	# 计算过渡后的相机位置
	var target_pos := target.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	var h_dist := cos(orbit_pitch) * orbit_distance
	var v_dist := sin(-orbit_pitch) * orbit_distance
	var offset := Vector3(
		sin(orbit_yaw) * h_dist,
		v_dist + ORBIT_HEIGHT,
		cos(orbit_yaw) * h_dist
	)
	var desired_pos := target_pos + offset
	current_index = index
	_start_transition(desired_pos, target_pos)
	_update_button_styles()


func switch_to_free() -> void:
	current_index = -1
	# 自由模式不需要过渡，直接保持当前位置
	free_yaw = rotation.y
	free_pitch = rotation.x
	_update_button_styles()


# ===========================================================================
# UI 构建（纯代码）
# ===========================================================================

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	# --- 顶部按钮栏 ---
	var top_anchor := Control.new()
	top_anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(top_anchor)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_left", 8)
	top_margin.add_theme_constant_override("margin_right", 8)
	top_anchor.add_child(top_margin)

	var center_box := CenterContainer.new()
	top_margin.add_child(center_box)

	button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 6)
	center_box.add_child(button_container)

	_rebuild_buttons()

	# --- 左下信息面板 ---
	var bottom_left := Control.new()
	bottom_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(bottom_left)

	var bl_margin := MarginContainer.new()
	bl_margin.add_theme_constant_override("margin_bottom", 12)
	bl_margin.add_theme_constant_override("margin_left", 12)
	bottom_left.add_child(bl_margin)

	var info_panel := PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(300, 0)
	_apply_panel_style(info_panel)
	bl_margin.add_child(info_panel)

	info_label = RichTextLabel.new()
	info_label.fit_content = true
	info_label.bbcode_enabled = true
	info_label.add_theme_font_size_override("normal_font_size", 14)
	info_label.add_theme_constant_override("line_separation", 2)
	info_panel.add_child(info_label)

	# --- 底部提示 ---
	var hint_anchor := Control.new()
	hint_anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(hint_anchor)

	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_bottom", 10)
	hint_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_anchor.add_child(hint_margin)

	var hint_center := CenterContainer.new()
	hint_margin.add_child(hint_center)

	hint_label = Label.new()
	hint_label.text = "数字键 1-6 切换 NPC  |  0 = 自由模式  |  鼠标右键拖拽旋转  |  滚轮调距离  |  WASD 自由移动"
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	hint_center.add_child(hint_label)


func _rebuild_buttons() -> void:
	# 清除旧按钮
	for child in button_container.get_children():
		child.queue_free()
	target_buttons.clear()

	# NPC 按钮
	for i in range(targets.size()):
		var ai := targets[i] as CharacterBody3D
		if ai == null:
			continue
		var btn := Button.new()
		var team: String = ai.team_id if "team_id" in ai else "?"
		var display_name := _get_display_name(ai)
		var team_short: String = "蓝" if team == "blue" else ("敌" if team == "enemy" else "红")
		btn.text = "%d %s%s" % [i + 1, team_short, display_name]
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(120, 36)
		btn.pressed.connect(_on_button_pressed.bind(i))
		_apply_button_style(btn, team)
		button_container.add_child(btn)
		target_buttons.append(btn)

	# 分隔
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	button_container.add_child(sep)

	# 自由模式按钮
	var free_btn := Button.new()
	free_btn.text = "0 自由模式"
	free_btn.add_theme_font_size_override("font_size", 13)
	free_btn.custom_minimum_size = Vector2(100, 36)
	free_btn.pressed.connect(switch_to_free)
	_apply_button_style(free_btn, "free")
	button_container.add_child(free_btn)
	target_buttons.append(free_btn)  # 最后一个是自由模式按钮

	_update_button_styles()


func _apply_button_style(btn: Button, team: String) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	if team == "blue":
		style.bg_color = Color(0.10, 0.18, 0.35, 0.85)
		style.border_color = COLOR_BLUE
	elif team == "red":
		style.bg_color = Color(0.35, 0.12, 0.12, 0.85)
		style.border_color = COLOR_RED
	elif team == "enemy":
		style.bg_color = Color(0.30, 0.15, 0.05, 0.85)
		style.border_color = Color(0.85, 0.45, 0.10, 1)
	else:
		style.bg_color = Color(0.15, 0.15, 0.18, 0.85)
		style.border_color = COLOR_PANEL_BORDER
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = hover_style.bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = pressed_style.bg_color.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed_style)


func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.bg_color = COLOR_PANEL_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_PANEL_BORDER
	panel.add_theme_stylebox_override("panel", style)


func _update_button_styles() -> void:
	for i in range(target_buttons.size() - 1):  # 最后一个是自由模式按钮
		var btn := target_buttons[i] as Button
		if btn == null:
			continue
		if i == current_index:
			btn.add_theme_color_override("font_color", COLOR_SELECTED)
			btn.add_theme_color_override("font_hover_color", COLOR_SELECTED)
			btn.add_theme_color_override("font_pressed_color", COLOR_SELECTED)
		else:
			btn.add_theme_color_override("font_color", COLOR_TEXT)
			btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
			btn.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	# 自由模式按钮
	var free_btn := target_buttons[-1] as Button
	if free_btn != null:
		if current_index == -1:
			free_btn.add_theme_color_override("font_color", COLOR_SELECTED)
			free_btn.add_theme_color_override("font_hover_color", COLOR_SELECTED)
		else:
			free_btn.add_theme_color_override("font_color", COLOR_TEXT)
			free_btn.add_theme_color_override("font_hover_color", COLOR_TEXT)


func _on_button_pressed(index: int) -> void:
	switch_to_target(index)


## 获取 AI 的显示名称（职业中文名或敌人类型中文名）
func _get_display_name(ai: CharacterBody3D) -> String:
	if "enemy_type" in ai:
		return ENEMY_TYPE_CN.get(ai.enemy_type, ai.enemy_type)
	return PROFESSION_CN.get(ai.profession, ai.profession)


# ===========================================================================
# UI 更新（每帧）
# ===========================================================================

func _update_ui() -> void:
	if info_label == null:
		return
	if current_index >= 0 and current_index < targets.size():
		var ai := targets[current_index] as CharacterBody3D
		if ai == null or not is_instance_valid(ai):
			info_label.text = "[color=gray]目标已失效[/color]"
			return
		var display_name := _get_display_name(ai)
		var team_cn: String
		var team_color: String
		var team: String = ai.team_id if "team_id" in ai else "?"
		match team:
			"blue":
				team_cn = "蓝队"
				team_color = "#3B82F6"
			"red":
				team_cn = "红队"
				team_color = "#EF4444"
			"enemy":
				team_cn = "进攻方"
				team_color = "#F59E0B"
			_:
				team_cn = team
				team_color = "#CCCCCC"

		var diff_cn: String = "简单" if ai.difficulty == 0 else "困难"
		var state_val: int = ai.state if "state" in ai else 0
		var state_cn: String = STATE_CN.get(state_val, "未知(%d)" % state_val)
		var hp_val: float = ai.hp if "hp" in ai else 0.0
		var max_hp_val: float = ai.max_hp if "max_hp" in ai else 200.0
		var is_dead_val: bool = ai.is_dead if "is_dead" in ai else false
		var pos := ai.global_position
		var vel := ai.velocity if "velocity" in ai else Vector3.ZERO
		var hp_pct := 0.0
		if max_hp_val > 0:
			hp_pct = hp_val / max_hp_val * 100.0
		var hp_color := COLOR_HP_FULL if hp_pct > 30 else COLOR_HP_LOW
		var status_str := "存活"
		if is_dead_val:
			var respawn_t: float = ai.respawn_timer if "respawn_timer" in ai else 0.0
			status_str = "[color=red]已阵亡(%.1fs后复活)[/color]" % respawn_t
		elif "under_attack_timer" in ai and ai.under_attack_timer > 0:
			status_str = "[color=orange]受击中[/color]"
		elif "stun_remaining" in ai and ai.stun_remaining > 0:
			status_str = "[color=purple]眩晕中[/color]"
		elif "burn_remaining" in ai and ai.burn_remaining > 0:
			status_str = "[color=red]燃烧中[/color]"
		elif "slow_remaining" in ai and ai.slow_remaining > 0:
			status_str = "[color=cyan]减速中[/color]"

		# 状态效果详情
		var effects_str := ""
		if "stun_remaining" in ai and ai.stun_remaining > 0:
			effects_str += "[color=purple]眩晕%.1fs[/color] " % float(ai.stun_remaining)
		if "burn_remaining" in ai and ai.burn_remaining > 0:
			var burn_dps_val: float = float(ai.burn_dps) if "burn_dps" in ai else 0.0
			effects_str += "[color=red]燃烧%.1fs(%.0fDPS)[/color] " % [
				float(ai.burn_remaining), burn_dps_val]
		if "slow_remaining" in ai and ai.slow_remaining > 0:
			effects_str += "[color=cyan]冰冻%.1fs[/color] " % float(ai.slow_remaining)
		if "under_attack_timer" in ai and ai.under_attack_timer > 0:
			effects_str += "[color=orange]受击%.1fs[/color] " % float(ai.under_attack_timer)
		if effects_str.is_empty():
			effects_str = "[color=green]正常[/color]"

		# HP 血条（文本形式）
		var hp_bar_len := 20
		var hp_filled := int(round(hp_pct / 100.0 * hp_bar_len))
		var hp_bar := ""
		for j in range(hp_filled):
			hp_bar += "█"
		for j in range(hp_bar_len - hp_filled):
			hp_bar += "░"

		# 当前装备工具
		var tool_str := "无"
		if "profession_tool_ids" in ai and "current_tool_index" in ai:
			var tool_ids: Array = ai.profession_tool_ids
			var tool_idx: int = ai.current_tool_index
			if tool_idx >= 0 and tool_idx < tool_ids.size():
				tool_str = str(tool_ids[tool_idx])

		# 冷却状态
		var cooldown_str := ""
		if "cooldowns" in ai and "profession_tool_ids" in ai:
			var cds: Array = ai.cooldowns
			var tids: Array = ai.profession_tool_ids
			for j in range(mini(cds.size(), tids.size())):
				var cd: float = float(cds[j])
				if cd > 0.0:
					cooldown_str += "%s(%.1fs) " % [tids[j], cd]
			if cooldown_str.is_empty():
				cooldown_str = "全部就绪"

		# 最近决策
		var decision_str := "无"
		if "last_decision" in ai:
			decision_str = DECISION_CN.get(ai.last_decision, str(ai.last_decision))

		# 移动目标
		var move_target_str := "无"
		if "movement_target" in ai:
			var mt: Vector3 = ai.movement_target
			if not is_inf(mt.x):
				move_target_str = "(%.1f, %.1f)" % [mt.x, mt.z]

		# 威胁相关
		var threat_str := "无"
		if "recent_enemy_bullet_timer" in ai and ai.recent_enemy_bullet_timer > 0:
			threat_str = "[color=orange]%.1fs[/color]" % float(ai.recent_enemy_bullet_timer)

		# 目标玩家
		var target_player_str := "无"
		if "target_player" in ai and is_instance_valid(ai.target_player):
			var tp := ai.target_player as CharacterBody3D
			var tp_name := _get_display_name(tp)
			var tp_dist := ai.global_position.distance_to(tp.global_position)
			target_player_str = "%s(%.1fm)" % [tp_name, tp_dist]

		# 目标地块
		var target_plot_str := "无"
		if "target_plot" in ai and is_instance_valid(ai.target_plot):
			var tp_pos: Vector3 = ai.target_plot.global_position
			target_plot_str = "(%.1f, %.1f)" % [tp_pos.x, tp_pos.z]

		# 组装信息面板
		info_label.text = "[b][color=%s]%s %s[/color][/b] (%s)\n" % [team_color, team_cn, display_name, diff_cn]
		info_label.text += "状态: [color=cyan]%s[/color] | %s\n" % [state_cn, status_str]
		info_label.text += "HP: [color=%s]%.0f/%.0f[/color] [color=%s]%s[/color] %.0f%%\n" % [
			hp_color.to_html(false), hp_val, max_hp_val, hp_color.to_html(false), hp_bar, hp_pct]
		info_label.text += "状态效果: %s\n" % effects_str
		info_label.text += "决策: [color=yellow]%s[/color]\n" % decision_str
		info_label.text += "工具: %s | 冷却: %s\n" % [tool_str, cooldown_str]
		info_label.text += "威胁: %s | 目标玩家: %s\n" % [threat_str, target_player_str]
		info_label.text += "目标地块: %s | 移动目标: %s\n" % [target_plot_str, move_target_str]
		info_label.text += "位置: (%.1f, %.1f, %.1f) | 速度: %.1f" % [pos.x, pos.y, pos.z, vel.length()]
	else:
		info_label.text = "[b][color=yellow]自由观察模式[/color][/b]\nWASD 移动 | Shift 加速\nQ/E 升降 | 鼠标右键旋转视角"


# ===========================================================================
# 输入处理
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var idx: int = event.keycode - KEY_1
				if idx < targets.size():
					switch_to_target(idx)
			KEY_0:
				switch_to_free()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if current_index >= 0:
				orbit_distance = maxf(orbit_distance - 1.0, MIN_ORBIT_DISTANCE)
			else:
				global_position += -global_transform.basis.z * 3.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if current_index >= 0:
				orbit_distance = minf(orbit_distance + 1.0, MAX_ORBIT_DISTANCE)
			else:
				global_position += global_transform.basis.z * 3.0
	elif event is InputEventMouseMotion and is_looking:
		if current_index >= 0:
			orbit_yaw -= event.screen_relative.x * LOOK_SENSITIVITY
			orbit_pitch -= event.screen_relative.y * LOOK_SENSITIVITY
			orbit_pitch = clampf(orbit_pitch, -1.3, -0.05)
		else:
			free_yaw -= event.screen_relative.x * LOOK_SENSITIVITY
			free_pitch -= event.screen_relative.y * LOOK_SENSITIVITY
			free_pitch = clampf(free_pitch, -1.5, 0.2)
			rotation = Vector3(free_pitch, free_yaw, 0.0)
