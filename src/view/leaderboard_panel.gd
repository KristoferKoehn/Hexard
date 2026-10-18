class_name LeaderboardPanel
extends CanvasLayer

## Top scores per table (docs/design.md §9). The storage and ranking already existed in
## ProfileService; this is the missing view.
##
## Opens on the table the run that just ended belongs to, and can be cycled left and
## right through every table that has a score - including one with no scores yet, so a
## first run still explains itself rather than showing nothing.

signal closed

const COLUMNS := ["RANK", "SCORE", "LEVEL", "OUTCOME", "DATE"]
const RulesetScript := preload("res://src/core/ruleset.gd")

var profile: ProfileService

var _root: Control
var _title: Label
var _grid: GridContainer
var _configs: Array[RunConfig] = []
var _index := 0


func _ready() -> void:
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()
	visible = false


## `config` is the table to show first; it is prepended when it has no scores yet.
func open(config: RunConfig) -> void:
	_configs.clear()
	var here := config if config != null else RunConfig.of(RulesetScript.Mode.MARATHON)
	_configs.append(here)
	for table: String in profile.played_tables() if profile != null else []:
		var parts := table.split("|")
		if parts.size() < 2:
			continue
		var other := RunConfig.from_name(parts[0], parts[1])
		if other.key() != here.key():
			_configs.append(other)
	_index = 0
	refresh()
	visible = true


func close() -> void:
	visible = false


func refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		# Detach before freeing: queue_free is deferred, so the old rows would still be
		# children this frame and every refresh would double the list.
		_grid.remove_child(child)
		child.queue_free()

	var config: RunConfig = _configs[_index] if not _configs.is_empty() else null
	_title.text = "LEADERBOARD   %s   (%d of %d)" % [
		config.label() if config != null else "", _index + 1, maxi(_configs.size(), 1),
	]
	for field: String in COLUMNS:
		_grid.add_child(_text(field, 13, NeonStyle.DIM))

	var rows: Array = profile.top_scores_for(config, ProfileService.LEADERBOARD_SIZE) \
		if profile != null and config != null else []
	if rows.is_empty():
		_grid.add_child(_text("no scores on this table yet", 16, NeonStyle.DIM))
		return
	var rank := 0
	for row: Dictionary in rows:
		rank += 1
		var won := bool(row.get("won", false))
		var accent := NeonStyle.AMBER if won else NeonStyle.TEXT
		_grid.add_child(_text("%d." % rank, 16, NeonStyle.DIM))
		_grid.add_child(_text(str(int(row.get("score", 0))), 16, accent))
		_grid.add_child(_text("level %d" % int(row.get("level", 1)), 16, NeonStyle.TEXT))
		_grid.add_child(_text(_outcome(row), 15, NeonStyle.GOOD if won else NeonStyle.DIM))
		_grid.add_child(_text(_date(row), 15, NeonStyle.DIM))


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
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	outer.add_child(header)
	_title = _text("LEADERBOARD", 30, NeonStyle.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var previous := _button("<", Vector2(44, 32))
	previous.pressed.connect(func() -> void: _cycle(-1))
	header.add_child(previous)
	var next := _button(">", Vector2(44, 32))
	next.pressed.connect(func() -> void: _cycle(1))
	header.add_child(next)
	var back := _button("Back  (Esc)", Vector2(140, 32))
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)


func _cycle(step: int) -> void:
	if _configs.size() < 2:
		return
	_index = posmod(_index + step, _configs.size())
	refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				closed.emit()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_cycle(-1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_cycle(1)
				get_viewport().set_input_as_handled()


## Reason codes are internal ("bomb_exploded"); a score table should read as English.
func _outcome(row: Dictionary) -> String:
	if bool(row.get("won", false)):
		return "won"
	var reason := str(row.get("reason", ""))
	return reason.replace("_", " ") if not reason.is_empty() else "-"


func _date(row: Dictionary) -> String:
	var stamp := str(row.get("date", ""))
	return stamp.substr(0, 10) if stamp.length() > 10 else stamp


func _text(content: String, size: int, color: Color) -> Label:
	return NeonStyle.label(content, size, color)


func _button(label: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = minimum
	NeonStyle.style_button(button, 15)
	return button
