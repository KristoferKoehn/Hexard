class_name RunSummary
extends RefCounted

## Everything a finished run reports (docs/design.md §6.5), as a typed record.
##
## This replaces an untyped Dictionary that was read in two places with invented
## defaults — `summary.get("mode", "Marathon")`, `get("level", 1)`, and five fields
## that did not exist at all and so were always zero. A renamed key produced a
## plausible wrong leaderboard entry instead of an error; now it is a compile error.
##
## A DTO like this carries values and nothing else: no game, no board, no scoring.

var mode := ""
var difficulty := "normal"
var score := 0
var level := 1
var combos := 0
var turns := 0
var rounds := 0
var reason := ""
var won := false
var elapsed := 0.0
## Kill counts, accumulated by Game as moves resolve.
var cleared := 0
var pearls := 0
var starflowers := 0
var bombs_defused := 0
var seed_value := 0


static func from_game(game: Game) -> RunSummary:
	var summary := RunSummary.new()
	if game == null:
		return summary
	summary.mode = game.mode_name()
	summary.difficulty = str(game.ruleset.difficulty)
	summary.score = int(game.score)
	summary.level = int(game.level)
	summary.combos = int(game.total_combos)
	summary.turns = int(game.turns)
	summary.rounds = int(game.rounds_cleared)
	summary.reason = str(game.finish_reason)
	summary.won = bool(game.victory)
	summary.elapsed = float(game.elapsed)
	summary.cleared = int(game.total_cleared)
	summary.pearls = int(game.total_pearls)
	summary.starflowers = int(game.total_starflowers)
	summary.bombs_defused = int(game.total_defused)
	summary.seed_value = int(game.seed_value)
	return summary
