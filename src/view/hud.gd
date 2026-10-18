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
signal leaderboard_pressed
signal achievements_pressed

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
var _free_mode_unlocked := false
var _profile: ProfileService
var _menu_config: RunConfig
var _menu_records: Label
var _menu_lifetime: Label
var _difficulty: Control
var _difficulty_title: Label
var _difficulty_blurb: Label
var _open_mode: int = 0
var _flourish: MenuFlourish
var _result: Control
var _result_title: Label
var _result_body: Label

var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}


func _ready() -> void:
	_build_status()
	_flourish = MenuFlourish.new()
	add_child(_flourish)
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
	_refresh_controls()


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
	column.add_theme_constant_override("separation", 12)
	_menu.add_child(column)

	column.add_child(_title("HEXARD", 64))
	column.add_child(_title("rotate trios · build flowers · close the pearl ring", 18))

	# A mode is a door, not a radio button: picking one opens its difficulty screen, so
	# the menu never has to hold a half-made choice.
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 10)
	column.add_child(mode_row)
	for mode: int in [RulesetScript.Mode.MARATHON, RulesetScript.Mode.TIMED, RulesetScript.Mode.SURVIVAL]:
		# One line only: a mode button is a door, and its best score lives on the
		# leaderboard rather than doubling the height of the menu.
		var button := _menu_button(MODE_LABELS[mode], Vector2(210, 48), 20)
		button.pressed.connect(_on_mode_pressed.bind(mode))
		mode_row.add_child(button)
		_mode_buttons[mode] = button

	_menu_records = _title("", 15)
	column.add_child(_menu_records)
	_menu_lifetime = _title("", 14)
	column.add_child(_menu_lifetime)

	var system_row := HBoxContainer.new()
	system_row.alignment = BoxContainer.ALIGNMENT_CENTER
	system_row.add_theme_constant_override("separation", 10)
	column.add_child(system_row)
	var system := [
		["Achievements", func() -> void: achievements_pressed.emit()],
		["Leaderboard", func() -> void: leaderboard_pressed.emit()],
		["Settings", func() -> void: settings_pressed.emit()],
		["Tutorial", func() -> void: tutorial_pressed.emit()],
	]
	for entry: Array in system:
		var button := _menu_button(str(entry[0]), Vector2(150, 40), 16)
		button.pressed.connect(entry[1])
		system_row.add_child(button)

	column.add_child(_title("1/2/3 pick a mode   ·   Enter replay last   ·   Esc quit", 15))
	_build_difficulty()
	_refresh_menu_records()


