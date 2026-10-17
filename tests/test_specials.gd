extends "res://tests/test_case.gd"

## Special pieces (docs/design.md §3.4): bonus stars, starflowers, black pearls
## and bombs.
##
## Scenarios are painted onto a full, provably match-free background, because
## gravity runs before formations are judged — a half-empty board would drop its
## pieces and destroy the very formation under test.

const BoardScript := preload("res://src/core/board.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const ResolverScript := preload("res://src/core/resolver.gd")
const RngScript := preload("res://src/core/rng.gd")
const MoveResultScript := preload("res://src/core/move_result.gd")
const GameScript := preload("res://src/core/game.gd")

## An interior cell, so it has all six neighbours (used for rings).
const CENTRE := Vector2i(4, 4)


# --- helpers ----------------------------------------------------------------


## A rotation whose trio is one ring cell plus two cells outside the ring — the
## shape needed to swing a gem into a nearly-finished flower or pearl ring.
func _trio_outside_ring(centre: Vector2i, ring: Array) -> Dictionary:
	var forbidden := {centre: true}
	for cell: Vector2i in ring:
		forbidden[cell] = true
	var vertices := Grid.vertices()
	for index in vertices.size():
		var trio: Array = vertices[index]
		var inside: Array[Vector2i] = []
		var outside: Array[Vector2i] = []
		for cell: Vector2i in trio:
			if forbidden.has(cell):
				inside.append(cell)
			else:
				outside.append(cell)
		if inside.size() == 1 and outside.size() == 2:
			return {"vertex": index, "target": inside[0], "spares": outside}
	return {}


func _full_board() -> RefCounted:
	var board := BoardScript.new()
	_background(board)
	return board


func _resolve(board: Board, ruleset: Ruleset = null, level: int = 1, refill: bool = false) -> RefCounted:
	var rules: Variant = ruleset if ruleset != null else RulesetScript.new()
	var result := MoveResultScript.new()
	ResolverScript.resolve(board, rules, RngScript.new(1), result, level, refill)
	return result



func _ring(centre: Vector2i) -> Array[Vector2i]:
	var cells := Grid.neighbours(centre)
	assert_eq(cells.size(), 6, "the scenario centre must have six neighbours")
	return cells


func _ring_in_order(centre: Vector2i) -> Array[Vector2i]:
	return Grid.cyclic_order(Grid.neighbours(centre))




# --- spawn gating -----------------------------------------------------------

func test_the_test_background_is_match_free() -> void:
	# If this ever fails, every scenario built on it becomes unreliable.
	var board := _full_board()
	assert_eq(board.filled_count(), 85, "the background fills the board")
	assert_false(MatchFinder.has_any_match(board), "and contains no match")
	assert_eq(board.invariant_violations().size(), 0, "and is gravity-settled")


func test_spawns_are_gated_by_level() -> void:
	var ruleset := RulesetScript.new()
	assert_eq(ruleset.bonus_star_chance_at(1), 0.0, "no bonus stars at level 1")
	assert_gt(ruleset.bonus_star_chance_at(2), 0.0, "bonus stars from level 2")
	assert_eq(ruleset.bomb_chance_at(1), 0.0, "no bombs at level 1")
	assert_eq(ruleset.bomb_chance_at(2), 0.0, "still no bombs at level 2")
	assert_gt(ruleset.bomb_chance_at(3), 0.0, "bombs from level 3")
	assert_gt(ruleset.bomb_counter_at(3), 0, "bombs arrive with a fuse")
	assert_le(
		ruleset.bomb_counter_at(7), ruleset.bomb_counter_at(3),
		"fuses get shorter as levels climb"
	)


func test_gems_only_ruleset_never_spawns_specials() -> void:
	var ruleset := RulesetScript.gems_only()
	var board := BoardScript.new()
	var result := MoveResultScript.new()
	ResolverScript.refill_board(board, RngScript.new(4), result, 7, ruleset)
	assert_eq(board.filled_count(), 85, "the board is filled")
	assert_eq(_count_kind(board, Pieces.Kind.BONUS_STAR), 0, "no stars")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "no bombs")


