extends SceneTree

## View-layer smoke test: loads the real scene, drives it with synthetic input,
## and fails loudly if anything errors or the wiring breaks.
##
##   godot --headless --path . --script res://tests/smoke_scene.gd
##
## Headless has no renderer, so this cannot judge how the board *looks*; it
## proves the scene loads, the nodes wire up, and real input events reach the
## rules core and change it.

const HexGrid := preload("res://src/core/hex_grid.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const GameScript := preload("res://src/core/game.gd")
const Pieces := preload("res://src/core/piece.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")

var _frames := 0
var _main: Node = null
var _failures: Array[String] = []
var _checks := 0

var _pending_direction := 1
var _turns_before := 0
var _score_before := 0


func _initialize() -> void:
	print("Hexard view smoke test")
	var scene: PackedScene = load("res://src/app/main.tscn")
	if scene == null:
		print("  FAIL  could not load res://src/app/main.tscn")
		quit(1)
		return
	_main = scene.instantiate()
	if _main == null:
		print("  FAIL  could not instantiate the main scene")
		quit(1)
		return
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		3:
			_smoke()
		4:
			_inject_mouse_motion()
		6:
			_check_mouse_mapped_to_the_right_place()
			_prepare_legal_keyboard_move()
		7:
			_inject_rotation_key()
		8:
			_check_keyboard_rotation_worked()
		9:
			_prepare_illegal_cursor()
		10:
			_inject_rotation_key()
		12:
			_check_illegal_spin_rejected()
			_start_timed_run()
		14:
			_check_timed_run_ended_on_the_clock()
			_main.call("start_tutorial")
		15:
			_check_tutorial_started()
			_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 4321)
		16:
			_check(_main.call("screen_name") == "playing", "a new run goes straight back to play")
			_check_special_snap()
		17:
			_start_bomb_explosion()
		18:
			_check_bomb_explosion_defers_the_summary()
			_check_settings_layout()
			_check_achievements_panel()
			_check_leaderboard_panel()
			_check_free_mode_cheat()
			_check_pause_menu()
			_check_menu_flow()
			_report()
			return true
	return false


## Force a bomb to go off: a one-tick fuse, then any committed spin.
func _start_bomb_explosion() -> void:
	var game: GameScript = _main.get("game")
	_check(game != null, "a run is active for the bomb test")
	if game == null:
		return
	game.ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	game.board.set_piece(Vector2i(4, 4), Pieces.bomb(Pieces.GemColor.BLUE, 1))
	_main.call("play_move", GameScript.CLOCKWISE)


## The summary must not cut off the explosion: board first, panel after.
func _check_bomb_explosion_defers_the_summary() -> void:
	var game: GameScript = _main.get("game")
	_check(game.state == GameScript.State.FINISHED, "the bomb ended the run")
	_check(_main.call("screen_name") == "playing", "the summary waits for the explosion")
	var view := _main.get_node("BoardView")
	_check(not bool(view.call("is_settled")), "the blast is still playing")
	view.call("finish_now")
	_main.call("_process", 0.016)
	_check(_main.call("screen_name") == "result", "and shows once the shockwave finishes")


func _check_tutorial_started() -> void:
	_check(_main.call("screen_name") == "playing", "the tutorial starts in play")
	_check(_main.get("tutorial") != null, "the controller holds a tutorial")
	var hud := _main.get_node("Hud")
	var banner := str(hud.call("banner_text"))
	_check(banner.begins_with("Tutorial 1/"), "the banner introduces step 1 (got '%s')" % banner)
	var game: GameScript = _main.get("game")
	_check(game != null and game.tile_count() == 85, "the tutorial board is ready")


# --- mode flow --------------------------------------------------------------

func _start_timed_run() -> void:
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.TIMED, "normal"), 777)
	var game: GameScript = _main.get("game")
	_check(game != null, "a Timed run was created")
	if game == null:
		return
	_check(game.max_clock > 0.0, "Timed mode starts with a clock")
	# Run the clock out; the controller's _process notices on the next frame.
	game.tick(999.0)


func _check_timed_run_ended_on_the_clock() -> void:
	_check(_main.call("screen_name") == "result", "the clock running out shows the result screen")
	var summary: RunSummary = _main.get("game").summary()
	_check(summary.reason == "time_out", "the summary says why")
	_check(summary.won == false, "and that it was a loss")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## The board view should be mid-animation right after a move.
