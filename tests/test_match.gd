extends "res://tests/test_case.gd"

## Match predicate and clear-group extraction (docs/design.md §3.2).
##
## The board starts empty here, so every scenario is exactly the pieces painted
## — no filler colours to accidentally complete a triple.

const BoardScript := preload("res://src/core/board.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")



func _vertex_of(cells: Array) -> int:
	var all_vertices := Grid.vertices()
	var key := Grid.triple_key(cells[0], cells[1], cells[2])
	for index in all_vertices.size():
		var vertex: Array = all_vertices[index]
		if Grid.triple_key(vertex[0], vertex[1], vertex[2]) == key:
			return index
	return -1


## Guards against writing scenarios around cell triples that are not actually
## rotation vertices (three mutually adjacent cells) — an easy mistake that
## otherwise shows up as a mystifying match failure.
func _assert_is_vertex(cells: Array, label: String) -> int:
	var index := _vertex_of(cells)
	assert_ge(index, 0, "%s: %s is a real rotation vertex" % [label, str(cells)])
	return index


# --- the predicate ----------------------------------------------------------

func test_a_triangle_of_three_clears() -> void:
	var board := BoardScript.new()
	var cells := [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)]
	_assert_is_vertex(cells, "triangle")
	_paint(board, cells, Pieces.GemColor.RED)

	assert_true(MatchFinder.has_any_match(board), "three mutually adjacent gems match")
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 1, "exactly one clear group")
	assert_eq(groups[0].size(), 3, "of three cells")
	assert_eq(groups[0].gem_color, Pieces.GemColor.RED, "of the matched colour")


func test_straight_line_of_three_does_not_clear() -> void:
	# Collinear gems share no vertex, so they must never clear on their own.
	var column_board := BoardScript.new()
	_paint(column_board, [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)], Pieces.GemColor.GREEN)
	assert_false(MatchFinder.has_any_match(column_board), "a vertical line of 3 must not clear")
	assert_eq(MatchFinder.clear_groups(column_board).size(), 0, "and produces no group")

	# (0,2)-(1,2)-(2,2) is a diagonal line across columns: also no shared vertex.
	var diagonal_board := BoardScript.new()
	_paint(diagonal_board, [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], Pieces.GemColor.GREEN)
	assert_false(MatchFinder.has_any_match(diagonal_board), "a diagonal line of 3 must not clear")


func test_two_of_a_kind_is_not_a_match() -> void:
	var board := BoardScript.new()
	_paint(board, [Vector2i(2, 3), Vector2i(2, 4)], Pieces.GemColor.CYAN)
	assert_false(MatchFinder.has_any_match(board), "two gems are never enough")


func test_empty_cells_never_match() -> void:
	var board := BoardScript.new()
	assert_false(MatchFinder.has_any_match(board), "an empty board has no matches")
	# Two gems plus one empty cell around a vertex: still no match.
	_paint(board, [Vector2i(2, 3), Vector2i(2, 4)], Pieces.GemColor.VIOLET)
	assert_false(MatchFinder.has_any_match(board), "empties break a would-be triple")


func test_colourless_specials_never_match() -> void:
	# Starflowers and pearls carry no colour, so three together must not clear
	# as an ordinary cluster (they have their own rules in M2).
	var board := BoardScript.new()
	for cell: Vector2i in [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)]:
		board.set_piece(cell, Pieces.starflower())
	assert_false(MatchFinder.has_any_match(board), "three starflowers are not a colour match")

	var pearls := BoardScript.new()
	for cell: Vector2i in [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)]:
		pearls.set_piece(cell, Pieces.pearl())
	assert_false(MatchFinder.has_any_match(pearls), "three pearls are not a colour match")


# --- group extraction -------------------------------------------------------

func test_four_cell_rhombus_clears_as_one_group() -> void:
	var board := BoardScript.new()
	# Two matching vertices sharing an edge: must merge into a single clear.
	_paint(board, [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)], Pieces.GemColor.YELLOW)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 1, "overlapping matches resolve as one group")
	assert_eq(groups[0].size(), 4, "and the group grows to four cells")


func test_six_cell_block_clears_as_one_group() -> void:
	var board := BoardScript.new()
	var cells := [
		Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4),
		Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4),
	]
	_paint(board, cells, Pieces.GemColor.BLUE)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 1, "one connected block")
	assert_eq(groups[0].size(), 6, "six cells in the group")


func test_two_separate_matches_are_two_groups() -> void:
	var board := BoardScript.new()
	_paint(board, [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 2)], Pieces.GemColor.RED)
	_paint(board, [Vector2i(6, 2), Vector2i(6, 3), Vector2i(7, 2)], Pieces.GemColor.CYAN)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 2, "disconnected matches resolve separately")


