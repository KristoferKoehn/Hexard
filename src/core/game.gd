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

var _rng_refill
var _commands: Array = []


func _init(run_seed: int = 1, rules: Variant = null) -> void:
	seed_value = run_seed
	ruleset = rules if rules != null else RulesetScript.new()
	board = BoardScript.new()
	_rng_refill = RngScript.new(run_seed).child("refill")
	fill_board()


# --- queries ----------------------------------------------------------------

func combos_remaining() -> int:
	return maxi(ruleset.combos_to_advance(level) - combos_in_level, 0)


func colors() -> Array:
	return ruleset.colors_for_level(level)


func signature() -> String:
	return board.signature()


func commands() -> Array:
	return _commands.duplicate(true)


func tile_count() -> int:
	return board.filled_count()


# --- moves ------------------------------------------------------------------

## Rotates the trio around `vertex_index` one 60-degree step.
func rotate(vertex_index: int, direction: int = CLOCKWISE):
	var result = MoveResultScript.new()
	if state != State.PLAYING:
		return _reject(result, "game is over")

	var vertices := Grid.vertices()
	if direction != CLOCKWISE and direction != COUNTER_CLOCKWISE:
		return _reject(result, "direction must be +1 or -1")
	if vertex_index < 0 or vertex_index >= vertices.size():
		return _reject(result, "vertex out of range")

	var cells: Array = vertices[vertex_index]
	result.rotation_vertex = vertex_index
	result.rotation_cells.assign(cells)
	result.direction = direction

	_cycle(cells, direction)
	if not MatchFinderScript.matches_near_vertex(board, vertex_index):
		if ruleset.rotation_mode == RulesetScript.RotationMode.STRICT:
			# Reference behaviour: a spin that clears nothing is not a move.
			_cycle(cells, -direction)
			var rejected = _reject(result, "no match (strict mode reverts)")
			# Still check the dead-board rule: if no spin at all can clear, the
			# player is stuck and the board must be reshuffled.
			settle(rejected)
			return rejected
		# FREE mode: the trio stays where the player left it. Still resolve, so
		# gravity re-settles anything the rotation lifted and any match the fall
		# creates is cleared (this is what makes Survival-style gaps safe).
		_record(vertex_index, direction)
		ResolverScript.resolve(board, ruleset, _rng_refill, result, level, ruleset.refills_board)
		settle(result)
		return result

	_record(vertex_index, direction)
	ResolverScript.resolve(board, ruleset, _rng_refill, result, level, ruleset.refills_board)
	_award(result)
	settle(result)
	return result


## Replays a logged command list on a fresh game with the same seed.
##
## `rules` is required: a replay must use the exact same ruleset as the run it
## replays (rotation mode changes what gets recorded), so this cannot default.
static func replay(run_seed: int, command_log: Array, rules: Variant) -> Game:
	assert(rules != null, "Game.replay needs the ruleset the run was played with")
	var game := Game.new(run_seed, rules)
	for command: Array in command_log:
		game.rotate(int(command[0]), int(command[1]))
	return game


## Every rotation that would clear something right now. Doubles as the hint
## source and the dead-board test.
func find_legal_rotations() -> Array:
	var out: Array = []
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		for direction in [CLOCKWISE, COUNTER_CLOCKWISE]:
			if _rotation_matches(vertex_index, direction, vertices[vertex_index]):
				out.append({"vertex": vertex_index, "direction": direction})
	return out


func has_any_legal_rotation() -> bool:
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		for direction in [CLOCKWISE, COUNTER_CLOCKWISE]:
			if _rotation_matches(vertex_index, direction, vertices[vertex_index]):
				return true
	return false


# --- board setup ------------------------------------------------------------

## Fills every cell with a gem, avoiding immediate matches. Used for a new run
## and for the dead-board shuffle.
func fill_board() -> void:
	var palette: Array = colors()
	for cell: Vector2i in Grid.all_cells():
		var candidates: Array = palette.duplicate()
		_rng_refill.shuffle(candidates)
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
		var settle = MoveResultScript.new()
		ResolverScript.resolve(board, ruleset, _rng_refill, settle, level, true)


# --- internals --------------------------------------------------------------

## Cycles the pieces around a vertex. +1 moves each piece to the next cell in
## cyclic order (clockwise on screen); -1 is the exact inverse.
func _cycle(cells: Array, direction: int) -> void:
	var count := cells.size()
	var pieces: Array[int] = []
	for cell: Vector2i in cells:
		pieces.append(board.get_piece(cell))
	for index in count:
		board.set_piece(cells[index], pieces[posmod(index - direction, count)])


func _rotation_matches(vertex_index: int, direction: int, cells: Array) -> bool:
	_cycle(cells, direction)
	var matched := MatchFinderScript.matches_near_vertex(board, vertex_index)
	_cycle(cells, -direction)
	return matched


func _record(vertex_index: int, direction: int) -> void:
	_commands.append([vertex_index, direction])
	turns += 1


func _reject(result, reason: String):
	result.committed = false
	result.rejected_reason = reason
	return result


func _award(result) -> void:
	score += result.score
	total_combos += result.combos
	combos_in_level += result.combos
	while level < ruleset.max_level() and combos_in_level >= ruleset.combos_to_advance(level):
		combos_in_level -= ruleset.combos_to_advance(level)
		level += 1
		result.level_up = true
	result.new_level = level


## After every move: is the board still playable? (docs/design.md §5.3)
func settle(result) -> void:
	if not MatchFinderScript.has_any_match(board) and not has_any_legal_rotation():
		result.dead_board = true
		_shuffle_board()
		result.shuffled = true
		shuffle_count += 1
	result.new_level = level


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
		_rng_refill.shuffle(pieces)
		for cell: Vector2i in cells:
			board.remove_piece(cell)
		for index in occupied.size():
			board.set_piece(occupied[index], pieces[index])
		board.apply_gravity()
		if not MatchFinderScript.has_any_match(board) and has_any_legal_rotation():
			return

	fill_board()
