extends RefCounted

## Minimal assertion harness — no plugin dependency, runs headless.
## Suites extend this with "res://tests/test_case.gd" and define test_* methods.
##
## Shared fixtures live here too, so each suite keeps its own scenarios while
## the plumbing (a match-free board, painting, counting, finding a legal move) is
## written once.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")

var failures: Array[String] = []
var assertions := 0
var _current_test := ""


# --- shared fixtures --------------------------------------------------------

## Fills the board with a pattern that cannot match: the colour index is
## (2q + r) mod 5, and no vertex's three cells share that value.
func _background(board) -> void:
	var palette: Array = Pieces.BASE_COLORS
	for cell: Vector2i in Grid.all_cells():
		board.set_piece(cell, Pieces.gem(palette[(2 * cell.x + cell.y) % palette.size()]))


func _paint(board, cells: Array, color: int) -> void:
	for cell: Vector2i in cells:
		board.set_piece(cell, Pieces.gem(color))


func _count_kind(board, kind: int) -> int:
	var total := 0
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_empty(piece) and Pieces.kind_of(piece) == kind:
			total += 1
	return total


func _has_formation(result, name: String) -> bool:
	for group in result.clear_groups:
		if group.has_formation(name):
			return true
	return false


func _first_group(result):
	assert_ge(result.clear_groups.size(), 1, "expected at least one clear group")
	return result.clear_groups[0]


## A rotation that clears nothing right now (there is nearly always one).
func _non_matching_rotation(game) -> Dictionary:
	var legal := {}
	for move: Dictionary in game.find_legal_rotations():
		legal["%d:%d" % [move["vertex"], move["direction"]]] = true
	for vertex_index in Grid.vertices().size():
		for direction in [1, -1]:
			if not legal.has("%d:%d" % [vertex_index, direction]):
				return {"vertex": vertex_index, "direction": direction}
	return {}


## Runs every test_* method in a deterministic (alphabetical) order.
func run_all() -> Array[Dictionary]:
	var names: Array[String] = []
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()

	var results: Array[Dictionary] = []
	for test_name in names:
		_current_test = test_name
		failures = []
		var before := assertions
		callv(test_name, [])
		# A test that dies before asserting anything (a runtime error inside the
		# code under test aborts the method) must not be reported as a pass.
		if assertions == before:
			_record("test made no assertions — it probably failed before running")
		results.append({"name": test_name, "failures": failures.duplicate()})
	return results


# --- assertions -------------------------------------------------------------

func assert_true(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		_record("expected true: " + message)


func assert_false(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		_record("expected false: " + message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		_record("%s — expected %s, got %s" % [message, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	assertions += 1
	if actual == unexpected:
		_record("%s — value should not equal %s" % [message, str(unexpected)])


func assert_ge(actual: Variant, minimum: Variant, message: String) -> void:
	assertions += 1
	if actual < minimum:
		_record("%s — expected >= %s, got %s" % [message, str(minimum), str(actual)])


func assert_gt(actual: Variant, minimum: Variant, message: String) -> void:
	assertions += 1
	if actual <= minimum:
		_record("%s — expected > %s, got %s" % [message, str(minimum), str(actual)])


func assert_le(actual: Variant, maximum: Variant, message: String) -> void:
	assertions += 1
	if actual > maximum:
		_record("%s — expected <= %s, got %s" % [message, str(maximum), str(actual)])


func assert_lt(actual: Variant, maximum: Variant, message: String) -> void:
	assertions += 1
	if actual >= maximum:
		_record("%s — expected < %s, got %s" % [message, str(maximum), str(actual)])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_record("%s — expected %.6f ± %.6f, got %.6f" % [message, expected, tolerance, actual])


func fail(message: String) -> void:
	assertions += 1
	_record(message)


func info(message: String) -> void:
	print("       · ", message)


func _record(message: String) -> void:
	failures.append("%s: %s" % [_current_test, message])
