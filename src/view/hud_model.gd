class_name HudModel
extends RefCounted

## What the status bar shows, captured once per frame (Presentation Model).
##
## The HUD used to read `game.score`, `game.ruleset.mode`, `game.board.locked_count()`
## and count bombs and pearls itself: three reaches through the facade per frame, and
## a view that could not be tested without a whole Game. This snapshot is the seam:
## built once in the controller, formatted by a pure function, and trivial to
## construct in a test.

const RulesetScript := preload("res://src/core/ruleset.gd")
const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")

var mode: int = RulesetScript.Mode.MARATHON
var mode_name := ""
var difficulty := "normal"
var strict := true
var score := 0
var level := 1
var combos_remaining := 0
var clock := 0.0
var max_clock := 0.0
var round := 1
var frozen := 0
var bombs := 0
var pearls := 0
var turn := 0
var seed_value := 0
var finished := false

## `displayed_score` lets the view roll the score up as each cascade lands; a
## negative value means "whatever the core says".
static func from_game(game: Game, displayed_score: int = -1) -> HudModel:
	var model := HudModel.new()
	if game == null:
		return model
	var ruleset: Ruleset = game.ruleset
	model.mode = int(ruleset.mode)
	model.mode_name = game.mode_name()
	model.difficulty = str(ruleset.difficulty)
	model.strict = int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.STRICT)
	model.score = displayed_score if displayed_score >= 0 else int(game.score)
	model.level = int(game.level)
	model.combos_remaining = int(game.combos_remaining())
	model.clock = float(game.clock)
	model.max_clock = float(game.max_clock)
	model.round = int(game.round)
	model.frozen = int(game.board.locked_count())
	model.bombs = count_kind(game.board, Pieces.Kind.BOMB)
	model.pearls = count_kind(game.board, Pieces.Kind.PEARL)
	model.turn = int(game.turns)
	model.seed_value = int(game.seed_value)
	model.finished = int(game.state) != 0
	return model


## Pieces of one kind on the board. Lives here rather than in the HUD so the view
## holds no board knowledge at all.
static func count_kind(board: Board, kind: int) -> int:
	var total := 0
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_empty(piece) and Pieces.kind_of(piece) == kind:
			total += 1
	return total