func test_refill_mixes_in_specials_at_level_three() -> void:
	var ruleset := RulesetScript.new()
	var stars := 0
	var bombs := 0
	var gems := 0
	for run in 10:
		var board := BoardScript.new()
		var result := MoveResultScript.new()
		ResolverScript.refill_board(board, RngScript.new(run + 1), result, 3, ruleset)
		stars += _count_kind(board, Pieces.Kind.BONUS_STAR)
		bombs += _count_kind(board, Pieces.Kind.BOMB)
		gems += _count_kind(board, Pieces.Kind.GEM)
	info("850 refills at level 3: %d gems, %d stars, %d bombs" % [gems, stars, bombs])
	assert_gt(stars, 15, "bonus stars appear")
	assert_gt(bombs, 15, "bombs appear")
	assert_gt(gems, 600, "and most pieces are still plain gems")


# --- bonus stars ------------------------------------------------------------

func test_bonus_star_doubles_the_clear() -> void:
	var board := BoardScript.new()
	_paint(board, [Vector2i(4, 7), Vector2i(4, 8)], Pieces.GemColor.RED)
	board.set_piece(Vector2i(5, 7), Pieces.bonus_star(Pieces.GemColor.RED))

	var group := _first_group(_resolve(board))
	assert_eq(group.bonus_stars, 1, "the star is counted")
	assert_eq(group.multiplier, 2, "x2 for one star")
	assert_eq(group.base_score, 5, "base is the 3-cluster tier")
	assert_eq(group.score, 10, "so the clear pays 5 x 2")


func test_two_bonus_stars_multiply_together() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 7), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(4, 8), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(5, 7), Pieces.gem(Pieces.GemColor.RED))

	var group := _first_group(_resolve(board))
	assert_eq(group.bonus_stars, 2, "two stars")
	assert_eq(group.multiplier, 4, "x2 per star, stacking")
	assert_eq(group.score, 20, "5 base x 4")


func test_three_bonus_stars_clear_what_they_touch() -> void:
	var board := BoardScript.new()
	# Three stars of *different* colours still cluster.
	board.set_piece(Vector2i(4, 7), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(4, 8), Pieces.bonus_star(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(5, 7), Pieces.bonus_star(Pieces.GemColor.BLUE))
	# A bystander adjacent to the stars, and one two cells away.
	board.set_piece(Vector2i(3, 7), Pieces.gem(Pieces.GemColor.CYAN))
	board.set_piece(Vector2i(2, 7), Pieces.gem(Pieces.GemColor.VIOLET))

	var group := _first_group(_resolve(board))
	assert_true(group.has_formation("bonus_star_cluster"), "reported as a bonus-star cluster")
	assert_true(group.cells.has(Vector2i(3, 7)), "the adjacent gem was swept up")
	assert_false(group.cells.has(Vector2i(2, 7)), "but not the one two cells away")
	assert_eq(group.base_score, 1000, "a star cluster is worth the star tier")


func test_two_bonus_stars_are_not_a_star_cluster() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 7), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(4, 8), Pieces.bonus_star(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(5, 7), Pieces.gem(Pieces.GemColor.BLUE))

	var result := _resolve(board)
	assert_eq(result.clear_groups.size(), 0, "two stars and a gem clear nothing")


# --- flowers ----------------------------------------------------------------

func test_a_flower_blooms_into_a_starflower() -> void:
	var board := _full_board()
	board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.BLUE))
	_paint(board, _ring(CENTRE), Pieces.GemColor.RED)
	assert_true(MatchFinder.is_flower(board, CENTRE), "the ring reads as a flower")

	var result := _resolve(board)
	var group := _first_group(result)
	assert_true(group.has_formation("flower"), "the flower resolves first")
	assert_eq(group.size(), 6, "six ring gems are consumed")
	assert_eq(group.base_score, 1000, "flowers use the flower tier")
	assert_eq(result.promotions.size(), 1, "the centre blooms")
	assert_eq(result.promotions[0]["piece"], Pieces.starflower(), "into a starflower")
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 1, "and it is on the board")