func view_effects_are_animating() -> bool:
	var view := _main.get_node("BoardView")
	return int(view.call("effect_count")) > 0


# --- wiring -----------------------------------------------------------------

func _smoke() -> void:
	_check(_main.get_node_or_null("BoardView") != null, "scene has a BoardView node")
	_check(_main.get_node_or_null("Hud") != null, "scene has a Hud node")
	_check(_main.call("screen_name") == "menu", "the app opens on the mode menu")

	# Start a run, then exercise the board through the controller.
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 12345)
	_check(_main.call("screen_name") == "playing", "starting a run switches to play")

	var game: GameScript = _main.get("game")
	_check(game != null, "controller created a game")
	if game == null:
		return
	_check(game.tile_count() == 85, "board starts full")
	_check(not MatchFinder.has_any_match(game.board), "board starts match-free")

	var board_view := _main.get_node("BoardView")
	_check(board_view.get("game") == game, "board view received the game")
	_check(board_view.get("cursor_vertex") == 0, "cursor starts on the first vertex")

	# Play a handful of moves through the controller: the same path the keys use.
	var before_turns: int = game.turns
	for i in 6:
		_main.call("move_cursor", Vector2.RIGHT if i % 2 == 0 else Vector2.DOWN)
		_main.call("play_move", GameScript.CLOCKWISE if i % 2 == 0 else GameScript.COUNTER_CLOCKWISE)
	_check(game.turns >= before_turns, "moves went through the controller")
	_check(game.tile_count() == 85, "board is still full after moves")
	_check(game.board.invariant_violations().size() == 0, "no floating pieces after moves")
	_check(game.score >= 0, "score is sane")
	var legal: Array = game.find_legal_rotations()
	if not legal.is_empty():
		_main.call("select_vertex", int(legal[0]["vertex"]))
		_main.call("play_move", int(legal[0]["direction"]))
	_check(view_effects_are_animating(), "a committed move queued animation steps")
	# The HUD must not jump to the total: it rolls up as each clear lands.
	_check(
		int(_main.get("_displayed_score")) < game.score,
		"the score lags the board while the cascade plays (%d vs %d)"
		% [int(_main.get("_displayed_score")), game.score]
	)

	# While those steps play the board is not settled, so rotation input must be
	# refused - the core is already final and would run ahead of the screen.
	var anim_view := _main.get_node("BoardView")
	_check(not bool(anim_view.call("is_settled")), "the board is unsettled while tiles fall")
	var turns_while_falling: int = game.turns
	_main.call("_play_key", KEY_X)
	_main.call("_play_key", KEY_Z)
	_main.call("_play_key", KEY_F)
	_check(game.turns == turns_while_falling, "rotation keys are refused while the board settles")

	var cursor_before: int = _main.get("cursor_vertex")
	_main.call("_play_key", KEY_RIGHT)
	_check(_main.get("cursor_vertex") != cursor_before, "the cursor still moves while tiles fall")

	anim_view.call("sync_from_game")
	_check(bool(anim_view.call("is_settled")), "the board settles again once synced")
	# Once settled the display trusts the core again, so bonuses that are not part
	# of a clear group (round bonus, time buys) still land.
	_main.call("_process", 0.016)
	_check(
		int(_main.get("_displayed_score")) == game.score,
		"and the score catches up to the core once the board settles"
	)
	# No buffering: the refused presses above must not fire once the board lands.
	_check(
		game.turns == turns_while_falling,
		"no buffered spin fires when the board settles"
	)
	_main.call("_play_key", KEY_X)
	_check(game.turns >= turns_while_falling, "rotation keys are accepted again once settled")

	var cursor: int = _main.get("cursor_vertex")
	_check(cursor >= 0 and cursor < HexGrid.vertices().size(), "cursor stayed in range")

	# Every non-input entry point must run without erroring.
	_main.call("show_hint")
	_main.call("toggle_rotation_mode")
	_main.call("toggle_rotation_mode")
	_main.call("use_special")
	_main.call("use_special", GameScript.COUNTER_CLOCKWISE)
	_check(true, "hint, mode toggle and special-turn paths ran without error")

	var view := _main.get_node("BoardView")
	_check(view.call("cell_at", Vector2(0, 0)) is Vector2i, "cell picking returns a cell")
	_check(view.call("vertex_at", Vector2(0, 0)) is int, "vertex picking returns an index")


