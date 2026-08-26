extends RefCounted
class_name ChocolateOSAppContext

signal service_event(event_name: String, payload: Dictionary)

var app_id := ""
var _desktop_ref: WeakRef

func _init(owner_desktop: ChocolateOSDesktop, owner_app_id: String) -> void:
	_desktop_ref = weakref(owner_desktop)
	app_id = owner_app_id

func query(service: String, request := {}) -> Dictionary:
	var desktop := _desktop()
	return desktop.query_app_service(app_id, service, request as Dictionary if request is Dictionary else {}) if desktop != null else {"ok": false, "reason": "desktop_closed"}

func command(service: String, action: String, payload := {}, expected_revision := 0) -> bool:
	var desktop := _desktop()
	return desktop.command_app_service(app_id, service, action, payload as Dictionary if payload is Dictionary else {}, expected_revision) if desktop != null else false

func storage_read() -> Dictionary:
	var desktop := _desktop()
	return desktop.read_app_storage(app_id) if desktop != null else {}

func storage_write(command_name: String, payload: Dictionary, expected_revision := 0) -> bool:
	return command("app_storage.write", command_name, payload, expected_revision)

func subscribe(event_name: String) -> bool:
	var desktop := _desktop()
	return desktop.subscribe_app_service(app_id, event_name, self) if desktop != null else false


func get_os_id() -> String:
	var desktop := _desktop()
	return desktop.get_current_os_id() if desktop != null else "OS08"

func _desktop() -> ChocolateOSDesktop:
	return _desktop_ref.get_ref() as ChocolateOSDesktop if _desktop_ref != null else null
