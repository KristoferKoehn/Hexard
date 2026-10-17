class_name BoardView
extends Node2D

## Dev-art board renderer (docs/design.md §8 is the polished version of this).
##
## Pure drawing: it reads game state and paints hexes, the cursor and clear
## flashes. It never mutates the rules core — polish (tweens, particles,
## sounds) is M4 work.

const HexGrid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")

const GEM_COLORS := {
	Pieces.GemColor.RED: Color("e8453c"),
	Pieces.GemColor.ORANGE: Color("f28c28"),
	Pieces.GemColor.YELLOW: Color("f2c53d"),
	Pieces.GemColor.GREEN: Color("45b74a"),
	Pieces.GemColor.CYAN: Color("31c1cf"),
	Pieces.GemColor.BLUE: Color("3a6fd8"),
	Pieces.GemColor.VIOLET: Color("9b5de5"),
}

const FLASH_DURATION := 0.32

@export var cell_size: float = 30.0

var game: RefCounted
var cursor_vertex := -1
var hint_vertex := -1
var hover_cell := Vector2i(-1, -1)

var _origin := Vector2.ZERO
var _flash_cells: Array[Vector2i] = []
var _flash_time := 0.0


func set_game(new_game: RefCounted) -> void:
	game = new_game
	_recenter()
	queue_redraw()


func _recenter() -> void:
	var bounds := HexGrid.pixel_bounds(cell_size)
	_origin = -bounds.position - bounds.size * 0.5


func cell_center(cell: Vector2i) -> Vector2:
	return HexGrid.to_pixel(cell, cell_size) + _origin


## Local point -> rotation vertex, for mouse picking.
func vertex_at(local_point: Vector2) -> int:
	return HexGrid.nearest_vertex(local_point - _origin, cell_size)


## Local point -> cell, for picking a special piece directly.
func cell_at(local_point: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for cell: Vector2i in HexGrid.all_cells():
		var distance := local_point.distance_squared_to(cell_center(cell))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## Cells that just cleared: fade them out over a few frames. Promotions flash
## too, so a bloom into a starflower or pearl reads.
func show_result(result: RefCounted) -> void:
	_flash_cells.clear()
	for group in result.clear_groups:
		for cell: Vector2i in group.cells:
			_flash_cells.append(cell)
	for promotion: Dictionary in result.promotions:
		_flash_cells.append(promotion["cell"])
	_flash_time = FLASH_DURATION if not _flash_cells.is_empty() else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(_flash_time - delta, 0.0)
		if _flash_time == 0.0:
			_flash_cells.clear()
		queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	for cell: Vector2i in HexGrid.all_cells():
		_draw_cell(cell)
	_draw_flash()
	_draw_cursor()


func _draw_cell(cell: Vector2i) -> void:
	var piece: int = game.board.get_piece(cell)
	var centre := cell_center(cell)
	if Pieces.is_empty(piece):
		# Survival-style gap: show a socket so the grid still reads.
		draw_polyline(_closed(_corners(centre, cell_size * 0.86)), Color(1, 1, 1, 0.10), 1.5)
		return

	var radius := cell_size * 0.92
	var corners := _corners(centre, radius)
	var base: Color = GEM_COLORS.get(Pieces.color_of(piece), Color(0.8, 0.8, 0.8))

	match Pieces.kind_of(piece):
		Pieces.Kind.STARFLOWER:
			draw_colored_polygon(_star_points(centre, radius * 1.05, radius * 0.45, 6), Color("f4f6fb"))
			draw_polyline(_closed(_star_points(centre, radius * 0.55, radius * 0.24, 6)), Color(0.55, 0.6, 0.7), 1.0)
		Pieces.Kind.PEARL:
			draw_circle(centre, radius * 0.82, Color("191c26"))
			draw_arc(centre, radius * 0.82, 0, TAU, 32, Color(0.55, 0.62, 0.85), 2.0)
			draw_circle(centre - Vector2(radius * 0.22, radius * 0.22), radius * 0.22, Color(0.75, 0.8, 0.95, 0.85))
		Pieces.Kind.BOMB:
			draw_colored_polygon(corners, base.darkened(0.25))
			draw_polyline(_closed(corners), Color("101319"), 2.5)
			draw_circle(centre, radius * 0.34, Color("101319"))
			_draw_centered_text(str(Pieces.counter_of(piece)), centre, 20, Color("ffd166"))
		_:
			draw_colored_polygon(corners, base)
			draw_polyline(_closed(corners), base.darkened(0.45), 2.0)
			# A cheap facet so the gems read as jewels rather than flat tiles.
			draw_colored_polygon(
				_corners(centre - Vector2(0.0, radius * 0.24), radius * 0.5),
				base.lightened(0.30)
			)
			if Pieces.is_bonus_star(piece):
				draw_colored_polygon(_star_points(centre, radius * 0.62, radius * 0.26, 6), Color("fff3c4"))
				draw_polyline(_closed(_star_points(centre, radius * 0.62, radius * 0.26, 6)), Color("8a6d1f"), 1.0)

	# Starflowers and pearls can be turned on their own: hint that they are grabbable.
	if Pieces.is_starflower(piece) or Pieces.is_pearl(piece):
		var hovered := cell == hover_cell
		var ring_color := Color(1.0, 0.86, 0.45, 0.85 if hovered else 0.45)
		draw_arc(centre, radius * 0.98, 0, TAU, 28, ring_color, 2.5 if hovered else 1.5)


func _draw_flash() -> void:
	if _flash_cells.is_empty() or _flash_time <= 0.0:
		return
	var alpha := _flash_time / FLASH_DURATION
	for cell: Vector2i in _flash_cells:
		draw_colored_polygon(_corners(cell_center(cell), cell_size * 0.92), Color(1, 1, 1, 0.65 * alpha))


func _draw_cursor() -> void:
	var vertices := HexGrid.vertices()

	if hint_vertex >= 0 and hint_vertex < vertices.size():
		var hint_centre := HexGrid.vertex_centroid(hint_vertex, cell_size) + _origin
		draw_arc(hint_centre, cell_size * 0.5, 0, TAU, 24, Color("ffd166"), 2.0)

	if cursor_vertex < 0 or cursor_vertex >= vertices.size():
		return
	for cell: Vector2i in vertices[cursor_vertex]:
		draw_colored_polygon(_corners(cell_center(cell), cell_size * 0.97), Color(1, 1, 1, 0.14))

	var centre := HexGrid.vertex_centroid(cursor_vertex, cell_size) + _origin
	draw_circle(centre, cell_size * 0.16, Color(1, 1, 1, 0.92))
	draw_circle(centre, cell_size * 0.10, Color(0.10, 0.12, 0.16, 0.92))


# --- small geometry helpers -------------------------------------------------

func _corners(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _star_points(centre: Vector2, outer: float, inner: float, arms: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in arms * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := PI / float(arms) * float(i) - PI * 0.5
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if points.size() > 0:
		closed.append(points[0])
	return closed


func _draw_centered_text(text: String, centre: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(
		font, centre + Vector2(-width * 0.5, size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color
	)
