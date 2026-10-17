class_name MoveResult
extends RefCounted

## Everything that happened during one player move, in a form the view layer
## can animate and the tests can assert on. Emitted by Game.rotate() and
## Game.rotate_piece().
##
## The core never touches Nodes: it produces one of these and the view decides
## how to present it (or applies it instantly in fast-forward mode).

## False when the move was rejected: STRICT mode reverted a non-matching spin,
## or the input was invalid. Nothing on the board changed.
var committed := true
var rejected_reason := ""

var rotation_vertex := -1
var rotation_cells: Array[Vector2i] = []
## Set when the move was a special-piece rotation (starflower ring / pearl Y).
var piece_cell := Vector2i(-1, -1)
## +1 = clockwise on screen (next index in Hexical cyclic order), -1 = CCW.
var direction := 0

var clear_groups: Array = []          # Array[ClearGroup], in resolution order
var gravity_moves: Array = []         # Array of {from: Vector2i, to: Vector2i}
var spawns: Array = []                # Array of {cell: Vector2i, piece: int}
## Cells that upgraded in place: {cell: Vector2i, piece: int}.
var promotions: Array = []
## Bombs that lost a tick this move: {cell: Vector2i, counter: int}.
var bombs_ticked: Array = []
var exploded_cells: Array[Vector2i] = []

var cleared_count := 0
var score := 0
var combos := 0
var cascades := 0
var level_up := false
var new_level := 1
var dead_board := false
var shuffled := false
## The run ended: a pearl finish (win) or a bomb (loss).
var finished := false
var finish_kind := ""
var bomb_exploded := false
var game_over := false


func describe() -> String:
	if not committed:
		return "move(rejected: %s)" % rejected_reason
	var kind := "trio"
	if piece_cell != Vector2i(-1, -1):
		kind = "piece@%s" % piece_cell
	return "move(%s, dir=%d, clears=%d, cells=%d, cascades=%d, score=%d, combos=%d)" % [
		kind, direction, clear_groups.size(), cleared_count, cascades, score, combos,
	]
