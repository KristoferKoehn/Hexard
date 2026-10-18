class_name SettingsPanel
extends CanvasLayer

## The settings screen (docs/design.md §8, §9): audio levels, juice toggles, key
## rebinding and a read-only records summary. Neon styling to match the board and
## the HUD.

signal closed
signal changed

const SettingsScript := preload("res://src/core/settings.gd")
const ProfileScript := preload("res://src/core/profile_service.gd")

var settings: Settings
var profile: ProfileService

var _root: Control
var _volume_buttons: Dictionary = {}
var _toggle_buttons: Dictionary = {}
var _binding_buttons: Dictionary = {}
var _records: Label
var _armed_action := ""

func _ready() -> void:
	layer = 2
	_root = Control.new()
	(_root as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	(_root as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	_build()
	visible = false

func open() -> void:
	_armed_action = ""
	_refresh()
	visible = true

func close() -> void:
	_armed_action = ""
	visible = false

# --- construction -----------------------------------------------------------

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

	# The way out is pinned above the scroll: it must never be the thing that scrolls
	# off screen, which is exactly what happened when the panel overflowed 720p.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	outer.add_child(header)
	var title := _heading("SETTINGS", 34, NeonStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := _button("Back  (Esc)", Vector2(150, 36))
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Rebind capture moves focus between rows, so keep the focused row in view.
	scroll.follow_focus = true
	outer.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_heading("audio", 16, NeonStyle.DIM))
	column.add_child(_volume_row("Master", "master_volume"))
	column.add_child(_volume_row("Effects", "sfx_volume"))
	column.add_child(_toggle_row("Muted", "muted"))

	column.add_child(_heading("juice", 16, NeonStyle.DIM))
	column.add_child(_toggle_row("Screen shake", "screen_shake"))
	column.add_child(_toggle_row("Flashes", "flashes"))
	column.add_child(_toggle_row("Reduced motion", "reduced_motion"))
	column.add_child(_toggle_row("Colour patterns", "colour_patterns"))

	column.add_child(_heading("controls  ·  click a key to rebind", 16, NeonStyle.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for action: String in SettingsScript.ACTION_LABELS:
		var label := _text(SettingsScript.ACTION_LABELS[action], 16, NeonStyle.TEXT)
		label.custom_minimum_size = Vector2(250, 0)
		grid.add_child(label)
		var button := _button("", Vector2(190, 30))
		button.pressed.connect(_on_binding_pressed.bind(action))
		grid.add_child(button)
		_binding_buttons[action] = button

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var reset := _button("Reset controls", Vector2(180, 36))
	reset.pressed.connect(_on_reset_controls)
	actions.add_child(reset)

	_records = _text("", 15, NeonStyle.DIM)
	_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.custom_minimum_size = Vector2(560, 0)
	_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_records)

func _heading(text: String, size: int, color: Color) -> Label:
	return _text(text, size, color)

func _text(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(label: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = minimum
	NeonStyle.style_button(button, 16)
	return button

func _volume_row(label_text: String, setting: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _text(label_text, 16, NeonStyle.TEXT)
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var down := _button("-", Vector2(34, 30))
	down.pressed.connect(_on_volume.bind(setting, -0.1))
	row.add_child(down)
	var value := _text("", 16, NeonStyle.ACCENT)
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var up := _button("+", Vector2(34, 30))
	up.pressed.connect(_on_volume.bind(setting, 0.1))
	row.add_child(up)
	_volume_buttons[setting] = value
	return row

func _toggle_row(label_text: String, setting: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _text(label_text, 16, NeonStyle.TEXT)
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var button := _button("", Vector2(120, 30))
	button.pressed.connect(_on_toggle.bind(setting))
	row.add_child(button)
	_toggle_buttons[setting] = button
	return row

# --- interaction ------------------------------------------------------------

func _on_volume(setting: String, delta: float) -> void:
	if settings == null:
		return
	if setting == "master_volume":
		settings.master_volume = clampf(settings.master_volume + delta, 0.0, 1.0)
	else:
		settings.sfx_volume = clampf(settings.sfx_volume + delta, 0.0, 1.0)
	_after_change()

func _on_toggle(setting: String) -> void:
	if settings == null:
		return
	match setting:
		"muted":
			settings.muted = not settings.muted
		"screen_shake":
			settings.screen_shake = not settings.screen_shake
		"flashes":
			settings.flashes = not settings.flashes
		"reduced_motion":
			settings.reduced_motion = not settings.reduced_motion
		"colour_patterns":
			settings.colour_patterns = not settings.colour_patterns
	_after_change()

func _on_binding_pressed(action: String) -> void:
	# Arm the row: the next key press becomes the binding, Esc cancels.
	_armed_action = action
	_refresh()

func _on_reset_controls() -> void:
	if settings != null:
		settings.reset_bindings()
		after_change_only()

func after_change_only() -> void:
	_armed_action = ""
	_refresh()
	changed.emit()

func _after_change() -> void:
	_armed_action = ""
	_refresh()
	changed.emit()

## Rebinding captures keys here so the controller never has to know about it.
func _input(event: InputEvent) -> void:
	if not visible or _armed_action == "":
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := int(key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	get_viewport().set_input_as_handled()
	if code == KEY_ESCAPE:
		_armed_action = ""
		_refresh()
		return
	settings.set_binding(_armed_action, [code])
	_armed_action = ""
	_refresh()
	changed.emit()

func _refresh() -> void:
	if settings == null:
		return
	for setting: String in _volume_buttons:
		var value: float = settings.master_volume if setting == "master_volume" else settings.sfx_volume
		(_volume_buttons[setting] as Label).text = "%d%%" % roundi(value * 100.0)
	for setting: String in _toggle_buttons:
		var on_state := false
		match setting:
			"muted":
				on_state = settings.muted
			"screen_shake":
				on_state = settings.screen_shake
			"flashes":
				on_state = settings.flashes
			"reduced_motion":
				on_state = settings.reduced_motion
			"colour_patterns":
				on_state = settings.colour_patterns
		# Reduced motion overrides the others, so say so instead of lying.
		var overridden := setting != "reduced_motion" and settings.reduced_motion
		var button := _toggle_buttons[setting] as Button
		button.text = ("overridden" if overridden else ("On" if on_state else "Off"))
		button.add_theme_color_override("font_color", NeonStyle.ACCENT if on_state else NeonStyle.DIM)
	for action: String in _binding_buttons:
		var button := _binding_buttons[action] as Button
		if action == _armed_action:
			button.text = "press a key…"
			button.add_theme_color_override("font_color", Color("ffd166"))
			continue
		button.add_theme_color_override("font_color", NeonStyle.TEXT)
		var names := PackedStringArray()
		for code: int in settings.keys_for(action):
			names.append(SettingsScript.key_name(code))
		button.text = " / ".join(names) if names.size() > 0 else "unbound"
	_records.text = _records_text()

func _records_text() -> String:
	if profile == null:
		return ""
	var totals: Dictionary = profile.totals
	var lines := PackedStringArray()
	lines.append(
		"records: %d games  ·  %d wins  ·  best level %d  ·  %d points  ·  %d combos"
		% [int(totals["games"]), int(totals["wins"]), int(totals["best_level"]),
			int(totals["score"]), int(totals["combos"])]
	)
	lines.append("achievements: %d of %d" % [profile.achievement_count(), Achievements.count()])
	for table: String in profile.played_tables():
		var parts := table.split("|")
		var best: Dictionary = profile.best_for(parts[0], parts[1])
		lines.append("  %s %s — best %d at level %d" % [parts[0], parts[1], int(best["score"]), int(best["level"])])
	return "\n".join(lines)
