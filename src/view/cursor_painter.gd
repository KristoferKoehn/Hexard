class_name CursorPainter
extends RefCounted

## Draws the cursor: the hint ring, the white outline around whatever a spin would
## swap, and the legality dot.
##
## Extracted from BoardView because the cursor's rules had accumulated real logic —
## which cells to outline (a trio, or a special's own swap set), whether the vertex
## dot should exist at all, and the tie-break between "legal" and "would revert" — and
## three separate bugs lived in it. The painter holds no game state: the caller passes
## the swap set in, so `Game.swapped_cells()` remains the single authority on what a
## turn moves and the outline cannot disagree with the rotation.

const HexGridScript := preload("res://src/core/hex_grid.gd")

const HINT_COLOR := Color("ffd166")
const OUTLINE_LEGAL := Color(1.0, 1.0, 1.0, 0.95)
const OUTLINE_ILLEGAL := Color(1.0, 1.0, 1.0, 0.40)
const OUTLINE_WIDTH := 2.5
const DOT_LEGAL := Color(0.45, 0.95, 0.55, 0.95)
const DOT_ILLEGAL := Color(0.62, 0.66, 0.74, 0.80)
const DOT_CORE := Color(0.06, 0.08, 0.12, 0.92)
const HALO := Color(0.45, 0.95, 0.55, 0.55)

var cell_size := 30.0
var origin := Vector2.ZERO

# Outline segments for the current selection. The shape depends only on which cells
# are outlined, so it is rebuilt when the selection changes and redrawn otherwise.
var _outline_key := ""
var _outline_segments: Array = []


## `swapped` is the set of cells a turn would move; `special` is the piece cell when
## the cursor has snapped onto a starflower or pearl, or HexGrid.NO_CELL.
func draw(
	canvas: CanvasItem, vertex: int, special: Vector2i, legal: bool, hint: int, swapped: Array
) -> void:
	var vertices := HexGridScript.vertices()

	if hint >= 0 and hint < vertices.size():
		var hint_centre := HexGridScript.vertex_centroid(hint, cell_size) + origin
		canvas.draw_arc(hint_centre, cell_size * 0.5, 0, TAU, 24, HINT_COLOR, 2.0)

	if vertex < 0 or vertex >= vertices.size():
		return

	var outline := OUTLINE_LEGAL if legal else OUTLINE_ILLEGAL
	_draw_cluster_outline(canvas, swapped, outline, OUTLINE_WIDTH)

	# A snapped special has no vertex position, so the usual vertex dot goes away - but
	# only when its own outline was actually drawn. Before a starflower exists there is no
	# swap set, and the cursor would otherwise be invisible.
	if special != HexGridScript.NO_CELL and not swapped.is_empty():
		return

	var centre := HexGridScript.vertex_centroid(vertex, cell_size) + origin
	canvas.draw_circle(centre, cell_size * 0.16, DOT_LEGAL if legal else DOT_ILLEGAL)
	canvas.draw_circle(centre, cell_size * 0.10, DOT_CORE)
	if legal:
		canvas.draw_arc(centre, cell_size * 0.28, 0, TAU, 24, HALO, 1.5)


## Only the edges that are not shared with another selected cell, so a trio reads as
## one cluster rather than three hexagons.
func _draw_cluster_outline(canvas: CanvasItem, cells: Array, color: Color, width: float) -> void:
	var key := ""
	for cell: Vector2i in cells:
		key += "%d,%d;" % [cell.x, cell.y]
	if key != _outline_key:
		_outline_key = key
		_outline_segments = _build_segments(cells)
	for segment: Array in _outline_segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		canvas.draw_line(a, b, color, width)
		# Round the meets: independent segments leave a notch at inner corners, so
		# each endpoint gets a dot of half the line width.
		canvas.draw_circle(a, width * 0.5, color)
		canvas.draw_circle(b, width * 0.5, color)


func _build_segments(cells: Array) -> Array:
	var members := {}
	for cell: Vector2i in cells:
		members[cell] = true
	var segments: Array = []
	for cell: Vector2i in cells:
		var centre := _cell_centre(cell)
		var corners := _corners(centre, cell_size * 0.96)
		for index in 6:
			# The neighbour across an edge is found by probing along that edge's
			# normal, so adjacency stays the grid's business rather than a second
			# copy of the offset tables here.
			var normal := deg_to_rad(30.0 + 60.0 * float(index))
			var probe := centre + Vector2(cos(normal), sin(normal)) * cell_size * 1.1
			var across := _nearest_cell(probe)
			if across != cell and members.has(across):
				continue
			segments.append([corners[index], corners[(index + 1) % 6]])
	return segments


func _cell_centre(cell: Vector2i) -> Vector2:
	return HexGridScript.to_pixel(cell, cell_size) + origin


func _nearest_cell(point: Vector2) -> Vector2i:
	var best := HexGridScript.NO_CELL
	var best_distance := INF
	for cell: Vector2i in HexGridScript.all_cells():
		var distance := point.distance_squared_to(_cell_centre(cell))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


func _corners(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 6:
		var angle := deg_to_rad(60.0 * index)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