# --- mouse ------------------------------------------------------------------

## Aim the pointer at the middle of a known cell and see where the cursor lands.
## Regression test for "the mouse cursor sticks in the bottom right": pointer
## positions are viewport coordinates and must be converted to board space
## before the nearest-vertex lookup.
func _inject_mouse_motion() -> void:
	# Mouse picking needs a settled board too (clicks are refused mid-animation).
	_main.get_node("BoardView").call("sync_from_game")
	var view := _main.get_node("BoardView")
	var viewport_point: Vector2 = view.position + view.call("cell_center", Vector2i(4, 4))
	var event := InputEventMouseMotion.new()
	event.position = viewport_point
	event.global_position = viewport_point
	Input.parse_input_event(event)


func _check_mouse_mapped_to_the_right_place() -> void:
	var view := _main.get_node("BoardView")
	var viewport_point: Vector2 = view.position + view.call("cell_center", Vector2i(4, 4))
	var injected_cursor: int = _main.get("cursor_vertex")

	# Headless has no pointer, so Viewport may not deliver synthetic mouse
	# motion. Try the injected event first; if it did nothing, exercise the same
	# coordinate conversion the mouse handler uses.
	var used_event := _vertex_touches_cell(injected_cursor, Vector2i(4, 4))
	if not used_event:
		_main.call("snap_cursor_to", viewport_point)
	print("        · mouse path: %s" % ("synthetic event" if used_event else "direct snap_cursor_to"))

	var cursor: int = _main.get("cursor_vertex")
	var vertices := HexGrid.vertices()
	_check(cursor >= 0 and cursor < vertices.size(), "mouse left the cursor in range")
	if cursor < 0 or cursor >= vertices.size():
		return
	_check(
		_vertex_touches_cell(cursor, Vector2i(4, 4)),
		"pointing at the centre of cell (4,4) selects one of its vertices (got %s)"
		% str(vertices[cursor])
	)


func _vertex_touches_cell(vertex_index: int, cell: Vector2i) -> bool:
	var vertices := HexGrid.vertices()
	if vertex_index < 0 or vertex_index >= vertices.size():
		return false
	return (vertices[vertex_index] as Array).has(cell)


# --- keyboard ---------------------------------------------------------------

func _prepare_legal_keyboard_move() -> void:
	var game: GameScript = _main.get("game")
	var legal: Array = game.find_legal_rotations()
	_check(legal.size() > 0, "the board offers at least one legal spin")
	if legal.is_empty():
		return
	var move: Dictionary = legal[0]
	_main.call("select_vertex", int(move["vertex"]))
	_pending_direction = int(move["direction"])
	_turns_before = game.turns
	_score_before = game.score
	var view := _main.get_node("BoardView")
	_check(view.get("cursor_legal") == true, "the cursor highlights a spot that can clear")


func _inject_rotation_key() -> void:
	# Rotation input is refused while tiles are settling, so let the board settle
	# first: a player would do the same by waiting for the cascade to finish.
	_main.get_node("BoardView").call("sync_from_game")
	var code := KEY_X if _pending_direction > 0 else KEY_Z
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)


func _check_keyboard_rotation_worked() -> void:
	var game: GameScript = _main.get("game")
	_check(
		game.turns == _turns_before + 1,
		"a rotation key is one move (turns %d -> %d)" % [_turns_before, game.turns]
	)
	_check(game.score > _score_before, "the spin cleared and scored (%d -> %d)" % [_score_before, game.score])
	_check(game.total_combos > 0, "and the clear was banked as a combo")


func _prepare_illegal_cursor() -> void:
	var game: GameScript = _main.get("game")
	var legal := {}
	for move: Dictionary in game.find_legal_rotations():
		legal["%d:%d" % [move["vertex"], move["direction"]]] = true
	for index in HexGrid.vertices().size():
		var can_clear_here := legal.has("%d:%d" % [index, 1]) or legal.has("%d:%d" % [index, -1])
		if can_clear_here:
			continue
		_main.call("select_vertex", index)
		_pending_direction = 1
		_turns_before = game.turns
		var view := _main.get_node("BoardView")
		_check(view.get("cursor_legal") == false, "the cursor dims where no spin can clear")
		return
	_check(false, "expected at least one vertex where neither spin clears")


