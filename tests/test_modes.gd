extends "res://tests/test_case.gd"

## Game modes and run lifecycle (docs/design.md §5, §6): Timed's clock, Survival's
## rounds and locked pieces, difficulty scaling, and the end-of-run summary.

const BoardScript := preload("res://src/core/board.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const ResolverScript := preload("res://src/core/resolver.gd")
const RngScript := preload("res://src/core/rng.gd")
const MoveResultScript := preload("res://src/core/move_result.gd")
const GameScript := preload("res://src/core/game.gd")


func _mode(run_mode: int, difficulty: String = "normal") -> RefCounted:
	return RulesetScript.for_run(RunConfig.of(run_mode, difficulty))


func _first_legal_move(game) -> Dictionary:
	var legal: Array = game.find_legal_rotations()
	if legal.is_empty():
		return {}
	return legal[0]


# --- mode plumbing ----------------------------------------------------------

func test_marathon_is_the_default_and_has_no_clock() -> void:
	var ruleset := RulesetScript.new()
	assert_eq(ruleset.mode, RulesetScript.Mode.MARATHON, "Marathon is the default")
	assert_true(ruleset.refills_board, "Marathon refills")
	assert_true(ruleset.spawns_specials, "Marathon spawns specials")

	var game := GameScript.new(3, ruleset)
	assert_eq(game.clock, 0.0, "no clock in Marathon")
	game.tick(30.0)
	assert_eq(game.clock, 0.0, "ticking does nothing outside Timed mode")
	assert_eq(game.state, GameScript.State.PLAYING, "and cannot end the run")


func test_survival_disables_refills_and_specials() -> void:
	var ruleset := _mode(RulesetScript.Mode.SURVIVAL)
	assert_false(ruleset.refills_board, "Survival never refills mid-round")
	assert_false(ruleset.spawns_specials, "Survival has no bonus stars or pearls")
	assert_eq(ruleset.bonus_star_chance_at(7), 0.0, "no stars at any level")
	assert_eq(ruleset.bomb_chance_at(7), 0.0, "and no bombs")


func test_difficulty_scales_bombs_and_clock() -> void:
	var easy := _mode(RulesetScript.Mode.MARATHON, "easy")
	var normal := _mode(RulesetScript.Mode.MARATHON, "normal")
	var hard := _mode(RulesetScript.Mode.MARATHON, "hard")

	assert_lt(easy.bomb_chance_at(5), normal.bomb_chance_at(5), "easy spawns fewer bombs")
	assert_gt(hard.bomb_chance_at(5), normal.bomb_chance_at(5), "hard spawns more")
	assert_gt(easy.bomb_counter_at(5), normal.bomb_counter_at(5), "easy fuses are longer")
	assert_lt(hard.bomb_counter_at(5), normal.bomb_counter_at(5), "hard fuses are shorter")

	var timed_normal := RulesetScript.for_run(RunConfig.of(RulesetScript.Mode.TIMED, "normal"))
	var timed_easy := RulesetScript.for_run(RunConfig.of(RulesetScript.Mode.TIMED, "easy"))
	var timed_hard := RulesetScript.for_run(RunConfig.of(RulesetScript.Mode.TIMED, "hard"))
	assert_eq(timed_normal.timed_start_seconds(), 50.0, "Normal starts at 50s")
	assert_gt(timed_easy.timed_start_seconds(), 50.0, "Easy starts with more")
	assert_lt(timed_hard.timed_start_seconds(), 50.0, "Hard starts with less")


# --- Timed ------------------------------------------------------------------

func test_timed_starts_with_a_clock() -> void:
	var game := GameScript.new(4, _mode(RulesetScript.Mode.TIMED))
	assert_eq(game.max_clock, 50.0, "clock starts at the difficulty's start value")
	assert_eq(game.clock, game.max_clock, "and is full")


func test_timed_clock_counts_down_and_ends_the_run() -> void:
	var game := GameScript.new(4, _mode(RulesetScript.Mode.TIMED))
	game.tick(10.0)
	assert_eq(game.clock, 40.0, "ten seconds gone")
	assert_eq(game.state, GameScript.State.PLAYING, "still playing")

	game.tick(45.0)
	assert_eq(game.clock, 0.0, "the clock stops at zero")
	assert_eq(game.state, GameScript.State.FINISHED, "and the run is over")
	assert_eq(game.finish_reason, "time_out", "for running out of time")
	assert_false(game.did_win(), "which is a loss")


func test_clears_buy_time_back() -> void:
	var ruleset := _mode(RulesetScript.Mode.TIMED)
	var game := GameScript.new(8, ruleset)
	var move := _first_legal_move(game)
	assert_true(move.size() > 0, "the board offers a move")
	game.clock = 10.0
	game.rotate(int(move["vertex"]), int(move["direction"]))
	assert_gt(game.clock, 10.0, "the clear paid time back")
	assert_le(game.clock, game.max_clock, "but never above the maximum")


func test_a_starflower_refills_the_clock_and_raises_the_cap() -> void:
	var game := GameScript.new(4, _mode(RulesetScript.Mode.TIMED))
	game.clock = 5.0
	var result := MoveResultScript.new()
	result.promotions.append({"cell": Vector2i(4, 4), "piece": Pieces.starflower(), "kind": "starflower"})
	game._reward_clock(result)
	assert_eq(game.clock, game.max_clock, "the clock is refilled")
	assert_eq(game.max_clock, 60.0, "and the maximum rose by 10 seconds")


func test_the_clock_cap_holds_at_two_minutes() -> void:
	var game := GameScript.new(4, _mode(RulesetScript.Mode.TIMED))
	for i in 12:
		var result := MoveResultScript.new()
		result.promotions.append({"cell": Vector2i(4, 4), "piece": Pieces.starflower(), "kind": "starflower"})
		game._reward_clock(result)
	assert_eq(game.max_clock, RulesetScript.TIMED_CAP, "the maximum caps at 120s")
	assert_eq(game.clock, RulesetScript.TIMED_CAP, "and so does the clock")


# --- Survival ---------------------------------------------------------------

func test_locked_pieces_are_inert() -> void:
	var game := GameScript.new(5, _mode(RulesetScript.Mode.SURVIVAL))
	var frozen := Vector2i(0, 8)
	game.board.lock(frozen)
	assert_true(game.board.is_locked(frozen), "the piece is locked")
	assert_false(game.board.is_playable(frozen), "and no longer playable")

	var result := game.rotate_piece(frozen, 1)
	assert_false(result.committed, "a frozen piece cannot be turned on its own")

	# A rotation that would move a locked cell is refused too.
	var vertices := Grid.vertices()
	var touching := -1
	for index in vertices.size():
		if (vertices[index] as Array).has(frozen):
			touching = index
			break
	assert_ge(touching, 0, "some vertex touches the frozen cell")
	assert_false(game.rotate(touching, 1).committed, "and its trio is frozen")


func test_locked_pieces_do_not_fall() -> void:
	var board := BoardScript.new()
	var chain := Grid.column(2)
	# Freeze a piece mid-column with a gap beneath it and a gem above.
	board.set_piece(chain[3], Pieces.gem(Pieces.GemColor.RED))
	board.lock(chain[3])
	board.set_piece(chain[2], Pieces.gem(Pieces.GemColor.GREEN))

	board.apply_gravity()
	assert_true(board.is_locked(chain[3]), "the frozen piece stayed frozen")
	assert_eq(board.get_piece(chain[3]), Pieces.gem(Pieces.GemColor.RED), "and did not move")
	assert_eq(board.get_piece(chain[2]), Pieces.gem(Pieces.GemColor.GREEN), "the gem above rests on it")
	assert_eq(board.invariant_violations().size(), 0, "which counts as settled")


func test_locked_pieces_do_not_match() -> void:
	var board := BoardScript.new()
	for cell: Vector2i in [Vector2i(4, 8), Vector2i(4, 7), Vector2i(5, 7)]:
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	board.lock(Vector2i(5, 7))
	assert_false(MatchFinder.has_any_match(board), "a frozen gem cannot complete a cluster")
	board.unlock(Vector2i(5, 7))
	assert_true(MatchFinder.has_any_match(board), "thawing it restores the match")


func test_a_survival_round_ends_and_freezes_the_leftovers() -> void:
	var game := GameScript.new(11, _mode(RulesetScript.Mode.SURVIVAL))
	game.ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var keep := [Vector2i(0, 8), Vector2i(2, 8), Vector2i(4, 8)]
	for cell: Vector2i in Grid.all_cells():
		if not keep.has(cell):
			game.board.remove_piece(cell)

	var result := game.rotate(0, 1)
	assert_true(result.committed, "the spin committed")
	assert_true(result.round_ended, "and the round closed")
	assert_eq(game.round, 2, "round counter advanced")
	assert_eq(game.board.locked_count(), 3, "the three leftovers froze")
	assert_gt(game.tile_count(), 3, "and the gaps were refilled")
	assert_false(MatchFinder.has_any_match(game.board), "the new round starts stable")
	assert_eq(game.board.invariant_violations().size(), 0, "and settled")
	assert_eq(game.state, GameScript.State.PLAYING, "the run continues")


func test_survival_is_won_by_clearing_the_board() -> void:
	var game := GameScript.new(5, _mode(RulesetScript.Mode.SURVIVAL))
	for cell: Vector2i in Grid.all_cells():
		game.board.remove_piece(cell)
	game.settle(MoveResultScript.new())
	assert_eq(game.state, GameScript.State.FINISHED, "the run ends")
	assert_eq(game.finish_reason, "board_cleared", "because the board is clear")
	assert_true(game.did_win(), "which is a win")


func test_survival_is_lost_when_everything_freezes() -> void:
	var game := GameScript.new(5, _mode(RulesetScript.Mode.SURVIVAL))
	game.board.lock_all_remaining()
	game.settle(MoveResultScript.new())
	assert_eq(game.state, GameScript.State.FINISHED, "the run ends")
	assert_eq(game.finish_reason, "all_locked", "with nothing left to turn")
	assert_false(game.did_win(), "which is a loss")


func test_survival_is_won_by_surviving_fifty_rounds() -> void:
	var game := GameScript.new(5, _mode(RulesetScript.Mode.SURVIVAL))
	game.rounds_cleared = RulesetScript.SURVIVAL_ROUNDS_TO_WIN - 1
	game.ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var keep := [Vector2i(0, 8), Vector2i(2, 8)]
	for cell: Vector2i in Grid.all_cells():
		if not keep.has(cell):
			game.board.remove_piece(cell)
	game.rotate(0, 1)
	assert_eq(game.rounds_cleared, RulesetScript.SURVIVAL_ROUNDS_TO_WIN, "fifty rounds")
	assert_eq(game.finish_reason, "rounds_survived", "the run is a win")
	assert_true(game.did_win(), "and counts as one")


func test_survival_flower_unlocks_the_board_and_sweeps_a_colour() -> void:
	var board := BoardScript.new()
	# A full match-free background, a flower, and a couple of frozen pieces.
	var palette: Array = Pieces.BASE_COLORS
	for cell: Vector2i in Grid.all_cells():
		board.set_piece(cell, Pieces.gem(palette[(2 * cell.x + cell.y) % palette.size()]))
	var centre := Vector2i(4, 4)
	board.set_piece(centre, Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in Grid.neighbours(centre):
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	board.lock(Vector2i(0, 8))
	board.lock(Vector2i(2, 8))

	var result := MoveResultScript.new()
	ResolverScript.resolve(
		board, RulesetScript.for_run(RunConfig.of(RulesetScript.Mode.SURVIVAL)), RngScript.new(1), result, 1, false
	)
	assert_true(_has_formation(result, "flower"), "the flower fired")
	assert_true(_has_formation(result, "flower_sweep"), "and swept its colour")
	assert_eq(board.locked_count(), 0, "every frozen piece thawed")
	assert_eq(_count_kind(board, Pieces.Kind.STARFLOWER), 0, "no starflower is created in Survival")


func test_a_bonus_star_thaws_its_neighbours() -> void:
	var board := BoardScript.new()
	board.set_piece(Vector2i(4, 7), Pieces.bonus_star(Pieces.GemColor.RED))
	board.set_piece(Vector2i(4, 8), Pieces.bonus_star(Pieces.GemColor.GREEN))
	board.set_piece(Vector2i(5, 7), Pieces.bonus_star(Pieces.GemColor.BLUE))
	board.set_piece(Vector2i(3, 7), Pieces.gem(Pieces.GemColor.CYAN))
	board.lock(Vector2i(3, 7))

	var result := MoveResultScript.new()
	ResolverScript.resolve(board, RulesetScript.new(), RngScript.new(1), result, 1, false)
	assert_true(_has_formation(result, "bonus_star_cluster"), "the stars went off")
	assert_true(_has_formation(result, "thawed"), "and thawed what they touched")
	assert_false(board.is_locked(Vector2i(3, 7)), "the frozen neighbour is free")


# --- run summary ------------------------------------------------------------

func test_summary_describes_the_finished_run() -> void:
	var game := GameScript.new(4, _mode(RulesetScript.Mode.TIMED, "hard"))
	game.tick(999.0)
	var summary: RunSummary = game.summary()
	assert_eq(summary.mode, "Timed", "mode name")
	assert_eq(summary.difficulty, "hard", "difficulty")
	assert_eq(summary.reason, "time_out", "why it ended")
	assert_eq(summary.won, false, "and that it was a loss")
	assert_gt(summary.elapsed, 0.0, "with elapsed time")
	# The counters the profile reads must actually be produced by the run: they used
	# to be absent from the summary entirely, so ProfileService recorded zeros.
	assert_eq(summary.turns, game.turns, "turns are reported")
	assert_eq(summary.seed_value, game.seed_value, "the replay seed is reported")
	assert_ge(summary.cleared, 0, "cleared tiles are reported")




