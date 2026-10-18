class_name Hud
extends CanvasLayer

## Everything the player sees outside the board: the per-mode status line, the
## mode/difficulty menu, and the end-of-run summary.
##
## The HUD owns presentation only — it emits signals and the controller decides
## what a choice means (docs/design.md §10.1).

signal mode_chosen(mode: int)
signal difficulty_chosen(difficulty: String)
signal start_pressed
signal tutorial_pressed
signal settings_pressed
signal restart_pressed
signal menu_pressed

const RulesetScript := preload("res://src/core/ruleset.gd")
const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")

const INFO_FONT_SIZE := 22
const MESSAGE_FONT_SIZE := 18


const MODE_LABELS := {
	RulesetScript.Mode.MARATHON: "Marathon",
	RulesetScript.Mode.TIMED: "Timed",
	RulesetScript.Mode.SURVIVAL: "Survival",
}
const MODE_BLURBS := {
	RulesetScript.Mode.MARATHON: "Endless. Build flowers, dodge bombs, aim for the pearl ring.",
	RulesetScript.Mode.TIMED: "Same board, but the clock only refills when you clear.",
	RulesetScript.Mode.SURVIVAL: "No refills. Frozen leftovers pile up: clear the board or suffocate.",
}
const DIFFICULTIES := ["easy", "normal", "hard"]

var _info: RichTextLabel
# The status row is a bbcode string that is re-parsed and re-laid-out on every
# assignment, so identical frames are skipped rather than rebuilt.
var _last_status := ""
var _message: Label
var _controls: Label
var _banner: Label
var _menu: Control
var _menu_blurb: Label
var _result: Control
var _result_title: Label
var _result_body: Label

var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}


func _ready() -> void:
	_build_status()
	_build_menu()
	_build_result()
	# Every button we built gets the neon treatment in one place, so new buttons
	# are themed automatically instead of each builder repeating five overrides.
	_neonify(self)