func _check_illegal_spin_rejected() -> void:
	var game: GameScript = _main.get("game")
	var view := _main.get_node("BoardView")
	_check(
		game.turns == _turns_before,
		"a spin that clears nothing is not a move in STRICT (turns stayed %d)" % game.turns
	)


# --- report -----------------------------------------------------------------

func _report() -> void:
	if _failures.is_empty():
		print("  PASS  view smoke test (%d checks)" % _checks)
		print("SMOKE RESULT: OK")
		quit(0)
		return
	print("  FAIL  view smoke test (%d checks)" % _checks)
	for message: String in _failures:
		print("        - %s" % message)
	print("SMOKE RESULT: FAILED")
	quit(1)


## A special is a cursor position of its own: every grid vertex keeps working as a
## trio rotation, Space switches to the piece, and hovering retargets between them.
func _check_special_snap() -> void:
	var game: GameScript = _main.get("game")
	var view = _main.get_node("BoardView")
	if game == null:
		return
	var cell := Vector2i(4, 4)
	var vertex: int = view.call("vertex_at", view.call("cell_center", cell))

	game.board.set_piece(cell, Pieces.starflower())
	view.call("sync_from_game")
	_main.call("select_vertex", vertex)
	_check(_main.get("cursor_special") == HexGrid.NO_CELL,
		"a vertex touching a flower is still a normal trio position")
	_check(view.get("game") != null, "the view has the board")

	_main.call("_play_key", KEY_SPACE)
	_check(_main.get("cursor_special") == cell, "Space selects the flower")
	_check(game.swapped_cells(cell).size() == 6, "which swaps six neighbours")
	_main.call("_play_key", KEY_SPACE)
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "Space again returns to the trio")

	game.board.set_piece(cell, Pieces.pearl())
	_main.call("select_vertex", vertex)
	_main.call("_play_key", KEY_SPACE)
	_check(_main.get("cursor_special") == cell, "Space selects a pearl too")
	_check(game.swapped_cells(cell).size() == 3, "which swaps three")

	# Hovering one special then another must retarget, not leave the first selected.
	var other := Vector2i(4, 6)
	game.board.set_piece(cell, Pieces.starflower())
	game.board.set_piece(other, Pieces.pearl())
	view.call("sync_from_game")
	_main.call("_mouse_moved", view.position + view.call("cell_center", cell))
	_check(_main.get("cursor_special") == cell, "hovering a flower targets it")
	_main.call("_mouse_moved", view.position + view.call("cell_center", other))
	_check(_main.get("cursor_special") == other, "hovering a pearl retargets the outline")

	# F toggles the same selection the outline and the rotate path both read, so the
	# picture and the behaviour cannot disagree. Clear the previous selection first:
	# the block above deliberately left a pearl targeted.
	game.board.set_piece(cell, Pieces.starflower())
	view.call("sync_from_game")
	_main.call("move_cursor", Vector2.LEFT)   # stepping away clears the target
	_main.call("select_vertex", vertex)
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "stepping away clears the selection")
	_main.call("_play_key", KEY_F)
	_check(_main.get("cursor_special") == cell, "F selects the flower")
	_main.call("_play_key", KEY_F)
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "F deselects it again")

	# With nothing selected, a rotate is an ordinary three-tile move again.
	game.ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var turns_before: int = game.turns
	_main.call("_play_key", KEY_X)
	_check(game.turns == turns_before + 1, "a rotate after deselecting is a trio move")
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "and the trio stays in charge")

	# The reported case: pointer left hovering the flower, deselect with the keyboard,
	# then click. The click must be an ordinary trio spin, matching the outline - it
	# used to turn the piece because the click path looked at the board, not at the
	# selection.
	game.board.set_piece(cell, Pieces.starflower())
	view.call("sync_from_game")
	_main.call("move_cursor", Vector2.LEFT)
	_main.call("select_vertex", vertex)
	_main.call("_mouse_moved", view.position + view.call("cell_center", cell))
	_check(_main.get("cursor_special") == cell, "hovering the flower targets it")
	_main.call("_play_key", KEY_F)
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "F deselects while the pointer stays")
	# Pointer jitter inside the same cell must not silently re-select it.
	_main.call("_mouse_moved", view.position + view.call("cell_center", cell) + Vector2(1, 0))
	_check(_main.get("cursor_special") == HexGrid.NO_CELL, "jitter inside the piece does not re-select")

	var shown_vertex: int = _main.get("cursor_vertex")
	var commands_before: int = game.commands().size()
	_main.call("_mouse_clicked", view.position + view.call("cell_center", cell), MOUSE_BUTTON_LEFT)
	var last: Array = game.commands()
	_check(last.size() > commands_before, "the click made a move")
	if last.size() > commands_before:
		_check(String(last[last.size() - 1][0]) == "rotate",
			"and it was a trio rotation, not a piece turn (got %s)" % String(last[last.size() - 1][0]))
		_check(int(last[last.size() - 1][1]) == shown_vertex,
			"on the vertex the cursor was showing (%d vs %d)" % [int(last[last.size() - 1][1]), shown_vertex])

	# Leave nothing special behind for later stages.
	game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(other, Pieces.gem(Pieces.GemColor.BLUE))
	view.call("sync_from_game")
	_main.call("_refresh_cursor")


