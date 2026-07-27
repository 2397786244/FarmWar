extends Node3D
## 测试场景根脚本。设置 GlobalVar.gameworld，供 boom/AntiAir 等工具作为父节点。
## 并在农田生成后，把四角农田分配给蓝红两队（中心高地农田保持中立，供争夺）。


func _ready() -> void:
	GlobalVar.gameworld = self
	# 延迟一帧，等所有 FarmFieldGenerator 的 _ready 执行完毕生成 tile
	call_deferred("_assign_farm_ownership")


func _assign_farm_ownership() -> void:
	var fm := get_node_or_null("/root/Farmlandmanager")
	if fm == null:
		return
	# 队伍 → 农田 generator 名称列表
	# 蓝队在 z 负侧（北），红队在 z 正侧（南），与 AI 代码方向假设一致
	var assignment := {
		"blue": ["NorthWestFarm", "NorthEastFarm"],
		"red": ["SouthWestFarm", "SouthEastFarm"],
	}
	for team in assignment:
		for farm_name in assignment[team]:
			var farm := get_node_or_null(farm_name)
			if farm == null:
				continue
			for tile in farm.get_children():
				if tile.has_method("plant") and "land_owner" in tile:
					# 通过 Farmlandmanager 改归属，确保索引同步更新
					fm.change_land_owner(tile, team)
	print("[AIPlayerTest] 农田归属分配完成")
