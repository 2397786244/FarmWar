extends RefCounted
class_name EmbeddedLabCatalog

## Embedded Lab only describes the research tree.  It deliberately does not
## contain robot runtime behavior; a completed node produces a program_id that
## can later be written to a hard drive.

const COST_PER_LEVEL := 10000
const LEVEL_DURATIONS_SECONDS := [60.0, 105.0, 150.0, 195.0, 240.0]
const LEVEL_LABELS := ["I", "II", "III", "IV", "V"]

const TRACKS := [
	{
		"track_id": "collection",
		"display_name": "采集程序",
		"letter": "C",
		"color": Color("#48ad68"),
		"description": "负责资源寻找、接近与采集流程。",
	},
	{
		"track_id": "transport",
		"display_name": "运输程序",
		"letter": "T",
		"color": Color("#d9a936"),
		"description": "负责装载、运输、交付与返回流程。",
	},
	{
		"track_id": "combat",
		"display_name": "战斗程序",
		"letter": "B",
		"color": Color("#d95757"),
		"description": "负责目标识别、战斗决策与武器控制。",
	},
	{
		"track_id": "defense",
		"display_name": "防御程序",
		"letter": "D",
		"color": Color("#4f83d1"),
		"description": "负责危险检测、保护策略与撤退处理。",
	},
]


static func get_all_programs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for track_value: Dictionary in TRACKS:
		var track_id := str(track_value.get("track_id", ""))
		for level in range(1, 6):
			var program_id := "%s_program_%d" % [track_id, level]
			var prerequisites: Array[String] = []
			if level > 1:
				prerequisites.append("%s_program_%d" % [track_id, level - 1])
			result.append({
				"program_id": program_id,
				"track_id": track_id,
				"display_name": "%s %s" % [str(track_value.get("display_name", "程序")), LEVEL_LABELS[level - 1]],
				"short_label": "%s%d" % [str(track_value.get("letter", "P")), level],
				"level": level,
				"letter": str(track_value.get("letter", "P")),
				"color": track_value.get("color", Color.WHITE),
				"track_description": str(track_value.get("description", "")),
				"description": _description_for(track_id, level),
				"cost": COST_PER_LEVEL * level,
				"duration_seconds": LEVEL_DURATIONS_SECONDS[level - 1],
				"prerequisites": prerequisites,
			})
	return result


static func get_definition(program_id: String) -> Dictionary:
	for definition: Dictionary in get_all_programs():
		if str(definition.get("program_id", "")) == program_id:
			return definition.duplicate(true)
	return {}


static func get_track_definitions(track_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in get_all_programs():
		if str(definition.get("track_id", "")) == track_id:
			result.append(definition)
	return result


static func get_default_state() -> Dictionary:
	return {
		"revision": 1,
		"unlocked_program_ids": [],
		"active_research": {},
	}


static func format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, ceili(seconds))
	var minutes := int(total_seconds / 60)
	var remainder := total_seconds % 60
	return "%02d:%02d" % [minutes, remainder]


static func _description_for(track_id: String, level: int) -> String:
	var level_name: String = str(LEVEL_LABELS[level - 1])
	match track_id:
		"collection":
			return "采集能力模块 %s：解锁第 %d 级资源采集流程。" % [level_name, level]
		"transport":
			return "运输能力模块 %s：解锁第 %d 级装载与交付流程。" % [level_name, level]
		"combat":
			return "战斗能力模块 %s：解锁第 %d 级战斗控制流程。" % [level_name, level]
		"defense":
			return "防御能力模块 %s：解锁第 %d 级危险应对流程。" % [level_name, level]
	return "嵌入式程序模块 %s。" % level_name