func _neonify(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			_apply_neon(child)
		_neonify(child)


func _apply_neon(button: Button) -> void:
	NeonStyle.style_button(button)






# --- status -----------------------------------------------------------------

func _build_status() -> void:
	# Rich text so the numbers can carry the accent colour while the labels stay
	# quiet — the fastest way to read a score row is by scanning the figures.
	_info = _make_rich(Vector2(18, 10), INFO_FONT_SIZE)
	_banner = _make_label(Vector2(18, 44), 17, NeonStyle.GOOD)
	_banner.visible = false
	_message = _make_label(Vector2(18, 632), MESSAGE_FONT_SIZE, NeonStyle.AMBER)
	_controls = _make_label(Vector2(18, 684), 15, NeonStyle.DIM)
	_controls.text = "arrows/WASD  move    ·    Z/X or click  rotate    ·    F/Space  select special    ·    H  hint    ·    R  new board    ·    T  rotation mode    ·    esc  quit"


func _make_rich(position: Vector2, font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.position = position
	label.size = Vector2(1244, font_size + 16)
	label.bbcode_enabled = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Grow with the text: clipping a score row is much worse than a wide control.
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", NeonStyle.TEXT)
	add_child(label)
	return label


## One labelled figure: quiet label, accented value.
static func _stat(name: String, value: String, accent: Color = NeonStyle.ACCENT) -> String:
	return "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [
		NeonStyle.DIM.to_html(false), name, accent.to_html(false), value,
	]


func _make_label(position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position
	# Labels must never eat input: a wide status line would otherwise swallow
	# mouse clicks over the bottom of the board.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


## Renders the status bar from a snapshot. `Hud.format_status()` is static and pure
## so the row can be unit-tested without a scene or a running game.
func update_from_game(model: HudModel) -> void:
	if _info == null or model == null:
		return
	var text := format_status(model)
	# The row is a bbcode string that is re-parsed and re-laid-out on assignment, so
	# identical frames are skipped rather than rebuilt.
	if text == _last_status:
		return
	_last_status = text
	_info.text = text


static func format_status(model: HudModel) -> String:
	var parts := PackedStringArray()
	parts.append(_stat("SCORE", str(model.score)))
	parts.append(_stat("LEVEL", str(model.level)))
	parts.append(_stat("COMBOS TO NEXT", str(model.combos_remaining)))
	if model.mode == int(RulesetScript.Mode.TIMED):
		parts.append(_stat("TIME", _clock_text(model.clock, model.max_clock)))
	elif model.mode == int(RulesetScript.Mode.SURVIVAL):
		parts.append(_stat("ROUND", str(model.round)))
		parts.append(_stat("FROZEN", str(model.frozen)))
	else:
		parts.append(_stat("BOMBS", str(model.bombs)))
	parts.append(_stat("PEARLS", str(model.pearls)))
	parts.append(_stat("TURN", str(model.turn)))
	parts.append(_stat("SEED", str(model.seed_value), NeonStyle.DIM))
	var tag_color := NeonStyle.ACCENT if model.strict else NeonStyle.AMBER
	var tail := "[color=#%s][%s][/color]" % [tag_color.to_html(false), "STRICT" if model.strict else "FREE"]
	if model.finished:
		tail += "  [color=#%s]RUN OVER[/color]" % NeonStyle.AMBER.to_html(false)
	parts.append(tail)
	return "     ".join(parts)

func set_message(text: String) -> void:
	if _message != null:
		_message.text = text


## The tutorial's instruction banner, above the board.
func set_banner(text: String) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.visible = text.length() > 0


## Current banner text (used by the view smoke test).
func banner_text() -> String:
	return _banner.text if _banner != null else ""


static func _clock_text(clock: float, maximum: float) -> String:
	return "%0.1f/%0.0fs" % [maxf(clock, 0.0), maximum]


func _build_menu() -> void:
	_menu = CenterContainer.new()
	(_menu as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	(_menu as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_menu)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_menu.add_child(column)

	column.add_child(_title("HEXARD", 64))
	column.add_child(_title("rotate trios · build flowers · close the pearl ring", 18))

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	column.add_child(mode_row)
	var mode_group := ButtonGroup.new()
	for mode: int in [RulesetScript.Mode.MARATHON, RulesetScript.Mode.TIMED, RulesetScript.Mode.SURVIVAL]:
		var button := _toggle(MODE_LABELS[mode], mode_group)
		button.pressed.connect(_on_mode_button.bind(mode))
		mode_row.add_child(button)
		_mode_buttons[mode] = button

	_menu_blurb = _title("", 16)
	column.add_child(_menu_blurb)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	column.add_child(difficulty_row)
	difficulty_row.add_child(_title("difficulty:", 16))
	var difficulty_group := ButtonGroup.new()
	for difficulty: String in DIFFICULTIES:
		var button := _toggle(difficulty.capitalize(), difficulty_group)
		button.pressed.connect(_on_difficulty_button.bind(difficulty))
		difficulty_row.add_child(button)
		_difficulty_buttons[difficulty] = button

	var start := Button.new()
	start.text = "Start  (Enter)"
	start.custom_minimum_size = Vector2(220, 44)
	start.pressed.connect(func() -> void: start_pressed.emit())

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 10)
	action_row.add_child(start)
	var tutorial := Button.new()
	tutorial.text = "Tutorial"
	tutorial.custom_minimum_size = Vector2(140, 44)
	tutorial.pressed.connect(func() -> void: tutorial_pressed.emit())
	action_row.add_child(tutorial)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(140, 44)
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	action_row.add_child(settings_button)
	column.add_child(action_row)

	column.add_child(_title("←/→ mode   ·   ↑/↓ difficulty   ·   Enter start", 15))


func _title(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", NeonStyle.TEXT if font_size <= 20 else NeonStyle.ACCENT)
	label.add_theme_color_override("font_outline_color", Color(0.09, 0.60, 0.76, 0.85))
	label.add_theme_constant_override("outline_size", 5 if font_size <= 20 else 9)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(150, 40)
	return button


func _on_mode_button(mode: int) -> void:
	mode_chosen.emit(mode)


func _on_difficulty_button(difficulty: String) -> void:
	difficulty_chosen.emit(difficulty)


func show_menu(mode: int, difficulty: String) -> void:
	_menu.visible = true
	_result.visible = false
	_set_status_visible(false)
	if _mode_buttons.has(mode):
		(_mode_buttons[mode] as Button).button_pressed = true
	if _difficulty_buttons.has(difficulty):
		(_difficulty_buttons[difficulty] as Button).button_pressed = true
	_menu_blurb.text = MODE_BLURBS.get(mode, "")


func highlight_menu(mode: int, difficulty: String) -> void:
	if _mode_buttons.has(mode):
		(_mode_buttons[mode] as Button).button_pressed = true
	if _difficulty_buttons.has(difficulty):
		(_difficulty_buttons[difficulty] as Button).button_pressed = true
	_menu_blurb.text = MODE_BLURBS.get(mode, "")


func show_playing() -> void:
	_menu.visible = false
	_result.visible = false
	_set_status_visible(true)


func _set_status_visible(visible_now: bool) -> void:
	_info.visible = visible_now
	_message.visible = visible_now
	_controls.visible = visible_now
	if not visible_now:
		_banner.visible = false


# --- result -----------------------------------------------------------------

func _build_result() -> void:
	_result = CenterContainer.new()
	(_result as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	(_result as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_result)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_result.add_child(column)

	_result_title = _title("", 56)
	column.add_child(_result_title)
	_result_body = _title("", 20)
	column.add_child(_result_body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var again := Button.new()
	again.text = "Play again  (R)"
	again.custom_minimum_size = Vector2(170, 42)
	again.pressed.connect(func() -> void: restart_pressed.emit())
	buttons.add_child(again)
	var menu_button := Button.new()
	menu_button.text = "Menu  (M)"
	menu_button.custom_minimum_size = Vector2(150, 42)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu_button)


func show_result(summary: RunSummary) -> void:
	_menu.visible = false
	_result.visible = true
	_set_status_visible(false)

	var won := summary.won
	_result_title.text = "PERFECT FINISH" if won else "RUN OVER"
	_result_title.add_theme_color_override("font_color", Color("8ef0a0") if won else Color("ff8a80"))

	var lines := PackedStringArray()
	lines.append(_reason_text(summary.reason))
	lines.append("%s · %s" % [summary.mode, summary.difficulty.capitalize()])
	lines.append("Score %d      Level %d      Combos %d" % [
		summary.score, summary.level, summary.combos,
	])
	if summary.rounds > 0:
		lines.append("Rounds survived: %d" % summary.rounds)
	lines.append("Turns %d      Time %0.1fs" % [summary.turns, summary.elapsed])
	_result_body.text = "\n".join(lines)


func _reason_text(reason: String) -> String:
	match reason:
		"pearl_ring":
			return "A ring of six black pearls. The grand one."
		"pearl_cluster":
			return "Three black pearls closed together."
		"board_cleared":
			return "The board is empty."
		"rounds_survived":
			return "Fifty rounds survived."
		"bomb_exploded":
			return "A bomb went off."
		"time_out":
			return "The clock ran out."
		"all_locked":
			return "Every tile froze."
		_:
			return reason.capitalize()
