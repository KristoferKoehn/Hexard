class_name BombRules
extends RefCounted

## Bomb fuses and the blast (docs/design.md §3.4).
##
## Pure over a Board and a MoveResult: this decides what the bombs do and records it,
## and tells the caller whether one went off. Ending the *run* is the Game's job,
## which keeps the lifecycle in one place instead of at the bottom of a rules
## function — the old version called Game._finish() from here.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")


## Ticks every fuse by one move. Returns true if a bomb reached zero, in which case
## the whole board has been destroyed and `result` says so.
static func tick(board: Board, result: MoveResult) -> bool:
	var exploders: Array[Vector2i] = []
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_bomb(piece):
			continue
		var remaining := Pieces.counter_of(piece) - 1
		if remaining <= 0:
			exploders.append(cell)
			board.set_piece(cell, Pieces.with_counter(piece, 0))
			continue
		board.set_piece(cell, Pieces.with_counter(piece, remaining))
		result.bombs_ticked.append({"cell": cell, "counter": remaining})

	if exploders.is_empty():
		return false

	# A dying bomb takes the whole board with it. `exploded_cells` starts with the
	# bomb itself, so the view can use element 0 as the blast origin.
	var shattered: Array[Vector2i] = exploders.duplicate()
	for cell: Vector2i in Grid.all_cells():
		if not shattered.has(cell):
			shattered.append(cell)
	for cell: Vector2i in shattered:
		board.remove_piece(cell)

	# Nothing here scores: the blast is the game-over event, not a clear.
	result.bomb_exploded = true
	result.game_over = true
	result.finished = true
	result.finish_kind = "bomb_exploded"
	result.exploded_cells.assign(shattered)
	return true
