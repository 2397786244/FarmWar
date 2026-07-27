# Food War 角色骨骼动画使用说明

## 已包含的动画

所有六个角色 GLB 使用相同骨架和动画名称，动画帧率为 30 FPS。

| 动画名 | 时长 | 是否循环 | 用途 |
| --- | ---: | --- | --- |
| `Idle` | 2.0 秒 | 是 | 普通待机 |
| `IdleTool` | 2.0 秒 | 是 | 右手持工具待机 |
| `IdleAim` | 1.0 秒 | 是 | 单手瞄准待机 |
| `Walk` | 0.8 秒 | 是 | 原地行走 |
| `JumpStart` | 0.33 秒 | 否 | 起跳准备和离地 |
| `JumpLoop` | 0.67 秒 | 是 | 空中姿势 |
| `JumpLand` | 0.4 秒 | 否 | 落地缓冲 |
| `ShootOneHand` | 0.33 秒 | 否 | 右手单手射击和后坐力 |
| `PunchRight` | 0.53 秒 | 否 | 右手出拳 |
| `ToolUseRight` | 0.67 秒 | 否 | 右手工具向前使用并收回 |

动画全部为原地动画，不会改变角色在世界中的位置。角色移动、重力和跳跃高度继续由
`CharacterBody3D.velocity`、`move_and_slide()` 等游戏逻辑控制。

## Godot 场景结构

将角色 GLB 实例化到玩家或 NPC 场景中。导入后的模型内部包含：

```text
CharacterBody3D
└── CharacterModel（GLB 实例）
    ├── CharacterSkeleton
    ├── 各个 MeshInstance3D
    └── AnimationPlayer
```

如果角色场景中已有自己的 `AnimationPlayer`，不要与 GLB 内部的播放器混淆。可以在场景树中
右键 GLB 实例并启用“可编辑子项”，确认实际的 `AnimationPlayer` 路径。

## 最小播放示例

```gdscript
@onready var animation_player: AnimationPlayer = \
	$CharacterModel/AnimationPlayer

func _ready() -> void:
	# glTF 本身不保存循环开关，因此在运行时统一设置。
	for animation_name in ["Idle", "IdleTool", "IdleAim", "Walk", "JumpLoop"]:
		var animation := animation_player.get_animation(animation_name)
		if animation:
			animation.loop_mode = Animation.LOOP_LINEAR

	animation_player.play("Idle")
```

如果你的 GLB 节点路径会变化，可以递归查找：

```gdscript
@onready var animation_player: AnimationPlayer = \
	$CharacterModel.find_child("AnimationPlayer", true, false)
```

## 行走和待机切换

不要在每一帧无条件重新调用 `play()`。先检查当前动画，避免动画不断从第一帧重播：

```gdscript
func play_if_changed(animation_name: StringName, blend := 0.15) -> void:
	if animation_player.current_animation == animation_name:
		return
	animation_player.play(animation_name, blend)


func update_locomotion_animation() -> void:
	if not is_on_floor():
		play_if_changed(&"JumpLoop", 0.08)
	elif Vector2(velocity.x, velocity.z).length() > 0.15:
		play_if_changed(&"Walk", 0.12)
	elif is_aiming:
		play_if_changed(&"IdleAim", 0.12)
	elif current_tool != null:
		play_if_changed(&"IdleTool", 0.12)
	else:
		play_if_changed(&"Idle", 0.12)
```

## 跳跃动画

```gdscript
var was_on_floor := true
var action_animation_locked := false


func try_jump() -> void:
	if not is_on_floor():
		return

	velocity.y = jump_velocity
	animation_player.play(&"JumpStart", 0.06)


func update_jump_animation() -> void:
	var on_floor_now := is_on_floor()

	if not on_floor_now and animation_player.current_animation == &"JumpStart":
		if not animation_player.is_playing():
			animation_player.play(&"JumpLoop", 0.06)

	if on_floor_now and not was_on_floor:
		play_one_shot(&"JumpLand")

	was_on_floor = on_floor_now
```

物理代码应该先执行 `move_and_slide()`，然后再判断是否刚刚落地。

## 射击、出拳和工具动画

动作动画播放期间要暂时锁定普通待机/行走切换，否则 `_physics_process()` 会立即用 `Walk`
或 `Idle` 覆盖动作。

```gdscript
func play_one_shot(animation_name: StringName, blend := 0.06) -> void:
	if action_animation_locked:
		return

	action_animation_locked = true
	animation_player.play(animation_name, blend)
	await animation_player.animation_finished
	action_animation_locked = false


func shoot() -> void:
	# 子弹生成和冷却逻辑仍由武器脚本处理。
	play_one_shot(&"ShootOneHand")


func punch() -> void:
	play_one_shot(&"PunchRight")


func use_current_tool() -> void:
	play_one_shot(&"ToolUseRight")
```

普通动画更新需要尊重锁定：

```gdscript
func _physics_process(delta: float) -> void:
	# 先执行移动和武器逻辑……

	if not action_animation_locked:
		update_locomotion_animation()
```

如果射速快于 `ShootOneHand` 的完整时长，可以在每次开火时调用：

```gdscript
animation_player.stop()
animation_player.play(&"ShootOneHand", 0.03)
```

## 将工具绑定到右手

在角色的 `Skeleton3D` 下添加 `BoneAttachment3D`：

1. 将 `bone_name` 设置为 `Hand.R`。
2. 将当前工具实例作为 `BoneAttachment3D` 的子节点。
3. 调整工具的局部位置和旋转，使握把对齐手掌。
4. 切换工具时，只替换挂点下面的工具模型。

示例结构：

```text
CharacterSkeleton
└── RightHandAttachment（BoneAttachment3D，bone_name = Hand.R）
    └── CurrentTool
```

不同工具的握把位置不一致，建议每个工具场景增加一个统一命名的 `GripPoint` 标记，或者保存
各工具对应的局部位置、旋转偏移。

## 推荐状态优先级

动画状态从高到低：

1. `PunchRight`、`ShootOneHand`、`ToolUseRight`
2. `JumpStart`、`JumpLoop`、`JumpLand`
3. `Walk`
4. `IdleAim`
5. `IdleTool`
6. `Idle`

射击、出拳和使用工具属于一次性动作。跳跃动画由角色是否在地面以及竖直速度决定。待机与行走
只能在没有高优先级动作时更新。

## 注意事项

- 当前模型采用低多边形刚性蒙皮，方形头、手臂和衣服不会出现软体扭曲。
- 腿部模型仍是一整段低模造型，因此行走偏卡通直腿风格。
- 不要用动画控制角色世界坐标，否则会与 `CharacterBody3D` 的物理移动冲突。
- 修改 GLB 后，Godot 如果没有立即刷新，可在文件系统面板右键 GLB，选择“重新导入”。
