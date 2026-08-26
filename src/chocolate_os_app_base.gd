extends Control
class_name ChocolateOSAppBase

var app_context: ChocolateOSAppContext

func on_install() -> void: pass
func on_launch(context: ChocolateOSAppContext) -> void: app_context = context
func on_focus() -> void: pass
func on_blur() -> void: pass
func on_suspend() -> void: pass
func on_resume() -> void: pass
func on_close() -> void: pass
func on_uninstall() -> void: pass

func migrate_data(_old_version: int, _new_version: int, data: Dictionary) -> Dictionary:
	return data.duplicate(true)
