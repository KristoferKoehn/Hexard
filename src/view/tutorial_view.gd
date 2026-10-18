class_name TutorialView
extends CanvasLayer

## The tutorial section: five looping demonstrations with their text underneath.
##
## Deliberately not interactive. The previous version rigged a board and watched the
## player's moves, which read as a series of disconnected puzzle boards; a demonstration
## that simply shows the thing happening, next to a sentence about it, is both shorter and
## clearer. Each panel is the real board replaying a canned move, so nothing here can
## disagree with the game.

signal closed

var _root: Control


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()
	visible = false


func open() -> void:
	visible = true


func close() -> void:
	visible = false


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
	var title := NeonStyle.label("TUTORIAL", 32, NeonStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "Back  (Esc)"
	back.custom_minimum_size = Vector2(140, 32)
	NeonStyle.style_button(back, 15)
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for entry: Dictionary in TutorialLibrary.CLIPS:
		rows.add_child(_row(entry))


## One demonstration: the recording on the left, the words underneath it.
func _row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)

	var player := ClipPlayer.new()
	player.clip_id = str(entry["id"])
	column.add_child(player)

	var text := NeonStyle.label(str(entry["text"]), 15, NeonStyle.DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(ClipPlayer.CLIP_SIZE.x, 0)
	column.add_child(text)

	var heading := NeonStyle.label(str(entry["title"]), 22, NeonStyle.TEXT)
	heading.custom_minimum_size = Vector2(360, 0)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(heading)
	return row


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
