class_name BoardView
extends Node2D

## The board, its container, and the move animation (docs/design.md §7.5, §8).
##
## The rules core resolves a move instantly, so this view keeps its own
## presentation board (`_display`) that lags behind. A move is replayed as a
## queue of steps — spin, then per cascade depth: clear → fall → drop — and the
## display is committed step by step. When the queue drains, the display is
## snapped to the core so the two can never drift.

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

## Emitted when a clear step lands, carrying what that step was worth. The HUD
## rolls the score up cascade by cascade with this, instead of jumping straight
## to the total the rules core already knows.
signal clear_scored(amount: int)

## Emitted as each animation step begins, so sound follows the visuals instead
## of firing once per move.
signal step_began(kind: String, step: Dictionary)

# --- timing (seconds) -------------------------------------------------------
const SPIN_TIME := 0.11
const CLEAR_TIME := 0.14
const FALL_TIME := 0.17
const DROP_TIME := 0.15
const STEP_GAP := 0.045
const BLOOM_TIME := 0.28
## A bomb going off: the flash, then the crater's debris flying outward.
const BLAST_TIME := 0.42
const SHATTER_TIME := 0.34
## Screen shake on a bomb: amplitude in pixels at full strength, and how long it
## takes to decay. Deliberately small — the board should kick, not jitter.
const SHAKE_AMPLITUDE := 7.0
const SHAKE_TIME := 0.55
## A refused spin turns out and straight back; the snap-back is quicker than the
## turn so it reads as a rejection rather than a move.
const BOUNCE_TIME := 0.22

# --- neon container ---------------------------------------------------------
const PLATE_PAD := 26.0
const PLATE_RADIUS := 46
const PLATE_FILL := Color("0b101c")
const PLATE_RIM := Color("35e0f0")
const SOCKET_FILL := Color("0d1420")
const SOCKET_LINE := Color("1d3b4d")

@export var cell_size: float = 30.0

var game: RefCounted
var cursor_vertex := -1
var cursor_legal := true
var hint_vertex := -1
var hover_cell := Vector2i(-1, -1)

var _origin := Vector2.ZERO
var _display: Dictionary = {}      # cell -> piece, what is actually drawn
var _steps: Array = []
var _step_index := 0
var _step_time := 0.0
var _playing := false
var _plate: StyleBoxFlat = null
var _backdrop: ImageTexture = null
## Juice settings; null means "full juice" (tests and the tutorial).
var settings: Settings
var _announced_step := -1
var _shake_strength := 0.0
var _shake_clock := 0.0
## True while steps that actually change the board are playing. A refused-spin
## bounce does not count: nothing is in flight, so further spins are safe.
var _settling := false


# --- setup ------------------------------------------------------------------

func set_game(new_game: RefCounted) -> void:
	game = new_game
	_recenter()
	sync_from_game()


## Copies the core board into the presentation board and cancels playback. Needed
## wherever the board changes without a MoveResult (new run, tutorial rigging).
func sync_from_game() -> void:
	_steps.clear()
	_step_index = 0
	_step_time = 0.0
	_playing = false
	_settling = false
	_display.clear()
	if game == null:
		queue_redraw()
		return
	for cell: Vector2i in HexGrid.all_cells():
		var piece: int = game.board.get_piece(cell)
		if not Pieces.is_empty(piece):
			_display[cell] = piece
	queue_redraw()


func _recenter() -> void:
	var bounds := HexGrid.pixel_bounds(cell_size)
	_origin = -bounds.position - bounds.size * 0.5
	_plate = null


# --- geometry ---------------------------------------------------------------

func cell_center(cell: Vector2i) -> Vector2:
	return HexGrid.to_pixel(cell, cell_size) + _origin


func vertex_at(local_point: Vector2) -> int:
	return HexGrid.nearest_vertex(local_point - _origin, cell_size)


