class_name Resolver
extends RefCounted

## Cascade state machine (docs/design.md §3.3).
##
## Repeats until the board is stable:
##   find the highest-priority formation -> score and remove it -> gravity -> refill
##
## Priority order (one category per iteration, so simultaneous events stay
## deterministic): flowers, pearl finish, bonus-star clusters, starflower
## clusters, colour clusters.
##
## Everything is deterministic for a given board, ruleset and RNG state, which
## is what makes replays and golden tests possible.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinderScript := preload("res://src/core/match_finder.gd")
const ClearGroupScript := preload("res://src/core/clear_group.gd")


## Mutates `board`, accumulating everything into `result`.
## `refill` is false in Survival mode, where cleared cells stay empty for the
## rest of the round.
static func resolve(board, ruleset, rng, result, level: int, refill: bool = true) -> void:
	# Pieces fall before formations are judged. On a board with gaps (Survival)
	# a rotation can lift a piece into an empty cell, so this pass is what keeps
	# "nothing is ever left floating" true after *every* move.
	apply_gravity(board, result)

	var depth := 0
	while true:
		if not _resolve_step(board, ruleset, result, level, depth + 1):
			break
		depth += 1
		apply_gravity(board, result)
		if refill:
			refill_board(board, rng, result, level, ruleset)
		if result.finished:
			break
	result.cascades = depth


## One resolution step. Returns true when something happened.
static func _resolve_step(board, ruleset, result, level: int, depth: int) -> bool:
	if _resolve_flowers(board, ruleset, result, level, depth):
		return true
	if _resolve_pearl_rings(board, ruleset, result, level, depth):
		return true
	if _resolve_pearl_finish(board, ruleset, result, level, depth):
		return true
	if _resolve_star_clusters(board, ruleset, result, level, depth):
		return true
	if _resolve_starflower_clusters(board, ruleset, result, level, depth):
		return true
	return _resolve_colour_clusters(board, ruleset, result, level, depth)


## Six starflowers ringing a centre: the starflowers are consumed and the centre
## becomes a black pearl (docs/design.md §3.4).
static func _resolve_pearl_rings(board, ruleset, result, level: int, depth: int) -> bool:
	var centres := MatchFinderScript.pearl_ring_centres(board)
	if centres.is_empty():
		return false

	for centre: Vector2i in centres:
		if not MatchFinderScript.is_pearl_creation_ring(board, centre):
			continue  # an earlier ring in this batch may have consumed it
		var ring := Grid.neighbours(centre)
		var group = ClearGroupScript.new()
		group.cells = _sorted(ring)
		group.cascade_depth = depth
		group.base_score = ruleset.scoring.points("pearl_base")
		group.score = ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
		group.set_formations(["pearl_built"])
		_record(result, group)
		for cell: Vector2i in ring:
			board.remove_piece(cell)
		board.set_piece(centre, Pieces.pearl())
		result.promotions.append({"cell": centre, "piece": Pieces.pearl()})
	return true


## Ring of six same-coloured gems: the ring clears and the centre blooms into a
## starflower — or into a black pearl when it was already a starflower.
static func _resolve_flowers(board, ruleset, result, level: int, depth: int) -> bool:
	var centres := MatchFinderScript.flower_centres(board)
	if centres.is_empty():
		return false

	for centre: Vector2i in centres:
		if not MatchFinderScript.is_flower(board, centre):
			continue  # an earlier flower in this batch may have consumed it
		var ring := Grid.neighbours(centre)
		var group = ClearGroupScript.new()
		group.cells = _sorted(ring)
		group.cascade_depth = depth
		group.base_score = ruleset.scoring.points("flower_base")
		group.score = ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
		group.set_formations(["flower"])
		_record(result, group)
		for cell: Vector2i in ring:
			board.remove_piece(cell)

		var centre_piece: int = board.get_piece(centre)
		if Pieces.is_starflower(centre_piece):
			# A flower around a starflower is the pearl recipe.
			board.set_piece(centre, Pieces.pearl())
			result.promotions.append({"cell": centre, "piece": Pieces.pearl()})
		else:
			board.set_piece(centre, Pieces.starflower())
			result.promotions.append({"cell": centre, "piece": Pieces.starflower()})
	return true


## The perfect finish: a pearl cluster or a pearl ring ends the run.
static func _resolve_pearl_finish(board, ruleset, result, level: int, depth: int) -> bool:
	var finish := MatchFinderScript.pearl_finish(board)
	if finish.is_empty():
		return false

	var kind: String = finish["kind"]
	var key := "pearl_ring_base" if kind == "pearl_ring" else "pearl_cluster_base"
	var group = ClearGroupScript.new()
	group.cells = _sorted(finish["cells"])
	group.cascade_depth = depth
	group.base_score = ruleset.scoring.points(key)
	group.score = ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
	group.set_formations([kind])
	_record(result, group)
	for cell: Vector2i in group.cells:
		board.remove_piece(cell)

	result.finished = true
	result.finish_kind = kind
	return true


