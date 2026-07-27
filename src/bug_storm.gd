extends Node3D
class_name BugStorm

## BugStorm：虫灾雾区（ShapeCast3D Tick 检测版）
##
## 手动节点结构：
## BugStorm (Node3D，本脚本)
## ├── DamageCast (ShapeCast3D)       # 每次 tick 主动检测范围内 Land / Character
## ├── StormVisual / FogVisual (MeshInstance3D)
## ├── FogParticles (GPUParticles3D)  # 可选：虫雾翻滚
## └── BugParticles (GPUParticles3D)  # 可选：虫群小黑点 / 飞虫粒子
##
## ShapeCast3D 配置要求：
## - Shape：建议 SphereShape3D，半径由你在 Inspector 手动设置
## - Target Position：建议 Vector3.ZERO
## - Collision Mask：你手动勾选 land 和 character 的碰撞层
## - Collide With Bodies：true
## - Collide With Areas：按需求；如果药雾也是 Area3D，可设 true
## - Exclude Parent：true
##
## 核心逻辑：
## - 不再使用 Area3D 的 body_entered / body_exited 维护目标列表
## - 每次 tick 时执行 DamageCast.force_shapecast_update()
## - 遍历 DamageCast.get_collision_count()
## - 取 collider
## - 对合法目标执行 target.impact("bug", bug_strength, source_team)
##
## 说明：
## - FarmTile 的 PlantProtector 免疫逻辑仍应放在 FarmTile.impact("bug", ...) 内部。
## - MedicineMist 可以通过 group "medicine_mist" 被距离轮询检测，也可以让 ShapeCast3D 检测 Area 后提前驱散。


signal storm_started
signal storm_tick
signal storm_fading
signal storm_finished
signal neutralized_by_medicine


enum StormState {
	SPAWNING,
	ACTIVE,
	FADING,
	FINISHED,
}


@export_group("Basic")
@export var source_team: String = ""

## 虫灾进入 ACTIVE 状态后的持续时间。
@export_range(0.5, 60.0, 0.5) var lifetime: float = 15.0

## 虫灾结束后的视觉消退时间。
@export_range(0.1, 10.0, 0.1) var fade_time: float = 2.5

## 每隔多久执行一次 ShapeCast3D 检查，并对命中的目标施加 bug。
@export_range(0.1, 5.0, 0.1) var tick_interval: float = 1.0

## 传给 impact("bug", bug_strength, source_team) 的强度。
@export var bug_strength: float = 1.0

## 用于视觉缩放、粒子范围和药雾距离检测。
## ShapeCast3D 的 Shape 半径仍由你在 Inspector 手动配置。
@export var effect_distance: float = 15.0

## false：不影响 source_team 同队单位 / 己方 FarmTile。
@export var affect_friendly: bool = false

## 是否在 tick 时打印 ShapeCast 命中和 impact 调试信息。
@export var debug_print_tick: bool = false


@export_group("Medicine Counter")
## 如果 ShapeCast3D 检测到 group=medicine_mist 的 Area3D / Node，立刻驱散。
@export var auto_detect_protect_from_cast: bool = true

## 如果药雾只是 Node3D，没有 Area3D，也可以通过 group 距离轮询检测。
@export var poll_medicine_group: bool = true

@export_range(0.1, 5.0, 0.1) var medicine_poll_interval: float = 0.5

## 用于距离轮询检测药雾的半径。
@export var medicine_neutralize_radius: float = 5.0


@export_group("Visual")
@export_range(0.0, 1.0, 0.01) var max_fog_alpha: float = 0.48

## 虫雾生成后的淡入时间。
@export_range(0.0, 5.0, 0.1) var fade_in_time: float = 0.5

## 消退时是否整体膨胀一点，表现虫雾散开。
@export var expand_on_fade: bool = true

@export var fade_out_scale_multiplier: float = 1.25

## 消退完成后是否销毁自己。
@export var free_when_finished: bool = true

