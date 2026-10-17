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

const SPIN_TIME := 0.12
const CLEAR_TIME := 0.30
const FALL_TIME := 0.22
const BLOOM_TIME := 0.38

@export var cell_size: float = 30.0

var game: RefCounted
var cursor_vertex := -1
## False when no spin at the cursor can clear anything (the usual case in STRICT
## mode) — the cursor dims so the player can see that before spinning.
var cursor_legal := true
var hint_vertex := -1
var hover_cell := Vector2i(-1, -1)

var _origin := Vector2.ZERO
var _effects: Array = []


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


## Turns a move into a short animation (docs/design.md §8).
##
## The rules core has already reached its final state, so these are transient
## overlays: a spin, shrinking clear ghosts, falling streaks and a bloom ring.
## Nothing here blocks input, and nothing mutates game state.
func show_result(result: RefCounted) -> void:
	_effects.clear()
	if result.rotation_cells.size() > 0:
		_effects.append({
			"kind": "spin", "cells": result.rotation_cells.duplicate(),
			"t": 0.0, "duration": SPIN_TIME, "delay": 0.0,
		})
	for group in result.clear_groups:
		var cells: Array[Vector2i] = []
		for cell: Vector2i in group.cells:
			cells.append(cell)
		_effects.append({
			"kind": "clear", "cells": cells,
			"t": 0.0, "duration": CLEAR_TIME, "delay": SPIN_TIME,
		})
	for move: Dictionary in result.gravity_moves:
		_effects.append({
			"kind": "fall", "from": move["from"], "to": move["to"],
			"t": 0.0, "duration": FALL_TIME, "delay": SPIN_TIME + CLEAR_TIME * 0.4,
		})
	for promotion: Dictionary in result.promotions:
		_effects.append({
			"kind": "bloom", "cell": promotion["cell"],
			"t": 0.0, "duration": BLOOM_TIME, "delay": SPIN_TIME,
		})
	queue_redraw()


## Live effect count, so tests can tell an animated move from a silent one.
func effect_count() -> int:
	return _effects.size()


func _process(delta: float) -> void:
	if _effects.is_empty():
		return
	var live: Array = []
	for effect: Dictionary in _effects:
		if float(effect["delay"]) > 0.0:
			effect["delay"] = float(effect["delay"]) - delta
			live.append(effect)
			continue
		effect["t"] = float(effect["t"]) + delta
		if float(effect["t"]) < float(effect["duration"]):
			live.append(effect)
	_effects = live
	queue_redraw()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	for cell: Vector2i in HexGrid.all_cells():
		_draw_cell(cell)
	_draw_effects()
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


func _draw_effects() -> void:
	for effect: Dictionary in _effects:
		if float(effect["delay"]) > 0.0:
			continue
		var progress := clampf(float(effect["t"]) / float(effect["duration"]), 0.0, 1.0)
		match str(effect["kind"]):
			"spin":
				_draw_spin(effect, progress)
			"clear":
				_draw_clear(effect, progress)
			"fall":
				_draw_fall(effect, progress)
			"bloom":
				_draw_bloom(effect, progress)


## The trio visibly turning: three ghost hexes orbit the vertex and fade.
func _draw_spin(effect: Dictionary, progress: float) -> void:
	var cells: Array = effect["cells"]
	if cells.size() != 3:
		return
	var centre := Vector2.ZERO
	for cell: Vector2i in cells:
		centre += cell_center(cell)
	centre /= 3.0
	var angle := deg_to_rad(60.0) * progress
	var alpha := 0.30 * (1.0 - progress)
	for cell: Vector2i in cells:
		var spun := (cell_center(cell) - centre).rotated(angle)
		draw_colored_polygon(_corners(centre + spun, cell_size * 0.84), Color(1, 1, 1, alpha))


## Cleared gems shrink away.
func _draw_clear(effect: Dictionary, progress: float) -> void:
	var radius := cell_size * 0.92 * (1.0 - progress * 0.85)
	var alpha := 0.85 * (1.0 - progress)
	for cell: Vector2i in effect["cells"]:
		draw_colored_polygon(_corners(cell_center(cell), radius), Color(1, 1, 1, alpha))


## A falling gem leaves a warm streak along its path.
func _draw_fall(effect: Dictionary, progress: float) -> void:
	var from_pos := cell_center(effect["from"])
	var to_pos := cell_center(effect["to"])
	var position := from_pos.lerp(to_pos, progress * progress)
	var alpha := 0.40 * (1.0 - progress)
	draw_colored_polygon(_corners(position, cell_size * 0.45), Color(1.0, 0.93, 0.66, alpha))


## A promotion blooms outward from its cell.
func _draw_bloom(effect: Dictionary, progress: float) -> void:
	var centre := cell_center(effect["cell"])
	var radius := cell_size * (0.35 + 1.7 * progress)
	draw_arc(centre, radius, 0, TAU, 32, Color(1.0, 0.88, 0.42, 0.85 * (1.0 - progress)), 2.5)


func _draw_cursor() -> void:
	var vertices := HexGrid.vertices()

	if hint_vertex >= 0 and hint_vertex < vertices.size():
		var hint_centre := HexGrid.vertex_centroid(hint_vertex, cell_size) + _origin
		draw_arc(hint_centre, cell_size * 0.5, 0, TAU, 24, Color("ffd166"), 2.0)

	if cursor_vertex < 0 or cursor_vertex >= vertices.size():
		return
	for cell: Vector2i in vertices[cursor_vertex]:
		var tint := 0.20 if cursor_legal else 0.08
		draw_colored_polygon(_corners(cell_center(cell), cell_size * 0.97), Color(1, 1, 1, tint))

	var centre := HexGrid.vertex_centroid(cursor_vertex, cell_size) + _origin
	# Green means "spinning here will clear"; dim grey means it would just revert.
	var dot := Color(0.45, 0.95, 0.55, 0.95) if cursor_legal else Color(0.62, 0.66, 0.74, 0.80)
	draw_circle(centre, cell_size * 0.16, dot)
	draw_circle(centre, cell_size * 0.10, Color(0.10, 0.12, 0.16, 0.92))
	if cursor_legal:
		draw_arc(centre, cell_size * 0.28, 0, TAU, 24, Color(0.45, 0.95, 0.55, 0.55), 1.5)


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
