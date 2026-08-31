extends Control
class_name CooldownRing

const BACKGROUND_COLOR := Color(UITheme.COLOR_BORDER, 0.85)
const FOREGROUND_COLOR := Color(UITheme.COLOR_TEXT, 0.94)
const RING_WIDTH := 4.0
const RING_RADIUS := 20.0

var _remaining := 0.0
var _duration := 0.0


func _ready() -> void:
	UITheme.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_cooldown(remaining: float, duration: float) -> void:
	_remaining = maxf(0.0, remaining)
	_duration = maxf(0.0, duration)
	visible = _remaining > 0.0 and _duration > 0.0
	queue_redraw()


## Uses the same ring for an action that is being charged, rather than a
## cooldown that is elapsing.  The foreground arc therefore grows clockwise.
func set_progress(elapsed: float, duration: float) -> void:
	_remaining = clampf(elapsed, 0.0, maxf(0.0, duration))
	_duration = maxf(0.0, duration)
	visible = _remaining > 0.0 and _duration > 0.0
	queue_redraw()


func _draw() -> void:
	if _duration <= 0.0:
		return
	var center := size * 0.5
	var ratio := clampf(_remaining / _duration, 0.0, 1.0)
	draw_arc(center, RING_RADIUS, 0.0, TAU, 48, BACKGROUND_COLOR, RING_WIDTH, true)
	if ratio > 0.0:
		draw_arc(center, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * ratio, maxi(2, ceili(48.0 * ratio)), FOREGROUND_COLOR, RING_WIDTH, true)
