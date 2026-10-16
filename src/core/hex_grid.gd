class_name HexGrid
extends RefCounted

## Pure geometry for Hexard's 85-cell board. No Node dependencies.
##
## Layout: flat-top hexagons in 10 vertical columns, "odd-q" offset
## convention -- odd columns are shifted down by half a cell and hold 8
## cells, even columns hold 9 cells: 5 * 9 + 5 * 8 = 85.
##
## The shifted columns must also be the short ones: that makes both the
## top and bottom edges zigzag and leaves no dangling cell. The board
## then reads as 17 staggered half-rows of exactly 5 cells.
##
## A rotation vertex is a point where exactly three mutually adjacent
## cells meet; there are 135 of them (asserted by tests/test_hex_grid.gd).

const COLUMNS := 10
const EVEN_COLUMN_HEIGHT := 9
const ODD_COLUMN_HEIGHT := 8
const EXPECTED_CELL_COUNT := 85
const EXPECTED_VERTEX_COUNT := 135
const EXPECTED_HALF_ROWS := 17

const _OFFSETS_EVEN := [
	Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 0),
]
const _OFFSETS_ODD := [
	Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(-1, 1),
	Vector2i(1, 0), Vector2i(1, 1),
]

static var _cells_cache: Array[Vector2i] = []
static var _vertices_cache: Array = []


# --- cells ------------------------------------------------------------------

static func column_height(column_index: int) -> int:
	return EVEN_COLUMN_HEIGHT if column_index % 2 == 0 else ODD_COLUMN_HEIGHT


static func has_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= COLUMNS:
		return false
	return cell.y >= 0 and cell.y < column_height(cell.x)


static func all_cells() -> Array[Vector2i]:
	if _cells_cache.is_empty():
		for column_index in COLUMNS:
			for row in column_height(column_index):
				_cells_cache.append(Vector2i(column_index, row))
	return _cells_cache


## Vertical half-row index of a cell: even columns sit on even half-rows,
## odd (shifted) columns on odd half-rows.
static func half_row(cell: Vector2i) -> int:
	return cell.y * 2 + (1 if cell.x % 2 == 1 else 0)


static func column(column_index: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in column_height(column_index):
		out.append(Vector2i(column_index, row))
	return out


# --- adjacency --------------------------------------------------------------

static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not has_cell(cell):
		return out
	var offsets: Array = _OFFSETS_EVEN if cell.x % 2 == 0 else _OFFSETS_ODD
	for offset: Vector2i in offsets:
		var candidate: Vector2i = cell + offset
		if has_cell(candidate):
			out.append(candidate)
	return out


static func are_neighbours(a: Vector2i, b: Vector2i) -> bool:
	return neighbours(a).has(b)


# --- rotation vertices ------------------------------------------------------

## All 135 rotation vertices, each a 3-cell array in stable cyclic order.
static func vertices() -> Array:
	if _vertices_cache.is_empty():
		_build_vertices()
	return _vertices_cache


static func _build_vertices() -> void:
	var seen := {}
	for cell: Vector2i in all_cells():
		var around := neighbours(cell)
		for i in around.size():
			for j in range(i + 1, around.size()):
				var b: Vector2i = around[i]
				var c: Vector2i = around[j]
				if not are_neighbours(b, c):
					continue
				var key := triple_key(cell, b, c)
				if seen.has(key):
					continue
				seen[key] = true
				_vertices_cache.append(cyclic_order([cell, b, c]))


## Canonical key for an unordered triple of cells.
static func triple_key(a: Vector2i, b: Vector2i, c: Vector2i) -> String:
	var parts: Array[Vector2i] = [a, b, c]
	parts.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return _cell_before(x, y))
	return "%d,%d|%d,%d|%d,%d" % [
		parts[0].x, parts[0].y, parts[1].x, parts[1].y, parts[2].x, parts[2].y,
	]


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


## Sorts three cells into a stable cyclic order around the vertex centre.
## Screen Y grows downwards, so ascending angle means clockwise on screen:
## index +1 is one 60-degree clockwise step.
static func cyclic_order(cells: Array) -> Array[Vector2i]:
	var centre := Vector2.ZERO
	for cell: Vector2i in cells:
		centre += Vector2(cell)
	centre /= float(cells.size())

	var scored := []
	for cell: Vector2i in cells:
		var offset := Vector2(cell) - centre
		scored.append({"cell": cell, "angle": atan2(offset.y, offset.x)})
	scored.sort_custom(func(a, b): return float(a["angle"]) < float(b["angle"]))

	var out: Array[Vector2i] = []
	for entry in scored:
		out.append(entry["cell"])
	return out


# --- pixel space ------------------------------------------------------------

static func to_pixel(cell: Vector2i, size: float = 32.0) -> Vector2:
	var x := cell.x * 1.5 * size
	var y := cell.y * sqrt(3.0) * size
	if cell.x % 2 == 1:
		y += sqrt(3.0) * 0.5 * size
	return Vector2(x, y)


## Flat-top hexagon vertices, first corner pointing right.
static func corners(cell: Vector2i, size: float = 32.0, rotation: float = 0.0) -> PackedVector2Array:
	var centre := to_pixel(cell, size)
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i) + rotation
		points.append(centre + Vector2(cos(angle), sin(angle)) * size)
	return points


static func pixel_bounds(size: float = 32.0) -> Rect2:
	var rect := Rect2(to_pixel(Vector2i(0, 0), size), Vector2.ZERO)
	for cell: Vector2i in all_cells():
		rect = rect.expand(to_pixel(cell, size))
	var margin := size * 1.05
	return rect.grow(margin)


# --- debug ------------------------------------------------------------------

## ASCII silhouette; used by the test suite to eyeball the board shape.
static func to_ascii() -> String:
	var lines := PackedStringArray()
	for half in EXPECTED_HALF_ROWS:
		var line := ""
		for column_index in COLUMNS:
			var parity := column_index % 2
			if parity != half % 2:
				line += "  "
				continue
			var row := (half - (1 if parity == 1 else 0)) / 2
			line += "O " if has_cell(Vector2i(column_index, row)) else ". "
		lines.append(line.rstrip(" "))
	return "\n".join(lines)


## Number of cells on each half-row (should be 5 for all 17).
static func half_row_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(EXPECTED_HALF_ROWS)
	counts.fill(0)
	for cell: Vector2i in all_cells():
		counts[half_row(cell)] += 1
	return counts
