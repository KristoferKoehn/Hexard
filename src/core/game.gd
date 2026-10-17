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

var _round_cleared := 0
var _rng_refill
var _commands: Array = []


func _init(run_seed: int = 1, rules: Variant = null) -> void:
	seed_value = run_seed
	ruleset = rules if rules != null else RulesetScript.new()
	board = BoardScript.new()
	_rng_refill = RngScript.new(run_seed).child("refill")
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
	for cell: Vector2i in cells:
		if board.is_locked(cell):
			return _reject_settling(result, "a frozen piece cannot be turned")
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
		_finish_move(result)
		return result

	_record(vertex_index, direction)
	ResolverScript.resolve(board, ruleset, _rng_refill, result, level, ruleset.refills_board)
	_finish_move(result)
	return result


## Rotates a special piece in place (docs/design.md §3.4):
##   starflower -> cycles all six neighbours one step
##   black pearl -> cycles three of six neighbours in a Y / inverted-Y
## These rotations always persist, match or not, in both rotation modes.
func rotate_piece(cell: Vector2i, direction: int = CLOCKWISE):
	var result = MoveResultScript.new()
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
		cells = _pearl_y_cells(cell)
		if cells.size() != 3:
			return _reject(result, "a pearl needs six neighbours to turn")
	else:
		return _reject(result, "that piece cannot be rotated on its own")
	for neighbour: Vector2i in cells:
		if board.is_locked(neighbour):
			return _reject_settling(result, "a frozen neighbour cannot be turned")

	_cycle(cells, direction)
	result.piece_cell = cell
	result.rotation_cells.assign(cells)
	result.direction = direction
	_record_piece(cell, direction)
	ResolverScript.resolve(board, ruleset, _rng_refill, result, level, ruleset.refills_board)
	_finish_move(result)
	return result


## Three of a pearl's six neighbours, alternating around it. Which three depends
## on the column parity, which gives the reference's Y and inverted-Y shapes.
func _pearl_y_cells(cell: Vector2i) -> Array[Vector2i]:
	var ordered := Grid.cyclic_order(Grid.neighbours(cell))
	var cells: Array[Vector2i] = []
	var parity := cell.x % 2
	for index in ordered.size():
		if index % 2 == parity:
			cells.append(ordered[index])
	return cells


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


## Would spinning this vertex one step in this direction clear anything?
## Cheap (two rotations and a local match test), so the view can ask per frame.
func is_legal_rotation(vertex_index: int, direction: int) -> bool:
	var vertices := Grid.vertices()
	if vertex_index < 0 or vertex_index >= vertices.size():
		return false
	if direction != CLOCKWISE and direction != COUNTER_CLOCKWISE:
		return false
	return _rotation_matches(vertex_index, direction, vertices[vertex_index])


## True when either direction clears here — what the cursor highlight shows.
func has_legal_spin(vertex_index: int) -> bool:
	return is_legal_rotation(vertex_index, CLOCKWISE) \
		or is_legal_rotation(vertex_index, COUNTER_CLOCKWISE)


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
	board.clear_locks()
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
	_commands.append(["rotate", vertex_index, direction])
	turns += 1


func _record_piece(cell: Vector2i, direction: int) -> void:
	_commands.append(["piece", cell.x, cell.y, direction])
	turns += 1


func _reject(result, reason: String):
	result.committed = false
	result.rejected_reason = reason
	return result


## A rejection that still lets the board close its round: a Survival board where
## everything is frozen must not be able to soft-lock the player.
func _reject_settling(result, reason: String):
	settle(_reject(result, reason))
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


## Shared tail of every committed move: bank the score, pay out mode-specific
## rewards, age the bombs, and check whether the board is still playable.
func _finish_move(result) -> void:
	_award(result)
	if ruleset.mode == RulesetScript.Mode.SURVIVAL:
		_round_cleared += result.cleared_count
	bombs_defused += result.bombs_defused
	_reward_clock(result)

	if result.finished:
		# The resolver ended the run itself (a pearl finish).
		_finish(result.finish_kind, true)
		result.game_over = false
		settle(result)
		return

	_tick_bombs(result)
	settle(result)