func cell_at(local_point: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for cell: Vector2i in HexGrid.all_cells():
		var distance := local_point.distance_squared_to(cell_center(cell))
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


# --- animation --------------------------------------------------------------

## Number of animation steps still queued (the smoke test uses this).
func effect_count() -> int:
	return _steps.size() if _playing else 0


func is_animating() -> bool:
	return _playing


## False while pieces are still moving or clearing. The controller refuses spins
## during this window: the rules core resolves instantly, so letting a new move
## in would advance it past what is on screen and drop the animation in flight.
func is_settled() -> bool:
	return not _settling


## Commits whatever is left of the current timeline without waiting. Used when a
## new result arrives mid-playback, so no step is ever silently discarded.
func finish_now() -> void:
	while _playing:
		_commit(_steps[_step_index])
		_step_index += 1
		if _step_index >= _steps.size():
			_stop(false)


## Replays a move: spin, then per cascade depth clear â†’ fall â†’ drop.
func show_result(result: RefCounted) -> void:
	# A new result while the previous one is still playing: finish it first so
	# nothing is dropped mid-flight, then play this one from that state.
	if _playing:
		finish_now()
	_steps.clear()
	_step_index = 0
	_step_time = 0.0
	_announced_step = -1

	# A spin the rules refused: show the turn it asked for, then undo it.
	if not result.committed:
		if result.rotation_cells.size() > 0:
			_steps.append({
				"kind": "bounce", "cells": result.rotation_cells.duplicate(),
				"dir": result.direction, "duration": BOUNCE_TIME * _motion(),
			})
			_playing = true
			_settling = false
			queue_redraw()
		return

	if result.rotation_cells.size() > 0:
		_steps.append({
			"kind": "spin", "cells": result.rotation_cells.duplicate(),
			"dir": result.direction, "duration": SPIN_TIME * _motion(),
		})

	for depth: int in _depths(result):
		var cleared := _cells_at_depth(result, depth)
		if not cleared.is_empty():
			_steps.append({
				"kind": "clear", "cells": cleared, "duration": CLEAR_TIME * _motion(),
				"score": _score_at_depth(result, depth), "depth": depth,
				"groups": _groups_at_depth(result, depth),
			})
		var falls := _entries_at_depth(result.gravity_moves, depth)
		if not falls.is_empty():
			_steps.append({"kind": "fall", "moves": falls, "duration": FALL_TIME * _motion()})
		var drops := _entries_at_depth(result.spawns, depth)
		if not drops.is_empty():
			_steps.append({"kind": "drop", "spawns": drops, "duration": DROP_TIME * _motion()})
		_steps.append({"kind": "wait", "duration": STEP_GAP * _motion()})

	if not result.promotions.is_empty():
		_steps.append({
			"kind": "bloom", "promotions": result.promotions.duplicate(),
			"duration": BLOOM_TIME * _motion(),
		})

	# A dying bomb takes the board with it: flash, shockwave, debris.
	if result.bomb_exploded and result.exploded_cells.size() > 0:
		var origin: Vector2i = result.exploded_cells[0]
		_steps.append({"kind": "blast", "cell": origin, "duration": BLAST_TIME * _motion()})
		_steps.append({
			"kind": "shatter", "cells": result.exploded_cells.duplicate(),
			"centre": origin, "duration": SHATTER_TIME * _motion(),
		})
		if _shake_allowed():
			_shake_strength = 1.0
			_shake_clock = 0.0

	_playing = not _steps.is_empty()
	_settling = _playing
	queue_redraw()


## Cascade depths present in this move, in order (1, 2, …).
func _depths(result: MoveResult) -> Array[int]:
	var seen := {}
	for group in result.clear_groups:
		seen[int(group.cascade_depth)] = true
	if seen.is_empty():
		seen[1] = true
	var depths: Array[int] = []
	for depth: int in seen:
		depths.append(depth)
	depths.sort()
	return depths


func _cells_at_depth(result: MoveResult, depth: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for group in result.clear_groups:
		if int(group.cascade_depth) != depth:
			continue
		for cell: Vector2i in group.cells:
			out.append(cell)
	return out


## What one cascade step is worth: the sum of the groups that cleared in it.
func _groups_at_depth(result: MoveResult, depth: int) -> Array:
	var out: Array = []
	for group in result.clear_groups:
		if int(group.cascade_depth) == depth:
			out.append(group)
	return out


func _score_at_depth(result: MoveResult, depth: int) -> int:
	var total := 0
	for group in result.clear_groups:
		if int(group.cascade_depth) == depth:
			total += int(group.score)
	return total


func _entries_at_depth(entries: Array, depth: int) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		if int(entry.get("depth", 0)) == depth:
			out.append(entry)
	return out


func _process(delta: float) -> void:
	if _playing and _step_index != _announced_step:
		_announced_step = _step_index
		step_began.emit(str(_steps[_step_index]["kind"]), _steps[_step_index])
	# The shake decays even after the timeline ends, so it can never freeze.
	if _shake_strength > 0.0:
		_shake_clock += delta
		_shake_strength = maxf(_shake_strength - delta / SHAKE_TIME, 0.0)
		queue_redraw()
	if not _playing:
		return
	var step: Dictionary = _steps[_step_index]
	_step_time += delta
	if _step_time >= float(step["duration"]):
		_commit(step)
		_step_index += 1
		_step_time = 0.0
		if _step_index >= _steps.size():
			_stop()
	queue_redraw()


func _stop(sync: bool = true) -> void:
	_playing = false
	_announced_step = -1
	_settling = false
	_steps.clear()
	_step_index = 0
	if sync:
		sync_from_game()


## Folds one finished step into the presentation board.
func _commit(step: Dictionary) -> void:
	match str(step["kind"]):
		"spin":
			var cells: Array = step["cells"]
			var dir: int = int(step["dir"])
			var n := cells.size()
			var pieces: Array[int] = []
			for cell: Vector2i in cells:
				pieces.append(int(_display.get(cell, Pieces.EMPTY)))
			for i in n:
				_display[cells[i]] = pieces[posmod(i - dir, n)]
		"clear":
			for cell: Vector2i in step["cells"]:
				_display.erase(cell)
			clear_scored.emit(int(step.get("score", 0)))
		"fall":
			# Two phases so pieces cannot consume each other's sources.
			var placed := {}
			for move: Dictionary in step["moves"]:
				var from: Vector2i = move["from"]
				placed[move["to"]] = int(_display.get(from, Pieces.EMPTY))
			for move: Dictionary in step["moves"]:
				_display.erase(move["from"])
			for to: Vector2i in placed:
				if not Pieces.is_empty(int(placed[to])):
					_display[to] = placed[to]
		"drop":
			for spawn: Dictionary in step["spawns"]:
				_display[spawn["cell"]] = spawn["piece"]
		"bloom":
			for promotion: Dictionary in step["promotions"]:
				var piece: int = promotion["piece"]
				if not Pieces.is_empty(piece):
					_display[promotion["cell"]] = piece
		"shatter":
			for cell: Vector2i in step["cells"]:
				_display.erase(cell)
		_:
			pass


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if game == null:
		return
	# Two offset frequencies so the kick reads as impact rather than a slide.
	if _shake_strength > 0.0:
		var amount := _shake_strength * _shake_strength * SHAKE_AMPLITUDE
		draw_set_transform(Vector2(sin(_shake_clock * 78.0), cos(_shake_clock * 61.0)) * amount)
	var active := _active_step()
	var skip := _skipped_cells(active)

	_draw_backdrop()
	_draw_plate()
	for cell: Vector2i in HexGrid.all_cells():
		_draw_socket(cell)
	for cell: Vector2i in _display:
		if skip.has(cell):
			continue
		_draw_piece(cell_center(cell), int(_display[cell]), cell_size * 0.92, 1.0)
	if not active.is_empty():
		_draw_step(active)
	_draw_cursor()


func _active_step() -> Dictionary:
	if not _playing or _step_index >= _steps.size():
		return {}
	var step: Dictionary = _steps[_step_index]
	if _step_time <= 0.0 and float(step["duration"]) <= 0.0:
		return {}
	return step


func _step_progress(step: Dictionary) -> float:
	var duration := float(step["duration"])
	if duration <= 0.0:
		return 1.0
	return clampf(_step_time / duration, 0.0, 1.0)


func _skipped_cells(step: Dictionary) -> Dictionary:
	var skip := {}
	if step.is_empty():
		return skip
	match str(step["kind"]):
		"spin", "clear", "bounce":
			for cell: Vector2i in step["cells"]:
				skip[cell] = true
		"blast":
			skip[step["cell"]] = true
		"shatter":
			for cell: Vector2i in step["cells"]:
				skip[cell] = true
		"fall":
			for move: Dictionary in step["moves"]:
				skip[move["from"]] = true
		"drop":
			for spawn: Dictionary in step["spawns"]:
				skip[spawn["cell"]] = true
	return skip


## A smooth radial glow behind the plate. Drawn as one dithered texture rather
## than concentric circles: stacked translucent circles band badly in 8-bit.
func _draw_backdrop() -> void:
	if _backdrop == null:
		_build_backdrop()
	var centre := _plate_rect().get_center()
	var span := cell_size * 34.0
	draw_texture_rect(_backdrop, Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span)), false)


