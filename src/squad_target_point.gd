extends Node3D
class_name SquadTargetPoint

## 地图中持久化的 Squad 战略目标。黄色圆柱由运行时地图编辑器临时添加，
## 不属于本场景，因此游戏运行时这里只保留不可见的 Node3D。

@export var target_id := ""


func _ready() -> void:
	add_to_group("squad_target_points")
	if target_id.is_empty():
		target_id = name

