class_name AchievementsPanel
extends CanvasLayer

## The full achievement list: everything earnable, what each asks for, and whether it
## has been earned. Reached from the settings screen.
##
## Laid out like the settings panel and for the same reason: the list is taller than
## 720p, so the body scrolls and the way out is pinned outside it.

signal closed
signal reset_pressed

var profile: ProfileService

var _root: Control
var _rows: VBoxContainer
var _count: Label
var _reset: Button
var _armed := false
var _disarm_timer := 0.0


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()
	visible = false


func open() -> void:
	_disarm()
	refresh()
	visible = true


func close() -> void:
	_disarm()
	visible = false


func refresh() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		# Detach before freeing: queue_free() is deferred, so the old rows would still
		# be children this frame and the list would double every refresh.
		_rows.remove_child(child)
		child.queue_free()
	var earned: Dictionary = profile.achievements if profile != null else {}
	for row: Dictionary in Achievements.all_with_state(earned):
		_rows.add_child(_row(row))
	if _count != null:
		_count.text = "%d of %d" % [earned.size(), Achievements.count()]


func _build() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", NeonStyle.panel_box(30))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 56
	panel.offset_top = 22
	panel.offset_right = -56
	panel.offset_bottom = -22
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	outer.add_child(header)
	var title := _text("ACHIEVEMENTS", 32, NeonStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_count = _text("", 17, NeonStyle.DIM)
	header.add_child(_count)

	# Deliberately tiny: wiping the record is rare, so it should not compete with
	# anything, and it arms on the first press rather than acting on a misclick.
	_reset = _button("Reset", Vector2(78, 26), 13)
	_reset.add_theme_color_override("font_color", NeonStyle.DIM)
	_reset.pressed.connect(_on_reset)
	header.add_child(_reset)

	var back := _button("Back  (Esc)", Vector2(140, 32), 15)
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_disarm()
		closed.emit()
		get_viewport().set_input_as_handled()


func _row(data: Dictionary) -> Control:
	var earned := bool(data["earned"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)

	var mark := _text("★" if earned else "·", 20,
		NeonStyle.AMBER if earned else NeonStyle.DIM)
	mark.custom_minimum_size = Vector2(22, 0)
	line.add_child(mark)

	var title := _text(str(data["title"]), 18,
		NeonStyle.AMBER if earned else NeonStyle.TEXT)
	title.custom_minimum_size = Vector2(260, 0)
	line.add_child(title)

	var hint := _text(str(data["hint"]), 15, NeonStyle.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(hint)
	return line


func _on_reset() -> void:
	if not _armed:
		_armed = true
		_disarm_timer = 3.0
		_reset.text = "Sure?"
		_reset.add_theme_color_override("font_color", NeonStyle.AMBER)
		return
	_disarm()
	reset_pressed.emit()


func _disarm() -> void:
	_armed = false
	_disarm_timer = 0.0
	if _reset != null:
		_reset.text = "Reset"
		_reset.add_theme_color_override("font_color", NeonStyle.DIM)


func _process(delta: float) -> void:
	if not _armed:
		return
	_disarm_timer -= delta
	if _disarm_timer <= 0.0:
		_disarm()


func _text(content: String, size: int, color: Color) -> Label:
	return NeonStyle.label(content, size, color)


func _button(label: String, minimum: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = minimum
	NeonStyle.style_button(button, font_size)
	return button
