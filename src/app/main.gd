extends Node2D

## Dev controller: owns the Game, moves the cursor, feeds input to the rules
## core and hands results to the view. Everything here is deliberately thin —
## rules live in src/core (docs/design.md §10.1).

const HexGrid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")

const DEFAULT_SEED := 20261016
## How well a candidate vertex must line up with a direction to be considered.
const DIRECTION_ALIGNMENT := 0.55

@onready var board_view: BoardView = $BoardView
@onready var hud: Hud = $Hud

var game: RefCounted
var cursor_vertex := 0


func _ready() -> void:
	new_game(DEFAULT_SEED)


func new_game(seed_value: int) -> void:
	game = GameScript.new(seed_value)
	cursor_vertex = 0
	board_view.set_game(game)
	board_view.hint_vertex = -1
	_refresh_cursor()
	hud.update_from_game(game)
	hud.set_message("new board, seed %d — build toward a pearl ring" % seed_value)


# --- actions (also the programmatic API the smoke test drives) --------------

func play_move(direction: int) -> void:
	if game == null:
		return
	board_view.hint_vertex = -1
	var result = game.rotate(cursor_vertex, direction)
	var turn := "CW" if direction == GameScript.CLOCKWISE else "CCW"

	if not result.committed:
		var guidance := ""
		if result.rejected_reason.begins_with("no match"):
			guidance = "  — the cursor is grey here; press H to find a spin that clears"
		hud.set_message("%s: %s%s" % [turn, result.rejected_reason, guidance])
		_refresh_cursor()
		return

	_apply(result, turn)


## Turns the starflower or pearl under the cursor, if there is one.
func use_special(direction: int = GameScript.CLOCKWISE) -> void:
	if game == null:
		return
	var cells: Array = HexGrid.vertices()[cursor_vertex]
	var target := Vector2i(-1, -1)
	for cell: Vector2i in cells:
		var piece: int = game.board.get_piece(cell)
		if Pieces.is_starflower(piece) or Pieces.is_pearl(piece):
			target = cell
			break
	if target == Vector2i(-1, -1):
		hud.set_message("no starflower or pearl under the cursor")
		return
	play_piece_move(target, direction)


func play_piece_move(cell: Vector2i, direction: int) -> void:
	if game == null:
		return
	board_view.hint_vertex = -1
	var result = game.rotate_piece(cell, direction)
	if not result.committed:
		hud.set_message("piece: %s" % result.rejected_reason)
		return
	_apply(result, "turn piece")


## Shared presentation tail for any committed move.
func _apply(result, label: String) -> void:
	board_view.show_result(result)
	_refresh_cursor()
	hud.update_from_game(game)

	if result.bomb_exploded:
		hud.set_message("BOOM — a bomb went off. Press R for a new board.")
		return
	if result.finished:
		hud.set_message("PERFECT FINISH (%s) for %d points!" % [result.finish_kind, result.score])
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
	if result.bombs_ticked.size() > 0:
		parts.append("bomb ticking")
	if result.level_up:
		parts.append("LEVEL %d" % result.new_level)
	if result.shuffled:
		parts.append("board was dead — shuffled")
	hud.set_message("  ·  ".join(parts))


func move_cursor(direction: Vector2) -> void:
	if game == null:
		return
	var vertices := HexGrid.vertices()
	var current := HexGrid.vertex_centroid(cursor_vertex, board_view.cell_size)
	var best := cursor_vertex
	var best_score := -INF
	for index in vertices.size():
		if index == cursor_vertex:
			continue
		var offset := HexGrid.vertex_centroid(index, board_view.cell_size) - current
		var distance := offset.length()
		if distance < 0.001:
			continue
		var alignment := offset.normalized().dot(direction)
		if alignment < DIRECTION_ALIGNMENT:
			continue
		# Prefer well-aligned, then near: enough for a dev cursor.
		var score := alignment - distance / (board_view.cell_size * 6.0)
		if score > best_score:
			best_score = score
			best = index
	cursor_vertex = best
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
	if game == null:
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
	var ruleset: Variant = game.ruleset
	if int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.FREE):
		ruleset.rotation_mode = RulesetScript.RotationMode.STRICT
		hud.set_message("rotation mode: STRICT (reference) — non-clearing spins revert")
	else:
		ruleset.rotation_mode = RulesetScript.RotationMode.FREE
		hud.set_message("rotation mode: FREE — the trio stays where you put it")
	hud.update_from_game(game)


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_key(_key_code(key))
	elif event is InputEventMouseMotion:
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


func _mouse_moved(viewport_point: Vector2) -> void:
	var local := board_view.to_local(viewport_point)
	var cell := board_view.cell_at(local)
	# Hovering a special piece is more useful than hovering its vertex.
	if Pieces.is_starflower(game.board.get_piece(cell)) or Pieces.is_pearl(game.board.get_piece(cell)):
		board_view.hover_cell = cell
		board_view.queue_redraw()
		return
	board_view.hover_cell = Vector2i(-1, -1)
	snap_cursor_to(viewport_point)


func _mouse_clicked(viewport_point: Vector2, button_index: int) -> void:
	var direction := GameScript.CLOCKWISE if button_index == MOUSE_BUTTON_LEFT else GameScript.COUNTER_CLOCKWISE
	if button_index != MOUSE_BUTTON_LEFT and button_index != MOUSE_BUTTON_RIGHT:
		return
	var local := board_view.to_local(viewport_point)
	var cell := board_view.cell_at(local)
	if Pieces.is_starflower(game.board.get_piece(cell)) or Pieces.is_pearl(game.board.get_piece(cell)):
		play_piece_move(cell, direction)
		return
	snap_cursor_to(viewport_point)
	play_move(direction)


func _handle_key(keycode: int) -> void:
	match keycode:
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
