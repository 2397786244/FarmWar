extends RefCounted
class_name ChocolateOSCatalog

const MANIFEST_PATHS := [
	"res://computer/apps/browser/manifest.tres",
	"res://computer/apps/my_computer/manifest.tres",
	"res://computer/apps/network/manifest.tres",
	"res://computer/apps/recycle_bin/manifest.tres",
	"res://computer/apps/settings/manifest.tres",
	"res://computer/apps/shutdown/manifest.tres",
	"res://computer/apps/farm_info/manifest.tres",
	"res://computer/apps/weather/manifest.tres",
]

static var _manifests: Dictionary = {}
static var _program_to_app: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _manifests.is_empty():
		return
	for path: String in MANIFEST_PATHS:
		var manifest := load(path) as ChocolateOSAppManifest
		if manifest == null or manifest.app_id.is_empty() or manifest.program_id.is_empty():
			push_warning("ChocolateOS application manifest is invalid: %s" % path)
			continue
		_manifests[manifest.app_id] = manifest
		_program_to_app[manifest.program_id] = manifest.app_id


static func get_manifest(app_id: String) -> ChocolateOSAppManifest:
	_ensure_loaded()
	return _manifests.get(app_id, null) as ChocolateOSAppManifest


static func get_manifest_for_program(program_id: String) -> ChocolateOSAppManifest:
	_ensure_loaded()
	return get_manifest(str(_program_to_app.get(program_id, "")))


static func get_all_app_ids() -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for value: Variant in _manifests.keys():
		result.append(str(value))
	result.sort()
	return result


static func get_supported_app_ids(os_id: String) -> Array[String]:
	var result: Array[String] = []
	for app_id: String in get_all_app_ids():
		var manifest := get_manifest(app_id)
		if manifest != null and manifest.supports_os(os_id):
			result.append(app_id)
	return result


static func get_default_installed_app_ids(os_id: String) -> Array[String]:
	var result: Array[String] = []
	for app_id: String in get_supported_app_ids(os_id):
		var manifest := get_manifest(app_id)
		if manifest.system_app or manifest.default_installed:
			result.append(app_id)
	return result


static func get_store_app_ids(os_id: String) -> Array[String]:
	var result: Array[String] = []
	for app_id: String in get_supported_app_ids(os_id):
		var manifest := get_manifest(app_id)
		if not manifest.system_app and manifest.app_store_distribution:
			result.append(app_id)
	return result


static func get_default_layout(os_id: String, installed_ids: Array[String]) -> Dictionary:
	var result := {}
	for app_id: String in installed_ids:
		var manifest := get_manifest(app_id)
		if manifest != null and manifest.supports_os(os_id):
			result[app_id] = [manifest.default_grid_position.x, manifest.default_grid_position.y]
	return result


static func get_first_free_grid_cell(layout: Dictionary, columns := 13, rows := 6) -> Vector2i:
	var occupied := {}
	for value: Variant in layout.values():
		var cell := _as_grid_cell(value)
		occupied["%d:%d" % [cell.x, cell.y]] = true
	for x in range(columns):
		for y in range(rows):
			if not occupied.has("%d:%d" % [x, y]):
				return Vector2i(x, y)
	return Vector2i(columns - 1, rows - 1)


static func normalize_layout(layout_value: Variant, installed_ids: Array[String], os_id: String) -> Dictionary:
	var source: Dictionary = layout_value as Dictionary if layout_value is Dictionary else {}
	var result := {}
	var occupied := {}
	for app_id: String in installed_ids:
		var manifest := get_manifest(app_id)
		if manifest == null or not manifest.supports_os(os_id):
			continue
		var cell := _as_grid_cell(source.get(app_id, [manifest.default_grid_position.x, manifest.default_grid_position.y]))
		cell.x = clampi(cell.x, 0, 12)
		cell.y = clampi(cell.y, 0, 5)
		var key := "%d:%d" % [cell.x, cell.y]
		if occupied.has(key):
			cell = get_first_free_grid_cell(result)
			key = "%d:%d" % [cell.x, cell.y]
		occupied[key] = true
		result[app_id] = [cell.x, cell.y]
	return result


static func _as_grid_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		return Vector2i(roundi((value as Vector2).x), roundi((value as Vector2).y))
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO
