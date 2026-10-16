extends "res://tests/test_case.gd"

## Board storage, gravity and invariants (docs/design.md §2.2, §3.3).

const Grid := preload("res://src/core/hex_grid.gd")
const BoardScript := preload("res://src/core/board.gd")
const Pieces := preload("res://src/core/piece.gd")


func test_starts_empty() -> void:
	var board := BoardScript.new()
	assert_eq(board.filled_count(), 0, "a fresh board has no gems")
	assert_eq(board.empty_cells().size(), 85, "every cell is empty")
	assert_eq(board.invariant_violations().size(), 0, "an empty board is healthy")


func test_piece_set_and_get() -> void:
	var board := BoardScript.new()
	var cell := Vector2i(4, 3)
	board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	assert_false(board.is_empty(cell), "the cell is now occupied")
	assert_eq(board.filled_count(), 1, "one gem placed")
	assert_eq(Pieces.describe(board.get_piece(cell)), "gem:red", "piece round-trips")
	board.remove_piece(cell)
	assert_true(board.is_empty(cell), "removing clears the cell")


func test_gravity_compacts_a_column() -> void:
	var board := BoardScript.new()
	var column_index := 2
	var chain := Grid.column(column_index)
	# Two gems at the very top, the rest of the column empty.
	board.set_piece(chain[0], Pieces.gem(Pieces.GemColor.BLUE))
	board.set_piece(chain[1], Pieces.gem(Pieces.GemColor.GREEN))

	var moved := board.apply_gravity()
	assert_eq(moved, 2, "both gems fall")
	assert_eq(board.filled_count(), 2, "gravity never creates or destroys gems")
	assert_false(board.is_empty(chain[chain.size() - 1]), "the bottom cell is filled")
	assert_false(board.is_empty(chain[chain.size() - 2]), "the cell above it is filled")
	assert_true(board.is_empty(chain[0]), "the top cell is vacated")
	assert_eq(board.invariant_violations().size(), 0, "no floating pieces after gravity")


func test_gravity_preserves_relative_order() -> void:
	var board := BoardScript.new()
	var chain := Grid.column(3)
	var top_gem := Pieces.gem(Pieces.GemColor.RED)
	var bottom_gem := Pieces.gem(Pieces.GemColor.YELLOW)
	board.set_piece(chain[1], top_gem)
	board.set_piece(chain[5], bottom_gem)

	board.apply_gravity()
	assert_eq(board.get_piece(chain[chain.size() - 2]), top_gem, "the upper gem stays above")
	assert_eq(board.get_piece(chain[chain.size() - 1]), bottom_gem, "the lower gem stays below")


func test_gravity_is_idempotent() -> void:
	var board := BoardScript.new()
	var chain := Grid.column(6)
	board.set_piece(chain[0], Pieces.gem(Pieces.GemColor.CYAN))
	board.set_piece(chain[3], Pieces.bomb(Pieces.GemColor.RED, 8))

	assert_ge(board.apply_gravity(), 1, "first pass moves pieces")
	assert_eq(board.apply_gravity(), 0, "second pass moves nothing")


func test_gravity_is_per_column_only() -> void:
	var board := BoardScript.new()
	var left := Vector2i(4, 0)
	var right := Vector2i(5, 0)
	board.set_piece(left, Pieces.gem(Pieces.GemColor.VIOLET))
	board.set_piece(right, Pieces.gem(Pieces.GemColor.GREEN))
	board.apply_gravity()
	var left_bottom := Vector2i(4, Grid.column_height(4) - 1)
	var right_bottom := Vector2i(5, Grid.column_height(5) - 1)
	assert_false(board.is_empty(left_bottom), "the left gem fell down its own column")
	assert_false(board.is_empty(right_bottom), "the right gem fell down its own column")
	assert_true(board.is_empty(right), "and nothing slid sideways")