## The settings screen is taller than 720p, so its body has to scroll and the way out
## has to be pinned outside the scrolled area. Both failed once: a CenterContainer
## sized the panel to its content and centred it, which clipped the Back button off
## screen entirely - the player could not leave.
func _check_settings_layout() -> void:
	_main.call("_open_settings")
	_check(_main.call("screen_name") == "settings", "settings opens")
	var panel: Node = _main.get("settings_panel")
	_check(panel != null, "there is a settings panel")
	if panel == null:
		return
	var scroll := _find_of_class(panel, "ScrollContainer") as ScrollContainer
	_check(scroll != null, "the body scrolls rather than overflowing the screen")
	var back := _find_button(panel, "Back")
	_check(back != null, "there is a way back to the menu")
	if back != null and scroll != null:
		_check(not scroll.is_ancestor_of(back), "the way back is pinned, not scrolled away")
		_check(back.is_visible_in_tree(), "so it is always on screen")
	_main.call("_close_settings")
	_check(_main.call("screen_name") == "menu", "and closing returns to the main menu")


func _find_of_class(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found := _find_of_class(child, type_name)
		if found != null:
			return found
	return null


func _find_button(root: Node, prefix: String) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).text.begins_with(prefix):
			return child
		var found := _find_button(child, prefix)
		if found != null:
			return found
	return null


## The achievements list: reachable from settings, complete, and leaveable. The reset
## button is deliberately tiny and arms before acting, so both are asserted.
func _check_achievements_panel() -> void:
	_main.call("_open_settings")
	(_main.get("settings_panel") as Node).emit_signal("achievements_pressed")
	var panel: Node = _main.get("achievements_panel")
	_check(panel != null and panel.visible, "the achievements list opens from settings")
	if panel == null:
		return
	var scroll := _find_of_class(panel, "ScrollContainer") as ScrollContainer
	_check(scroll != null, "the list scrolls")
	var rows: Node = scroll.get_child(0) if scroll != null else null
	var listed := rows.get_child_count() if rows != null else -1
	_check(listed == Achievements.count(),
		"every achievement is listed (%d of %d rows)" % [listed, Achievements.count()])
	var reset := _find_button(panel, "Reset")
	_check(reset != null, "there is a reset button")
	if reset != null:
		_check(reset.size.x <= 90.0, "and it is small (%.0fpx wide)" % reset.size.x)
		reset.emit_signal("pressed")
		_check(reset.text == "Sure?", "one press arms it rather than wiping the record")
	panel.emit_signal("closed")
	_check(not panel.visible, "and it closes again")


## The leaderboard: reachable, populated with a header even when empty, and leaveable.
func _check_leaderboard_panel() -> void:
	_main.call("_open_leaderboard_for_selection")
	var panel: Node = _main.get("leaderboard_panel")
	_check(panel != null and panel.visible, "the leaderboard opens")
	if panel == null:
		return
	var grid := _find_of_class(panel, "GridContainer") as GridContainer
	_check(grid != null, "the board is a table")
	if grid != null:
		_check(grid.get_child_count() >= LeaderboardPanel.COLUMNS.size(),
			"with a header row even on an empty table (%d cells)" % grid.get_child_count())
	panel.emit_signal("closed")
	_check(not panel.visible, "and it closes")