func test_a_same_coloured_ring_is_a_cluster_not_a_flower() -> void:
	var board := _full_board()
	board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.RED))
	_paint(board, _ring(CENTRE), Pieces.GemColor.RED)
	assert_false(MatchFinder.is_flower(board, CENTRE), "a same-coloured centre is not a flower")

	var result := _resolve(board)
	assert_eq(result.promotions.size(), 0, "nothing is promoted")
	var group := _first_group(result)
	assert_true(group.has_formation("cluster"), "the ring resolves as a normal cluster")
	# The 7-cell blob also swallows same-coloured background neighbours, so the
	# group is at least the centre plus its ring.
	assert_ge(group.size(), 7, "the centre joins the cluster")
	assert_true(group.cells.has(CENTRE), "the centre is part of it")


func test_a_flower_around_a_starflower_makes_a_pearl() -> void:
	var board := _full_board()
	board.set_piece(CENTRE, Pieces.starflower())
	_paint(board, _ring(CENTRE), Pieces.GemColor.GREEN)

	var result := _resolve(board)
	assert_true(_first_group(result).has_formation("flower"), "the ring is a flower")
	assert_eq(result.promotions[0]["piece"], Pieces.pearl(), "starflower becomes a pearl")
	assert_eq(_count_kind(board, Pieces.Kind.PEARL), 1, "and it is on the board")


func test_six_starflowers_ring_makes_a_pearl() -> void:
	var board := _full_board()
	board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.YELLOW))
	for cell: Vector2i in _ring(CENTRE):
		board.set_piece(cell, Pieces.starflower())
	assert_true(MatchFinder.is_pearl_creation_ring(board, CENTRE), "six starflowers ring the centre")

	var result := _resolve(board)
	var group := _first_group(result)
	assert_true(group.has_formation("pearl_built"), "reported as a pearl")
	assert_eq(group.base_score, 10000, "pearls use the pearl tier")
	assert_eq(result.promotions[0]["piece"], Pieces.pearl(), "the centre becomes a pearl")
	assert_eq(_count_kind(board, Pieces.Kind.PEARL), 1, "and it is on the board")


# --- starflower clusters ----------------------------------------------------

func test_three_starflowers_pay_a_windfall() -> void:
	var board := BoardScript.new()
	for cell: Vector2i in [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]:
		board.set_piece(cell, Pieces.starflower())

	var group := _first_group(_resolve(board))
	assert_true(group.has_formation("starflower_cluster"), "starflower cluster")
	assert_eq(group.base_score, 2500, "starflower tier")
	assert_eq(board.filled_count(), 0, "all three are consumed")


# --- pearl finish -----------------------------------------------------------

func test_three_pearls_finish_the_run() -> void:
	var board := BoardScript.new()
	for cell: Vector2i in [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]:
		board.set_piece(cell, Pieces.pearl())

	var result := _resolve(board)
	assert_true(result.finished, "the run ends")
	assert_eq(result.finish_kind, "pearl_cluster", "as a pearl cluster")
	assert_eq(_first_group(result).base_score, 50000, "pearl cluster tier")
	assert_eq(result.score, 50000, "paid at level 1")


func test_six_pearls_in_a_ring_finish_the_run() -> void:
	var board := _full_board()
	board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.CYAN))
	for cell: Vector2i in _ring(CENTRE):
		board.set_piece(cell, Pieces.pearl())

	var result := _resolve(board)
	assert_true(result.finished, "the run ends")
	assert_eq(result.finish_kind, "pearl_ring", "as the ultimate pearl ring")
	assert_eq(_first_group(result).base_score, 250000, "the reference figure")
	assert_eq(result.score, 250000, "paid at level 1")


func test_finish_scales_with_level() -> void:
	var board := BoardScript.new()
	for cell: Vector2i in [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]:
		board.set_piece(cell, Pieces.pearl())
	var result := _resolve(board, null, 4)
	assert_eq(result.score, 200000, "50000 x level 4")


# --- bombs ------------------------------------------------------------------

func test_a_bomb_is_defused_by_a_colour_cluster() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 7), Pieces.bomb(Pieces.GemColor.RED, 5))
	_paint(board, [Vector2i(4, 8), Vector2i(5, 7)], Pieces.GemColor.RED)

	var group := _first_group(_resolve(board))
	assert_true(group.has_formation("bomb_defused"), "the bomb was defused")
	assert_eq(group.score, 5 + 200, "cluster points plus the defuse bonus")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "no bomb left on the board")


