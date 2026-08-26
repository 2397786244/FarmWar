extends Resource
class_name ChocolateOSAppManifest

@export var app_id := ""
@export var program_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var version := "1.0"
@export var supported_os: PackedStringArray = ["OS08", "OS26"]
@export var icon_os08 := ""
@export var icon_os26 := ""
@export var entry_kind := "placeholder"
@export var entry_scene: PackedScene
@export var system_app := false
@export var removable := true
@export var single_instance := true
@export var app_store_distribution := true
@export var default_installed := false
@export var default_grid_position := Vector2i.ZERO
@export var pinned_to_dock := false
@export var permissions: PackedStringArray = []
@export var dependencies: PackedStringArray = []
@export var data_version := 1


func supports_os(os_id: String) -> bool:
	return supported_os.has(os_id)


func icon_path_for_os(os_id: String) -> String:
	return icon_os26 if os_id == "OS26" else icon_os08