## StormVisual / FogVisual 的高度缩放。
@export var fog_visual_height: float = 8.0

## FogParticles 的粒子数量。
@export var fog_particle_amount: int = 90

## BugParticles 的粒子数量。
@export var bug_particle_amount: int = 180


## 兼容 DamageCast / ShapeCast / DamageShapeCast 三种节点名。
@onready var damage_cast: ShapeCast3D = _find_damage_cast()

## 兼容你当前的 $StormVisual，也兼容之前结构里的 $FogVisual。
@onready var fog_visual: MeshInstance3D = _find_fog_visual()

@onready var fog_particles: GPUParticles3D = (
	get_node_or_null("FogParticles") as GPUParticles3D
)

@onready var bug_particles: GPUParticles3D = (
	get_node_or_null("BugParticles") as GPUParticles3D
)


var _state: int = StormState.SPAWNING
var _life_left: float = 0.0
var _tick_timer: float = 0.0
var _fade_in_left: float = 0.0
var _fade_left: float = 0.0
var _medicine_poll_left: float = 0.0

var _fog_material: StandardMaterial3D
var _base_scale: Vector3 = Vector3.ONE
var _started: bool = false
var _valid_setup: bool = false

# Clients use the same scene for the replicated visual, but only the server may
# apply bug damage through its ShapeCast.
@export var visual_only := false


## 作用：初始化 BugStorm 状态、验证节点、配置视觉和粒子，并延迟到下一物理帧启动。
func _ready() -> void:
	add_to_group("bug_storm")

	_validate_nodes()
	if not _valid_setup:
		return

	_base_scale = scale
	_life_left = lifetime
	_tick_timer = 0.0
	_fade_in_left = fade_in_time
	_fade_left = fade_time
	_medicine_poll_left = 0.0

	_setup_damage_cast()
	_setup_fog_material()
	_setup_fog_particles()
	_setup_bug_particles()
	_set_visual_alpha(0.0)

	# 等一个物理帧，确保 ShapeCast3D 已经进入物理世界。
	call_deferred("_start_after_physics")


## 作用：查找 DamageCast 节点。你可以命名为 DamageCast / ShapeCast / DamageShapeCast。
func _find_damage_cast() -> ShapeCast3D:
	var cast := get_node_or_null("DamageCast") as ShapeCast3D
	if cast != null:
		return cast

	cast = get_node_or_null("ShapeCast") as ShapeCast3D
	if cast != null:
		return cast

	return get_node_or_null("DamageShapeCast") as ShapeCast3D


## 作用：查找视觉雾团节点；优先使用 StormVisual，其次兼容 FogVisual。
func _find_fog_visual() -> MeshInstance3D:
	var visual := get_node_or_null("StormVisual") as MeshInstance3D
	if visual != null:
		return visual

	return get_node_or_null("FogVisual") as MeshInstance3D


## 作用：检查必要节点是否存在，并设置 _valid_setup。
func _validate_nodes() -> void:
	var missing: Array[String] = []

	if damage_cast == null:
		missing.append("DamageCast / ShapeCast / DamageShapeCast (ShapeCast3D)")

	if fog_visual == null:
		missing.append("StormVisual 或 FogVisual (MeshInstance3D)")

	if fog_particles == null:
		push_warning(
			"BugStorm: 未找到 FogParticles。虫灾仍能工作，"
			+ "但少了虫雾翻滚效果。"
		)

	if bug_particles == null:
		push_warning(
			"BugStorm: 未找到 BugParticles。虫灾仍能工作，"
			+ "但少了虫群小黑点。"
		)

	if not missing.is_empty():
		push_error(
			"BugStorm: 缺少必要节点："
			+ ", ".join(missing)
			+ "。请手动创建 ShapeCast3D 和视觉节点。"
		)

		_valid_setup = false
		set_process(false)
		set_physics_process(false)
		return

	_valid_setup = true