## Three bonus stars of any colours: they clear, plus every tile they touch.
static func _resolve_star_clusters(board, ruleset, result, level: int, depth: int) -> bool:
	var cells := MatchFinderScript.star_cluster_cells(board)
	if cells.is_empty():
		return false

	var group = ClearGroupScript.new()
	group.cells = _sorted(cells)
	group.cascade_depth = depth
	group.base_score = ruleset.scoring.points("star_cluster_base")
	group.score = ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
	group.set_formations(["bonus_star_cluster"])
	_record(result, group)
	for cell: Vector2i in group.cells:
		board.remove_piece(cell)
	return true


## Three starflowers together are worth a windfall.
static func _resolve_starflower_clusters(board, ruleset, result, level: int, depth: int) -> bool:
	var cells := MatchFinderScript.starflower_cluster_cells(board)
	if cells.is_empty():
		return false

	var group = ClearGroupScript.new()
	group.cells = _sorted(cells)
	group.cascade_depth = depth
	group.base_score = ruleset.scoring.points("starflower_match_base")
	group.score = ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
	group.set_formations(["starflower_cluster"])
	_record(result, group)
	for cell: Vector2i in group.cells:
		board.remove_piece(cell)
	return true


## Ordinary colour clusters, plus the two bomb rules.
static func _resolve_colour_clusters(board, ruleset, result, level: int, depth: int) -> bool:
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

		group.cascade_depth = depth
		group.bonus_stars = stars
		group.multiplier = int(pow(2.0, stars))
		group.base_score = ruleset.scoring.base_for_cluster(group.cells.size())
		group.score = (
			ruleset.scoring.clear_score(group.base_score, level, depth, ruleset.difficulty)
			* group.multiplier
		)
		group.set_formations(["cluster"])

		var clear_cells: Array[Vector2i] = group.cells.duplicate()
		if not bombs.is_empty():
			group.score += ruleset.scoring.clear_score(
				ruleset.scoring.points("bomb_defuse_base") * bombs.size(), level, depth, ruleset.difficulty
			)
			group.formations.append("bomb_defused")
			# Defusing with a bonus star of the bomb's colour wipes that colour
			# off the whole board.
			for bomb_cell: Vector2i in bombs:
				var bomb_color := int(Pieces.color_of(board.get_piece(bomb_cell)))
				if not _has_star_of_color(board, group.cells, bomb_color):
					continue
				var extras := MatchFinderScript.cells_with_color(board, bomb_color)
				var added := 0
				for cell: Vector2i in extras:
					if clear_cells.has(cell):
						continue
					clear_cells.append(cell)
					added += 1
				if added > 0:
					group.score += ruleset.scoring.clear_score(
						ruleset.scoring.points("bomb_colour_wipe_base") * added,
						level, depth, ruleset.difficulty
					)
					if not group.formations.has("bomb_colour_wipe"):
						group.formations.append("bomb_colour_wipe")

		group.cells = _sorted(clear_cells)
		_record(result, group)
		for cell: Vector2i in clear_cells:
			board.remove_piece(cell)
	return true


static func _has_star_of_color(board, cells: Array, gem_color: int) -> bool:
	for cell: Vector2i in cells:
		var piece: int = board.get_piece(cell)
		if Pieces.is_bonus_star(piece) and int(Pieces.color_of(piece)) == gem_color:
			return true
	return false


static func _record(result, group) -> void:
	result.clear_groups.append(group)
	result.score += group.score
	result.cleared_count += group.cells.size()
	# One clear event counts as one combo, cascade steps included.
	result.combos += 1


static func _sorted(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells:
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return out


## Gravity pass; records moves into `result` when one is supplied.
static func apply_gravity(board, result = null) -> void:
	if result == null:
		board.apply_gravity()
		return
	var moves: Array = board.apply_gravity_moves()
	for move: Dictionary in moves:
		result.gravity_moves.append(move)


## New pieces fall in above the top edge to fill the gaps gravity left behind.
## From level 2 some of them are bonus stars; from level 3 some are bombs.
static func refill_board(board, rng, result, level: int, ruleset) -> void:
	var colors: Array = Pieces.colors_for_level(level)
	for column_index in Grid.COLUMNS:
		for cell: Vector2i in Grid.column(column_index):
			if not board.is_empty(cell):
				continue
			var piece := _roll_piece(rng, colors, ruleset, level)
			board.set_piece(cell, piece)
			result.spawns.append({"cell": cell, "piece": piece})


static func _roll_piece(rng, colors: Array, ruleset, level: int) -> int:
	var roll: float = rng.next_float()
	var bomb_chance: float = ruleset.bomb_chance_at(level)
	if bomb_chance > 0.0 and roll < bomb_chance:
		return Pieces.bomb(rng.pick(colors), ruleset.bomb_counter_at(level))
	var star_chance: float = ruleset.bonus_star_chance_at(level)
	if star_chance > 0.0 and roll < bomb_chance + star_chance:
		return Pieces.bonus_star(rng.pick(colors))
	return Pieces.gem(rng.pick(colors))
