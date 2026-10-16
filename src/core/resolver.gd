class_name Resolver
extends RefCounted

## Cascade state machine (docs/design.md §3.3).
##
## Repeats until the board is stable:
##   find clear groups -> score and remove them -> gravity -> refill
##
## Everything is deterministic for a given board, ruleset and RNG state, which
## is what makes replays and golden tests possible.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinderScript := preload("res://src/core/match_finder.gd")


## Mutates `board`, accumulating everything into `result`.
## `refill` is false in Survival mode, where cleared cells stay empty for the
## rest of the round.
static func resolve(board, ruleset, rng, result, level: int, refill: bool = true) -> void:
	# Pieces fall before matches are judged. On a board with gaps (Survival) a
	# rotation can lift a piece into an empty cell, so this pass is what keeps
	# "nothing is ever left floating" true after *every* move.
	apply_gravity(board, result)

	var depth := 0
	while true:
		var groups: Array = MatchFinderScript.clear_groups(board)
		if groups.is_empty():
			break
		depth += 1
		for group in groups:
			group.cascade_depth = depth
			group.base_score = ruleset.scoring.base_for_cluster(group.size())
			group.score = ruleset.scoring.clear_score(
				group.base_score, level, depth, ruleset.difficulty
			)
			result.clear_groups.append(group)
			result.score += group.score
			result.cleared_count += group.size()
			# One clear event counts as one combo, cascade steps included.
			result.combos += 1
			for cell: Vector2i in group.cells:
				board.remove_piece(cell)
		apply_gravity(board, result)
		if refill:
			refill_board(board, rng, result, level)
	result.cascades = depth


## Gravity pass; records moves into `result` when one is supplied.
static func apply_gravity(board, result = null) -> void:
	if result == null:
		board.apply_gravity()
		return
	var moves: Array = board.apply_gravity_moves()
	for move: Dictionary in moves:
		result.gravity_moves.append(move)


## New gems fall in above the top edge to fill the gaps gravity left behind.
static func refill_board(board, rng, result, level: int) -> void:
	var colors: Array = Pieces.colors_for_level(level)
	for column_index in Grid.COLUMNS:
		for cell: Vector2i in Grid.column(column_index):
			if not board.is_empty(cell):
				continue
			var piece := Pieces.make(Pieces.Kind.GEM, rng.pick(colors))
			board.set_piece(cell, piece)
			result.spawns.append({"cell": cell, "piece": piece})