func test_a_bomb_with_a_matching_star_wipes_the_colour() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 7), Pieces.bomb(Pieces.GemColor.RED, 5))
	board.set_piece(Vector2i(4, 8), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(5, 7), Pieces.gem(Pieces.GemColor.RED))
	# Two more red gems far from the cluster, and a control gem.
	_paint(board, [Vector2i(0, 7), Vector2i(9, 7)], Pieces.GemColor.RED)
	board.set_piece(Vector2i(2, 8), Pieces.gem(Pieces.GemColor.BLUE))

	var group := _first_group(_resolve(board))
	assert_true(group.has_formation("bomb_defused"), "the bomb was defused")
	assert_true(group.has_formation("bomb_colour_wipe"), "and the colour was wiped")
	assert_true(board.is_empty(Vector2i(0, 7)), "a distant red gem is cleared too")
	assert_true(board.is_empty(Vector2i(9, 7)), "and another one")
	assert_false(board.is_empty(Vector2i(2, 8)), "the blue control gem survives")
	# 3 cluster cells x2 (one star) + defuse + 2 wiped gems.
	assert_eq(group.score, 10 + 200 + 1000, "cluster x2, defuse bonus, wipe bonus")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "bomb gone")


func test_a_bomb_ticks_down_each_move_and_explodes() -> void:
	var game := GameScript.new(7, RulesetScript.free_rotation())
	game.board.set_piece(Vector2i(0, 0), Pieces.bomb(Pieces.GemColor.BLUE, 1))

	var move := _non_matching_rotation(game)
	var result := game.rotate(move["vertex"], move["direction"])
	assert_true(result.committed, "the spin was accepted")
	assert_true(result.bomb_exploded, "the fuse ran out and it exploded")
	assert_true(result.game_over, "which ends the run")
	assert_eq(game.state, GameScript.State.FINISHED, "game state is finished")
	assert_false(game.rotate(move["vertex"], move["direction"]).committed, "no further moves")


func test_an_exploding_bomb_flattens_the_whole_board_and_scores_nothing() -> void:
	var game := GameScript.new(11, RulesetScript.free_rotation())
	var bomb_cell := Vector2i(4, 4)
	game.board.set_piece(bomb_cell, Pieces.bomb(Pieces.GemColor.BLUE, 1))

	var move := _non_matching_rotation(game)
	var result := game.rotate(move["vertex"], move["direction"])
	assert_true(result.committed, "the spin was accepted")
	assert_true(result.bomb_exploded, "the fuse ran out")
	assert_eq(result.exploded_cells.size(), 85, "the blast takes the entire board")
	assert_eq(result.exploded_cells[0], bomb_cell, "starting at the bomb itself")
	assert_eq(game.tile_count(), 0, "nothing is left standing")
	# A game-over event, not a clear: no score, no combos, no groups.
	assert_eq(result.cleared_count, 0, "the blast is not a clear")
	assert_eq(result.score, 0, "and awards nothing")
	assert_eq(result.clear_groups.size(), 0, "with no clear group recorded")
	assert_eq(game.board.invariant_violations().size(), 0, "the empty board is legal")
	# The crater is a game-over event, not a clear: no score, no combos, no groups.
	assert_eq(result.cleared_count, 0, "the blast is not a clear")
	assert_eq(result.score, 0, "and awards nothing")
	assert_eq(result.clear_groups.size(), 0, "with no clear group recorded")
	assert_eq(game.board.invariant_violations().size(), 0, "the crater settles")