func _build_backdrop() -> void:
	const SIDE := 128
	var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIDE, SIDE) * 0.5
	var max_distance := centre.length()
	var noise := RandomNumberGenerator.new()
	noise.seed = 4242
	for y in SIDE:
		for x in SIDE:
			var distance := Vector2(x, y).distance_to(centre) / max_distance
			var falloff := pow(clampf(1.0 - distance, 0.0, 1.0), 2.2)
			# Dither by a fraction of one step so the falloff cannot stair-step.
			var alpha := falloff * 0.50 + (noise.randf() - 0.5) / 255.0
			image.set_pixel(x, y, Color(0.09, 0.60, 0.76, clampf(alpha, 0.0, 1.0)))
	_backdrop = ImageTexture.create_from_image(image)


func _plate_rect() -> Rect2:
	var bounds := HexGrid.pixel_bounds(cell_size)
	return Rect2(bounds.position + _origin, bounds.size).grow(PLATE_PAD)


func _draw_plate() -> void:
	if _plate == null:
		_plate = StyleBoxFlat.new()
		_plate.bg_color = PLATE_FILL
		_plate.set_corner_radius_all(PLATE_RADIUS)
		_plate.set_border_width_all(2)
		_plate.border_color = PLATE_RIM
		_plate.shadow_color = Color(0.05, 0.85, 0.95, 0.22)
		_plate.shadow_size = 18
		_plate.anti_aliasing = true
	draw_style_box(_plate, _plate_rect())


