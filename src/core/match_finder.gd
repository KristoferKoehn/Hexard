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
##
## Locked pieces (Survival) are inert: they never form or extend a formation.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const ClearGroupScript := preload("res://src/core/clear_group.gd")


# --- the predicate ----------------------------------------------------------

## True when the three cells around this vertex are all the same gem colour.
static func vertex_is_match_at(board: Board, vertex_index: int) -> bool:
	var all_vertices := Grid.vertices()
	if vertex_index < 0 or vertex_index >= all_vertices.size():
		return false
	return _cells_are_monochrome(board, all_vertices[vertex_index])


static func _cells_are_monochrome(board: Board, cells: Array) -> bool:
	if not _is_matchable(board, cells[0]):
		return false
	var color := Pieces.color_of(board.get_piece(cells[0]))
	for index in range(1, cells.size()):
		if not _is_matchable(board, cells[index]):
			return false
		if Pieces.color_of(board.get_piece(cells[index])) != color:
			return false
	return true


## Can this cell take part in a formation? Present, unlocked, and coloured.
static func _is_matchable(board: Board, cell: Vector2i) -> bool:
	if board.is_locked(cell):
		return false
	var piece: int = board.get_piece(cell)
	if not Pieces.has_color(piece):
		return false
	return Pieces.color_of(piece) != Pieces.GemColor.NONE


## Full-board scan. Used after gravity/refill steps where many cells moved.
static func has_any_match(board: Board) -> bool:
	for vertex: Array in Grid.vertices():
		if _cells_are_monochrome(board, vertex):
			return true
	return false


## Does the current arrangement match at this vertex or any vertex sharing a
## cell with it? Cheap test for "did the rotation I just applied match?".
static func matches_near_vertex(board: Board, vertex_index: int) -> bool:
	for index: int in Grid.vertex_neighbours(vertex_index):
		if vertex_is_match_at(board, index):
			return true
	return false


## Indices of every matching vertex, ascending.
static func matching_vertices(board: Board) -> Array[int]:
	var out: Array[int] = []
	var all_vertices := Grid.vertices()
	for index in all_vertices.size():
		if _cells_are_monochrome(board, all_vertices[index]):
			out.append(index)
	return out


# --- groups -----------------------------------------------------------------

## All clear groups in resolution order: bigger groups first, then by their
## top-left cell, so resolution is deterministic for replays.
static func clear_groups(board: Board) -> Array:
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
		var group := ClearGroupScript.new()
		group.cells = cells
		group.gem_color = Pieces.color_of(board.get_piece(cells[0]))
		groups.append(group)
	groups.sort_custom(_group_before)
	return groups


## Grow a matching vertex into the maximal connected same-coloured group.
static func _expand(board: Board, seed_cells: Array) -> Array[Vector2i]:
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
			if not _is_matchable(board, neighbour):
				continue
			if Pieces.color_of(board.get_piece(neighbour)) != color:
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


# --- special formations (docs/design.md §3.4) -------------------------------

## A flower is six pieces of one colour ringing a centre. The ring may be gems,
## bonus stars or bombs — anything carrying a colour counts as a petal — and the
## centre may be a different colour or a different type. A bomb in the middle is
## consumed by the bloom rather than ticking, so a flower can disarm one.
static func is_flower(board: Board, centre: Vector2i) -> bool:
	var centre_piece: int = board.get_piece(centre)
	if Pieces.is_empty(centre_piece) or Pieces.is_pearl(centre_piece):
		return false
	var ring := Grid.neighbours(centre)
	if ring.size() != 6:
		return false

	var ring_color := -1
	for cell: Vector2i in ring:
		if board.is_locked(cell):
			return false
		var piece: int = board.get_piece(cell)
		if Pieces.is_empty(piece) or not Pieces.has_color(piece):
			return false
		var color := int(Pieces.color_of(piece))
		if ring_color == -1:
			ring_color = color
		elif color != ring_color:
			return false

	# A bomb at the centre is always accepted: it is replaced by the bloom before
	# anything can tick, which is what makes a flower a way to defuse one. Any
	# other coloured centre must differ from the ring, so a plain single-colour
	# blob is never mistaken for a flower.
	if Pieces.is_bomb(centre_piece):
		return true
	if Pieces.has_color(centre_piece) and int(Pieces.color_of(centre_piece)) == ring_color:
		return false
	return true