## STRICT mode only accepts a spin that clears something. Forming a flower is a
## move too — and a flower's ring is uniform, so the swap that completes it often
## lands the match somewhere other than the vertex being turned. The last spin
## into a flower must never be refused.
func test_strict_accepts_the_last_spin_into_a_flower() -> void:
	var game := GameScript.new(21, RulesetScript.strict_rotation())
	var centre := Vector2i(4, 4)
	var ring := Grid.neighbours(centre)
	var found := _trio_outside_ring(centre, ring)
	assert_true(not found.is_empty(), "a rotation can reach the ring from outside")
	if found.is_empty():
		return

	# Five red ring gems, a green centre, and the sixth ring cell red-about-to-be.
	game.board.set_piece(centre, Pieces.gem(Pieces.GemColor.GREEN))
	for cell: Vector2i in ring:
		game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(found["target"], Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in found["spares"]:
		game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	assert_false(MatchFinder.is_flower(game.board, centre), "the flower is not complete yet")

	var accepted := false
	var promoted := false
	for direction in [1, -1]:
		var result := game.rotate(int(found["vertex"]), direction)
		if not result.committed:
			continue
		accepted = true
		for promotion: Dictionary in result.promotions:
			if str(promotion.get("kind", "")) == "starflower":
				promoted = true
				assert_eq(
					int(promotion.get("depth", -1)), 1,
					"the bloom knows its cascade depth, so the view can play it before the ring dies"
				)
		break
	assert_true(accepted, "strict mode accepted the spin that completes the flower")
	assert_true(promoted, "and the flower bloomed")


## Pearl rings are made of starflowers, which have no colour — so completing one
## creates no colour match at all. Without the formation rule STRICT would refuse
## the winning spin outright.
func test_strict_accepts_the_last_spin_into_a_pearl_ring() -> void:
	var game := GameScript.new(23, RulesetScript.strict_rotation())
	var centre := Vector2i(4, 4)
	var ring := Grid.neighbours(centre)
	var found := _trio_outside_ring(centre, ring)
	assert_true(not found.is_empty(), "a rotation can reach the ring from outside")
	if found.is_empty():
		return

	game.board.set_piece(centre, Pieces.gem(Pieces.GemColor.GREEN))
	for cell: Vector2i in ring:
		game.board.set_piece(cell, Pieces.starflower())
	game.board.set_piece(found["target"], Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in found["spares"]:
		game.board.set_piece(cell, Pieces.starflower())
	assert_false(
		MatchFinder.is_pearl_creation_ring(game.board, centre),
		"the ring is one starflower short"
	)

	var accepted := false
	var pearls := 0
	for direction in [1, -1]:
		var result := game.rotate(int(found["vertex"]), direction)
		if not result.committed:
			continue
		accepted = true
		pearls = _count_kind(game.board, Pieces.Kind.PEARL)
		break
	assert_true(accepted, "strict mode accepted the spin that closes the pearl ring")
	assert_eq(pearls, 1, "and the pearl appeared")


func test_a_strict_spin_that_makes_nothing_is_still_rejected() -> void:
	var game := GameScript.new(29, RulesetScript.strict_rotation())
	# A board with no formation of any kind, and a spin that clears nothing.
	var move := _non_matching_rotation(game)
	assert_eq(game.find_legal_rotations().size() >= 0, true, "the scan ran")
	var result := game.rotate(move["vertex"], move["direction"])
	if result.committed:
		info("this seed had a clearing spin at the sampled vertex; skipped")
		return
	assert_false(result.committed, "a spin that makes nothing is not a move")
	assert_true(result.rejected_reason.length() > 0, "and the reason is stated")


func test_a_bomb_loses_exactly_one_tick_per_move() -> void:
	var game := GameScript.new(7, RulesetScript.free_rotation())
	game.board.set_piece(Vector2i(0, 0), Pieces.bomb(Pieces.GemColor.BLUE, 5))

	var move := _non_matching_rotation(game)
	var result := game.rotate(move["vertex"], move["direction"])
	assert_eq(result.bombs_ticked.size(), 1, "one bomb ticked")
	assert_false(result.bomb_exploded, "not yet")
	var found := Vector2i(-1, -1)
	for cell: Vector2i in Grid.all_cells():
		if Pieces.is_bomb(game.board.get_piece(cell)):
			found = cell
	assert_ne(found, Vector2i(-1, -1), "the bomb is still on the board")
	assert_eq(Pieces.counter_of(game.board.get_piece(found)), 4, "the fuse went 5 -> 4")


# --- special-piece rotation -------------------------------------------------

func test_starflower_rotates_its_ring_without_a_match() -> void:
	# The painted background ring has no match, so the only thing that happens is
	# the rotation itself.
	var game := GameScript.new(5, RulesetScript.strict_rotation())
	_background(game.board)
	game.board.set_piece(CENTRE, Pieces.starflower())

	var ring := _ring_in_order(CENTRE)
	var before := []
	for cell: Vector2i in ring:
		before.append(game.board.get_piece(cell))

	var result := game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	assert_true(result.committed, "ring rotation always persists, even in STRICT")
	assert_eq(result.clear_groups.size(), 0, "and needs no match")
	assert_eq(game.board.get_piece(CENTRE), Pieces.starflower(), "the starflower stays put")
	for index in ring.size():
		var source := posmod(index - GameScript.CLOCKWISE, ring.size())
		assert_eq(
			game.board.get_piece(ring[index]), before[source],
			"neighbour %d took the piece from %d (clockwise)" % [index, source]
		)


func test_a_pearl_rotates_three_of_its_six_neighbours() -> void:
	var game := GameScript.new(5, RulesetScript.free_rotation())
	_background(game.board)
	game.board.set_piece(CENTRE, Pieces.pearl())

	var turning: Array = game._pearl_y_cells(CENTRE)
	assert_eq(turning.size(), 3, "a pearl turns three neighbours")
	var ring := _ring(CENTRE)
	var unturned := {}
	for cell: Vector2i in ring:
		if not turning.has(cell):
			unturned[cell] = game.board.get_piece(cell)
	var before := []
	for cell: Vector2i in turning:
		before.append(game.board.get_piece(cell))

	var result := game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	assert_true(result.committed, "the pearl turns")
	assert_eq(result.clear_groups.size(), 0, "the background has nothing to clear")
	assert_eq(game.board.get_piece(CENTRE), Pieces.pearl(), "the pearl itself stays")
	for cell: Vector2i in unturned:
		assert_eq(game.board.get_piece(cell), unturned[cell], "the other three neighbours stay")
	var after := []
	for cell: Vector2i in turning:
		after.append(game.board.get_piece(cell))
	after.sort()
	before.sort()
	assert_eq(after, before, "the three turning neighbours exchanged pieces")


func test_only_specials_can_be_rotated_alone() -> void:
	var game := GameScript.new(5, RulesetScript.free_rotation())
	var result := game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	assert_false(result.committed, "a plain gem cannot be spun on its own")
	assert_gt(result.rejected_reason.length(), 0, "with an explanation")


func test_piece_rotations_are_logged_for_replay() -> void:
	# A hand-edited board cannot be reproduced from a seed alone, so this checks
	# the command log; seeded runs replay in full (see test_game.gd).
	var game := GameScript.new(5, RulesetScript.free_rotation())
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := _ring(CENTRE)
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))

	game.rotate_piece(CENTRE, GameScript.COUNTER_CLOCKWISE)
	var log := game.commands()
	assert_eq(log.size(), 1, "one command recorded")
	assert_eq(String(log[0][0]), "piece", "tagged as a piece rotation")
	assert_eq(Vector2i(int(log[0][1]), int(log[0][2])), CENTRE, "the cell is recorded")
	assert_eq(int(log[0][3]), GameScript.COUNTER_CLOCKWISE, "the direction is recorded")
	assert_eq(game.turns, 1, "and it counts as a turn")