func test_invariant_detects_a_floating_piece() -> void:
	var board := BoardScript.new()
	var chain := Grid.column(0)
	# A gem with an empty cell beneath it is exactly the state the resolver
	# must never leave behind (except mid-round in Survival).
	board.set_piece(chain[2], Pieces.gem(Pieces.GemColor.ORANGE))
	assert_eq(board.invariant_violations().size(), 1, "one floating piece is reported")
	board.remove_piece(chain[2])
	board.set_piece(chain[chain.size() - 1], Pieces.gem(Pieces.GemColor.ORANGE))
	assert_eq(board.invariant_violations().size(), 0, "a resting gem is fine")


func test_first_empty_from_top_finds_the_gap() -> void:
	var board := BoardScript.new()
	var chain := Grid.column(7)
	board.set_piece(chain[chain.size() - 1], Pieces.gem(Pieces.GemColor.RED))
	assert_eq(board.first_empty_from_top(7), chain[0], "the first gap is at the top")
	for cell: Vector2i in chain:
		board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	assert_eq(board.first_empty_from_top(7), null, "a full column reports no gap")


func test_signature_is_stable_and_sensitive() -> void:
	var board := BoardScript.new()
	var before := board.signature()
	assert_eq(before, BoardScript.new().signature(), "identical boards share a signature")
	board.set_piece(Vector2i(0, 0), Pieces.gem(Pieces.GemColor.RED))
	assert_ne(board.signature(), before, "changing a cell changes the signature")


func test_board_ascii_dump_shape() -> void:
	var board := BoardScript.new()
	var lines := board.to_ascii().split("\n")
	assert_eq(lines.size(), Grid.EXPECTED_HALF_ROWS, "dump covers every half-row")


func test_bomb_counter_encoding() -> void:
	var bomb := Pieces.bomb(Pieces.GemColor.BLUE, 8)
	assert_eq(Pieces.kind_of(bomb), Pieces.Kind.BOMB, "kind survives packing")
	assert_eq(Pieces.color_of(bomb), Pieces.GemColor.BLUE, "colour survives packing")
	assert_eq(Pieces.counter_of(bomb), 8, "counter survives packing")
	var ticked := Pieces.with_counter(bomb, 7)
	assert_eq(Pieces.counter_of(ticked), 7, "counter can be decremented")
	assert_eq(Pieces.color_of(ticked), Pieces.GemColor.BLUE, "colour is untouched by a tick")
	assert_eq(Pieces.describe(ticked), "bomb:blue(7)", "bombs describe their countdown")


func test_special_piece_encodings_are_distinct() -> void:
	var gem := Pieces.gem(Pieces.GemColor.RED)
	var star := Pieces.bonus_star(Pieces.GemColor.RED)
	var flower := Pieces.starflower()
	var pearl := Pieces.pearl()
	var bomb := Pieces.bomb(Pieces.GemColor.RED, 5)
	var all := [gem, star, flower, pearl, bomb]
	var seen := {}
	for id: int in all:
		assert_false(seen.has(id), "piece ids must be distinguishable: %s" % Pieces.describe(id))
		seen[id] = true
	assert_true(Pieces.is_bonus_star(star), "bonus star flag")
	assert_true(Pieces.is_starflower(flower), "starflower flag")
	assert_true(Pieces.is_pearl(pearl), "pearl flag")
	assert_true(Pieces.is_bomb(bomb), "bomb flag")
	assert_false(Pieces.has_color(flower), "a starflower is colourless")
	assert_false(Pieces.has_color(pearl), "a pearl is colourless")
	assert_true(Pieces.has_color(star), "a bonus star keeps its gem colour")


func test_color_palette_ramps_with_level() -> void:
	assert_eq(Pieces.colors_for_level(1).size(), 5, "five colours at level 1")
	assert_eq(Pieces.colors_for_level(3).size(), 5, "still five at level 3")
	assert_eq(Pieces.colors_for_level(4).size(), 6, "a sixth colour at level 4")
	assert_eq(Pieces.colors_for_level(5).size(), 7, "the full palette by level 5")
	assert_eq(Pieces.colors_for_level(7).size(), 7, "no extra colours beyond seven")
	assert_eq(Pieces.colors_for_level(1).size(), Pieces.BASE_COLORS.size(), "level 1 uses BASE_COLORS")