## 作用：配置 ShapeCast3D 的基础运行状态；碰撞层、Shape、TargetPosition 仍由你手动配置。
func _setup_damage_cast() -> void:
	damage_cast.enabled = true
	damage_cast.target_position = Vector3.ZERO
	damage_cast.collide_with_bodies = true
	# FarmTile is on layer 64 (Land). Keep this explicit so runtime-created
	# server storms cannot inherit an editor-side mask that only finds players.
	damage_cast.collision_mask = 64
	if damage_cast.shape is SphereShape3D:
		var area_shape := (damage_cast.shape as SphereShape3D).duplicate() as SphereShape3D
		area_shape.radius = effect_distance
		damage_cast.shape = area_shape

	# 如果你的药雾是 Area3D，并且希望 ShapeCast 直接检测药雾，可以在 Inspector 打开。
	# 这里不强制为 true，避免改变你对 land/character 的手动设置。
	# damage_cast.collide_with_areas = true

	if damage_cast.shape == null:
		push_warning(
			"BugStorm: DamageCast 没有设置 Shape。请在 Inspector 设置 SphereShape3D。"
		)


## 作用：配置半透明虫雾主体材质；使用 material_override，避免 surface index 越界。
func _setup_fog_material() -> void:
	if fog_visual == null:
		return

	fog_visual.scale = Vector3(
		effect_distance,
		fog_visual_height,
		effect_distance
	)

	var src_mat: Material = fog_visual.material_override

	if (
		src_mat == null
		and fog_visual.mesh != null
		and fog_visual.mesh.get_surface_count() > 0
	):
		src_mat = fog_visual.get_active_material(0)

	if src_mat is StandardMaterial3D:
		_fog_material = (src_mat as StandardMaterial3D).duplicate()
	else:
		_fog_material = StandardMaterial3D.new()

	_fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fog_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var color := _fog_material.albedo_color
	if color == Color.WHITE or color.a <= 0.01:
		color = Color(0.149, 0.247, 0.078, 0.0)
	else:
		color.a = 0.0

	_fog_material.albedo_color = color
	fog_visual.material_override = _fog_material

	if fog_visual.mesh == null:
		push_warning(
			"BugStorm: StormVisual/FogVisual 没有设置 Mesh。"
			+ "脚本不会报错，但你看不到半透明雾团。"
		)