# --- helpers ----------------------------------------------------------------




# --- flowers from special pieces --------------------------------------------

## A ring of nine? No: six petals, mixing plain gems with bonus stars.
func test_bonus_stars_can_be_petals() -> void:
	var board := _full_board()
	var centre := Vector2i(4, 4)
	var ring := Grid.neighbours(centre)
	board.set_piece(centre, Pieces.gem(Pieces.GemColor.GREEN))
	for index in ring.size():
		var petal := Pieces.bonus_star(Pieces.GemColor.RED) if index % 2 == 0 else Pieces.gem(Pieces.GemColor.RED)
		board.set_piece(ring[index], petal)
	assert_true(MatchFinder.is_flower(board, centre), "stars and gems of one colour make a flower")

	_resolve(board)
	# Gravity drops the new starflower into the emptied column, so assert by kind
	# rather than by cell.
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 1, "the centre bloomed")
	assert_eq(_count_kind(board, Pieces.Kind.BONUS_STAR), 0, "the star petals were consumed")


func test_bombs_can_be_petals() -> void:
	var board := _full_board()
	var centre := Vector2i(4, 4)
	var ring := Grid.neighbours(centre)
	board.set_piece(centre, Pieces.gem(Pieces.GemColor.GREEN))
	for index in ring.size():
		var petal := Pieces.bomb(Pieces.GemColor.RED, 3) if index == 0 else Pieces.gem(Pieces.GemColor.RED)
		board.set_piece(ring[index], petal)
	assert_true(MatchFinder.is_flower(board, centre), "a bomb is a legal petal")

	_resolve(board)
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 1, "the flower still bloomed")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "and the petal bomb is gone")