func _draw_socket(cell: Vector2i) -> void:
	var corners := _corners(cell_center(cell), cell_size * 0.94)
	draw_colored_polygon(corners, SOCKET_FILL)
	draw_polyline(_closed(corners), SOCKET_LINE, 1.0)


func _draw_piece(centre: Vector2, piece: int, radius: float, alpha: float) -> void:
	if Pieces.is_empty(piece) or radius <= 0.5:
		return
	var base: Color = GEM_COLORS.get(Pieces.color_of(piece), Color(0.8, 0.8, 0.8))
	base.a = alpha
	var corners := _corners(centre, radius)

	match Pieces.kind_of(piece):
		Pieces.Kind.STARFLOWER:
			var star := _star_points(centre, radius * 1.05, radius * 0.45, 6)
			draw_colored_polygon(star, Color(0.96, 0.97, 1.0, alpha))
			draw_polyline(_closed(_star_points(centre, radius * 0.55, radius * 0.24, 6)),
				Color(0.55, 0.6, 0.7, alpha), 1.0)
		Pieces.Kind.PEARL:
			draw_circle(centre, radius * 0.82, Color(0.10, 0.12, 0.18, alpha))
			draw_arc(centre, radius * 0.82, 0, TAU, 32, Color(0.58, 0.66, 0.88, alpha), 2.0)
			draw_circle(centre - Vector2(radius * 0.22, radius * 0.22), radius * 0.22,
				Color(0.78, 0.84, 0.98, alpha * 0.9))
		Pieces.Kind.BOMB:
			draw_colored_polygon(corners, base.darkened(0.3))
			draw_polyline(_closed(corners), Color(0.06, 0.08, 0.11, alpha), 2.5)
			draw_circle(centre, radius * 0.34, Color(0.06, 0.08, 0.11, alpha))
			_draw_centered_text(str(Pieces.counter_of(piece)), centre, 19, Color(1.0, 0.82, 0.4, alpha))
		_:
			draw_colored_polygon(corners, base)
			draw_polyline(_closed(corners), base.darkened(0.45), 2.0)
			draw_colored_polygon(
				_corners(centre - Vector2(0.0, radius * 0.24), radius * 0.5),
				Color(1, 1, 1, 0.28 * alpha)
			)
			if Pieces.is_bonus_star(piece):
				var star := _star_points(centre, radius * 0.62, radius * 0.26, 6)
				draw_colored_polygon(star, Color(1.0, 0.95, 0.77, alpha))
				draw_polyline(_closed(star), Color(0.54, 0.43, 0.12, alpha), 1.0)


