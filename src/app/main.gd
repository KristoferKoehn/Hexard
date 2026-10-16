extends Node2D

## Dev controller: owns the Game, moves the cursor, feeds input to the rules
## core and hands results to the view. Everything here is deliberately thin —
## rules live in src/core (docs/design.md §10.1).

const HexGrid := preload("res://src/core/hex_grid.gd")
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
	board_view.cursor_vertex = cursor_vertex
	board_view.hint_vertex = -1
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
		hud.set_message("%s: %s" % [turn, result.rejected_reason])
		return

	board_view.show_result(result)
	hud.update_from_game(game)

	var parts := PackedStringArray([turn])
	if result.cleared_count > 0:
		parts.append("cleared %d  +%d" % [result.cleared_count, result.score])
		if result.cascades > 1:
			parts.append("cascade x%d" % result.cascades)
		if result.combos > 1:
			parts.append("%d combos" % result.combos)
	else:
		parts.append("no clear (position kept)")
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
	board_view.cursor_vertex = cursor_vertex
	board_view.queue_redraw()


func snap_cursor_to(point: Vector2) -> void:
	if game == null or board_view == null:
		return
	cursor_vertex = board_view.vertex_at(point)
	board_view.cursor_vertex = cursor_vertex
	board_view.queue_redraw()


func show_hint() -> void:
	if game == null:
		return
	var legal: Array = game.find_legal_rotations()
	if legal.is_empty():
		hud.set_message("no legal rotation exists — the next move will shuffle the board")
		return
	var move: Dictionary = legal[0]
	cursor_vertex = int(move["vertex"])
	board_view.cursor_vertex = cursor_vertex
	board_view.hint_vertex = cursor_vertex
	board_view.queue_redraw()
	hud.set_message(
		"hint: %s clears something here" % ("CW" if int(move["direction"]) > 0 else "CCW")
	)


func toggle_rotation_mode() -> void:
	if game == null:
		return
	var ruleset: Variant = game.ruleset
	if int(ruleset.rotation_mode) == RulesetScript.RotationMode.FREE:
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
			_handle_key(key.keycode)
	elif event is InputEventMouseMotion:
		snap_cursor_to(board_view.to_local((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		snap_cursor_to(board_view.to_local(button.position))
		if button.button_index == MOUSE_BUTTON_LEFT:
			play_move(GameScript.CLOCKWISE)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			play_move(GameScript.COUNTER_CLOCKWISE)


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
		KEY_H:
			show_hint()
		KEY_R:
			new_game(randi())
		KEY_T:
			toggle_rotation_mode()
		KEY_ESCAPE:
			get_tree().quit()
