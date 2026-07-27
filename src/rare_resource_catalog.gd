extends RefCounted
class_name RareResourceCatalog

const RESOURCES := [
	{"id": "meteorite", "display_name": "陨石", "event_title": "陨石坠落了！", "event_description": "地图上出现了一个可争夺的稀有陨石资源。", "lifetime_seconds": 300.0},
	{"id": "giant_watermelon", "display_name": "巨大的野生西瓜", "event_title": "一个巨大的野生西瓜出现了！", "event_description": "一块区域发现了巨大的野生西瓜。", "lifetime_seconds": 300.0},
	{"id": "airdrop_crate", "display_name": "空投箱子", "event_title": "一个空投箱子降落了！", "event_description": "空投箱已经降落，所有队伍都可以争夺。", "lifetime_seconds": 300.0},
	{"id": "giant_pumpkin", "display_name": "巨大南瓜", "event_title": "一个巨大的南瓜出现了！", "event_description": "地图中出现了巨大南瓜，所有队伍都可以争夺。", "lifetime_seconds": 300.0, "scene_path": "res://items/GiantPumpkin.tscn"},
	{"id": "giant_pepper", "display_name": "巨大辣椒", "event_title": "一个巨大的辣椒出现了！", "event_description": "地图中出现了巨大辣椒，所有队伍都可以争夺。", "lifetime_seconds": 300.0, "scene_path": "res://items/GiantPepper.tscn"},
]

static func get_random_resource(rng: RandomNumberGenerator) -> Dictionary:
	return RESOURCES[rng.randi_range(0, RESOURCES.size() - 1)].duplicate(true)