## Transient visuals for whichever step is playing.
func _draw_step(step: Dictionary) -> void:
	var t := _step_progress(step)
	match str(step["kind"]):
		"spin":
			_draw_spin(step, t)
		"bounce":
			_draw_bounce(step, t)
		"clear":
			_draw_clear(step, t)
		"fall":
			_draw_fall(step, t)
		"drop":
			_draw_drop(step, t)
		"bloom":
			_draw_bloom(step, t)
		"blast":
			_draw_blast(step, t)
		"shatter":
			_draw_shatter(step, t)


func _draw_spin(step: Dictionary, t: float) -> void:
	var cells: Array = step["cells"]
	var n := cells.size()
	var dir: int = int(step["dir"])
	var centre := Vector2.ZERO
	for cell: Vector2i in cells:
		centre += cell_center(cell)
	centre /= float(n)
	for i in n:
		var source: Vector2i = cells[posmod(i - dir, n)]
		var piece: int = int(_display.get(source, Pieces.EMPTY))
		if Pieces.is_empty(piece):
			continue
		var from := cell_center(source)
		var to := cell_center(cells[i])
		var position := from.lerp(to, t)
		# Bulge around the vertex so the trio reads as turning, not sliding.
		position += (position - centre).rotated(PI * 0.5) * sin(t * PI) * 0.25
		_draw_piece(position, piece, cell_size * 0.90, 1.0)


## A refused spin: turn to the position that was asked for, then straight back.
## The snap-back is faster than the turn, which reads as refusal rather than a
## move, and an amber outline marks the trio that could not go anywhere.
func _draw_bounce(step: Dictionary, t: float) -> void:
	var cells: Array = step["cells"]
	var n := cells.size()
	var dir: int = int(step["dir"])
	var sweep := t / 0.42 if t <= 0.42 else (1.0 - t) / 0.58
	var centre := Vector2.ZERO
	for cell: Vector2i in cells:
		centre += cell_center(cell)
	centre /= float(n)

	var amber := Color(1.0, 0.72, 0.32, 0.6 * (1.0 - t))
	for i in n:
		var source: Vector2i = cells[posmod(i - dir, n)]
		var piece: int = int(_display.get(source, Pieces.EMPTY))
		if Pieces.is_empty(piece):
			continue
		var from := cell_center(source)
		var to := cell_center(cells[i])
		var position := from.lerp(to, sweep)
		position += (position - centre).rotated(PI * 0.5) * sin(sweep * PI) * 0.25
		_draw_piece(position, piece, cell_size * 0.90, 1.0)

	for cell: Vector2i in cells:
		draw_polyline(_closed(_corners(cell_center(cell), cell_size * 0.97)), amber, 2.0)


