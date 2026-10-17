extends Node2D

## Dev controller: owns the Game, moves the cursor, feeds input to the rules
## core and hands results to the view. Rules live in src/core (docs/design.md
## Ãƒâ€šÃ‚Â§10.1); this file is the thin layer that also drives the menu, the clock and
## the end-of-run screen.

const HexGrid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const TutorialScript := preload("res://src/core/tutorial.gd")

enum Screen { MENU, PLAYING, RESULT }

@onready var board_view: BoardView = $BoardView
@onready var hud: Hud = $Hud

var game: Game
var cursor_vertex := 0
var screen: Screen = Screen.MENU
var selected_mode: int = RulesetScript.Mode.MARATHON
var selected_difficulty := "normal"
var tutorial: Tutorial = null
## Set when the run ended mid-animation (a bomb going off), so the summary panel
## waits for the shockwave instead of cutting it off.
var _pending_result := false
## What the HUD shows: it lags game.score until each cascade step lands.
var _displayed_score := 0


func _ready() -> void:
	hud.mode_chosen.connect(_on_mode_chosen)
	hud.difficulty_chosen.connect(_on_difficulty_chosen)
	hud.start_pressed.connect(_on_start_pressed)
	hud.tutorial_pressed.connect(_on_tutorial_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.menu_pressed.connect(_on_menu_pressed)
	hud.show_menu(selected_mode, selected_difficulty)
	# A cleared group landing in the animation rolls the score up step by step.
	board_view.clear_scored.connect(_on_clear_scored)


func _process(delta: float) -> void:
	if screen != Screen.PLAYING or game == null:
		return
	# Only Timed mode consumes time, but the clock display still needs updating.
	game.tick(delta)
	# The score rolls up clear by clear; once the board has settled, trust the
	# core again so bonuses outside a clear group (round bonus, buys) land too.
	if board_view.is_settled() and _displayed_score != game.score:
		_displayed_score = game.score
	hud.update_from_game(game, _displayed_score)
	if game.state == GameScript.State.FINISHED:
		# A countdown ending has nothing to play out; a bomb does.
		if _pending_result and board_view.is_settled():
			_pending_result = false
			_enter_result()
		elif not _pending_result:
			_enter_result()


# --- run lifecycle ----------------------------------------------------------

## Starts a run. A negative seed picks a fresh random one.
func start_run(run_mode: int, difficulty: String, run_seed: int = -1) -> void:
	selected_mode = run_mode
	selected_difficulty = difficulty
	tutorial = null
	var seed_value := run_seed if run_seed >= 0 else randi()
	game = GameScript.new(seed_value, RulesetScript.for_run(run_mode, difficulty))
	_enter_playing()
	hud.set_message(
		"%s Ãƒâ€šÃ‚Â· %s ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â seed %d%s"
		% [game.mode_name(), difficulty, seed_value, "  Ãƒâ€šÃ‚Â·  the clock is running" if run_mode == RulesetScript.Mode.TIMED else ""]
	)


## The scripted tutorial: its own game, its own board rigs (docs/design.md Ãƒâ€šÃ‚Â§7.4).
func start_tutorial() -> void:
	tutorial = TutorialScript.new()
	game = tutorial.game
	_enter_playing()
	_sync_tutorial()


func _sync_tutorial() -> void:
	if tutorial == null:
		hud.set_banner("")
		return
	# The tutorial rigs the board in place, so the view has to re-read it.
	board_view.sync_from_game()
	if tutorial.complete:
		hud.set_banner("Tutorial complete ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â press M for the menu, or R to keep playing this board")
		hud.set_message("you have seen every mechanic")
		return
	hud.set_banner(
		"Tutorial %d/%d Ãƒâ€šÃ‚Â· %s ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â %s"
		% [tutorial.step_number(), tutorial.step_count(), tutorial.step_title(), tutorial.instruction()]
	)
	var target: int = tutorial.hint_vertex()
	select_vertex(target)
	board_view.hint_vertex = target
	board_view.queue_redraw()


func _on_tutorial_pressed() -> void:
	start_tutorial()


## Restarts the current mode with a new seed (the R key).
func new_game(seed_value: int) -> void:
	if game == null:
		start_run(selected_mode, selected_difficulty, seed_value)
		return
	tutorial = null
	var ruleset := RulesetScript.for_run(int(game.ruleset.mode), game.ruleset.difficulty)
	ruleset.rotation_mode = int(game.ruleset.rotation_mode)
	game = GameScript.new(seed_value, ruleset)
	_enter_playing()
	hud.set_message("new board, seed %d" % seed_value)


func _enter_playing() -> void:
	screen = Screen.PLAYING
	cursor_vertex = 0
	_pending_result = false
	_displayed_score = game.score
	board_view.set_game(game)
	board_view.hint_vertex = -1
	board_view.hover_cell = Vector2i(-1, -1)
	_refresh_cursor()
	if tutorial == null:
		hud.set_banner("")
	hud.show_playing()
	hud.update_from_game(game, _displayed_score)


func _enter_result() -> void:
	screen = Screen.RESULT
	board_view.hint_vertex = -1
	hud.show_result(game.summary())


## Which screen is up, as a string (used by the view smoke test).
func screen_name() -> String:
	match screen:
		Screen.MENU:
			return "menu"
		Screen.RESULT:
			return "result"
		_:
			return "playing"


func _on_mode_chosen(mode: int) -> void:
	selected_mode = mode
	hud.highlight_menu(selected_mode, selected_difficulty)


func _on_difficulty_chosen(difficulty: String) -> void:
	selected_difficulty = difficulty
	hud.highlight_menu(selected_mode, selected_difficulty)


func _on_start_pressed() -> void:
	start_run(selected_mode, selected_difficulty)


func _on_restart_pressed() -> void:
	start_run(selected_mode, selected_difficulty)


func _on_menu_pressed() -> void:
	screen = Screen.MENU
	game = null
	tutorial = null
	board_view.set_game(null)
	hud.set_banner("")
	hud.show_menu(selected_mode, selected_difficulty)


## A cascade step landed: roll the displayed score forward by what it was worth.
func _on_clear_scored(amount: int) -> void:
	_displayed_score += amount
	if game != null:
		hud.update_from_game(game, _displayed_score)


# --- actions (also the programmatic API the smoke test drives) --------------

func play_move(direction: int) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	board_view.hint_vertex = -1
	var result := game.rotate(cursor_vertex, direction)
	var turn := "CW" if direction == GameScript.CLOCKWISE else "CCW"

	if not result.committed:
		board_view.show_result(result)   # a refused spin still turns out and back
		var guidance := ""
		if result.rejected_reason.begins_with("no match"):
			guidance = "  ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the cursor is grey here; press H to find a spin that clears"
		hud.set_message("%s: %s%s" % [turn, result.rejected_reason, guidance])
		_refresh_cursor()
		return

	_apply(result, turn)


## Turns the starflower or pearl under the cursor, if there is one.
func use_special(direction: int = GameScript.CLOCKWISE) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	for cell: Vector2i in HexGrid.vertices()[cursor_vertex]:
		if _special_at(cell) != Vector2i(-1, -1):
			play_piece_move(cell, direction)
			return
	hud.set_message("no starflower or pearl under the cursor")


## The cell itself if it holds a piece that can be turned on its own.
func _special_at(cell: Vector2i) -> Vector2i:
	var piece: int = game.board.get_piece(cell)
	if Pieces.is_starflower(piece) or Pieces.is_pearl(piece):
		return cell
	return Vector2i(-1, -1)


func play_piece_move(cell: Vector2i, direction: int) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	board_view.hint_vertex = -1
	var result := game.rotate_piece(cell, direction)
	if not result.committed:
		hud.set_message("piece: %s" % result.rejected_reason)
		return
	_apply(result, "turn piece")


## Shared presentation tail for any committed move.
func _apply(result: MoveResult, label: String) -> void:
	board_view.show_result(result)
	_refresh_cursor()
	hud.update_from_game(game, _displayed_score)

	if game.state == GameScript.State.FINISHED:
		if board_view.is_animating():
			# Let the explosion finish; the summary waits for the shockwave.
			_pending_result = true
			hud.set_message("the bomb went off")
			return
		_enter_result()
		return

	if tutorial != null:
		if tutorial.evaluate(result):
			_sync_tutorial()
		return

	var parts := PackedStringArray([label])
	if result.cleared_count > 0:
		parts.append("cleared %d  +%d" % [result.cleared_count, result.score])
		if result.cascades > 1:
			parts.append("cascade x%d" % result.cascades)
		if result.combos > 1:
			parts.append("%d combos" % result.combos)
	else:
		parts.append("no clear (position kept)")
	if result.promotions.size() > 0:
		parts.append("promoted x%d" % result.promotions.size())
	if result.bombs_defused > 0:
		parts.append("bomb defused x%d" % result.bombs_defused)
	if result.bombs_ticked.size() > 0:
		parts.append("bomb ticking")
	if result.round_ended:
		parts.append("round %d ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â +%d" % [result.round_reached, result.round_bonus])
	if result.level_up:
		parts.append("LEVEL %d" % result.new_level)
	if result.shuffled:
		parts.append("board was dead ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â shuffled")
	hud.set_message("  Ãƒâ€šÃ‚Â·  ".join(parts))


func move_cursor(direction: Vector2) -> void:
	if game == null:
		return
	cursor_vertex = HexGrid.step_vertex(cursor_vertex, direction, board_view.cell_size)
	_refresh_cursor()


## Jumps the cursor to a specific rotation vertex (hint and tests use this).
func select_vertex(index: int) -> void:
	cursor_vertex = clampi(index, 0, HexGrid.vertices().size() - 1)
	_refresh_cursor()


## `viewport_point` is screen space; picking must happen in board space.
func snap_cursor_to(viewport_point: Vector2) -> void:
	if game == null or board_view == null:
		return
	cursor_vertex = board_view.vertex_at(board_view.to_local(viewport_point))
	_refresh_cursor()


## Keeps the view in sync, including whether a spin at the cursor can clear.
func _refresh_cursor() -> void:
	board_view.cursor_vertex = cursor_vertex
	board_view.cursor_legal = game != null and game.has_legal_spin(cursor_vertex)
	board_view.queue_redraw()


func show_hint() -> void:
	if game == null or screen != Screen.PLAYING:
		return
	var legal: Array = game.find_legal_rotations()
	if legal.is_empty():
		hud.set_message("no legal rotation exists ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the next move will shuffle the board")
		return
	var move: Dictionary = legal[0]
	select_vertex(int(move["vertex"]))
	board_view.hint_vertex = cursor_vertex
	board_view.queue_redraw()
	hud.set_message(
		"hint: %s clears something here" % ("CW" if int(move["direction"]) > 0 else "CCW")
	)


func toggle_rotation_mode() -> void:
	if game == null:
		return
	var ruleset: Variant = game.ruleset
	if int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.FREE):
		ruleset.rotation_mode = RulesetScript.RotationMode.STRICT
		hud.set_message("rotation mode: STRICT (reference) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â non-clearing spins revert")
	else:
		ruleset.rotation_mode = RulesetScript.RotationMode.FREE
		hud.set_message("rotation mode: FREE ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the trio stays where you put it")
	hud.update_from_game(game, _displayed_score)


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_key(_key_code(key))
		return
	if screen != Screen.PLAYING or game == null:
		return
	if event is InputEventMouseMotion:
		_mouse_moved((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			_mouse_clicked(button.position, button.button_index)


## Physical (layout-independent) code first, so WASD and Z/X work on every
## keyboard layout; logical code as the fallback.
func _key_code(key: InputEventKey) -> int:
	if key.physical_keycode != 0:
		return int(key.physical_keycode)
	return int(key.keycode)


func _handle_key(code: int) -> void:
	match screen:
		Screen.MENU:
			_menu_key(code)
		Screen.RESULT:
			_result_key(code)
		_:
			_play_key(code)


func _menu_key(code: int) -> void:
	var modes := [RulesetScript.Mode.MARATHON, RulesetScript.Mode.TIMED, RulesetScript.Mode.SURVIVAL]
	match code:
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			var step := -1 if code == KEY_LEFT or code == KEY_A else 1
			var next := modes.find(selected_mode) + step
			selected_mode = modes[posmod(next, modes.size())]
			hud.highlight_menu(selected_mode, selected_difficulty)
		KEY_UP, KEY_W, KEY_DOWN, KEY_S:
			var difficulties := ["easy", "normal", "hard"]
			var step := -1 if code == KEY_UP or code == KEY_W else 1
			var next := difficulties.find(selected_difficulty) + step
			selected_difficulty = difficulties[posmod(next, difficulties.size())]
			hud.highlight_menu(selected_mode, selected_difficulty)
		KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
			start_run(selected_mode, selected_difficulty)
		KEY_ESCAPE:
			get_tree().quit()


func _result_key(code: int) -> void:
	match code:
		KEY_R:
			start_run(selected_mode, selected_difficulty)
		KEY_M:
			_on_menu_pressed()
		KEY_ESCAPE:
			get_tree().quit()


## Rotation keys, which must wait for the board to settle. Cursor movement is
## deliberately not in this list: moving the cursor is always safe.
const ROTATION_KEYS := [KEY_Z, KEY_Q, KEY_X, KEY_E, KEY_F]


func _play_key(code: int) -> void:
	# One move at a time. The rules core resolves instantly and is always final,
	# so accepting a spin mid-animation would advance it past what the player can
	# see (and used to drop the animation in flight).
	if not board_view.is_settled() and ROTATION_KEYS.has(code):
		return
	match code:
		KEY_LEFT, KEY_A:
			move_cursor(Vector2.LEFT)
		KEY_RIGHT, KEY_D:
			move_cursor(Vector2.RIGHT)
		KEY_UP, KEY_W:
			move_cursor(Vector2.UP)
		KEY_DOWN, KEY_S:
			move_cursor(Vector2.DOWN)
		KEY_Z, KEY_Q:
			play_move(GameScript.COUNTER_CLOCKWISE)
		KEY_X, KEY_E:
			play_move(GameScript.CLOCKWISE)
		KEY_F:
			use_special(GameScript.CLOCKWISE)
		KEY_H:
			show_hint()
		KEY_R:
			new_game(randi())
		KEY_T:
			toggle_rotation_mode()
		KEY_ESCAPE:
			get_tree().quit()


func _mouse_moved(viewport_point: Vector2) -> void:
	var cell := board_view.cell_at(board_view.to_local(viewport_point))
	# Hovering a special piece is more useful than hovering its vertex.
	var special := _special_at(cell)
	board_view.hover_cell = special
	if special == Vector2i(-1, -1):
		snap_cursor_to(viewport_point)
	else:
		board_view.queue_redraw()


func _mouse_clicked(viewport_point: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT and button_index != MOUSE_BUTTON_RIGHT:
		return
	if not board_view.is_settled():
		return
	var direction := GameScript.CLOCKWISE if button_index == MOUSE_BUTTON_LEFT else GameScript.COUNTER_CLOCKWISE
	var cell := board_view.cell_at(board_view.to_local(viewport_point))
	if _special_at(cell) != Vector2i(-1, -1):
		play_piece_move(cell, direction)
		return
	snap_cursor_to(viewport_point)
	play_move(direction)