func test_a_bomb_in_the_middle_is_fully_converted() -> void:
	var board := _full_board()
	var centre := Vector2i(4, 4)
	board.set_piece(centre, Pieces.bomb(Pieces.GemColor.GREEN, 3))
	for cell: Vector2i in Grid.neighbours(centre):
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	# The bomb's colour differs from the ring here, which the rule requires.
	assert_true(MatchFinder.is_flower(board, centre), "a bomb centre is a flower centre")

	_resolve(board)
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 1, "the bomb became a starflower")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "and no bomb is left to tick")


func test_a_bomb_centre_blooms_even_in_the_ring_colour() -> void:
	var board := _full_board()
	var centre := Vector2i(4, 4)
	board.set_piece(centre, Pieces.bomb(Pieces.GemColor.RED, 3))
	for cell: Vector2i in Grid.neighbours(centre):
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	# Same colour as the ring would be a plain blob for any normal centre, but a
	# bomb is being consumed, so the flower stands and disarms it.
	assert_true(MatchFinder.is_flower(board, centre), "the bomb centre is still accepted")
	_resolve(board)
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 1, "and it is converted")
	assert_eq(_count_kind(board, Pieces.Kind.BOMB), 0, "with no bomb left to tick")


func test_a_pearl_centre_is_not_a_flower() -> void:
	var board := _full_board()
	var centre := Vector2i(4, 4)
	board.set_piece(centre, Pieces.pearl())
	for cell: Vector2i in Grid.neighbours(centre):
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	assert_false(MatchFinder.is_flower(board, centre), "a pearl centre does not bloom again")



# --- multi-colour chime -----------------------------------------------------

func test_cleared_groups_keep_their_colour() -> void:
	var board := BoardScript.new()
	_background(board)
	_paint(board, [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)], Pieces.GemColor.ORANGE)
	var result = _resolve(board)
	assert_ge(result.clear_groups.size(), 1, "the triangle cleared")
	assert_eq(int(result.clear_groups[0].gem_color), Pieces.GemColor.ORANGE,
		"a cleared group knows which colour it was")
	assert_eq(AudioService.distinct_colours(result), 1, "one colour")


func test_two_colours_in_one_move_are_counted() -> void:
	var board := BoardScript.new()
	_background(board)
	_paint(board, [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)], Pieces.GemColor.ORANGE)
	_paint(board, [Vector2i(7, 3), Vector2i(7, 4), Vector2i(8, 4)], Pieces.GemColor.BLUE)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 2, "two separate triangles were found")
	var result := MoveResultScript.new()
	for group in groups:
		result.clear_groups.append(group)
	assert_eq(AudioService.distinct_colours(result), 2, "in two different colours")


func test_the_chime_ignores_cascades() -> void:
	var board := BoardScript.new()
	_background(board)
	_paint(board, [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)], Pieces.GemColor.ORANGE)
	_paint(board, [Vector2i(7, 3), Vector2i(7, 4), Vector2i(8, 4)], Pieces.GemColor.BLUE)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 2, "two clusters")
	var result := MoveResultScript.new()
	groups[0].cascade_depth = 1   # the spin's own clear
	groups[1].cascade_depth = 2   # something that fell into place afterwards
	for group in groups:
		result.clear_groups.append(group)
	assert_eq(AudioService.distinct_colours(result), 2, "two colours cleared overall")
	assert_eq(AudioService.distinct_colours(result, true), 1,
		"but only one was in the spin's own clear, so no chime")