func _draw_clear(step: Dictionary, t: float) -> void:
	var radius := cell_size * 0.92 * (1.0 - t * 0.85)
	var alpha := 1.0 - t
	for cell: Vector2i in step["cells"]:
		_draw_piece(cell_center(cell), int(_display.get(cell, Pieces.EMPTY)), radius, alpha)


func _draw_fall(step: Dictionary, t: float) -> void:
	var eased := t * t
	for move: Dictionary in step["moves"]:
		var piece: int = int(_display.get(move["from"], Pieces.EMPTY))
		if Pieces.is_empty(piece):
			continue
		var position := cell_center(move["from"]).lerp(cell_center(move["to"]), eased)
		# A little squash as it lands sells the weight.
		var squash := 1.0 + 0.10 * maxf(0.0, t - 0.75) * 4.0
		_draw_piece(position, piece, cell_size * 0.92 / squash, 1.0)


func _draw_drop(step: Dictionary, t: float) -> void:
	var eased := 1.0 - pow(1.0 - t, 2.0)
	for spawn: Dictionary in step["spawns"]:
		var cell: Vector2i = spawn["cell"]
		var target := cell_center(cell)
		var start := target - Vector2(0.0, cell_size * 4.0)
		_draw_piece(start.lerp(target, eased), int(spawn["piece"]), cell_size * 0.92, minf(1.0, t * 2.0))


func _draw_bloom(step: Dictionary, t: float) -> void:
	for promotion: Dictionary in step["promotions"]:
		var centre := cell_center(promotion["cell"])
		var radius := cell_size * (0.35 + 1.7 * t)
		draw_arc(centre, radius, 0, TAU, 32, Color(1.0, 0.88, 0.42, 0.85 * (1.0 - t)), 2.5)


## The bomb's flash and the shockwave rings running out from it.
func _draw_blast(step: Dictionary, t: float) -> void:
	var centre := cell_center(step["cell"])
	# Core flash: brightest at the instant it goes.
	if _flashes_allowed():
		draw_circle(centre, cell_size * (0.7 + 1.5 * t), Color(1.0, 0.96, 0.84, 0.85 * (1.0 - t)))
		draw_circle(centre, cell_size * (0.4 + 0.6 * t), Color(1.0, 1.0, 1.0, 0.95 * (1.0 - t)))
	# Three staggered rings so the wave reads as travelling, not as one circle.
	for index in 3:
		var lag := t - float(index) * 0.10
		if lag <= 0.0:
			continue
		var radius := cell_size * (0.6 + (2.4 + float(index) * 1.1) * lag * 3.2)
		draw_arc(
			centre, radius, 0, TAU, 44,
			Color(0.55, 0.93, 1.0, 0.9 * (1.0 - lag)), maxf(3.0 - float(index) * 0.8, 1.0)
		)


## Debris thrown outward from the blast, shrinking and fading.
func _draw_shatter(step: Dictionary, t: float) -> void:
	var origin := cell_center(step["centre"])
	for cell: Vector2i in step["cells"]:
		var piece: int = int(_display.get(cell, Pieces.EMPTY))
		if Pieces.is_empty(piece):
			continue
		var from := cell_center(cell)
		var direction := from - origin
		if direction.length() < 0.001:
			direction = Vector2(0.0, -1.0)
		var thrown := from + direction.normalized() * cell_size * 1.8 * t
		_draw_piece(thrown, piece, cell_size * 0.92 * (1.0 - t), 1.0 - t)


## Juice knobs come from Settings; null means full juice (tests, tutorial).
func _motion() -> float:
	return settings.motion_scale() if settings != null else 1.0


func _shake_allowed() -> bool:
	return settings == null or settings.shake_enabled()


func _flashes_allowed() -> bool:
	return settings == null or settings.flashes_enabled()


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
	draw_circle(centre, cell_size * 0.10, Color(0.06, 0.08, 0.12, 0.92))
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