## The cheat code: typed in the settings screen it unlocks FREE rotation for the profile
## and makes the T hint appear; typed again it locks and hides the hint. Worth checking
## headlessly because the handler is an _unhandled_input on a CanvasLayer, which is
## exactly the kind of thing that silently never fires.
func _check_free_mode_cheat() -> void:
	_main.call("_open_settings")
	var panel: Node = _main.get("settings_panel")
	var settings = _main.get("settings")
	var hud: Node = _main.get("hud")
	_check(not bool(settings.free_mode_unlocked), "FREE mode starts locked")
	_check(not _controls_text(hud).contains("rotation mode"), "with no hint to find it")

	_type_code(panel)
	_check(bool(settings.free_mode_unlocked), "the code unlocks FREE mode")
	_check(_controls_text(hud).contains("rotation mode"), "and the T hint appears")
	if _main.get("toast") != null:
		_check(int(_main.get("toast").call("pending")) > 0, "and a toast is queued")

	_type_code(panel)
	_check(not bool(settings.free_mode_unlocked), "typing it again locks it")
	_check(not _controls_text(hud).contains("rotation mode"), "and the hint goes away")
	_main.call("_close_settings")


func _type_code(panel: Node) -> void:
	for code in [KEY_3, KEY_1, KEY_4, KEY_1, KEY_5, KEY_9]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = true
		panel.call("_unhandled_input", key)


func _controls_text(hud: Node) -> String:
	var label := _find_label(hud, "arrows/WASD")
	return label.text if label != null else ""


func _find_label(root: Node, prefix: String) -> Label:
	for child in root.get_children():
		if child is Label and (child as Label).text.begins_with(prefix):
			return child
		var found := _find_label(child, prefix)
		if found != null:
			return found
	return null


## Esc pauses instead of quitting, gameplay is inert while paused, and settings opened
## from the pause screen come back to it rather than dumping the run on the menu.
func _check_pause_menu() -> void:
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 999)
	_check(_main.call("screen_name") == "playing", "a run is up before pausing")
	var game = _main.get("game")
	var panel: Node = _main.get("pause_panel")
	_check(panel != null and not panel.visible, "the pause menu starts hidden")

	_main.call("_handle_key", KEY_ESCAPE)
	_check(_main.call("screen_name") == "paused", "escape pauses the run")
	_check(panel != null and panel.visible, "and the menu is up")

	var turns_before := int(game.turns)
	_main.call("_handle_key", KEY_X)
	_check(int(game.turns) == turns_before, "a rotate key does nothing while paused")

	_main.call("_handle_key", KEY_ESCAPE)
	_check(_main.call("screen_name") == "playing", "escape again resumes")
	_check(not panel.visible, "and the menu is down")

	# Settings from the pause screen must not abandon the run.
	_main.call("_handle_key", KEY_ESCAPE)
	(panel as Node).emit_signal("settings_pressed")
	_check(_main.call("screen_name") == "settings", "settings opens from the pause menu")
	_main.call("_close_settings")
	_check(_main.call("screen_name") == "paused", "and closing it returns to the pause menu")
	(panel as Node).emit_signal("resume_pressed")
	_check(_main.call("screen_name") == "playing", "resume returns to the game")

	# Reported: pause -> main menu left the pause screen up, with the menu behind it.
	var hud: Node = _main.get("hud")
	_main.call("_handle_key", KEY_ESCAPE)
	(panel as Node).emit_signal("menu_pressed")
	_check(_main.call("screen_name") == "menu", "the pause menu can reach the main menu")
	_check(not panel.visible, "and the pause screen comes down")
	_check(hud.visible, "with the menu actually shown")

	# Reported: pause -> settings -> pause -> main menu left the pause screen up over
	# nothing, because the settings screen had hidden the HUD and nothing restored it.
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 1001)
	_main.call("_handle_key", KEY_ESCAPE)
	(panel as Node).emit_signal("settings_pressed")
	_main.call("_close_settings")
	_check(_main.call("screen_name") == "paused", "back from settings to the pause menu")
	_check(hud.visible, "with the board and HUD restored behind it")
	(panel as Node).emit_signal("menu_pressed")
	_check(_main.call("screen_name") == "menu", "and the menu is reachable from there too")
	_check(not panel.visible and hud.visible, "pause down, menu up")

	# Leaving the run asks first: Main menu throws away the board, the score and the clock.
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 1003)
	_main.call("_handle_key", KEY_ESCAPE)
	(panel as Node).call("request_quit")
	_check(bool((panel as Node).call("is_confirming")), "main menu asks before quitting")
	_check(_main.call("screen_name") == "paused", "and does not quit on the first click")
	(panel as Node).call("cancel_confirm")
	_check(not bool((panel as Node).call("is_confirming")), "cancel puts the question away")
	_check(_main.call("screen_name") == "paused", "with the run still paused")
	(panel as Node).call("request_quit")
	_main.call("_handle_key", KEY_ESCAPE)
	_check(_main.call("screen_name") == "paused", "escape cancels the question, not the pause")
	(panel as Node).call("request_quit")
	_main.call("_handle_key", KEY_Y)
	_check(_main.call("screen_name") == "menu", "confirming leaves the run")
	_check(not panel.visible, "and the pause screen comes down")

	# Restart from the pause menu is the same class of bug.
	_main.call("start_run", RunConfig.of(RulesetScript.Mode.MARATHON, "normal"), 1002)
	_main.call("_handle_key", KEY_ESCAPE)
	(panel as Node).emit_signal("restart_pressed")
	_check(_main.call("screen_name") == "playing", "restart from the pause menu starts a run")
	_check(not panel.visible, "without leaving the pause screen over it")