## Timed mode: clears buy seconds back; a starflower refills and raises the cap
## (docs/design.md §6.2).
func _reward_clock(result) -> void:
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


## Every bomb loses one move. Reaching zero detonates it and ends the run.
func _tick_bombs(result) -> void:
	var exploders: Array[Vector2i] = []
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_bomb(piece):
			continue
		var remaining := Pieces.counter_of(piece) - 1
		if remaining <= 0:
			exploders.append(cell)
			board.set_piece(cell, Pieces.with_counter(piece, 0))
			continue
		board.set_piece(cell, Pieces.with_counter(piece, remaining))
		result.bombs_ticked.append({"cell": cell, "counter": remaining})

	if exploders.is_empty():
		return
	result.bomb_exploded = true
	result.game_over = true
	result.finished = true
	result.finish_kind = "bomb_exploded"
	result.exploded_cells.assign(exploders)
	_finish("bomb_exploded", false)


## After every move: is the board still playable? (docs/design.md §5.3, §6.3)
func settle(result) -> void:
	if state != State.FINISHED and not result.finished:
		if ruleset.mode == RulesetScript.Mode.SURVIVAL:
			_settle_survival(result)
		elif not MatchFinderScript.has_any_match(board) and not has_any_legal_rotation():
			result.dead_board = true
			_shuffle_board()
			result.shuffled = true
			shuffle_count += 1
	result.new_level = level


## Survival never reshuffles: when nothing can be cleared the round is over —
## the leftovers freeze, the gaps refill, and the next round begins.
func _settle_survival(result) -> void:
	if board.filled_count() == 0:
		_end_survival("board_cleared", true, result)
		return
	if has_any_legal_rotation():
		return
	_close_round(result)


## Ends the current Survival round: pay the round bonus, freeze what is left,
## refill, and check the two survival endings.
func _close_round(result) -> void:
	var bonus := _round_cleared * RulesetScript.SURVIVAL_ROUND_BONUS_PER_GEM
	score += bonus
	result.score += bonus
	result.round_bonus = bonus
	_round_cleared = 0
	round += 1
	rounds_cleared += 1
	result.round_ended = true
	result.round_reached = round

	board.lock_all_remaining()
	if board.empty_cells().is_empty():
		# Everything on the board froze: there is nowhere left to play.
		_end_survival("all_locked", false, result)
		return

	ResolverScript.refill_board(board, _rng_refill, result, level, ruleset)
	# Fresh pieces can land straight into a match; settle them so the new round
	# starts stable (this is the only refill outside a resolve loop).
	ResolverScript.resolve(board, ruleset, _rng_refill, result, level, ruleset.refills_board)

	if rounds_cleared >= RulesetScript.SURVIVAL_ROUNDS_TO_WIN:
		_end_survival("rounds_survived", true, result)


## Marks the run finished from inside a move's bookkeeping.
func _end_survival(reason: String, did_win: bool, result) -> void:
	_finish(reason, did_win)
	result.finished = true
	result.finish_kind = reason


# --- run lifecycle ----------------------------------------------------------

func _finish(reason: String, did_win: bool) -> void:
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
		_finish("time_out", false)


func mode_name() -> String:
	match ruleset.mode:
		RulesetScript.Mode.TIMED:
			return "Timed"
		RulesetScript.Mode.SURVIVAL:
			return "Survival"
		_:
			return "Marathon"


func summary() -> Dictionary:
	return {
		"mode": mode_name(),
		"difficulty": ruleset.difficulty,
		"score": score,
		"level": level,
		"combos": total_combos,
		"turns": turns,
		"rounds": rounds_cleared,
		"reason": finish_reason,
		"won": victory,
		"elapsed": elapsed,
	}


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
