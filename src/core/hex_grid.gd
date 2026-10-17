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
static var _vertex_neighbours_cache: Array = []
static var _vertex_adjacency_cache: Array = []


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


## Every existing cell within `radius` steps of `cell`, itself first, then rings
## outward in a stable order (used for blast radii).
static func cells_within(cell: Vector2i, radius: int) -> Array[Vector2i]:
	if not has_cell(cell) or radius < 0:
		return []
	var seen := {cell: true}
	var ordered: Array[Vector2i] = [cell]
	var frontier: Array[Vector2i] = [cell]
	for _step in radius:
		var next: Array[Vector2i] = []
		for current: Vector2i in frontier:
			for neighbour: Vector2i in neighbours(current):
				if seen.has(neighbour):
					continue
				seen[neighbour] = true
				ordered.append(neighbour)
				next.append(neighbour)
		frontier = next
	return ordered


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


## Vertices that share at least one cell with this vertex (including itself).
## A rotation can only change matches at its own vertex and at the vertices
## touching the three cells it moved, so testing these is enough to decide
## whether a spin produced a match — no full-board scan needed.
static func vertex_neighbours(vertex_index: int) -> Array[int]:
	if _vertex_neighbours_cache.is_empty():
		_build_vertex_neighbours()
	if vertex_index < 0 or vertex_index >= _vertex_neighbours_cache.size():
		return []
	return _vertex_neighbours_cache[vertex_index]


static func _build_vertex_neighbours() -> void:
	var all_vertices := vertices()
	_vertex_neighbours_cache.resize(all_vertices.size())

	var owners := {}  # cell -> Array[int] of vertex indices touching it
	for index in all_vertices.size():
		for cell: Vector2i in all_vertices[index]:
			if not owners.has(cell):
				owners[cell] = []
			owners[cell].append(index)

	for index in all_vertices.size():
		var related := {}
		related[index] = true
		for cell: Vector2i in all_vertices[index]:
			for other: int in owners[cell]:
				related[other] = true
		var list: Array[int] = []
		for key: int in related:
			list.append(key)
		list.sort()
		_vertex_neighbours_cache[index] = list


static func vertex_centroid(vertex_index: int, size: float = 32.0) -> Vector2:
	var all_vertices := vertices()
	if vertex_index < 0 or vertex_index >= all_vertices.size():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for cell: Vector2i in all_vertices[vertex_index]:
		sum += to_pixel(cell, size)
	return sum / float(all_vertices[vertex_index].size())


## Index of the rotation vertex closest to a pixel position.
static func nearest_vertex(point: Vector2, size: float = 32.0) -> int:
	var best := -1
	var best_distance := INF
	var all_vertices := vertices()
	for index in all_vertices.size():
		var distance := point.distance_squared_to(vertex_centroid(index, size))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


# --- vertex navigation (the keyboard cursor lives on this graph) -------------

## Structural adjacency between rotation vertices: two vertices are joined when
## they share exactly two cells, i.e. they are the two ends of one cell edge.
## Interior vertices therefore have degree 3; boundary ones have fewer.
static func vertex_adjacency() -> Array:
	if _vertex_adjacency_cache.is_empty():
		_build_vertex_adjacency()
	return _vertex_adjacency_cache


static func _build_vertex_adjacency() -> void:
	var all_vertices := vertices()
	_vertex_adjacency_cache.resize(all_vertices.size())

	var owners := {}  # cell -> Array[int] of vertex indices touching it
	for index in all_vertices.size():
		for cell: Vector2i in all_vertices[index]:
			if not owners.has(cell):
				owners[cell] = []
			owners[cell].append(index)

	for index in all_vertices.size():
		var shared := {}  # other vertex -> how many cells we have in common
		for cell: Vector2i in all_vertices[index]:
			for other: int in owners[cell]:
				if other == index:
					continue
				shared[other] = int(shared.get(other, 0)) + 1
		var list: Array[int] = []
		for other: int in shared:
			if int(shared[other]) == 2:
				list.append(other)
		list.sort()
		_vertex_adjacency_cache[index] = list


## Vertices up to `rings` hops away, excluding the starting vertex.
static func vertices_within(vertex_index: int, rings: int = 2) -> Array[int]:
	var all_vertices := vertices()
	if vertex_index < 0 or vertex_index >= all_vertices.size():
		return []
	var adjacency := vertex_adjacency()
	var seen := {vertex_index: true}
	var frontier: Array[int] = [vertex_index]
	var out: Array[int] = []
	for ring in rings:
		var next: Array[int] = []
		for index: int in frontier:
			for other: int in adjacency[index]:
				if seen.has(other):
					continue
				seen[other] = true
				next.append(other)
				out.append(other)
		frontier = next
	return out


## One keyboard step from a vertex towards a screen direction.
##
## Only nearby vertices are candidates (unlike a global "best aligned" search,
## which teleported across the board and left some vertices unreachable). Among
## them it prefers a good directional match, then a shorter hop.
static func step_vertex(
	vertex_index: int,
	direction: Vector2,
	size: float = 32.0,
	rings: int = 2,
	min_alignment: float = 0.30
) -> int:
	var all_vertices := vertices()
	if vertex_index < 0 or vertex_index >= all_vertices.size():
		return vertex_index
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		return vertex_index

	var origin := vertex_centroid(vertex_index, size)
	var best := vertex_index
	var best_score := -INF
	for candidate: int in vertices_within(vertex_index, rings):
		var offset := vertex_centroid(candidate, size) - origin
		var distance := offset.length()
		if distance < 0.001:
			continue
		var alignment := offset.normalized().dot(dir)
		if alignment < min_alignment:
			continue
		var score := alignment - distance / (size * 8.0)
		if score > best_score:
			best_score = score
			best = candidate
	return best


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