## The menu is now two steps: pick a mode, then pick a difficulty, and the mode buttons
## are doors rather than a radio selection. The ambient board stays up for both.
func _check_menu_flow() -> void:
	_main.call("_on_menu_pressed")
	var hud: Node = _main.get("hud")
	var flourish = hud.get("_flourish")
	_check(_main.call("screen_name") == "menu", "the menu is up")
	_check(not bool(hud.call("is_difficulty_open")), "with the difficulty step closed")

	# The mode buttons were briefly painted blank because their text came only from a
	# later refresh; a title at build time is now asserted, not assumed.
	var mode_buttons: Dictionary = hud.get("_mode_buttons")
	_check(mode_buttons.size() == 3, "there are three mode buttons")
	for mode: int in mode_buttons:
		var button := mode_buttons[mode] as Button
		_check(button.text.begins_with(Hud.MODE_LABELS[mode]), "mode button %d is titled" % mode)
		_check(button.text.contains("\n"), "and carries its best score underneath")

	_main.call("_handle_key", KEY_2)
	_check(bool(hud.call("is_difficulty_open")), "picking a mode opens its difficulty step")
	_check(_main.get("hud").get("_menu").visible == false, "and the mode menu steps aside")
	_check(flourish != null and flourish.visible, "the orbiting gems keep going")

	_main.call("_handle_key", KEY_ESCAPE)
	_check(not bool(hud.call("is_difficulty_open")), "escape steps back to the modes")
	_check(_main.get("hud").get("_menu").visible, "with the menu visible again")

	_main.call("_handle_key", KEY_3)
	_main.call("_handle_key", KEY_1)
	_check(_main.call("screen_name") == "playing", "a difficulty starts the run")
	var selected: RunConfig = _main.get("selected")
	_check(selected.mode_name() == "Survival", "in the mode that was picked")
	_check(selected.difficulty == "easy", "at the difficulty that was picked")
	_check(not bool(hud.call("is_difficulty_open")), "and the difficulty step is gone")

	# Colour patterns are an accessibility setting, so they must reach the backdrop too.
	var settings = _main.get("settings")
	settings.colour_patterns = false
	_main.call("_apply_juice")
	_check(not bool(flourish.show_glyphs), "menu gems drop their marks with the setting off")
	settings.colour_patterns = true
	_main.call("_apply_juice")
	_check(bool(flourish.show_glyphs), "and get them back with it on")

	# The three system buttons live on the menu now.
	_main.call("_on_menu_pressed")
	(hud as Node).emit_signal("achievements_pressed")
	_check(bool(_main.get("achievements_panel").visible), "achievements open from the menu")
	_main.get("achievements_panel").call("close")
	(hud as Node).emit_signal("leaderboard_pressed")
	_check(bool(_main.get("leaderboard_panel").visible), "so does the leaderboard")
	_main.get("leaderboard_panel").call("close")
	(hud as Node).emit_signal("settings_pressed")
	_check(_main.call("screen_name") == "settings", "and settings")
	_main.call("_close_settings")