static func flower_centres(board: Board) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in Grid.all_cells():
		if is_flower(board, cell):
			out.append(cell)
	return out


## Six starflowers ringing a centre: the centre becomes a black pearl.
static func is_pearl_creation_ring(board: Board, centre: Vector2i) -> bool:
	if Pieces.is_pearl(board.get_piece(centre)):
		return false
	return _six_neighbours_all(board, centre, Pieces.Kind.STARFLOWER)


## Six pearls ringing a centre: the pearl finish, the biggest payout in the game.
## A pearl at the centre is allowed — that is a ring of seven, and the ring rule
## should claim it before the three-pearl cluster rule does.
static func is_pearl_finish_ring(board: Board, centre: Vector2i) -> bool:
	return _six_neighbours_all(board, centre, Pieces.Kind.PEARL)


static func _six_neighbours_all(board: Board, centre: Vector2i, kind: int) -> bool:
	var ring := Grid.neighbours(centre)
	if ring.size() != 6:
		return false
	return _cells_all_kind(board, ring, kind)


static func pearl_ring_centres(board: Board) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in Grid.all_cells():
		if is_pearl_creation_ring(board, cell):
			out.append(cell)
	return out


## The perfect finish: a ring of six pearls (the biggest payout) or a cluster of
## three. Returns {} when neither exists.
static func pearl_finish(board: Board) -> Dictionary:
	for cell: Vector2i in Grid.all_cells():
		if is_pearl_finish_ring(board, cell):
			return {"kind": "pearl_ring", "cells": Grid.neighbours(cell), "anchor": cell}
	for vertex: Array in Grid.vertices():
		if _cells_all_kind(board, vertex, Pieces.Kind.PEARL):
			var cells: Array[Vector2i] = []
			for cell: Vector2i in vertex:
				cells.append(cell)
			return {"kind": "pearl_cluster", "cells": cells, "anchor": Vector2i(-1, -1)}
	return {}


## Cells removed by a bonus-star cluster: the three stars plus every tile each
## star touches (docs/design.md §3.4). Locked tiles stay put.
static func star_cluster_cells(board: Board) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for vertex: Array in Grid.vertices():
		if not _cells_all_kind(board, vertex, Pieces.Kind.BONUS_STAR):
			continue
		for star: Vector2i in vertex:
			_add_cell_and_neighbours(board, star, seen, out)
	return out


## Three starflowers together pay a windfall and clear.
static func starflower_cluster_cells(board: Board) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for vertex: Array in Grid.vertices():
		if not _cells_all_kind(board, vertex, Pieces.Kind.STARFLOWER):
			continue
		for cell: Vector2i in vertex:
			if not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out


## Every playable cell holding a piece of this gem colour (bomb colour wipe).
static func cells_with_color(board: Board, gem_color: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in Grid.all_cells():
		if not _is_matchable(board, cell):
			continue
		if int(Pieces.color_of(board.get_piece(cell))) == gem_color:
			out.append(cell)
	return out


static func _cells_all_kind(board: Board, cells: Array, kind: int) -> bool:
	for cell: Vector2i in cells:
		if board.is_locked(cell):
			return false
		var piece: int = board.get_piece(cell)
		if Pieces.is_empty(piece) or int(Pieces.kind_of(piece)) != kind:
			return false
	return true


static func _add_cell_and_neighbours(board: Board, cell: Vector2i, seen: Dictionary, out: Array[Vector2i]) -> void:
	if not seen.has(cell):
		seen[cell] = true
		out.append(cell)
	for neighbour: Vector2i in Grid.neighbours(cell):
		if seen.has(neighbour):
			continue
		if board.is_locked(neighbour) or Pieces.is_empty(board.get_piece(neighbour)):
			continue
		seen[neighbour] = true
		out.append(neighbour)
