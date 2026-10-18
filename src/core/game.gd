class_name Game
extends RefCounted

## Facade over the rules core (docs/design.md §3, §5).
##
##   var game := Game.new(1234)
##   var result := game.rotate(vertex_index, Game.CLOCKWISE)
##
## Owns the board, the RNG streams, level/combo progression, the dead-board
## rule and the command log that makes replays exact. No Node references: the
## view layer consumes MoveResult objects.

const Grid := preload("res://src/core/hex_grid.gd")
const BoardScript := preload("res://src/core/board.gd")
const Pieces := preload("res://src/core/piece.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const MatchFinderScript := preload("res://src/core/match_finder.gd")
const ResolverScript := preload("res://src/core/resolver.gd")
const RngScript := preload("res://src/core/rng.gd")
const MoveResultScript := preload("res://src/core/move_result.gd")

enum State { PLAYING, FINISHED }

## Screen-clockwise is the next index in HexicGrid's cyclic vertex order.
const CLOCKWISE := 1
const COUNTER_CLOCKWISE := -1

var ruleset
var board
var state: State = State.PLAYING
var score := 0
var level := 1
var combos_in_level := 0
var total_combos := 0
var seed_value := 0
var turns := 0
var shuffle_count := 0

## Timed mode (docs/design.md §6.2).
var clock := 0.0
var max_clock := 0.0
var elapsed := 0.0

## Survival mode (docs/design.md §6.3).
var round := 1
var rounds_cleared := 0
var bombs_defused := 0

## How the run ended, and whether that counts as a win.
var finish_reason := ""
var victory := false

var round_cleared := 0
var rng_refill
var _commands: Array = []

func _init(run_seed: int = 1, rules: Variant = null) -> void:
	seed_value = run_seed
	ruleset = rules if rules != null else RulesetScript.new()
	board = BoardScript.new()
	rng_refill = RngScript.new(run_seed).child("refill")
	if ruleset.mode == RulesetScript.Mode.TIMED:
		max_clock = ruleset.timed_start_seconds()
		clock = max_clock
	fill_board()

# --- queries ----------------------------------------------------------------

func combos_remaining() -> int:
	return maxi(ruleset.combos_to_advance(level) - combos_in_level, 0)

func colors() -> Array:
	return ruleset.colors_for_level(level)

func signature() -> String:
	return board.signature()

var total_cleared := 0
var total_pearls := 0
var total_starflowers := 0
var total_defused := 0


func commands() -> Array:
	return _commands.duplicate(true)

func tile_count() -> int:
	return board.filled_count()

# --- moves ------------------------------------------------------------------

## Rotates the trio around `vertex_index` one 60-degree step.
func rotate(vertex_index: int, direction: int = CLOCKWISE) -> MoveResult:
	var result := MoveResultScript.new()
	if state != State.PLAYING:
		return _reject(result, "game is over")

	var vertices := Grid.vertices()
	if direction != CLOCKWISE and direction != COUNTER_CLOCKWISE:
		return _reject(result, "direction must be +1 or -1")
	if vertex_index < 0 or vertex_index >= vertices.size():
		return _reject(result, "vertex out of range")

	var cells: Array = vertices[vertex_index]
	for cell: Vector2i in cells:
		if board.is_locked(cell):
			return _reject_settling(result, "a frozen piece cannot be turned")
	result.rotation_vertex = vertex_index
	result.rotation_cells.assign(cells)
	result.direction = direction

	TurnRules.cycle(board, cells, direction)
	if not TurnRules.makes_something(board, vertex_index, direction, cells, true):
		if ruleset.rotation_mode == RulesetScript.RotationMode.STRICT:
			# Reference behaviour: a spin that clears nothing is not a move.
			TurnRules.cycle(board, cells, -direction)
			var rejected := _reject(result, "the spin clears nothing (strict mode reverts)")
			# Still check the dead-board rule: if no spin at all can clear, the
			# player is stuck and the board must be reshuffled.
			settle(rejected)
			return rejected
		# FREE mode: the trio stays where the player left it. Still resolve, so
		# gravity re-settles anything the rotation lifted and any match the fall
		# creates is cleared (this is what makes Survival-style gaps safe).
		_record(vertex_index, direction)
		ResolverScript.resolve(board, ruleset, rng_refill, result, level, ruleset.refills_board)
		_finish_move(result)
		return result

	_record(vertex_index, direction)
	ResolverScript.resolve(board, ruleset, rng_refill, result, level, ruleset.refills_board)
	_finish_move(result)
	return result

func rotate_piece(cell: Vector2i, direction: int = CLOCKWISE) -> MoveResult:
	var result := MoveResultScript.new()
	if state != State.PLAYING:
		return _reject(result, "game is over")
	if direction != CLOCKWISE and direction != COUNTER_CLOCKWISE:
		return _reject(result, "direction must be +1 or -1")
	if not Grid.has_cell(cell):
		return _reject(result, "cell out of range")

	var piece: int = board.get_piece(cell)
	if board.is_locked(cell):
		return _reject_settling(result, "that piece is frozen")
	var cells: Array[Vector2i] = []
	if Pieces.is_starflower(piece):
		# Cyclic (angular) order, so the ring visibly turns one step.
		cells = Grid.cyclic_order(Grid.neighbours(cell))
		if cells.size() != 6:
			return _reject(result, "a starflower needs six neighbours to turn")
	elif Pieces.is_pearl(piece):
		cells = TurnRules.pearl_y_cells(cell)
		if cells.size() != 3:
			return _reject(result, "a pearl needs three neighbours in a Y to turn")
	else:
		return _reject(result, "that piece cannot be rotated on its own")
	for neighbour: Vector2i in cells:
		if board.is_locked(neighbour):
			return _reject_settling(result, "a frozen neighbour cannot be turned")

	TurnRules.cycle(board, cells, direction)
	result.piece_cell = cell
	result.rotation_cells.assign(cells)
	result.direction = direction
	_record_piece(cell, direction)
	ResolverScript.resolve(board, ruleset, rng_refill, result, level, ruleset.refills_board)
	_finish_move(result)
	return result

## Replays a logged command list on a fresh game with the same seed.
##
## `rules` is required: a replay must use the exact same ruleset as the run it
## replays (rotation mode changes what gets recorded), so this cannot default.
static func replay(run_seed: int, command_log: Array, rules: Variant) -> Game:
	assert(rules != null, "Game.replay needs the ruleset the run was played with")
	var game := Game.new(run_seed, rules)
	for command: Array in command_log:
		match String(command[0]):
			"piece":
				game.rotate_piece(Vector2i(int(command[1]), int(command[2])), int(command[3]))
			_:
				game.rotate(int(command[1]), int(command[2]))
	return game

## Fills every cell with a gem, avoiding immediate matches. Used for a new run
## and for the dead-board shuffle.
# --- turn rules -------------------------------------------------------------
# Thin delegates: the rules live in TurnRules, so the view and the tests can ask the
# same questions the move path asks without holding a Game.

func swapped_cells(cell: Vector2i) -> Array[Vector2i]:
	return TurnRules.swapped_cells(board, cell)

func is_legal_rotation(vertex_index: int, direction: int) -> bool:
	return TurnRules.is_legal_rotation(board, vertex_index, direction)

func has_legal_spin(vertex_index: int) -> bool:
	return TurnRules.has_legal_spin(board, vertex_index)

func find_legal_rotations() -> Array:
	return TurnRules.find_legal_rotations(board)

func has_any_legal_rotation() -> bool:
	return TurnRules.has_any_legal_rotation(board)

func fill_board() -> void:
	board.clear_locks()
	var palette: Array = colors()
	for cell: Vector2i in Grid.all_cells():
		var candidates: Array = palette.duplicate()
		rng_refill.shuffle(candidates)
		var placed := false
		for color: int in candidates:
			board.set_piece(cell, Pieces.make(Pieces.Kind.GEM, color))
			if not MatchFinderScript.has_any_match(board):
				placed = true
				break
		if not placed:
			# No colour avoids a match here; take the first and let the settle
			# pass below clear it so a run always starts on a stable board.
			board.set_piece(cell, Pieces.make(Pieces.Kind.GEM, candidates[0]))

	if MatchFinderScript.has_any_match(board):
		var settle := MoveResultScript.new()
		ResolverScript.resolve(board, ruleset, rng_refill, settle, level, true)

# --- internals --------------------------------------------------------------

func _record(vertex_index: int, direction: int) -> void:
	_commands.append(["rotate", vertex_index, direction])
	turns += 1

func _record_piece(cell: Vector2i, direction: int) -> void:
	_commands.append(["piece", cell.x, cell.y, direction])
	turns += 1

func _reject(result: MoveResult, reason: String) -> MoveResult:
	result.committed = false
	result.rejected_reason = reason
	return result

## A rejection that still lets the board close its round: a Survival board where
## everything is frozen must not be able to soft-lock the player.
func _reject_settling(result: MoveResult, reason: String) -> MoveResult:
	settle(_reject(result, reason))
	return result

func _award(result: MoveResult) -> void:
	score += result.score
	total_combos += result.combos
	combos_in_level += result.combos
	while level < ruleset.max_level() and combos_in_level >= ruleset.combos_to_advance(level):
		combos_in_level -= ruleset.combos_to_advance(level)
		level += 1
		result.level_up = true
	result.new_level = level

## Shared tail of every committed move: bank the score, pay out mode-specific
## rewards, age the bombs, and check whether the board is still playable.
func _finish_move(result: MoveResult) -> void:
	# Lifetime counters. These are what the summary reports, and before they existed
	# ProfileService invented a zero for each one.
	total_cleared += result.cleared_count
	total_defused += result.bombs_defused
	for promotion: Dictionary in result.promotions:
		match str(promotion.get("kind", "")):
			"starflower":
				total_starflowers += 1
			"pearl":
				total_pearls += 1
	_award(result)
	if ruleset.mode == RulesetScript.Mode.SURVIVAL:
		round_cleared += result.cleared_count
	bombs_defused += result.bombs_defused
	_reward_clock(result)

	if result.finished:
		# The resolver ended the run itself (a pearl finish).
		finish_run(result.finish_kind, true)
		result.game_over = false
		settle(result)
		return

	_tick_bombs(result)
	settle(result)

## Timed mode: clears buy seconds back; a starflower refills and raises the cap
## (docs/design.md §6.2).
func _reward_clock(result: MoveResult) -> void:
	if ruleset.mode != RulesetScript.Mode.TIMED:
		return
	clock += float(result.cleared_count) * RulesetScript.TIMED_PER_GEM
	clock += float(result.combos) * RulesetScript.TIMED_PER_COMBO

	var bloomed := false
	for promotion: Dictionary in result.promotions:
		if int(promotion["piece"]) == Pieces.starflower():
			bloomed = true
	if bloomed:
		max_clock = minf(max_clock + RulesetScript.TIMED_STARFLOWER_BONUS, RulesetScript.TIMED_CAP)
		clock = max_clock
	elif result.level_up:
		clock = max_clock
	else:
		clock = minf(clock, max_clock)

## Fuses tick once per committed move; BombRules decides what happens and reports
## whether one went off. Ending the run stays here.
func _tick_bombs(result: MoveResult) -> void:
	if BombRules.tick(board, result):
		finish_run("bomb_exploded", false)
func settle(result: MoveResult) -> void:
	if state != State.FINISHED and not result.finished:
		if ruleset.mode == RulesetScript.Mode.SURVIVAL:
			SurvivalDirector.settle(self, result)
		elif not MatchFinderScript.has_any_match(board) and not has_any_legal_rotation():
			result.dead_board = true
			_shuffle_board()
			result.shuffled = true
			shuffle_count += 1
	result.new_level = level
func finish_run(reason: String, did_win: bool) -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	finish_reason = reason
	victory = did_win

func did_win() -> bool:
	return victory

## Advances real time. Only Timed mode cares; the view calls this each frame.
func tick(delta: float) -> void:
	if state != State.PLAYING or ruleset.mode != RulesetScript.Mode.TIMED:
		return
	elapsed += delta
	clock = maxf(clock - delta, 0.0)
	if clock <= 0.0:
		finish_run("time_out", false)

func mode_name() -> String:
	match ruleset.mode:
		RulesetScript.Mode.TIMED:
			return "Timed"
		RulesetScript.Mode.SURVIVAL:
			return "Survival"
		_:
			return "Marathon"

## What the run reports when it ends. A typed record rather than a dictionary:
## the consumers used to read it with invented defaults, including five fields
## that were never written at all.
func summary() -> RunSummary:
	return RunSummary.from_game(self)

## Redistributes the existing gems; if no arrangement is playable (or the board
## is empty), regenerates a fresh one.
func _shuffle_board() -> void:
	var cells := Grid.all_cells()
	# Only permute occupied cells: scattering pieces into empty space would
	# leave them floating (Survival-style boards have gaps).
	var occupied: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not board.is_empty(cell):
			occupied.append(cell)
	if occupied.size() < 3:
		fill_board()
		return

	var pieces: Array[int] = []
	for cell: Vector2i in occupied:
		pieces.append(board.get_piece(cell))

	for attempt in 12:
		rng_refill.shuffle(pieces)
		for cell: Vector2i in cells:
			board.remove_piece(cell)
		for index in occupied.size():
			board.set_piece(occupied[index], pieces[index])
		board.apply_gravity()
		if not MatchFinderScript.has_any_match(board) and has_any_legal_rotation():
			return

	fill_board()
