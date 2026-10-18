class_name AchievementToast
extends CanvasLayer

## A small banner that says what was just earned, then goes away.
##
## Queued rather than overwritten: several achievements can land on the same run end,
## and replacing the text faster than it can be read is how toasts become noise.

const HOLD := 1.9
const FADE_IN := 0.18
const FADE_OUT := 0.35

var _label: Label
var _queue: Array[String] = []
var _active := ""
var _time := 0.0


func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_label = NeonStyle.label("", 21, NeonStyle.AMBER, 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 86
	_label.offset_bottom = 126
	_label.modulate.a = 0.0
	root.add_child(_label)


func show_text(text: String) -> void:
	if text.is_empty():
		return
	_queue.append(text)


func pending() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	if _active.is_empty():
		if _queue.is_empty():
			return
		_active = _queue.pop_front()
		_label.text = _active
		_time = 0.0
	_time += delta
	var total := FADE_IN + HOLD + FADE_OUT
	if _time >= total:
		_active = ""
		_label.modulate.a = 0.0
		return
	# Fade in, hold, fade out - with a small rise so it arrives rather than appears.
	if _time < FADE_IN:
		_label.modulate.a = _time / FADE_IN
	elif _time < FADE_IN + HOLD:
		_label.modulate.a = 1.0
	else:
		_label.modulate.a = 1.0 - (_time - FADE_IN - HOLD) / FADE_OUT
	var rise := clampf(1.0 - _time / total, 0.0, 1.0) * 8.0
	_label.offset_top = 86.0 + rise
	_label.offset_bottom = 126.0 + rise