## 作用：初始化 FogParticles，让它表现为虫灾里的慢速翻滚雾气。
func _setup_fog_particles() -> void:
	if fog_particles == null:
		return

	fog_particles.emitting = false
	fog_particles.one_shot = false
	fog_particles.amount = fog_particle_amount
	fog_particles.lifetime = 3.2
	fog_particles.preprocess = 1.5
	fog_particles.explosiveness = 0.0
	fog_particles.randomness = 0.9
	fog_particles.fixed_fps = 30
	fog_particles.local_coords = true

	fog_particles.visibility_aabb = AABB(
		Vector3(-effect_distance, -1.0, -effect_distance),
		Vector3(
			effect_distance * 2.0,
			fog_visual_height + 2.0,
			effect_distance * 2.0
		)
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = effect_distance * 0.75
	particle_material.direction = Vector3(0.0, 0.35, 0.0)
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 0.15
	particle_material.initial_velocity_max = 0.85
	particle_material.gravity = Vector3(0.0, 0.08, 0.0)
	particle_material.radial_accel_min = -0.2
	particle_material.radial_accel_max = 0.75
	particle_material.tangential_accel_min = -0.6
	particle_material.tangential_accel_max = 0.6
	particle_material.damping_min = 0.15
	particle_material.damping_max = 0.65
	particle_material.scale_min = 0.8
	particle_material.scale_max = 2.4
	particle_material.color = Color(0.13, 0.23, 0.055, 0.32)

	fog_particles.process_material = particle_material

	var fog_mesh := QuadMesh.new()
	fog_mesh.size = Vector2(1.0, 1.0)

	var fog_mat := StandardMaterial3D.new()
	fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	fog_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fog_mat.albedo_color = Color(0.11, 0.22, 0.055, 0.18)
	fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	fog_mesh.material = fog_mat

	fog_particles.draw_passes = 1
	fog_particles.draw_pass_1 = fog_mesh


## 作用：初始化 BugParticles，让它表现为虫灾雾中的黑褐色小虫群。
func _setup_bug_particles() -> void:
	if bug_particles == null:
		return

	bug_particles.emitting = false
	bug_particles.one_shot = false
	bug_particles.amount = bug_particle_amount
	bug_particles.lifetime = 2.2
	bug_particles.preprocess = 1.0
	bug_particles.explosiveness = 0.0
	bug_particles.randomness = 0.85
	bug_particles.fixed_fps = 30
	bug_particles.local_coords = true

	bug_particles.visibility_aabb = AABB(
		Vector3(-effect_distance, -1.0, -effect_distance),
		Vector3(effect_distance * 2.0, fog_visual_height, effect_distance * 2.0)
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = effect_distance
	particle_material.direction = Vector3(0.0, 0.25, 0.0)
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 0.5
	particle_material.initial_velocity_max = 2.5
	particle_material.gravity = Vector3(0.0, -0.5, 0.0)
	particle_material.radial_accel_min = -1.0
	particle_material.radial_accel_max = 1.8
	particle_material.tangential_accel_min = -1.0
	particle_material.tangential_accel_max = 1.8
	particle_material.damping_min = 0.2
	particle_material.damping_max = 0.8
	particle_material.scale_min = 0.035
	particle_material.scale_max = 0.085
	particle_material.color = Color(0.133, 0.0, 0.012, 0.949)

	bug_particles.process_material = particle_material

	var bug_mesh := QuadMesh.new()
	bug_mesh.size = Vector2(0.08, 0.035)

	var bug_mat := StandardMaterial3D.new()
	bug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bug_mat.albedo_color = Color(0.025, 0.018, 0.008, 0.95)
	bug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bug_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	bug_mesh.material = bug_mat

	bug_particles.draw_passes = 1
	bug_particles.draw_pass_1 = bug_mesh


## 作用：等待物理帧后正式启动虫灾，并开启粒子。
func _start_after_physics() -> void:
	await get_tree().physics_frame

	if not _valid_setup or _state == StormState.FINISHED:
		return

	_started = true
	_state = StormState.SPAWNING

	if fog_particles != null:
		fog_particles.emitting = true

	if bug_particles != null:
		bug_particles.emitting = true

	_check_existing_medicine_mist()
	storm_started.emit()


## 作用：根据当前状态分发更新逻辑：淡入、持续、消退或结束。
func _physics_process(delta: float) -> void:
	if not _started:
		return

	match _state:
		StormState.SPAWNING:
			_update_spawn(delta)

		StormState.ACTIVE:
			_update_active(delta)

		StormState.FADING:
			_update_fade(delta)

		StormState.FINISHED:
			return


## 作用：处理生成时的淡入效果，淡入结束后进入 ACTIVE。
func _update_spawn(delta: float) -> void:
	if fade_in_time <= 0.0:
		_set_visual_alpha(max_fog_alpha)
		_state = StormState.ACTIVE
		return

	_fade_in_left = maxf(0.0, _fade_in_left - delta)

	var t := 1.0 - (_fade_in_left / maxf(fade_in_time, 0.001))
	_set_visual_alpha(lerpf(0.0, max_fog_alpha, t))

	if _fade_in_left <= 0.0:
		_state = StormState.ACTIVE


## 作用：处理虫灾持续阶段：扣 lifetime、按 tick 执行 ShapeCast 检测、检测药雾、到期后进入消退。
func _update_active(delta: float) -> void:
	_life_left -= delta
	_tick_timer -= delta

	if poll_medicine_group:
		_medicine_poll_left -= delta
		if _medicine_poll_left <= 0.0:
			_medicine_poll_left = medicine_poll_interval
			_check_existing_medicine_mist()

	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_apply_bug_tick()

	if _life_left <= 0.0:
		_begin_fade(false)


## 作用：处理消退阶段，降低雾团透明度，停止玩法效果，最后销毁。
func _update_fade(delta: float) -> void:
	_fade_left = maxf(0.0, _fade_left - delta)

	var t := 1.0 - (_fade_left / maxf(fade_time, 0.001))
	var alpha := lerpf(max_fog_alpha, 0.0, t)
	_set_visual_alpha(alpha)

	if expand_on_fade:
		var target_scale := _base_scale * fade_out_scale_multiplier
		scale = _base_scale.lerp(target_scale, t)

	if _fade_left <= 0.0:
		_finish_storm()


## 作用：只修改 StormVisual/FogVisual 材质 alpha，用于淡入和淡出。
func _set_visual_alpha(alpha: float) -> void:
	if _fog_material == null:
		return

	var color := _fog_material.albedo_color
	color.a = clampf(alpha, 0.0, 1.0)
	_fog_material.albedo_color = color


## 作用：每个 tick 主动执行 ShapeCast3D，获取 collider 并对合法目标调用 impact("bug", ...)。
func _apply_bug_tick() -> void:
	# A multiplayer client owns only the replicated visual. FarmTile.impact()
	# must be executed by the dedicated authority so the resulting tile delta is
	# the sole source of truth for every client. Local mode remains unchanged.
	if visual_only or GameAuthority.is_client_proxy():
		return
	var targets := _collect_targets_by_shape_cast()

	if debug_print_tick:
		print("[BugStorm] tick targets=", targets.size())

	for target in targets:
		if not is_instance_valid(target):
			continue

		if debug_print_tick:
			print("[BugStorm] IMPACT:", target)

		target.call(
			"impact",
			"bug",
			bug_strength,
			source_team
		)

	#storm_tick.emit()


## 作用：执行 ShapeCast3D 原地检测，并返回去重后的合法虫灾目标。
func _collect_targets_by_shape_cast() -> Array[Node]:
	var result: Array[Node] = []

	if damage_cast == null:
		return result

	damage_cast.force_shapecast_update()

	var seen: Dictionary = {}
	var collision_count := damage_cast.get_collision_count()

	for i in range(collision_count):
		var collider := damage_cast.get_collider(i)

		if collider == null:
			continue

		if not collider is Node:
			continue

		var collider_node := collider as Node
		var farm_tile := Farmlandmanager.resolve_shapecast_tile(damage_cast, i)
		if farm_tile != null:
			collider_node = farm_tile

		if auto_detect_protect_from_cast:
			_try_neutralize_by_medicine_node(collider_node)

			if _state == StormState.FADING or _state == StormState.FINISHED:
				return result
		
		## 检测植物保护器
		if auto_detect_protect_from_cast:
			if collider_node is PlantProtector:
				_begin_fade(true)
				if _state == StormState.FADING or _state == StormState.FINISHED:
					return result
			
		var target := _resolve_bug_target_from_collider(collider_node)

		if target == null:
			continue
		
		if not _is_valid_bug_target(target):
			continue
		
		#print(target)
		var id := target.get_instance_id()
		if seen.has(id):
			continue

		seen[id] = true
		result.append(target)

	return result


## 作用：把 ShapeCast 命中的 collider 转换成真正要调用 impact() 的目标。
## 例如命中的是 Hit3D / 子 Area / 子 Mesh 时，会向父节点查找 impact()。
func _resolve_bug_target_from_collider(collider_node: Node) -> Node:
	var cursor: Node = collider_node
	var depth := 0

	while cursor != null and depth < 4:
		if (
			cursor is FarmTile
			or cursor is GamePlayer
			or cursor is AIPlayer
			or cursor.has_method("impact")
		):
			return cursor

		cursor = cursor.get_parent()
		depth += 1

	return null


## 作用：判断某个节点是否是合法虫灾目标，要求有 impact()，并按队伍过滤。
func _is_valid_bug_target(node: Node) -> bool:
	if node == null:
		return false

	if node == self:
		return false

	if is_ancestor_of(node):
		return false

	if not node.has_method("impact"):
		return false

	if not affect_friendly:
		var target_team := _get_combat_team(node)
		if not target_team.is_empty() and target_team == source_team:
			return false

	return true


# ------------------------------------------------------------------
# Medicine mist neutralization
# ------------------------------------------------------------------

## 作用：检测 ShapeCast 命中的节点或父节点是否属于 medicine_mist，从而提前驱散虫灾。
func _try_neutralize_by_medicine_node(node: Node) -> void:
	if node == null:
		return

	if node.is_in_group("medicine_mist"):
		neutralize_by_medicine(node)
		return

	var parent := node.get_parent()

	while parent != null:
		if parent.is_in_group("medicine_mist"):
			neutralize_by_medicine(parent)
			return

		parent = parent.get_parent()


## 作用：低频轮询场景中已有的 medicine_mist，用距离判断是否提前驱散虫灾。
func _check_existing_medicine_mist() -> void:
	if _state == StormState.FADING or _state == StormState.FINISHED:
		return

	var medicine_nodes := get_tree().get_nodes_in_group("medicine_mist")

	for node in medicine_nodes:
		if not is_instance_valid(node):
			continue

		if node == self:
			continue

		var node3d := _find_node3d_from_node(node)
		if node3d == null:
			continue

		if global_position.distance_to(node3d.global_position) <= medicine_neutralize_radius:
			neutralize_by_medicine(node)
			return


## 作用：给外部药雾直接调用的公开接口；调用后虫灾立刻停止玩法效果并进入消退。
func neutralize_by_medicine(_medicine_node: Node) -> void:
	if _state == StormState.FADING or _state == StormState.FINISHED:
		return

	#neutralized_by_medicine.emit()
	_begin_fade(true)


# ------------------------------------------------------------------
# Fade / finish
# ------------------------------------------------------------------

## 作用：开始消退；立即停止 ShapeCast 玩法效果，视觉继续淡出。
func _begin_fade(by_medicine: bool) -> void:
	if _state == StormState.FADING or _state == StormState.FINISHED:
		return

	_state = StormState.FADING
	_fade_left = fade_time

	# 玩法立即结束，视觉继续消退。
	if damage_cast != null:
		damage_cast.enabled = false

	if fog_particles != null:
		fog_particles.emitting = false

	if bug_particles != null:
		bug_particles.emitting = false

	if by_medicine:
		print("[BugStorm] neutralized by medicine mist.")
	else:
		print("[BugStorm] lifetime ended, fading.")

	storm_fading.emit()


## 作用：消退完成后进入 FINISHED，并根据设置销毁节点。
func _finish_storm() -> void:
	_state = StormState.FINISHED
	storm_finished.emit()

	if free_when_finished:
		queue_free()


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

## 作用：从任意 Node 向上查找最近的 Node3D，用于 medicine_mist 距离检测。
func _find_node3d_from_node(node: Node) -> Node3D:
	if node is Node3D:
		return node as Node3D

	var parent := node.get_parent()

	while parent != null:
		if parent is Node3D:
			return parent as Node3D

		parent = parent.get_parent()

	return null


## 作用：读取目标队伍名，支持 get_combat_team/team_id/team/tool_owner/land_owner 多种项目接口。
func _get_combat_team(node: Node) -> String:
	if node == null:
		return ""

	if node is AIPlayer:
		return str(node.get("team_id"))

	if node is GamePlayer:
		return str(node.get("team"))

	if node is FarmTile:
		return str(node.get("land_owner"))

	return ""


## 作用：安全检查对象是否存在某个导出/成员属性，避免直接 get() 报错。
func _has_property(object: Object, property_name: String) -> bool:
	for info: Dictionary in object.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true

	return false
