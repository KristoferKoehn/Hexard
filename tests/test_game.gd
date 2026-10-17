extends "res://tests/test_case.gd"

## Game facade: rotation modes, cascades, scoring, progression, dead boards,
## replay determinism (docs/design.md §3, §5, §10.2).

const Grid := preload("res://src/core/hex_grid.gd")
const BoardScript := preload("res://src/core/board.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const RngScript := preload("res://src/core/rng.gd")
const ResolverScript := preload("res://src/core/resolver.gd")
const MoveResultScript := preload("res://src/core/move_result.gd")
const GameScript := preload("res://src/core/game.gd")


## A rotation that clears nothing: anything absent from the legal set.
func _illegal_rotation(game) -> Dictionary:
	var legal := {}
	for move: Dictionary in game.find_legal_rotations():
		legal["%d:%d" % [move["vertex"], move["direction"]]] = true
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		for direction in [1, -1]:
			if not legal.has("%d:%d" % [vertex_index, direction]):
				return {"vertex": vertex_index, "direction": direction}
	return {}


func _play_legal_moves(game, count: int) -> int:
	var played := 0
	for step in count:
		var legal: Array = game.find_legal_rotations()
		if legal.is_empty():
			break
		var move: Dictionary = legal[0]
		var result = game.rotate(move["vertex"], move["direction"])
		if result.committed:
			played += 1
	return played


# --- new run ----------------------------------------------------------------

func test_new_run_starts_full_match_free_and_at_zero() -> void:
	for run_seed in [1, 2, 3, 42]:
		var game := GameScript.new(run_seed)
		assert_eq(game.tile_count(), 85, "board starts full (seed %d)" % run_seed)
		assert_false(MatchFinder.has_any_match(game.board), "and match-free (seed %d)" % run_seed)
		assert_eq(game.board.invariant_violations().size(), 0, "and gravity-settled")
		assert_eq(game.score, 0, "score starts at zero")
		assert_eq(game.level, 1, "level starts at one")
		assert_eq(game.total_combos, 0, "no combos yet")
		assert_eq(game.combos_remaining(), 50, "50 combos to reach level 2")
		assert_true(game.has_any_legal_rotation(), "at least one move exists")


func test_default_ruleset_is_strict() -> void:
	# The reference spins until a match or reverts, and that is what makes the
	# board move only when you clear something. FREE is the opt-in.
	var ruleset := RulesetScript.new()
	assert_eq(ruleset.rotation_mode, RulesetScript.RotationMode.STRICT, "default is STRICT")
	assert_eq(RulesetScript.free_rotation().rotation_mode, RulesetScript.RotationMode.FREE, "free() opts out")
	assert_eq(RulesetScript.strict_rotation().rotation_mode, RulesetScript.RotationMode.STRICT, "strict() is explicit")


func test_level_one_board_uses_only_base_colours() -> void:
	var game := GameScript.new(6)
	var palette := {}
	for color: int in Pieces.BASE_COLORS:
		palette[color] = true
	for cell: Vector2i in Grid.all_cells():
		var piece: int = game.board.get_piece(cell)
		assert_true(Pieces.has_color(piece), "every cell holds a coloured gem")
		assert_true(palette.has(Pieces.color_of(piece)), "level 1 palette only")


# --- input validation -------------------------------------------------------

func test_invalid_moves_are_rejected_without_side_effects() -> void:
	var game := GameScript.new(1)
	var before := game.signature()
	assert_false(game.rotate(-1, 1).committed, "negative vertex rejected")
	assert_false(game.rotate(9999, 1).committed, "out-of-range vertex rejected")
	assert_false(game.rotate(0, 0).committed, "zero direction rejected")
	assert_false(game.rotate(0, 5).committed, "invalid direction rejected")
	assert_eq(game.signature(), before, "the board is untouched")
	assert_eq(game.turns, 0, "and no move was consumed")


# --- rotation modes ---------------------------------------------------------

func test_free_mode_keeps_a_non_matching_rotation() -> void:
	var game := GameScript.new(3, RulesetScript.free_rotation())
	var move := _illegal_rotation(game)
	assert_true(move.size() > 0, "a non-matching rotation exists")
	var before := game.signature()
	var result = game.rotate(move["vertex"], move["direction"])
	assert_true(result.committed, "FREE mode accepts the spin")
	assert_eq(result.clear_groups.size(), 0, "nothing cleared")
	assert_ne(game.signature(), before, "but the trio stayed where it was put")
	assert_eq(game.tile_count(), 85, "board still full")
	assert_eq(game.score, 0, "and nothing was scored")
	assert_eq(game.turns, 1, "the move is counted")


func test_strict_mode_reverts_a_non_matching_rotation() -> void:
	var game := GameScript.new(3, RulesetScript.strict_rotation())
	var move := _illegal_rotation(game)
	var before := game.signature()
	var result = game.rotate(move["vertex"], move["direction"])
	assert_false(result.committed, "STRICT mode refuses a spin that clears nothing")
	assert_eq(game.signature(), before, "the board is byte-for-byte unchanged")
	assert_eq(game.turns, 0, "and no move is consumed")
	assert_eq(game.score, 0, "no score either")


func test_a_spin_and_its_inverse_cancel_out() -> void:
	var game := GameScript.new(21, RulesetScript.free_rotation())
	var move := _illegal_rotation(game)
	var before := game.signature()
	game.rotate(move["vertex"], move["direction"])
	game.rotate(move["vertex"], -move["direction"])
	assert_eq(game.signature(), before, "the cyclic rotation is exactly invertible")


# --- clearing, scoring, refill ---------------------------------------------

func test_a_legal_rotation_clears_scores_and_refills() -> void:
	var game := GameScript.new(8)
	var legal := game.find_legal_rotations()
	assert_gt(legal.size(), 0, "a fresh board offers a move")
	var move: Dictionary = legal[0]
	var result = game.rotate(move["vertex"], move["direction"])

	assert_true(result.committed, "the move committed")
	assert_ge(result.clear_groups.size(), 1, "at least one clear group")
	assert_ge(result.cleared_count, 3, "at least three gems cleared")
	assert_gt(result.score, 0, "points were scored")
	assert_eq(game.score, result.score, "and banked on the game")
	assert_eq(game.total_combos, result.combos, "combos accumulated")
	assert_eq(game.tile_count(), 85, "Marathon refills the board")
	assert_eq(game.board.invariant_violations().size(), 0, "no floating pieces left")
	assert_false(MatchFinder.has_any_match(game.board), "the board is left stable")
	assert_eq(result.clear_groups[0].cascade_depth, 1, "the first clear is depth 1")


func test_clear_score_matches_the_table() -> void:
	var game := GameScript.new(8)
	var rules := RulesetScript.new()
	var move: Dictionary = game.find_legal_rotations()[0]
	var result = game.rotate(move["vertex"], move["direction"])
	for group in result.clear_groups:
		var expected: int = rules.scoring.clear_score(
			rules.scoring.base_for_cluster(group.size()), 1, group.cascade_depth, "normal"
		)
		assert_eq(group.score, expected, "group score follows base x level x cascade")
		assert_eq(group.base_score, rules.scoring.base_for_cluster(group.size()), "base tier")


func test_cascade_chains_and_multiplies() -> void:
	# Hand-built, rules-legal board pinning the fall geometry (docs/design.md §2.2).
	# Both columns are gravity-settled bottom-anchored prefixes, and the vertex
	# {(2,7),(3,6),(3,7)} already matches:
	#   clear it  ->  (2,6) drops 1 row to (2,7)
	#                 (3,4)/(3,5) drop 2 rows to (3,6)/(3,7)
	#   so the same vertex matches again on cascade step 2 (green instead of red).
	var board := BoardScript.new()
	board.set_piece(Vector2i(2, 5), Pieces.gem(Pieces.GemColor.BLUE))
	board.set_piece(Vector2i(2, 6), Pieces.gem(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(2, 7), Pieces.gem(Pieces.GemColor.RED))
	board.set_piece(Vector2i(2, 8), Pieces.gem(Pieces.GemColor.BLUE))
	board.set_piece(Vector2i(3, 4), Pieces.gem(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(3, 5), Pieces.gem(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(3, 6), Pieces.gem(Pieces.GemColor.RED))
	board.set_piece(Vector2i(3, 7), Pieces.gem(Pieces.GemColor.RED))
	assert_eq(board.invariant_violations().size(), 0, "the scenario starts gravity-settled")
	assert_eq(MatchFinder.clear_groups(board).size(), 1, "exactly one match to start with")

	var ruleset := RulesetScript.new()
	var result := MoveResultScript.new()
	# refill = false keeps the scenario deterministic (Survival-style round).
	ResolverScript.resolve(board, ruleset, RngScript.new(1), result, 1, false)

	assert_eq(result.cascades, 2, "exactly two cascade steps")
	assert_eq(result.clear_groups.size(), 2, "two clear groups")
	assert_eq(result.clear_groups[0].cascade_depth, 1, "first at depth 1")
	assert_eq(result.clear_groups[1].cascade_depth, 2, "second at depth 2")
	assert_eq(result.clear_groups[0].score, 5, "depth 1 pays base x level")
	assert_eq(result.clear_groups[1].score, 8, "depth 2 pays base x level x 1.5 (rounded)")
	assert_eq(result.score, 13, "total is the sum of the steps")
	assert_eq(result.combos, 2, "each clear event counts one combo")
	assert_eq(result.cleared_count, 6, "six gems removed")
	assert_eq(board.filled_count(), 2, "the two blue gems survive and fall to the floor")
	assert_eq(board.get_piece(Vector2i(2, 7)), Pieces.gem(Pieces.GemColor.BLUE), "upper blue at the floor-1")
	assert_eq(board.get_piece(Vector2i(2, 8)), Pieces.gem(Pieces.GemColor.BLUE), "lower blue at the floor")
	assert_eq(board.invariant_violations().size(), 0, "and nothing is left floating")


func test_survival_style_resolve_leaves_gaps() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 8), Pieces.gem(Pieces.GemColor.RED))
	board.set_piece(Vector2i(4, 7), Pieces.gem(Pieces.GemColor.RED))
	board.set_piece(Vector2i(5, 7), Pieces.gem(Pieces.GemColor.RED))

	var result := MoveResultScript.new()
	ResolverScript.resolve(board, RulesetScript.new(), RngScript.new(2), result, 1, false)
	assert_eq(result.clear_groups.size(), 1, "one clear")
	assert_eq(board.filled_count(), 0, "cleared cells stay empty without refill")
	assert_eq(result.spawns.size(), 0, "and nothing new falls in")


# --- progression ------------------------------------------------------------

func test_combo_thresholds_follow_the_design_doc() -> void:
	var ruleset := RulesetScript.new()
	assert_eq(ruleset.max_level(), 7, "seven levels")
	assert_eq(ruleset.combos_to_advance(1), 50, "50 combos to leave level 1")
	assert_eq(ruleset.combos_to_advance(2), 60, "60 to leave level 2")
	assert_eq(ruleset.combos_to_advance(6), 100, "100 to leave level 6")
	assert_eq(ruleset.combos_to_advance(7), 0, "the max level needs nothing")
	assert_eq(ruleset.combos_to_advance(0), 0, "out of range is safe")


func test_level_advances_on_the_threshold() -> void:
	var ruleset := RulesetScript.new()
	ruleset.level_combo_thresholds = [2, 4, 6]
	var game := GameScript.new(5, ruleset)
	assert_eq(game.combos_remaining(), 2, "two combos to level 2")

	var guard := 0
	while game.total_combos < 2 and guard < 200:
		if _play_legal_moves(game, 1) == 0:
			break
		guard += 1

	assert_ge(game.total_combos, 2, "we cleared enough to advance")
	assert_ge(game.level, 2, "level went up")
	assert_le(game.level, ruleset.max_level(), "and never past the cap")


# --- dead board -------------------------------------------------------------

func test_a_dead_board_is_shuffled_back_to_life() -> void:
	var game := GameScript.new(11)
	# Strip the board: nothing can clear and no rotation can help.
	for cell: Vector2i in Grid.all_cells():
		game.board.remove_piece(cell)
	assert_false(game.has_any_legal_rotation(), "an empty board has no legal move")

	var result = game.rotate(0, 1)
	assert_true(result.dead_board, "the dead board is reported")
	assert_true(result.shuffled, "and shuffled")
	assert_eq(game.tile_count(), 85, "the shuffle leaves a full board")
	assert_false(MatchFinder.has_any_match(game.board), "which is match-free")
	assert_true(game.has_any_legal_rotation(), "and playable again")
	assert_eq(game.board.invariant_violations().size(), 0, "with no floating pieces")


func test_gravity_re_settles_after_every_move_on_a_gappy_board() -> void:
	# Regression: on a Survival-style board a rotation can *lift* a piece into
	# an empty cell. Gravity has to run after every committed move, not just
	# after clears, or pieces are left floating.
	var ruleset := RulesetScript.new()
	ruleset.refills_board = false
	var game := GameScript.new(31, ruleset)
	for cell: Vector2i in Grid.all_cells():
		if cell.y < Grid.column_height(cell.x) - 3:
			game.board.remove_piece(cell)
	game.board.apply_gravity()
	assert_eq(game.board.invariant_violations().size(), 0, "starting state is settled")

	var rng := RngScript.new(5)
	var vertices := Grid.vertices()
	for step in 60:
		game.rotate(rng.next_int(vertices.size()), 1 if rng.next_int(2) == 0 else -1)
		assert_eq(
			game.board.invariant_violations().size(), 0,
			"no floating pieces after move %d" % step
		)


# --- determinism and stability ---------------------------------------------

func test_replay_reproduces_the_whole_run() -> void:
	var ruleset := RulesetScript.free_rotation()
	var game := GameScript.new(4242, ruleset)
	var rng := RngScript.new(777)
	var vertices := Grid.vertices()
	for step in 40:
		game.rotate(rng.next_int(vertices.size()), 1 if rng.next_int(2) == 0 else -1)
	assert_gt(game.turns, 0, "the scripted run made moves")

	var replayed := GameScript.replay(4242, game.commands(), ruleset)
	assert_eq(replayed.signature(), game.signature(), "replay lands on the same board")
	assert_eq(replayed.score, game.score, "same score")
	assert_eq(replayed.total_combos, game.total_combos, "same combos")
	assert_eq(replayed.level, game.level, "same level")
	assert_eq(replayed.shuffle_count, game.shuffle_count, "same shuffles")


func test_replay_needs_the_same_ruleset() -> void:
	# Regression: replaying a FREE-mode log against the default STRICT ruleset
	# used to diverge wildly, because the mode decides what gets recorded.
	var free := RulesetScript.free_rotation()
	var game := GameScript.new(4242, free)
	var rng := RngScript.new(777)
	var vertices := Grid.vertices()
	for step in 20:
		game.rotate(rng.next_int(vertices.size()), 1 if rng.next_int(2) == 0 else -1)

	var same := GameScript.replay(4242, game.commands(), free)
	assert_eq(same.signature(), game.signature(), "same ruleset reproduces the run")

	var different := GameScript.replay(4242, game.commands(), RulesetScript.strict_rotation())
	assert_ne(
		different.signature(), game.signature(),
		"a different rotation mode must not pretend to reproduce the run"
	)


func test_random_playouts_keep_every_invariant() -> void:
	# ~1,200 random moves in the default suite; the 10,000-move soak lives in
	# tests/soak.gd (run_tests.ps1 -Soak).
	for run_seed in [1, 7, 13]:
		var game := GameScript.new(run_seed, RulesetScript.free_rotation())
		var rng := RngScript.new(run_seed * 31 + 5)
		var vertices := Grid.vertices()
		var committed := 0
		for step in 400:
			var vertex_index := rng.next_int(vertices.size())
			var direction := 1 if rng.next_int(2) == 0 else -1
			var result = game.rotate(vertex_index, direction)
			if result.committed:
				committed += 1
			assert_eq(game.board.invariant_violations().size(), 0, "no floating pieces (seed %d, step %d)" % [run_seed, step])
			assert_eq(game.tile_count(), 85, "Marathon keeps the board full")
			assert_ge(game.score, 0, "score never goes negative")
			assert_le(game.level, 7, "level never exceeds the cap")
		assert_gt(committed, 0, "random play commits moves (seed %d)" % run_seed)
		info("seed %d: %d moves, %d shuffles, score %d, level %d" % [run_seed, committed, game.shuffle_count, game.score, game.level])
		assert_le(game.shuffle_count, 12, "the dead-board shuffle must stay rare")
