extends Node3D
## 攻防模式测试场景根脚本。
## 防守方（蓝队）负责种植和防御；敌人（进攻方）负责破坏农田和射击队员。
## 所有四角农田归属蓝队，中心农田中立供争夺。敌人无农田。


func _ready() -> void:
	GlobalVar.gameworld = self
	# 延迟一帧，等所有 FarmFieldGenerator 的 _ready 执行完毕生成 tile
	call_deferred("_assign_farm_ownership")


func _assign_farm_ownership() -> void:
	var fm := get_node_or_null("/root/Farmlandmanager")
	if fm == null:
		return
	# 蓝队（防守方）拥有全部四角农田
	var assignment := {
		"blue": ["NorthWestFarm", "NorthEastFarm", "SouthWestFarm", "SouthEastFarm"],
	}
	for team in assignment:
		for farm_name in assignment[team]:
			var farm := get_node_or_null(farm_name)
			if farm == null:
				continue
			for tile in farm.get_children():
				if tile.has_method("plant") and "land_owner" in tile:
					fm.change_land_owner(tile, team)
	print("[AssaultTest] 农田归属分配完成：蓝队（防守方）拥有全部四角农田")
