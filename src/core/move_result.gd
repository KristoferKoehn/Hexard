class_name MoveResult
extends RefCounted

## Everything that happened during one player move, in a form the view layer
## can animate and the tests can assert on. Emitted by Game.rotate().
##
## The core never touches Nodes: it produces one of these and the view decides
## how to present it (or applies it instantly in fast-forward mode).

## False when the move was rejected: STRICT mode reverted a non-matching spin,
## or the vertex index was invalid. Nothing on the board changed.
var committed := true
var rejected_reason := ""

var rotation_vertex := -1
var rotation_cells: Array[Vector2i] = []
## +1 = clockwise on screen (next index in HexicGrid cyclic order), -1 = CCW.
var direction := 0

var clear_groups: Array = []          # Array[ClearGroup], in resolution order
var gravity_moves: Array = []         # Array of {from: Vector2i, to: Vector2i}
var spawns: Array = []                # Array of {cell: Vector2i, piece: int}

var cleared_count := 0
var score := 0
var combos := 0
var cascades := 0
var level_up := false
var new_level := 1
var dead_board := false
var shuffled := false
var finished := false


func describe() -> String:
	if not committed:
		return "move(rejected: %s)" % rejected_reason
	return "move(vertex=%d, dir=%d, clears=%d, cells=%d, cascades=%d, score=%d, combos=%d)" % [
		rotation_vertex, direction, clear_groups.size(), cleared_count, cascades, score, combos,
	]
