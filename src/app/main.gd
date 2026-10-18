extends Node2D

## Dev controller: owns the Game, moves the cursor, feeds input to the rules
## core and hands results to the view. Rules live in src/core (docs/design.md
## §10.1); this file is the thin layer that also drives the menu, the clock and
## the end-of-run screen.

const HexGrid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const TutorialScript := preload("res://src/core/tutorial.gd")

enum Screen { MENU, PLAYING, RESULT, SETTINGS }

@onready var board_view: BoardView = $BoardView
@onready var hud: Hud = $Hud

var game: Game
var cursor_vertex := 0
## When the cursor has snapped onto a starflower or pearl, this is its cell.
var cursor_special := HexGrid.NO_CELL
## The special the pointer is currently inside, so hover targets on entry only.
var _hovered_special := HexGrid.NO_CELL
var screen: Screen = Screen.MENU
var selected: RunConfig = RunConfig.of(RulesetScript.Mode.MARATHON, "normal")
var tutorial: Tutorial = null
## Set when the run ended mid-animation (a bomb going off), so the summary panel
## waits for the shockwave instead of cutting it off.
var _pending_result := false
## What the HUD shows: it lags game.score until each cascade step lands.
var _displayed_score := 0

var settings: Settings
var profile: ProfileService
var audio: AudioService
var settings_panel: SettingsPanel
var achievements_panel: AchievementsPanel
var leaderboard_panel: LeaderboardPanel
var toast: AchievementToast


