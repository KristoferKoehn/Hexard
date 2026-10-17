class_name Resolver
extends RefCounted

## Cascade state machine (docs/design.md §3.3).
##
## Repeats until the board is stable: find the highest-priority formation, score
## and remove it, fall, refill. One category resolves per iteration, so
## simultaneous events stay deterministic.
##
## Every formation ends in `_clear()`, which owns the bookkeeping (group, combo,
## clear count, cell removal) while the handler owns the scoring. Adding a new
## formation means writing one handler and one line in `_resolve_step()`.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinderScript := preload("res://src/core/match_finder.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const ScoringScript := preload("res://src/core/scoring_rules.gd")
const ClearGroupScript := preload("res://src/core/clear_group.gd")


## Mutates `board`, accumulating everything into `result`.
## `refill` is false in Survival mode, where cleared cells stay empty for the
## rest of the round.
static func resolve(board: Board, ruleset: Ruleset, rng: Rng, result: MoveResult, level: int, refill: bool = true) -> void:
	# Pieces fall before formations are judged. On a board with gaps (Survival) a
	# rotation can lift a piece into an empty cell, so this pass is what keeps
	# "nothing is ever left floating" true after *every* move.
	apply_gravity(board, result)

	var depth := 0
	while true:
		if not _resolve_step(board, ruleset, result, level, depth + 1):
			break
		depth += 1
		apply_gravity(board, result, depth)
		if refill:
			refill_board(board, rng, result, level, ruleset, depth)
		if result.finished:
			break
	result.cascades = depth


