extends "res://tests/test_case.gd"

## The scripted tutorial (docs/design.md §7.4): each step must rig a legal board,
## wait for the player to do the thing, and only then move on.

const MatchFinder := preload("res://src/core/match_finder.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const TutorialScript := preload("res://src/core/tutorial.gd")
const GameScript := preload("res://src/core/game.gd")


## Any spin that the rules will accept (the tutorial runs FREE rotation).
func _any_spin(tutorial) -> RefCounted:
	var legal: Array = tutorial.game.find_legal_rotations()
	if not legal.is_empty():
		var move: Dictionary = legal[0]
		return tutorial.game.rotate(int(move["vertex"]), int(move["direction"]))
	return tutorial.game.rotate(0, 1)


func test_tutorial_opens_on_a_playable_board() -> void:
	var tutorial := TutorialScript.new()
	assert_eq(tutorial.step_number(), 1, "starts on step 1")
	assert_eq(tutorial.goal_id(), "clear", "which is about clearing")
	assert_eq(tutorial.game.tile_count(), 85, "board is full")
	assert_false(MatchFinder.has_any_match(tutorial.game.board), "and match-free")
	assert_eq(tutorial.game.board.invariant_violations().size(), 0, "and settled")
	assert_true(
		tutorial.game.has_any_legal_rotation(),
		"the opening board offers at least one clearing spin"
	)
	assert_gt(tutorial.instruction().length(), 0, "with an instruction to read")


func test_a_clear_advances_the_first_step() -> void:
	var tutorial := TutorialScript.new()
	var result := _any_spin(tutorial)
	assert_ge(result.cleared_count, 3, "the spin cleared something")
	assert_true(tutorial.evaluate(result), "which completes step 1")
	assert_eq(tutorial.goal_id(), "stars", "moving on to bonus stars")


func test_the_star_step_rigs_a_star_cluster() -> void:
	var tutorial := TutorialScript.new()
	tutorial.evaluate(_any_spin(tutorial))
	var stars := MatchFinder.star_cluster_cells(tutorial.game.board)
	assert_gt(stars.size(), 0, "three bonus stars are sitting ready")
	assert_eq(MatchFinder.has_any_match(tutorial.game.board), false, "and nothing else is primed")


func test_clearing_the_stars_advances() -> void:
	var tutorial := TutorialScript.new()
	tutorial.evaluate(_any_spin(tutorial))
	var result := _any_spin(tutorial)
	assert_true(tutorial.evaluate(result), "the star cluster went off")
	assert_eq(tutorial.goal_id(), "starflower", "now teaching flowers")


func test_the_flower_step_blooms_on_the_next_move() -> void:
	var tutorial := TutorialScript.new()
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(_any_spin(tutorial))
	assert_true(MatchFinder.is_flower(tutorial.game.board, Vector2i(4, 4)), "a flower is primed")

	var result := _any_spin(tutorial)
	assert_true(tutorial.evaluate(result), "the flower blooms on the next spin")
	assert_eq(tutorial.goal_id(), "turn", "now teaching starflower turns")


func test_the_turn_step_wants_a_piece_turn_not_a_spin() -> void:
	var tutorial := TutorialScript.new()
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(_any_spin(tutorial))
	assert_eq(tutorial.goal_id(), "turn", "on the turning step")
	assert_true(
		Pieces.is_starflower(tutorial.game.board.get_piece(Vector2i(4, 4))),
		"a starflower is staged at the centre"
	)

	var spin := _any_spin(tutorial)
	assert_false(tutorial.evaluate(spin), "a trio spin does not complete this step")
	assert_eq(tutorial.goal_id(), "turn", "still waiting")

	var turned := tutorial.game.rotate_piece(Vector2i(4, 4), GameScript.CLOCKWISE)
	assert_true(turned.committed, "the starflower turned")
	assert_true(tutorial.evaluate(turned), "which completes the step")
	assert_eq(tutorial.goal_id(), "pearl", "now teaching pearls")


func test_the_pearl_step_completes_the_tutorial() -> void:
	var tutorial := TutorialScript.new()
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(_any_spin(tutorial))
	tutorial.evaluate(tutorial.game.rotate_piece(Vector2i(4, 4), GameScript.CLOCKWISE))
	assert_eq(tutorial.goal_id(), "pearl", "on the last step")

	var result := _any_spin(tutorial)
	assert_true(tutorial.evaluate(result), "the pearl ring resolves")
	assert_true(tutorial.complete, "and the tutorial is done")
	assert_eq(tutorial.step_title(), "Tutorial complete", "with a closing title")
	assert_eq(tutorial.goal_id(), "", "and no further goal")
	assert_eq(tutorial.evaluate(result), false, "a finished tutorial stays finished")


func test_a_rejected_move_never_advances() -> void:
	var tutorial := TutorialScript.new()
	var rejected := tutorial.game.rotate(-1, 1)
	assert_false(rejected.committed, "the move was rejected")
	assert_false(tutorial.evaluate(rejected), "and cannot complete a step")
	assert_eq(tutorial.step_number(), 1, "still on step 1")


func test_every_step_offers_a_vertex_to_look_at() -> void:
	var tutorial := TutorialScript.new()
	for step in tutorial.step_count():
		var vertex: int = tutorial.hint_vertex()
		assert_ge(vertex, 0, "step %d suggests a vertex" % step)
		assert_lt(vertex, Grid.vertices().size(), "step %d suggests a real vertex" % step)
		if tutorial.complete:
			break
		var result := _any_spin(tutorial)
		if tutorial.goal_id() == "turn":
			result = tutorial.game.rotate_piece(Vector2i(4, 4), GameScript.CLOCKWISE)
		tutorial.evaluate(result)


func test_a_missed_spin_restores_the_step() -> void:
	# The old behaviour left the board changed and the step stuck; a stray spin could
	# make a step impossible with no feedback.
	var tutorial := TutorialScript.new()
	var before: int = tutorial.game.board.get_piece(Vector2i(4, 4))
	var far := tutorial.game.rotate(0, 1)
	if far.committed:
		assert_false(tutorial.evaluate(far), "a spin away from the formation does not advance")
		assert_true(tutorial.retried, "and says so")
		assert_eq(tutorial.attempts, 1, "counting the attempt")
		assert_eq(tutorial.goal_id(), "clear", "still on the same step")
		assert_eq(tutorial.game.board.get_piece(Vector2i(3, 3)), Pieces.gem(Pieces.GemColor.RED),
			"and the rig is back exactly as it was")
		assert_eq(tutorial.game.board.get_piece(Vector2i(4, 4)), before, "cell for cell")


func test_advancing_clears_the_retry_flag() -> void:
	var tutorial := TutorialScript.new()
	var far := tutorial.game.rotate(0, 1)
	if far.committed:
		tutorial.evaluate(far)
		assert_true(tutorial.retried, "a miss is flagged")
	var advance := _any_spin(tutorial)
	assert_true(tutorial.evaluate(advance), "the real spin advances")
	assert_false(tutorial.retried, "clearing the flag")
	assert_eq(tutorial.attempts, 0, "and the attempt count")