func test_group_order_is_deterministic() -> void:
	var board := BoardScript.new()
	# A 6-block and a 3-triangle: the bigger group must resolve first.
	_paint(board, [
		Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4),
		Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4),
	], Pieces.GemColor.BLUE)
	var triangle := [Vector2i(7, 2), Vector2i(7, 3), Vector2i(8, 3)]
	_assert_is_vertex(triangle, "separate triangle")
	_paint(board, triangle, Pieces.GemColor.RED)
	var first := MatchFinder.clear_groups(board)
	var second := MatchFinder.clear_groups(board)
	assert_eq(first.size(), 2, "two groups found")
	assert_eq(first[0].size(), 6, "larger group first")
	assert_eq(MatchFinder.group_key(first[0].cells), MatchFinder.group_key(second[0].cells), "stable order")


# --- vertex helpers ---------------------------------------------------------

func test_vertex_is_match_at_reports_the_right_index() -> void:
	var board := BoardScript.new()
	var cells := [Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4)]
	_paint(board, cells, Pieces.GemColor.ORANGE)
	var index := _vertex_of(cells)
	assert_ge(index, 0, "the scenario's vertex exists")
	assert_true(MatchFinder.vertex_is_match_at(board, index), "the vertex reads as a match")
	var matching := MatchFinder.matching_vertices(board)
	assert_true(matching.has(index), "matching_vertices includes it")
	assert_eq(matching.size(), 1, "and reports nothing else")


func test_matches_near_vertex_stays_local() -> void:
	var board := BoardScript.new()
	var local := [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)]
	var far := [Vector2i(8, 3), Vector2i(8, 4), Vector2i(9, 3)]
	var local_index := _assert_is_vertex(local, "local triangle")
	var far_index := _assert_is_vertex(far, "far triangle")
	_paint(board, local, Pieces.GemColor.RED)
	_paint(board, far, Pieces.GemColor.RED)

	assert_true(MatchFinder.matches_near_vertex(board, local_index), "the local match is detected")
	assert_true(MatchFinder.matches_near_vertex(board, far_index), "the far match is detected too")
	# Locality: the two matches must not be in each other's neighbourhoods.
	assert_false(
		Grid.vertex_neighbours(local_index).has(far_index),
		"the far vertex is outside the local vertex's neighbourhood"
	)
	assert_false(
		Grid.vertex_neighbours(far_index).has(local_index),
		"and the relationship is symmetric"
	)


func test_vertex_neighbour_graph_is_sane() -> void:
	for index in Grid.vertices().size():
		var related: Array[int] = Grid.vertex_neighbours(index)
		assert_true(related.has(index), "a vertex is its own neighbour")
		assert_ge(related.size(), 3, "vertex %d should touch several others" % index)
		for other: int in related:
			assert_true(
				Grid.vertex_neighbours(other).has(index),
				"vertex adjacency is symmetric (%d <-> %d)" % [index, other]
			)


## Hexi HD clear rule: a tile must touch two other same-coloured tiles to score or
## be deleted. A gem attached to a cluster by a single edge is a tail, not part of
## the cluster, so it stays on the board and earns nothing.
func test_a_tail_hanging_off_a_cluster_is_spared() -> void:
	var board := BoardScript.new()
	_background(board)
	var triangle: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 5), Vector2i(3, 4)]
	var tail := Vector2i(5, 3)   # touches (4,4) only: one same-coloured neighbour
	# ORANGE is absent from the match-free background pattern, so the tail's other
	# neighbours cannot accidentally count as same-coloured.
	var petals: Array = [triangle[0], triangle[1], triangle[2], tail]
	_paint(board, petals, Pieces.GemColor.ORANGE)

	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 1, "there is one cluster")
	var group = groups[0]
	assert_eq(group.cells.size(), 3, "only the solid core clears")
	assert_false(group.cells.has(tail), "the single-edge tail is spared")
	assert_eq(group.gem_color, Pieces.GemColor.ORANGE, "and it is the orange cluster")


## A compact four is still a four: every tile in it touches two others.
func test_a_compact_four_still_clears_four() -> void:
	var board := BoardScript.new()
	_background(board)
	var rhombus: Array = [Vector2i(4, 4), Vector2i(4, 5), Vector2i(3, 4), Vector2i(3, 5)]
	_paint(board, rhombus, Pieces.GemColor.RED)
	var groups := MatchFinder.clear_groups(board)
	assert_eq(groups.size(), 1, "one cluster")
	assert_eq(groups[0].cells.size(), 4, "a solid rhombus keeps all four")
