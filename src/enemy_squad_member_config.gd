extends Resource
class_name EnemySquadMemberConfig

@export_enum("future_warrior", "future_engineer", "future_enemy_player")
var ai_type := "future_warrior"

@export_range(0, 32, 1)
var count := 1

## 留空时 EnemySquad 使用 ai_type 对应的默认场景。
@export var scene_override: PackedScene