func _ready() -> void:
	hud.mode_chosen.connect(_on_mode_chosen)
	hud.difficulty_chosen.connect(_on_difficulty_chosen)
	hud.start_pressed.connect(_on_start_pressed)
	hud.tutorial_pressed.connect(_on_tutorial_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.menu_pressed.connect(_on_menu_pressed)
	hud.show_menu(selected)
	# A cleared group landing in the animation rolls the score up step by step.
	board_view.clear_scored.connect(_on_clear_scored)

	settings = Settings.new()
	settings.load_from()
	profile = ProfileService.new()
	profile.load_from()
	audio = AudioService.new()
	add_child(audio)
	settings_panel = SettingsPanel.new()
	settings_panel.settings = settings
	settings_panel.profile = profile
	add_child(settings_panel)
	settings_panel.closed.connect(_close_settings)
	settings_panel.changed.connect(_on_settings_changed)
	settings_panel.achievements_pressed.connect(_open_achievements)
	achievements_panel = AchievementsPanel.new()
	achievements_panel.profile = profile
	add_child(achievements_panel)
	achievements_panel.closed.connect(_close_achievements)
	achievements_panel.reset_pressed.connect(_on_achievements_reset)
	leaderboard_panel = LeaderboardPanel.new()
	leaderboard_panel.profile = profile
	add_child(leaderboard_panel)
	leaderboard_panel.closed.connect(_close_leaderboard)
	hud.leaderboard_pressed.connect(_open_leaderboard_for_run)
	settings_panel.leaderboard_pressed.connect(_open_leaderboard_for_selection)
	settings_panel.free_mode_toggled.connect(_on_free_mode_toggled)
	hud.set_free_mode_unlocked(settings.free_mode_unlocked)
	toast = AchievementToast.new()
	add_child(toast)
	hud.settings_pressed.connect(_open_settings)
	board_view.step_began.connect(audio.on_step)
	_apply_juice()


func _process(delta: float) -> void:
	if screen != Screen.PLAYING or game == null:
		return
	# Only Timed mode consumes time, but the clock display still needs updating.
	game.tick(delta)
	# The score rolls up clear by clear; once the board has settled, trust the
	# core again so bonuses outside a clear group (round bonus, buys) land too.
	if board_view.is_settled() and _displayed_score != game.score:
		_displayed_score = game.score
	_apply_juice()
	hud.update_from_game(HudModel.from_game(game, _displayed_score))
	if game.state == GameScript.State.FINISHED:
		# A countdown ending has nothing to play out; a bomb does.
		if _pending_result and board_view.is_settled():
			_pending_result = false
			_enter_result()
		elif not _pending_result:
			_enter_result()


# --- run lifecycle ----------------------------------------------------------

## Starts a run. A negative seed picks a fresh random one.
func start_run(config: RunConfig, run_seed: int = -1) -> void:
	selected = config
	tutorial = null
	var seed_value := run_seed if run_seed >= 0 else randi()
	game = GameScript.new(seed_value, RulesetScript.for_run(config))
	_enter_playing()
	hud.set_message(
		"%s · %s — seed %d%s"
		% [game.mode_name(), config.difficulty, seed_value, "  ·  the clock is running" if config.mode == RulesetScript.Mode.TIMED else ""]
	)


## The scripted tutorial: its own game, its own board rigs (docs/design.md §7.4).
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
		hud.set_banner("Tutorial complete — press M for the menu, or R to keep playing this board")
		hud.set_message("you have seen every mechanic")
		return
	hud.set_banner(
		"Tutorial %d/%d · %s — %s"
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
		start_run(selected, seed_value)
		return
	tutorial = null
	var ruleset := RulesetScript.for_run(RunConfig.from_ruleset(game.ruleset))
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
	board_view.hover_cell = HexGrid.NO_CELL
	_refresh_cursor()
	if tutorial == null:
		hud.set_banner("")
	hud.show_playing()
	hud.update_from_game(HudModel.from_game(game, _displayed_score))


func _enter_result() -> void:
	screen = Screen.RESULT
	board_view.hint_vertex = -1
	var summary := game.summary()
	var unlocked: Array[String] = []
	if profile != null:
		profile.record_run(summary, Time.get_datetime_string_from_system())
		# Evaluated against the totals *after* recording, so accumulation achievements
		# see this run as part of the history.
		var earned := Achievements.evaluate(summary, profile.totals, profile.achievements)
		for id: String in earned:
			profile.unlock(id)
		profile.save_to()
		unlocked = Achievements.titles_for(earned)
		if not unlocked.is_empty():
			# One cue for the batch however many unlocked, then one toast each in turn.
			audio.play_cue("achievement")
			if toast != null:
				for title: String in unlocked:
					toast.show_text("★  Achievement  ·  " + title)
			if achievements_panel != null:
				achievements_panel.refresh()
	if settings_panel != null:
		settings_panel.profile = profile
	hud.show_result(summary, unlocked)


## Which screen is up, as a string (used by the view smoke test).
func screen_name() -> String:
	match screen:
		Screen.MENU:
			return "menu"
		Screen.RESULT:
			return "result"
		Screen.SETTINGS:
			return "settings"
		_:
			return "playing"


func _on_mode_chosen(mode: int) -> void:
	selected = RunConfig.of(mode, selected.difficulty)
	hud.highlight_menu(selected)


func _on_difficulty_chosen(difficulty: String) -> void:
	selected = RunConfig.of(selected.mode, difficulty)
	hud.highlight_menu(selected)


func _on_start_pressed() -> void:
	start_run(selected)


func _on_restart_pressed() -> void:
	start_run(selected)


func _on_menu_pressed() -> void:
	screen = Screen.MENU
	game = null
	tutorial = null
	board_view.set_game(null)
	hud.set_banner("")
	hud.show_menu(selected)


## A cascade step landed: roll the displayed score forward by what it was worth.
func _on_clear_scored(amount: int) -> void:
	_displayed_score += amount
	if game != null:
		hud.update_from_game(HudModel.from_game(game, _displayed_score))


# --- actions (also the programmatic API the smoke test drives) --------------

func play_move(direction: int) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	# A starflower or pearl anywhere in the trio means the spin turns that piece
	# instead of the three tiles. Re-derived from the board here rather than read
	# from the cursor, so a piece that changed under the cursor cannot act stale.
	if cursor_special != HexGrid.NO_CELL and _special_at(cursor_special) != HexGrid.NO_CELL:
		play_piece_move(cursor_special, direction)
		return
	cursor_special = HexGrid.NO_CELL
	board_view.hint_vertex = -1
	var result := game.rotate(cursor_vertex, direction)
	var turn := "CW" if direction == GameScript.CLOCKWISE else "CCW"

	if not result.committed:
		board_view.show_result(result)   # a refused spin still turns out and back
		audio.play_move(result)
		var guidance := ""
		if result.rejected_reason.begins_with("no match"):
			guidance = "  — the cursor is grey here; press H to find a spin that clears"
		hud.set_message("%s: %s%s" % [turn, result.rejected_reason, guidance])
		_refresh_cursor()
		return

	_apply(result, turn)


## Turns the starflower or pearl under the cursor, if there is one.
## Retained for callers that still ask for it: selecting a special is the step
## that matters now, and a rotate turns whatever is selected.
func use_special(_direction: int = GameScript.CLOCKWISE) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	if cursor_special == HexGrid.NO_CELL:
		_toggle_special_target()


## The cell itself if it holds a piece that can be turned on its own.
func _special_at(cell: Vector2i) -> Vector2i:
	var piece: int = game.board.get_piece(cell)
	if Pieces.is_starflower(piece) or Pieces.is_pearl(piece):
		return cell
	return HexGrid.NO_CELL


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
	audio.play_move(result)
	_refresh_cursor()
	hud.update_from_game(HudModel.from_game(game, _displayed_score))

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
		parts.append("round %d — +%d" % [result.round_reached, result.round_bonus])
	if result.level_up:
		parts.append("LEVEL %d" % result.new_level)
	if result.shuffled:
		parts.append("board was dead — shuffled")
	hud.set_message("  ·  ".join(parts))


func move_cursor(direction: Vector2) -> void:
	if game == null:
		return
	# Stepping away from a special returns the cursor to ordinary vertex selection.
	cursor_special = HexGrid.NO_CELL
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
	cursor_vertex = _vertex_under_pointer(viewport_point)
	_refresh_cursor()


## The vertex nearest the pointer, keeping the current one when it is just as close.
## A tile's centre is equidistant from its six vertices, so plain nearest-vertex has
## to pick one arbitrarily and the highlight jumps to a corner the player never
## pointed at. Half a pixel is enough: nearer edges still win.
func _vertex_under_pointer(viewport_point: Vector2) -> int:
	var local := board_view.to_local(viewport_point)
	var nearest := board_view.vertex_at(local)
	if cursor_vertex >= 0 and cursor_vertex < HexGrid.vertices().size():
		if board_view.vertex_distance(cursor_vertex, local) <= board_view.vertex_distance(nearest, local) + 0.5:
			return cursor_vertex
	return nearest


## Keeps the view in sync, including whether a spin at the cursor can clear.
func _refresh_cursor() -> void:
	board_view.cursor_vertex = cursor_vertex
	if cursor_special != HexGrid.NO_CELL and _special_at(cursor_special) == HexGrid.NO_CELL:
		# The piece turned into something else (or was destroyed): back to trio mode.
		cursor_special = HexGrid.NO_CELL
	board_view.cursor_special = cursor_special
	if cursor_special != HexGrid.NO_CELL:
		# Snapped onto a special: a rotate turns the piece, not the trio.
		board_view.cursor_legal = _special_turn_is_legal(cursor_special)
	else:
		board_view.cursor_legal = game != null and game.has_legal_spin(cursor_vertex)
	board_view.queue_redraw()


## The starflower or pearl the cursor is pointing at: any of the trio's cells that
## holds a special. Every vertex touching a special therefore switches to piece mode,
## which matches how the cursor's outline is drawn.
func _special_at_cursor() -> Vector2i:
	for cell: Vector2i in HexGrid.vertices()[cursor_vertex]:
		if _special_at(cell) != HexGrid.NO_CELL:
			return cell
	return HexGrid.NO_CELL


## Cycles the cursor between the trio at this vertex and a starflower or pearl it
## contains. The special is its own cursor position, so every grid vertex keeps
## working as a normal three-tile rotation.
func _toggle_special_target() -> void:
	if cursor_special != HexGrid.NO_CELL:
		cursor_special = HexGrid.NO_CELL
		hud.set_message("trio mode — spinning turns three tiles")
		_refresh_cursor()
		return
	var special := _special_at_cursor()
	if special == HexGrid.NO_CELL:
		hud.set_message("no starflower or pearl at this position (Space switches to one)")
		_refresh_cursor()
		return
	cursor_special = special
	var piece: int = game.board.get_piece(special)
	var what := "starflower" if Pieces.is_starflower(piece) else "pearl"
	hud.set_message("%s selected — spinning turns all its neighbours" % what)
	_refresh_cursor()


func _special_turn_is_legal(cell: Vector2i) -> bool:
	if game == null:
		return false
	for neighbour: Vector2i in game.swapped_cells(cell):
		if game.board.is_locked(neighbour):
			return false
	return true


func show_hint() -> void:
	if game == null or screen != Screen.PLAYING:
		return
	var legal: Array = game.find_legal_rotations()
	if legal.is_empty():
		hud.set_message("no legal rotation exists — the next move will shuffle the board")
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
	# Locked means hidden: a keypress must not advertise that the mode exists.
	if not settings.free_mode_unlocked:
		return
	var ruleset: Variant = game.ruleset
	if int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.FREE):
		ruleset.rotation_mode = RulesetScript.RotationMode.STRICT
		hud.set_message("rotation mode: STRICT (reference) — non-clearing spins revert")
	else:
		ruleset.rotation_mode = RulesetScript.RotationMode.FREE
		hud.set_message("rotation mode: FREE — the trio stays where you put it")
	hud.update_from_game(HudModel.from_game(game, _displayed_score))


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
		Screen.SETTINGS:
			pass
		_:
			_play_key(code)


func _menu_key(code: int) -> void:
	match code:
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			var step := -1 if code == KEY_LEFT or code == KEY_A else 1
			selected = selected.next_mode(step)
			hud.highlight_menu(selected)
		KEY_UP, KEY_W, KEY_DOWN, KEY_S:
			var step := -1 if code == KEY_UP or code == KEY_W else 1
			selected = selected.next_difficulty(step)
			hud.highlight_menu(selected)
		KEY_S:
			_open_settings()
		KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
			start_run(selected)
		KEY_ESCAPE:
			get_tree().quit()


func _result_key(code: int) -> void:
	match code:
		KEY_R:
			start_run(selected)
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
			_toggle_special_target()
		KEY_SPACE:
			_toggle_special_target()
		KEY_H:
			show_hint()
		KEY_R:
			new_game(randi())
		KEY_T:
			toggle_rotation_mode()
		KEY_ESCAPE:
			get_tree().quit()


func _mouse_moved(viewport_point: Vector2) -> void:
	if game == null or screen != Screen.PLAYING:
		return
	var cell := board_view.cell_at(board_view.to_local(viewport_point))
	var special := _special_at(cell)
	board_view.hover_cell = special
	# Track the vertex under the pointer even while a special is selected, so a later
	# deselect or click starts from the vertex the player is actually looking at.
	cursor_vertex = _vertex_under_pointer(viewport_point)
	if special != HexGrid.NO_CELL:
		# Target a special on ENTER only. Re-targeting on every motion would undo a
		# keyboard deselect as soon as the pointer jittered by a pixel.
		if special != _hovered_special:
			_hovered_special = special
			cursor_special = special
	else:
		_hovered_special = HexGrid.NO_CELL
		cursor_special = HexGrid.NO_CELL
	_refresh_cursor()


func _mouse_clicked(viewport_point: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT and button_index != MOUSE_BUTTON_RIGHT:
		return
	if not board_view.is_settled():
		return
	var direction := GameScript.CLOCKWISE if button_index == MOUSE_BUTTON_LEFT else GameScript.COUNTER_CLOCKWISE
	# A click does exactly what the rotate keys do: move the cursor to the click, then
	# let the selection decide. It used to turn whatever special sat under the pointer,
	# so a click could rotate a piece the outline showed as deselected.
	snap_cursor_to(viewport_point)
	play_move(direction)


# --- settings and audio -----------------------------------------------------

func _open_settings() -> void:
	if settings_panel == null:
		return
	screen = Screen.SETTINGS
	hud.visible = false
	settings_panel.open()


func _close_settings() -> void:
	if settings_panel != null:
		settings_panel.close()
	settings.save_to()
	hud.visible = true
	screen = Screen.MENU
	hud.show_menu(selected)


## From the result screen: the table the run that just ended belongs to.
func _open_leaderboard_for_run() -> void:
	var config: RunConfig = RunConfig.from_ruleset(game.ruleset) if game != null else selected
	_open_leaderboard(config)


## From the settings screen: whichever table is currently selected in the menu.
func _open_leaderboard_for_selection() -> void:
	_open_leaderboard(selected)


func _open_leaderboard(config: RunConfig) -> void:
	if leaderboard_panel == null:
		return
	leaderboard_panel.profile = profile
	leaderboard_panel.open(config)


func _close_leaderboard() -> void:
	if leaderboard_panel != null:
		leaderboard_panel.close()


func _open_achievements() -> void:
	if achievements_panel == null:
		return
	achievements_panel.profile = profile
	achievements_panel.open()


## The achievements panel sits above the settings screen, so closing it returns to
## the menu that opened it rather than to the game.
func _close_achievements() -> void:
	if achievements_panel != null:
		achievements_panel.close()


func _on_achievements_reset() -> void:
	if profile == null:
		return
	profile.reset_achievements()
	profile.save_to()
	if achievements_panel != null:
		achievements_panel.refresh()
	if settings_panel != null:
		settings_panel.refresh()


## The cheat code just unlocked or locked FREE rotation.
func _on_free_mode_toggled(unlocked: bool) -> void:
	if toast != null:
		toast.show_text("Free Mode Unlocked" if unlocked else "Free mode locked")
	audio.play_cue("accept" if unlocked else "lock")
	hud.set_free_mode_unlocked(unlocked)
	# Locking must not leave the running game in the mode it just revoked.
	if not unlocked and game != null:
		if int(game.ruleset.rotation_mode) == int(RulesetScript.RotationMode.FREE):
			game.ruleset.rotation_mode = RulesetScript.RotationMode.STRICT
			hud.update_from_game(HudModel.from_game(game, _displayed_score))


func _on_settings_changed() -> void:
	settings.save_to()
	_apply_juice()


## Pushes the juice settings into the view. Reduced motion also shortens every
## animation step, which the view does from one place.
func _apply_juice() -> void:
	if settings == null:
		return
	board_view.settings = settings
	if audio != null:
		audio.settings = settings
