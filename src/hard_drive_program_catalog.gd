extends RefCounted
class_name HardDriveProgramCatalog

## Describes the single program stored on one physical hard drive.
##
## A drive stores only program_id.  The human-readable name, kind and
## description are resolved from the application and Embedded Lab catalogs so
## inventory UI, My Computer and Embedded Lab use the same interpretation.

static func describe(program_id: String) -> Dictionary:
	program_id = program_id.strip_edges()
	if program_id.is_empty():
		return {
			"program_id": "",
			"display_name": "空白硬盘",
			"program_type": "空白存储介质",
			"description": "还没有写入程序，可以在 Embedded Lab 中写入已解锁的程序。",
			"is_application": false,
			"is_firmware": false,
		}

	var manifest := ChocolateOSCatalog.get_manifest_for_program(program_id)
	if manifest != null:
		return {
			"program_id": program_id,
			"display_name": manifest.display_name,
			"program_type": "可安装应用程序",
			"description": manifest.description if not manifest.description.is_empty() else "可安装到兼容的 ChocolateOS 电脑。",
			"version": manifest.version,
			"is_application": true,
			"is_firmware": false,
		}

	var embedded_definition := EmbeddedLabCatalog.get_definition(program_id)
	if not embedded_definition.is_empty():
		return {
			"program_id": program_id,
			"display_name": str(embedded_definition.get("display_name", program_id)),
			"program_type": "嵌入式固件程序",
			"description": str(embedded_definition.get("description", "已解锁的嵌入式程序，可写入硬盘。")),
			"version": str(embedded_definition.get("short_label", "")),
			"is_application": false,
			"is_firmware": true,
		}

	# Keep unknown future firmware readable without requiring a catalog entry.
	# Robot firmware is intentionally not implemented here; this fallback only
	# preserves its future program_id for inventory display and replacement.
	return {
		"program_id": program_id,
		"display_name": program_id,
		"program_type": "嵌入式程序固件",
		"description": "该程序的详细定义尚未注册。程序标识会保存在硬盘中。",
		"is_application": false,
		"is_firmware": true,
	}


static func display_name_for(program_id: String) -> String:
	return str(describe(program_id).get("display_name", program_id))


static func option_text_for(program_id: String) -> String:
	if program_id.strip_edges().is_empty():
		return "空白"
	var details := describe(program_id)
	return "%s · %s" % [
		str(details.get("display_name", program_id)),
		str(details.get("program_type", "程序")),
	]
