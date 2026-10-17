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

var _info: Label
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


# --- status -----------------------------------------------------------------

func _build_status() -> void:
	_info = _make_label(Vector2(18, 14), INFO_FONT_SIZE, Color("eef1f7"))
	_banner = _make_label(Vector2(18, 44), 17, Color("8ef0a0"))
	_banner.visible = false
	_message = _make_label(Vector2(18, 626), MESSAGE_FONT_SIZE, Color("ffd166"))
	_controls = _make_label(Vector2(18, 678), 15, Color(0.75, 0.79, 0.87))
	_controls.text = "arrows/WASD: move   ·   Z/X or click: rotate   ·   F: turn a starflower/pearl   ·   H: hint   ·   R: new board   ·   T: rotation mode   ·   Esc: quit"


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


func update_from_game(game: RefCounted) -> void:
	if _info == null or game == null:
		return
	var mode := "STRICT" if _is_strict(game) else "FREE"
	var over := "" if int(game.state) == 0 else "   RUN OVER"
	var parts := PackedStringArray()
	parts.append("SCORE %d" % game.score)
	parts.append("LEVEL %d" % game.level)
	parts.append("COMBOS TO NEXT %d" % game.combos_remaining())
	if int(game.ruleset.mode) == int(RulesetScript.Mode.TIMED):
		parts.append("TIME %s" % _clock_text(game.clock, game.max_clock))
	elif int(game.ruleset.mode) == int(RulesetScript.Mode.SURVIVAL):
		parts.append("ROUND %d" % game.round)
		parts.append("FROZEN %d" % game.board.locked_count())
	else:
		parts.append("BOMBS %d" % _count(game.board, Pieces.Kind.BOMB))
	parts.append("PEARLS %d" % _count(game.board, Pieces.Kind.PEARL))
	parts.append("TURN %d" % game.turns)
	parts.append("SEED %d" % game.seed_value)
	parts.append("[%s]%s" % [mode, over])
	_info.text = "   ".join(parts)


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


func _clock_text(clock: float, maximum: float) -> String:
	return "%0.1f/%0.0fs" % [maxf(clock, 0.0), maximum]


func _count(board, kind: int) -> int:
	var total := 0
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_empty(piece) and Pieces.kind_of(piece) == kind:
			total += 1
	return total


func _is_strict(game: RefCounted) -> bool:
	var ruleset: Variant = game.ruleset
	return int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.STRICT)


# --- menu -------------------------------------------------------------------

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
	column.add_child(action_row)

	column.add_child(_title("←/→ mode   ·   ↑/↓ difficulty   ·   Enter start", 15))


func _title(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("eef1f7"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
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


func show_result(summary: Dictionary) -> void:
	_menu.visible = false
	_result.visible = true
	_set_status_visible(false)

	var won: bool = bool(summary.get("won", false))
	_result_title.text = "PERFECT FINISH" if won else "RUN OVER"
	_result_title.add_theme_color_override("font_color", Color("8ef0a0") if won else Color("ff8a80"))

	var lines := PackedStringArray()
	lines.append(_reason_text(str(summary.get("reason", ""))))
	lines.append("%s · %s" % [summary.get("mode", ""), str(summary.get("difficulty", "")).capitalize()])
	lines.append("Score %d      Level %d      Combos %d" % [
		int(summary.get("score", 0)), int(summary.get("level", 1)), int(summary.get("combos", 0)),
	])
	if int(summary.get("rounds", 0)) > 0:
		lines.append("Rounds survived: %d" % int(summary.get("rounds", 0)))
	lines.append("Turns %d      Time %0.1fs" % [
		int(summary.get("turns", 0)), float(summary.get("elapsed", 0.0)),
	])
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
