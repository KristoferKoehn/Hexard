class_name TurnRules
extends RefCounted

## Everything about a turn: which cells it would cycle, and whether it is worth
## making (docs/design.md §3.2).
##
## Pure functions over a Board — no Game, no MoveResult, no scoring. The view asks
## the same questions to draw its outline, and the answer comes from here, so the
## cursor cannot disagree with the rules.
##
## This was 128 lines of Game: the facade had become the place where turn rules,
## bombs, survival rounds and the run lifecycle all lived.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinderScript := preload("res://src/core/match_finder.gd")

const CLOCKWISE := 1
const COUNTER_CLOCKWISE := -1


# --- what a turn moves -------------------------------------------------------

## Cells a special turn at `cell` would cycle: six for a starflower ring, the three
## of a pearl's Y, and none for anything that cannot turn on its own.
static func swapped_cells(board: Board, cell: Vector2i) -> Array[Vector2i]:
	if not Grid.has_cell(cell):
		return []
	var piece: int = board.get_piece(cell)
	if Pieces.is_starflower(piece):
		return Grid.cyclic_order(Grid.neighbours(cell))
	if Pieces.is_pearl(piece):
		return pearl_y_cells(cell)
	var none: Array[Vector2i] = []
	return none


## The pearl's Y: three alternating neighbours, so a turn cycles a triangle-ish
## path rather than the whole ring.
static func pearl_y_cells(cell: Vector2i) -> Array[Vector2i]:
	var ordered := Grid.cyclic_order(Grid.neighbours(cell))
	var cells: Array[Vector2i] = []
	var parity := cell.x % 2
	for index in ordered.size():
		if index % 2 == parity:
			cells.append(ordered[index])
	return cells


## Rotates the pieces on `cells` one step. Order matters: the cells arrive in
## cyclic order, so this is a genuine rotation rather than a shuffle.
static func cycle(board: Board, cells: Array, direction: int) -> void:
	var count := cells.size()
	var pieces: Array[int] = []
	for cell: Vector2i in cells:
		pieces.append(board.get_piece(cell))
	for index in count:
		board.set_piece(cells[index], pieces[posmod(index - direction, count)])


# --- is a turn worth making --------------------------------------------------

## A spin is worth accepting when it makes anything at all: a colour match, or a
## formation — a flower blooming, or a pearl ring closing. That second clause is
## what lets the last spin into a flower land even in STRICT mode, where a spin
## that clears nothing is otherwise not a move.
##
## `already_cycled` means the caller has already applied the rotation (the real move
## path), so this must not cycle again.
static func makes_something(
	board: Board, vertex_index: int, direction: int, cells: Array, already_cycled: bool = false
) -> bool:
	if not already_cycled:
		cycle(board, cells, direction)
	var matched := MatchFinderScript.matches_near_vertex(board, vertex_index)
	if not matched:
		matched = formation_near(board, cells)
	if not already_cycled:
		cycle(board, cells, -direction)
	return matched


## Is any flower or pearl ring sitting on or beside these cells right now? Only the
## trio and its neighbours can have just finished one, so this stays cheap enough to
## run from the cursor highlight every frame.
static func formation_near(board: Board, cells: Array) -> bool:
	for cell: Vector2i in cells:
		if is_formation_centre(board, cell):
			return true
		for neighbour: Vector2i in Grid.neighbours(cell):
			if is_formation_centre(board, neighbour):
				return true
	return false


static func is_formation_centre(board: Board, cell: Vector2i) -> bool:
	return MatchFinderScript.formation_at(board, cell)


# --- queries ----------------------------------------------------------------

## Would spinning this vertex one step in this direction do something?
## Cheap (two rotations and a local test), so the view can ask per frame.
static func is_legal_rotation(board: Board, vertex_index: int, direction: int) -> bool:
	var vertices := Grid.vertices()
	if vertex_index < 0 or vertex_index >= vertices.size():
		return false
	if direction != CLOCKWISE and direction != COUNTER_CLOCKWISE:
		return false
	return makes_something(board, vertex_index, direction, vertices[vertex_index])


## True when either direction does something here — what the cursor highlight shows.
static func has_legal_spin(board: Board, vertex_index: int) -> bool:
	return is_legal_rotation(board, vertex_index, CLOCKWISE) \
		or is_legal_rotation(board, vertex_index, COUNTER_CLOCKWISE)


## Every rotation that would do something right now. Doubles as the hint source and
## the dead-board test, and follows the same rule as a real spin: clears or forms
## count, so a board with only a flower-completing spin is not dead.
static func find_legal_rotations(board: Board) -> Array:
	var out: Array = []
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		for direction in [CLOCKWISE, COUNTER_CLOCKWISE]:
			if makes_something(board, vertex_index, direction, vertices[vertex_index]):
				out.append({"vertex": vertex_index, "direction": direction})
	return out


static func has_any_legal_rotation(board: Board) -> bool:
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		for direction in [CLOCKWISE, COUNTER_CLOCKWISE]:
			if makes_something(board, vertex_index, direction, vertices[vertex_index]):
				return true
	return false
