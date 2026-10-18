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

var settings: Settings

var _root: Control
var _players: Array[ClipPlayer] = []


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()
	visible = false


func open() -> void:
	if _players.is_empty():
		_rebuild()
	visible = true
	for player: ClipPlayer in _players:
		player.set_active(true)


## Colour patterns can change while the section is open, and the clips draw gems too.
func apply_settings(value: Settings) -> void:
	settings = value
	for player: ClipPlayer in _players:
		player.settings = value
		player.call("apply_settings", value)


func close() -> void:
	visible = false
	for player: ClipPlayer in _players:
		player.set_active(false)
		player.queue_free()
	# Emptied rather than idled: the section leaves nothing behind in the tree, which is the
	# only thing that provably stops it costing frames. Rebuilt on the next open.
	_players.clear()


## Rebuilds the panel from scratch. The clips are freed on close, so the section is
## cheap when hidden and reconstructed when opened.
func _rebuild() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()


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

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var index := 0
	for entry: Dictionary in TutorialLibrary.CLIPS:
		grid.add_child(_card(entry, index))
		index += 1


## One topic, one card: title, the recording centred inside it, and the sentence
## underneath. The card's own rim is what separates topics now that they share a screen.
func _card(entry: Dictionary, index: int = 0) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", NeonStyle.panel_box(18))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)

	var heading := NeonStyle.label(str(entry["title"]), 21, NeonStyle.TEXT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var player := ClipPlayer.new()
	player.clip_id = str(entry["id"])
	player.settings = settings
	_players.append(player)
	# Spread the first plays across the loop so the clips take turns rather than resolving
	# five cascades on the same frame.
	player.start_delay = float(index) * ClipPlayer.STAGGER
	# Centred rather than stretched: the recording keeps its aspect and its framing.
	player.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(player)

	var text := NeonStyle.label(str(entry["text"]), 14, NeonStyle.DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(ClipPlayer.CLIP_SIZE.x, 0)
	column.add_child(text)
	return card


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
