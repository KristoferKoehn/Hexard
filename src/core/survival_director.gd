class_name SurvivalDirector
extends RefCounted

## Survival's round lifecycle (docs/design.md §6.3): when a round closes, what
## freezes, when the run is won or lost.
##
## This is the one part of Game that genuinely drives run state — score, round
## counters, finishing — so the Game is passed in rather than stored: the functions
## are still static and explicit about everything they touch, and Game keeps only a
## one-line delegation.

const RulesetScript := preload("res://src/core/ruleset.gd")
const ResolverScript := preload("res://src/core/resolver.gd")


## Called after every committed move in Survival. Ends the run if the board is clear,
## closes the round if nothing can be turned any more, and otherwise does nothing.
static func settle(game: Game, result: MoveResult) -> void:
	if game.board.filled_count() == 0:
		end_run(game, "board_cleared", true, result)
		return
	if game.has_any_legal_rotation():
		return
	close_round(game, result)


## Ends the current round: pay the round bonus, freeze what is left, refill, settle
## the refill, then check the two survival endings.
static func close_round(game: Game, result: MoveResult) -> void:
	var bonus := game.round_cleared * RulesetScript.SURVIVAL_ROUND_BONUS_PER_GEM
	game.score += bonus
	result.score += bonus
	result.round_bonus = bonus
	game.round_cleared = 0
	game.round += 1
	game.rounds_cleared += 1
	result.round_ended = true
	result.round_reached = game.round

	game.board.lock_all_remaining()
	if game.board.empty_cells().is_empty():
		# Everything on the board froze: there is nowhere left to play.
		end_run(game, "all_locked", false, result)
		return

	# The refill is settled because fresh pieces can land in a match that nothing
	# would ever clear (this is the only refill outside a resolve loop).
	ResolverScript.refill_board(game.board, game.rng_refill, result, game.level, game.ruleset)
	ResolverScript.resolve(
		game.board, game.ruleset, game.rng_refill, result, game.level, game.ruleset.refills_board
	)

	if game.rounds_cleared >= RulesetScript.SURVIVAL_ROUNDS_TO_WIN:
		end_run(game, "rounds_survived", true, result)


## Marks the run finished from inside a move's bookkeeping.
static func end_run(game: Game, reason: String, did_win: bool, result: MoveResult) -> void:
	game.finish_run(reason, did_win)
	result.finished = true
	result.finish_kind = reason