## One resolution step, highest priority first. Short-circuits on the first
## category that actually did something.
static func _resolve_step(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	return (
		_resolve_flowers(board, ruleset, result, level, depth)
		or _resolve_pearl_rings(board, ruleset, result, level, depth)
		or _resolve_pearl_finish(board, ruleset, result, level, depth)
		or _resolve_star_clusters(board, ruleset, result, level, depth)
		or _resolve_starflower_clusters(board, ruleset, result, level, depth)
		or _resolve_colour_clusters(board, ruleset, result, level, depth)
	)


# --- formations -------------------------------------------------------------

## Ring of six same-coloured gems: the ring clears and the centre blooms into a
## starflower — or into a black pearl when it was already a starflower.
##
## Survival has no starflowers: there a flower unlocks the whole board and sweeps
## every gem of the ring colour instead (docs/design.md §6.3).
static func _resolve_flowers(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var centres := MatchFinderScript.flower_centres(board)
	if centres.is_empty():
		return false

	var survival := int(ruleset.mode) == int(RulesetScript.Mode.SURVIVAL)
	for centre: Vector2i in centres:
		if not MatchFinderScript.is_flower(board, centre):
			continue  # an earlier flower in this batch may have consumed it
		var ring := Grid.neighbours(centre)
		var ring_color := int(Pieces.color_of(board.get_piece(ring[0])))
		_clear(
			board, result, ring, depth,
			ruleset.scoring.points(ScoringScript.FLOWER_BASE),
			ruleset.scoring.score_for(ScoringScript.FLOWER_BASE, level, depth, ruleset.difficulty),
			["flower"]
		)
		if survival:
			_survival_flourish(board, ruleset, result, level, depth, centre, ring_color)
		elif Pieces.is_starflower(board.get_piece(centre)):
			_promote(board, result, centre, Pieces.Kind.PEARL)
		else:
			_promote(board, result, centre, Pieces.Kind.STARFLOWER)
	return true


## Six starflowers ringing a centre: the starflowers are consumed and the centre
## becomes a black pearl (docs/design.md §3.4).
static func _resolve_pearl_rings(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var centres := MatchFinderScript.pearl_ring_centres(board)
	if centres.is_empty():
		return false

	for centre: Vector2i in centres:
		if not MatchFinderScript.is_pearl_creation_ring(board, centre):
			continue  # an earlier ring in this batch may have consumed it
		_clear(
			board, result, Grid.neighbours(centre), depth,
			ruleset.scoring.points(ScoringScript.PEARL_BASE),
			ruleset.scoring.score_for(ScoringScript.PEARL_BASE, level, depth, ruleset.difficulty),
			["pearl_built"]
		)
		_promote(board, result, centre, Pieces.Kind.PEARL)
	return true


## The perfect finish: a pearl cluster or a pearl ring ends the run.
static func _resolve_pearl_finish(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var finish := MatchFinderScript.pearl_finish(board)
	if finish.is_empty():
		return false

	var kind: String = finish["kind"]
	var key := ScoringScript.PEARL_RING_BASE if kind == "pearl_ring" else ScoringScript.PEARL_CLUSTER_BASE
	_clear(
		board, result, finish["cells"], depth,
		ruleset.scoring.points(key),
		ruleset.scoring.score_for(key, level, depth, ruleset.difficulty),
		[kind]
	)
	result.finished = true
	result.finish_kind = kind
	return true


## Three bonus stars of any colours: they clear, plus every tile they touch.
static func _resolve_star_clusters(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var cells := MatchFinderScript.star_cluster_cells(board)
	if cells.is_empty():
		return false

	var formations := ["bonus_star_cluster"]
	if _thaw_around(board, cells) > 0:
		formations.append("thawed")
	_clear(
		board, result, cells, depth,
		ruleset.scoring.points(ScoringScript.STAR_CLUSTER_BASE),
		ruleset.scoring.score_for(ScoringScript.STAR_CLUSTER_BASE, level, depth, ruleset.difficulty),
		formations
	)
	return true


## Three starflowers together are worth a windfall.
static func _resolve_starflower_clusters(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var cells := MatchFinderScript.starflower_cluster_cells(board)
	if cells.is_empty():
		return false

	_clear(
		board, result, cells, depth,
		ruleset.scoring.points(ScoringScript.STARFLOWER_MATCH_BASE),
		ruleset.scoring.score_for(ScoringScript.STARFLOWER_MATCH_BASE, level, depth, ruleset.difficulty),
		["starflower_cluster"]
	)
	return true


## Ordinary colour clusters, plus the two bomb rules: a defuse bonus, and a
## colour wipe when a bonus star of the bomb's colour is in the same clear.
static func _resolve_colour_clusters(board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int) -> bool:
	var groups: Array = MatchFinderScript.clear_groups(board)
	if groups.is_empty():
		return false

	for group in groups:
		var stars := 0
		var bombs: Array[Vector2i] = []
		for cell: Vector2i in group.cells:
			var piece: int = board.get_piece(cell)
			if Pieces.is_bonus_star(piece):
				stars += 1
			elif Pieces.is_bomb(piece):
				bombs.append(cell)

		var multiplier := int(pow(2.0, stars))
		var base: int = ruleset.scoring.base_for_cluster(group.cells.size())
		var score: int = (
			ruleset.scoring.clear_score(base, level, depth, ruleset.difficulty) * multiplier
		)
		var clear_cells: Array[Vector2i] = group.cells.duplicate()
		var formations := ["cluster"]
		var bonus_base := 0

		for bomb_cell: Vector2i in bombs:
			bonus_base += ruleset.scoring.points(ScoringScript.BOMB_DEFUSE_BASE)
			var bomb_color := int(Pieces.color_of(board.get_piece(bomb_cell)))
			if not _has_star_of_color(board, group.cells, bomb_color):
				continue
			var wiped := 0
			for cell: Vector2i in MatchFinderScript.cells_with_color(board, bomb_color):
				if clear_cells.has(cell):
					continue
				clear_cells.append(cell)
				wiped += 1
			if wiped > 0:
				bonus_base += ruleset.scoring.points(ScoringScript.BOMB_COLOUR_WIPE_BASE) * wiped
				if not formations.has("bomb_colour_wipe"):
					formations.append("bomb_colour_wipe")

		if not bombs.is_empty():
			result.bombs_defused += bombs.size()
			formations.append("bomb_defused")
			score += ruleset.scoring.clear_score(bonus_base, level, depth, ruleset.difficulty)
			if stars > 0 and _thaw_around(board, clear_cells) > 0:
				formations.append("thawed")

		var emitted := _clear(board, result, clear_cells, depth, base, score, formations)
		emitted.bonus_stars = stars
		emitted.multiplier = multiplier
	return true


# --- helpers ----------------------------------------------------------------

## Books one clear event: the group, the score, the combo, and the removal.
## Scoring stays with the caller, so every formation can price itself however
## the design document says.
static func _clear(
	board: Board, result: MoveResult, cells: Array, depth: int, base_score: int, score: int, formations: Array
) -> RefCounted:
	var group := ClearGroupScript.new()
	group.cells = _sorted(cells)
	group.cascade_depth = depth
	group.base_score = base_score
	group.score = score
	group.set_formations(formations)
	result.clear_groups.append(group)
	result.score += score
	result.cleared_count += group.cells.size()
	result.combos += 1
	for cell: Vector2i in group.cells:
		board.remove_piece(cell)
	return group


## The centre of a bloom becomes a new special piece.
static func _promote(board: Board, result: MoveResult, centre: Vector2i, kind: int) -> void:
	var piece := Pieces.make(kind, Pieces.GemColor.NONE)
	board.set_piece(centre, piece)
	result.promotions.append({"cell": centre, "piece": piece, "kind": Pieces.KIND_NAMES[kind]})


## Survival's replacement for blooming: thaw the board, then sweep the colour.
static func _survival_flourish(
	board: Board, ruleset: Ruleset, result: MoveResult, level: int, depth: int, centre: Vector2i, ring_color: int
) -> void:
	var thawed: int = board.unlock_all()
	var sweep := MatchFinderScript.cells_with_color(board, ring_color)
	if not sweep.is_empty():
		_clear(
			board, result, sweep, depth,
			ruleset.scoring.points(ScoringScript.FLOWER_SWEEP_BASE) * sweep.size(),
			ruleset.scoring.clear_score(
				ruleset.scoring.points(ScoringScript.FLOWER_SWEEP_BASE) * sweep.size(),
				level, depth, ruleset.difficulty
			),
			["flower_sweep"]
		)
	result.promotions.append(
		{"cell": centre, "piece": Pieces.EMPTY, "kind": "unlock_all", "thawed": thawed}
	)


## A blast thaws the frozen tiles around everything it touched.
static func _thaw_around(board: Board, cells: Array) -> int:
	var thawed := 0
	for cell: Vector2i in cells:
		for neighbour: Vector2i in Grid.neighbours(cell):
			if board.is_locked(neighbour):
				board.unlock(neighbour)
				thawed += 1
	return thawed


static func _has_star_of_color(board: Board, cells: Array, gem_color: int) -> bool:
	for cell: Vector2i in cells:
		var piece: int = board.get_piece(cell)
		if Pieces.is_bonus_star(piece) and int(Pieces.color_of(piece)) == gem_color:
			return true
	return false


static func _sorted(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells:
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return out


# --- board upkeep -----------------------------------------------------------

## Gravity pass; records moves into `result` when one is supplied.
static func apply_gravity(board: Board, result: MoveResult = null, depth: int = 0) -> void:
	if result == null:
		board.apply_gravity()
		return
	for move: Dictionary in board.apply_gravity_moves():
		move["depth"] = depth
		result.gravity_moves.append(move)


## New pieces fall in above the top edge to fill the gaps gravity left behind.
## From level 2 some of them are bonus stars; from level 3 some are bombs.
static func refill_board(board: Board, rng: Rng, result: MoveResult, level: int, ruleset: Ruleset, depth: int = 0) -> void:
	var colors: Array = Pieces.colors_for_level(level)
	for column_index in Grid.COLUMNS:
		for cell: Vector2i in Grid.column(column_index):
			if not board.is_empty(cell):
				continue
			var piece := _roll_piece(rng, colors, ruleset, level)
			board.set_piece(cell, piece)
			result.spawns.append({"cell": cell, "piece": piece, "depth": depth})


static func _roll_piece(rng: Rng, colors: Array, ruleset: Ruleset, level: int) -> int:
	var roll: float = rng.next_float()
	var bomb_chance: float = ruleset.bomb_chance_at(level)
	if bomb_chance > 0.0 and roll < bomb_chance:
		return Pieces.bomb(rng.pick(colors), ruleset.bomb_counter_at(level))
	var star_chance: float = ruleset.bonus_star_chance_at(level)
	if star_chance > 0.0 and roll < bomb_chance + star_chance:
		return Pieces.bonus_star(rng.pick(colors))
	return Pieces.gem(rng.pick(colors))
