extends "res://tests/test_case.gd"

## Geometry acceptance tests. These are the M0 gate: if the board model is
## wrong, every rule built on top of it is wrong.

const Grid := preload("res://src/core/hex_grid.gd")


func test_cell_count_is_85() -> void:
	assert_eq(Grid.all_cells().size(), 85, "board must hold exactly 85 cells")
	assert_eq(Grid.all_cells().size(), Grid.EXPECTED_CELL_COUNT, "matches the documented constant")


func test_column_heights_alternate_9_8() -> void:
	var long_columns := 0
	var short_columns := 0
	for column_index in Grid.COLUMNS:
		var height := Grid.column_height(column_index)
		var expected := 9 if column_index % 2 == 0 else 8
		assert_eq(height, expected, "column %d height" % column_index)
		if height == 9:
			long_columns += 1
		else:
			short_columns += 1
	assert_eq(long_columns, 5, "five 9-cell columns")
	assert_eq(short_columns, 5, "five 8-cell columns")
	assert_eq(long_columns * 9 + short_columns * 8, 85, "5*9 + 5*8 = 85")


func test_board_is_17_staggered_half_rows_of_5() -> void:
	# Independently reverse-engineered from the reference game: the board
	# must read as 17 half-rows with exactly 5 cells each.
	var counts := Grid.half_row_counts()
	assert_eq(counts.size(), Grid.EXPECTED_HALF_ROWS, "half-row count")
	for half in counts.size():
		assert_eq(counts[half], 5, "half-row %d must hold 5 cells" % half)


func test_half_rows_alternate_column_parity() -> void:
	for cell: Vector2i in Grid.all_cells():
		var half := Grid.half_row(cell)
		assert_eq(half % 2, cell.x % 2, "cell %s sits on a matching-parity half-row" % cell)


func test_adjacency_is_symmetric_and_irreflexive() -> void:
	for cell: Vector2i in Grid.all_cells():
		assert_false(Grid.neighbours(cell).has(cell), "cell %s is not its own neighbour" % cell)
		for other: Vector2i in Grid.neighbours(cell):
			assert_true(
				Grid.are_neighbours(other, cell),
				"adjacency must be symmetric between %s and %s" % [cell, other]
			)


func test_every_cell_has_at_least_two_neighbours() -> void:
	var minimum := 99
	for cell: Vector2i in Grid.all_cells():
		minimum = mini(minimum, Grid.neighbours(cell).size())
	assert_ge(minimum, 2, "no cell may be dangling")
	info("minimum neighbour count: %d" % minimum)


func test_shifted_columns_are_the_short_ones() -> void:
	# If the short columns were the unshifted ones, the protruding bottom
	# cells would have no lateral neighbours. Guard against that regression.
	for cell: Vector2i in Grid.all_cells():
		if cell.x % 2 == 1:
			continue
		var bottom := Vector2i(cell.x, Grid.column_height(cell.x) - 1)
		var lateral := 0
		for other: Vector2i in Grid.neighbours(bottom):
			if other.y < bottom.y:
				lateral += 1
		assert_ge(lateral, 2, "bottom cell %s keeps lateral neighbours" % bottom)


func test_neighbours_are_at_one_hex_edge_distance() -> void:
	var size := 32.0
	var expected := sqrt(3.0) * size
	for cell: Vector2i in Grid.all_cells():
		var origin := Grid.to_pixel(cell, size)
		for other: Vector2i in Grid.neighbours(cell):
			var distance := origin.distance_to(Grid.to_pixel(other, size))
			assert_almost_eq(distance, expected, 0.001, "spacing %s -> %s" % [cell, other])


func test_same_column_chain_is_vertically_aligned() -> void:
	var size := 32.0
	for column_index in Grid.COLUMNS:
		var chain := Grid.column(column_index)
		assert_eq(chain.size(), Grid.column_height(column_index), "chain length of column %d" % column_index)
		for row in range(1, chain.size()):
			var above := Grid.to_pixel(chain[row - 1], size)
			var below := Grid.to_pixel(chain[row], size)
			assert_almost_eq(above.x, below.x, 0.001, "column %d stays on one x" % column_index)
			assert_almost_eq(
				below.y - above.y, sqrt(3.0) * size, 0.001,
				"vertical step in column %d" % column_index
			)


func test_vertex_count_is_135() -> void:
	var vertices := Grid.vertices()
	assert_eq(vertices.size(), Grid.EXPECTED_VERTEX_COUNT, "rotation vertex count")
	info("rotation vertices: %d" % vertices.size())


func test_every_vertex_is_a_mutually_adjacent_triple() -> void:
	for vertex: Array in Grid.vertices():
		assert_eq(vertex.size(), 3, "a vertex always joins exactly three cells")
		var a: Vector2i = vertex[0]
		var b: Vector2i = vertex[1]
		var c: Vector2i = vertex[2]
		assert_ne(a, b, "vertex cells are distinct")
		assert_ne(b, c, "vertex cells are distinct")
		assert_ne(a, c, "vertex cells are distinct")
		assert_true(Grid.are_neighbours(a, b), "%s and %s share an edge" % [a, b])
		assert_true(Grid.are_neighbours(b, c), "%s and %s share an edge" % [b, c])
		assert_true(Grid.are_neighbours(a, c), "%s and %s share an edge" % [a, c])


func test_vertices_are_unique() -> void:
	var seen := {}
	for vertex: Array in Grid.vertices():
		var key := Grid.triple_key(vertex[0], vertex[1], vertex[2])
		assert_false(seen.has(key), "vertex %s must not be listed twice" % key)
		seen[key] = true


func test_vertex_cyclic_order_is_stable_and_complete() -> void:
	var vertex: Array = Grid.vertices()[0]
	var first := Grid.cyclic_order(vertex)
	var second := Grid.cyclic_order(vertex)
	assert_eq(first, second, "cyclic order is deterministic")
	assert_eq(first.size(), 3, "cyclic order keeps all three cells")
	for cell: Vector2i in vertex:
		assert_true(first.has(cell), "cyclic order keeps %s" % cell)


func test_ascii_silhouette() -> void:
	# Printed once so the shape can be eyeballed in CI output.
	var ascii := Grid.to_ascii()
	var lines := ascii.split("\n")
	assert_eq(lines.size(), Grid.EXPECTED_HALF_ROWS, "ascii dump covers every half-row")
	info("board silhouette:\n" + ascii)
