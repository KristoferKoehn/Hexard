class_name MatchFinder
extends RefCounted

## Match detection (docs/design.md §3.2).
##
## The one and only match trigger: a rotation vertex whose three cells all hold
## the same gem colour. Three same-coloured pieces in a straight line do NOT
## clear, because they share no vertex.
##
## When a vertex matches, the clear set is the maximal 6-connected group of
## same-coloured cells containing it, so 3, 4, 5 and 6+ clears all fall out of
## the same rule.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const ClearGroupScript := preload("res://src/core/clear_group.gd")


## True when the three cells around this vertex are all the same gem colour.
static func vertex_is_match_at(board, vertex_index: int) -> bool:
	var all_vertices := Grid.vertices()
	if vertex_index < 0 or vertex_index >= all_vertices.size():
		return false
	return _cells_are_monochrome(board, all_vertices[vertex_index])


static func _cells_are_monochrome(board, cells: Array) -> bool:
	var first: int = board.get_piece(cells[0])
	if not Pieces.has_color(first):
		return false
	var color := Pieces.color_of(first)
	if color == Pieces.GemColor.NONE:
		return false
	for index in range(1, cells.size()):
		var piece: int = board.get_piece(cells[index])
		if not Pieces.has_color(piece):
			return false
		if Pieces.color_of(piece) != color:
			return false
	return true


## Full-board scan. Used after gravity/refill steps where many cells moved.
static func has_any_match(board) -> bool:
	for vertex: Array in Grid.vertices():
		if _cells_are_monochrome(board, vertex):
			return true
	return false


## Does the current arrangement match at this vertex or any vertex sharing a
## cell with it? Cheap test for "did the rotation I just applied match?".
static func matches_near_vertex(board, vertex_index: int) -> bool:
	for index: int in Grid.vertex_neighbours(vertex_index):
		if vertex_is_match_at(board, index):
			return true
	return false


## Indices of every matching vertex, ascending.
static func matching_vertices(board) -> Array[int]:
	var out: Array[int] = []
	var all_vertices := Grid.vertices()
	for index in all_vertices.size():
		if _cells_are_monochrome(board, all_vertices[index]):
			out.append(index)
	return out


## All clear groups in resolution order: bigger groups first, then by their
## top-left cell, so resolution is deterministic for replays.
static func clear_groups(board) -> Array:
	var seen := {}
	var groups: Array = []
	for vertex: Array in Grid.vertices():
		if not _cells_are_monochrome(board, vertex):
			continue
		var cells := _expand(board, vertex)
		var key := group_key(cells)
		if seen.has(key):
			continue
		seen[key] = true
		var group = ClearGroupScript.new()
		group.cells = cells
		group.gem_color = Pieces.color_of(board.get_piece(cells[0]))
		groups.append(group)
	groups.sort_custom(_group_before)
	return groups


## Grow a matching vertex into the maximal connected same-coloured group.
static func _expand(board, seed_cells: Array) -> Array[Vector2i]:
	var color := Pieces.color_of(board.get_piece(seed_cells[0]))
	var visited := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in seed_cells:
		visited[cell] = true
		queue.append(cell)

	var result: Array[Vector2i] = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		result.append(cell)
		for neighbour: Vector2i in Grid.neighbours(cell):
			if visited.has(neighbour):
				continue
			var piece: int = board.get_piece(neighbour)
			if not Pieces.has_color(piece) or Pieces.color_of(piece) != color:
				continue
			visited[neighbour] = true
			queue.append(neighbour)

	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return result


static func group_key(cells: Array) -> String:
	var parts := PackedStringArray()
	for cell: Vector2i in cells:
		parts.append("%d,%d" % [cell.x, cell.y])
	return "|".join(parts)


static func _group_before(a, b) -> bool:
	if a.cells.size() != b.cells.size():
		return a.cells.size() > b.cells.size()
	return group_key(a.cells) < group_key(b.cells)
