extends RefCounted

## CargoCar interaction tracing is intentionally enabled for debug/editor builds.
## The messages are event-based (area creation, E presses and requests/results),
## so they do not spam the per-frame interaction hint refresh.
static func log(message: String) -> void:
	if not OS.is_debug_build():
		return
	print("[CargoCarDebug] %s" % message)