## The second step: which difficulty of the chosen mode.
func _build_difficulty() -> void:
	_difficulty = CenterContainer.new()
	(_difficulty as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	(_difficulty as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_difficulty)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_difficulty.add_child(column)

	_difficulty_title = _title("", 52)
	column.add_child(_difficulty_title)
	_difficulty_blurb = _title("", 17)
	column.add_child(_difficulty_blurb)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for difficulty: String in DIFFICULTIES:
		var button := _menu_button("", Vector2(200, 54), 18)
		button.pressed.connect(_on_difficulty_pressed.bind(difficulty))
		row.add_child(button)
		_difficulty_buttons[difficulty] = button

	var back := _menu_button("Back  (Esc)", Vector2(150, 38), 16)
	back.pressed.connect(func() -> void: close_difficulty())
	column.add_child(back)
	_difficulty.visible = false


func _menu_button(text: String, minimum: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	NeonStyle.style_button(button, font_size)
	return button


## A mode button: records the choice, then opens that mode's difficulty screen.
func _on_mode_pressed(mode: int) -> void:
	mode_chosen.emit(mode)
	show_difficulty(mode)


## A difficulty button: the mode is already chosen, so this starts the run.
func _on_difficulty_pressed(difficulty: String) -> void:
	difficulty_chosen.emit(difficulty)
	start_pressed.emit()


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


func show_menu(config: RunConfig) -> void:
	_menu_config = config
	_flourish.visible = true
	_difficulty.visible = false
	_menu.visible = true
	_result.visible = false
	_set_status_visible(false)
	_refresh_menu_records()


## Opens the difficulty step for a mode. The ambient board stays: it is the menu's
## backdrop, and this is still the menu.
func show_difficulty(mode: int) -> void:
	_open_mode = mode
	_menu.visible = false
	_difficulty.visible = true
	_flourish.visible = true
	_difficulty_title.text = MODE_LABELS.get(mode, "")
	_difficulty_blurb.text = MODE_BLURBS.get(mode, "")
	for difficulty: String in DIFFICULTIES:
		if _difficulty_buttons.has(difficulty):
			(_difficulty_buttons[difficulty] as Button).text = "%s  ·  %s" % [
				difficulty.capitalize(), _best_text(mode, difficulty),
			]


func close_difficulty() -> void:
	_difficulty.visible = false
	_menu.visible = true
	_refresh_menu_records()


func is_difficulty_open() -> bool:
	return _difficulty != null and _difficulty.visible


func open_mode() -> int:
	return _open_mode


## Kept for the controller, which tracks the selected run: it only refreshes the
## figures, because visibility now belongs to show_menu and show_difficulty.
func highlight_menu(config: RunConfig) -> void:
	_menu_config = config
	_refresh_menu_records()


func show_playing() -> void:
	if _flourish != null:
		_flourish.visible = false
	_menu.visible = false
	if _difficulty != null:
		_difficulty.visible = false
	_result.visible = false
	_set_status_visible(true)


## The T hint advertises a mode that is supposed to be a secret, so it follows the
## unlock rather than always being printed.
## The menu reports on the profile, so it needs it. One instance is kept alive by Main
## for the whole session, so no refresh plumbing is needed when it changes.
## Colour patterns are an accessibility setting, not decoration: when they are off the
## menu backdrop stops showing them too.
func set_glyphs_enabled(enabled: bool) -> void:
	if _flourish != null:
		_flourish.show_glyphs = enabled


func set_profile(value: ProfileService) -> void:
	_profile = value
	_refresh_menu_records()


## Best score, best level, run count and achievements for the table the menu is about to
## launch. A menu showing only labels says nothing about your own history with the game.
func _refresh_menu_records() -> void:
	if _menu_records == null:
		return
	# Titles are cheap to reassert, and a button that relies on build-time text alone is
	# a button that can be painted blank.
	for mode: int in _mode_buttons:
		(_mode_buttons[mode] as Button).text = MODE_LABELS.get(mode, "")
	if _profile == null:
		_menu_records.text = ""
		return
	var totals: Dictionary = _profile.totals
	_menu_records.text = "%d runs   ·   %d wins   ·   %d of %d achievements" % [
		int(totals.get("games", 0)), int(totals.get("wins", 0)),
		_profile.achievement_count(), Achievements.count(),
	]
	if _menu_lifetime != null:
		_menu_lifetime.text = "best level %d   ·   %d gems cleared   ·   %d bombs defused" % [
			int(totals.get("best_level", 0)), int(totals.get("cleared", 0)),
			int(totals.get("bombs_defused", 0)),
		]


## The best score for a table, or a dash when it has never been played.
func _best_text(mode: int, difficulty: String) -> String:
	if _profile == null:
		return "—"
	var best: Dictionary = _profile.best_for(RunConfig.mode_name_of(mode), difficulty)
	var score := int(best.get("score", 0))
	return _thousands(score) if score > 0 else "—"


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out


func set_free_mode_unlocked(unlocked: bool) -> void:
	_free_mode_unlocked = unlocked
	_refresh_controls()


func _refresh_controls() -> void:
	if _controls == null:
		return
	var parts := PackedStringArray([
		"arrows/WASD  move", "Z/X or click  rotate", "F/Space  select special",
		"H  hint", "R  new board",
	])
	if _free_mode_unlocked:
		parts.append("T  rotation mode")
	parts.append("esc  quit")
	_controls.text = "    ·    ".join(parts)


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
	var board := Button.new()
	board.text = "Leaderboard"
	board.custom_minimum_size = Vector2(160, 42)
	board.pressed.connect(func() -> void: leaderboard_pressed.emit())
	buttons.add_child(board)
	var menu_button := Button.new()
	menu_button.text = "Menu  (M)"
	menu_button.custom_minimum_size = Vector2(150, 42)
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(menu_button)


func show_result(summary: RunSummary, unlocked: Array[String] = []) -> void:
	if _flourish != null:
		_flourish.visible = false
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
	if not unlocked.is_empty():
		lines.append("")
		lines.append("★  Achieved: " + ", ".join(unlocked))
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
