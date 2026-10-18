class_name Board
extends RefCounted

## Cell storage for the 85-cell board plus the gravity compaction pass.
## Values are packed piece ids (see Piece); Piece.EMPTY means no gem.
##
## Survival mode can also **lock** a piece (docs/design.md §6.3): a locked piece
## is frozen — it does not fall, cannot be rotated, and is inert to matching. It
## only comes back to life when a flower or a bonus star unlocks it.

const HexGridScript := preload("res://src/core/hex_grid.gd")
const PieceScript := preload("res://src/core/piece.gd")

var _cells: Dictionary = {}
var _locked: Dictionary = {}

## Bumped whenever a piece or a lock changes. Caches that answer questions about the whole
## board (does this spin do anything?) key on this instead of on a signature: the cursor asks
## on every keystroke, and the answer can only change when this does.
var version := 0


func _init() -> void:
	clear()


func clear() -> void:
	version += 1
	for cell: Vector2i in HexGridScript.all_cells():
		_cells[cell] = PieceScript.EMPTY
	_locked.clear()


func get_piece(cell: Vector2i) -> int:
	return _cells.get(cell, PieceScript.EMPTY)


func set_piece(cell: Vector2i, piece: int) -> void:
	version += 1
	_cells[cell] = piece


func remove_piece(cell: Vector2i) -> void:
	version += 1
	_cells[cell] = PieceScript.EMPTY
	_locked.erase(cell)


func is_empty(cell: Vector2i) -> bool:
	return get_piece(cell) == PieceScript.EMPTY


# --- locking ----------------------------------------------------------------

func lock(cell: Vector2i) -> void:
	version += 1
	if not is_empty(cell):
		_locked[cell] = true


func unlock(cell: Vector2i) -> void:
	version += 1
	_locked.erase(cell)


func is_locked(cell: Vector2i) -> bool:
	return _locked.has(cell)


## A piece the rules can actually act on: present and not frozen.
func is_playable(cell: Vector2i) -> bool:
	return not is_empty(cell) and not is_locked(cell)



func locked_count() -> int:
	return _locked.size()


func unlock_all() -> int:
	version += 1
	var count := _locked.size()
	_locked.clear()
	return count


## Clears every lock without touching the pieces (used when a board is refilled).
func clear_locks() -> void:
	version += 1
	_locked.clear()


func lock_all_remaining() -> int:
	version += 1
	var count := 0
	for cell: Vector2i in HexGridScript.all_cells():
		if not is_empty(cell) and not is_locked(cell):
			_locked[cell] = true
			count += 1
	return count


func filled_count() -> int:
	var total := 0
	for value: int in _cells.values():
		if value != PieceScript.EMPTY:
			total += 1
	return total


func empty_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in HexGridScript.all_cells():
		if is_empty(cell):
			out.append(cell)
	return out


## Comps every column downwards (no sideways sliding; docs/design.md §2.2).
## Returns the number of pieces that changed cell.
func apply_gravity() -> int:
	return apply_gravity_moves().size()


## Same pass, but reports each piece's movement so the view can animate falls.
## Locked pieces are floors: nothing falls through them and they never move.
func apply_gravity_moves() -> Array:
	var moves: Array = []
	for column_index in HexGridScript.COLUMNS:
		var chain: Array[Vector2i] = HexGridScript.column(column_index)
		var write := chain.size() - 1
		for read in range(chain.size() - 1, -1, -1):
			var cell: Vector2i = chain[read]
			if is_locked(cell):
				# Frozen in place; the segment above restacks on top of it.
				write = read - 1
				continue
			var piece := get_piece(cell)
			if piece == PieceScript.EMPTY:
				continue
			if write != read:
				set_piece(chain[write], piece)
				remove_piece(cell)
				moves.append({"from": cell, "to": chain[write]})
			write -= 1
	return moves


## Highest empty cell in a column, or null when the column is full.
func first_empty_from_top(column_index: int) -> Variant:
	for cell: Vector2i in HexGridScript.column(column_index):
		if is_empty(cell):
			return cell
	return null


## Structural invariants that must hold after every rules step.
## Returns a list of violations; empty means healthy.
##
## Scan runs bottom-to-top: an empty cell with a filled cell above it means that
## piece is floating (it should have fallen). Empty cells *above* a resting piece
## are normal after gravity. A **locked** piece is a floor: it is allowed to hang
## with gaps beneath it, and anything above it rests on its top.
func invariant_violations() -> Array[String]:
	var problems: Array[String] = []
	for column_index in HexGridScript.COLUMNS:
		var chain: Array[Vector2i] = HexGridScript.column(column_index)
		var seen_empty := false
		for index in range(chain.size() - 1, -1, -1):
			var cell: Vector2i = chain[index]
			if is_locked(cell):
				seen_empty = false
				continue
			if is_empty(cell):
				seen_empty = true
			elif seen_empty:
				problems.append(
					"floating piece at %s (empty cell below it in column %d)" % [cell, column_index]
				)
	return problems


## Stable digest of the board, for golden tests and replay comparisons.
func signature() -> String:
	var parts := PackedStringArray()
	for cell: Vector2i in HexGridScript.all_cells():
		parts.append("%d:%d" % [cell.y * HexGridScript.COLUMNS + cell.x, get_piece(cell)])
	return ",".join(parts)


## Debug view: 17 staggered half-rows, ".." = empty, otherwise the piece kind.
func to_ascii() -> String:
	var lines := PackedStringArray()
	for half in HexGridScript.EXPECTED_HALF_ROWS:
		var line := ""
		for column_index in HexGridScript.COLUMNS:
			var parity := column_index % 2
			if parity != half % 2:
				line += "   "
				continue
			var row := (half - (1 if parity == 1 else 0)) / 2
			var cell := Vector2i(column_index, row)
			if not HexGridScript.has_cell(cell):
				line += "   "
			elif is_empty(cell):
				line += ".. "
			else:
				var piece := get_piece(cell)
				line += "%s%s " % [
					str(PieceScript.kind_of(piece)).substr(0, 1),
					str(PieceScript.color_of(piece)).substr(0, 1),
				]
		lines.append(line.rstrip(" "))
	return "\n".join(lines)
