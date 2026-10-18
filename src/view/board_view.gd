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

## Designed in OKLCH: lightness is a deliberate ladder (0.50 blue -> 0.91 yellow)
## so the seven hues stay apart in greyscale, which is what carries the palette
## through red-green colour blindness. Hue alone cannot.
const GEM_COLORS := {
	Pieces.GemColor.BLUE: Color("2f58c8"),    # oklch 0.50 0.18 265
	Pieces.GemColor.RED: Color("d73337"),     # oklch 0.58 0.20  25
	Pieces.GemColor.VIOLET: Color("ad67dc"),  # oklch 0.64 0.18 310
	Pieces.GemColor.GREEN: Color("00b74a"),   # oklch 0.68 0.21 150
	Pieces.GemColor.ORANGE: Color("fc9a10"),  # oklch 0.77 0.17  65
	Pieces.GemColor.CYAN: Color("34dde5"),    # oklch 0.82 0.13 200
	Pieces.GemColor.YELLOW: Color("fae353"),  # oklch 0.91 0.16 100
}

## Emitted when a clear step lands, carrying what that step was worth. The HUD
## rolls the score up cascade by cascade with this, instead of jumping straight
## to the total the rules core already knows.
signal clear_scored(amount: int)

## Emitted as each animation step begins, so sound follows the visuals instead
## of firing once per move.
signal step_began(kind: String, step: Dictionary)

# --- timing (seconds) -------------------------------------------------------
# Radii as fractions of cell_size, kept together so the visual hierarchy is legible
# in one place: a gem sits inside its socket, inside the cursor outline.
const GEM_SCALE := 0.92
const SOCKET_SCALE := 0.94
const OUTLINE_SCALE := 0.96
const REFUSE_SCALE := 0.97
## Pieces in flight are drawn slightly small so motion reads against the board.
const FLIGHT_SCALE := 0.90

const SPIN_TIME := 0.11
const CLEAR_TIME := 0.14
const FALL_TIME := 0.17
const DROP_TIME := 0.15
const STEP_GAP := 0.045
const BLOOM_TIME := 0.28
## A promotion lands before its formation is destroyed, so it gets its own beat.
const PROMOTE_TIME := 0.22
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

var game: Game
var cursor_vertex := -1
## Set when the cursor has snapped onto a starflower or pearl centre.
var cursor_special := HexGrid.NO_CELL
var _cursor_painter: CursorPainter = null
var cursor_legal := true
var hint_vertex := -1
var hover_cell := HexGrid.NO_CELL

var _origin := Vector2.ZERO
var _display: Dictionary = {}      # cell -> piece, what is actually drawn
var _steps: Array = []
var _step_index := 0
var _step_time := 0.0
var _playing := false
var _plate: StyleBoxFlat = null
var _backdrop: ImageTexture = null
## Juice settings; null means "full juice" (tests and the tutorial).
## Multiplies every animation duration. 1.0 is the game; the tutorial's clips use
## above 1.0 so a demonstration can be followed rather than glimpsed.
var playback_scale := 1.0
## Board-space rectangle the camera can actually see. The tutorial's clips show about a
## dozen cells through a small viewport while the board still holds 85, so culling here
## is most of that section's drawing cost.
var _cull_rect := Rect2()
var settings: Settings
var _announced_step := -1
var _shake_strength := 0.0
var _shake_clock := 0.0
## True while steps that actually change the board are playing. A refused-spin
## bounce does not count: nothing is in flight, so further spins are safe.
var _settling := false


# --- setup ------------------------------------------------------------------

func set_game(new_game: Game) -> void:
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


## Distance from a board-local point to one vertex's centroid. Nearest-vertex
## has no way to break a tie, and six vertices are equidistant from a tile centre,
## which is exactly where a click on a piece lands.
func vertex_distance(vertex_index: int, local_point: Vector2) -> float:
	return HexGrid.vertex_centroid(vertex_index, cell_size).distance_to(local_point - _origin)


func vertex_at(local_point: Vector2) -> int:
	return HexGrid.nearest_vertex(local_point - _origin, cell_size)


func cell_at(local_point: Vector2) -> Vector2i:
	var best := HexGrid.NO_CELL
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


## Replays a move: ask MoveTimeline what to play, then own the playback.
func show_result(result: MoveResult) -> void:
	# A new result while the previous one is still playing: finish it first so nothing
	# is dropped mid-flight, then play this one from that state.
	if _playing:
		finish_now()
	_steps = MoveTimeline.plan(result, _motion())
	_step_index = 0
	_step_time = 0.0
	_announced_step = -1
	_playing = not _steps.is_empty()
	# A refused spin bounces but changes nothing, so it must not count as unsettled.
	_settling = MoveTimeline.settles(_steps)
	if result.bomb_exploded and _shake_allowed():
		_shake_strength = 1.0
		_shake_clock = 0.0
	queue_redraw()
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

	_update_cull_rect()
	_draw_backdrop()
	_draw_plate()
	for cell: Vector2i in HexGrid.all_cells():
		if _visible(cell_center(cell)):
			_draw_socket(cell)
	for cell: Vector2i in _display:
		if skip.has(cell):
			continue
		if not _visible(cell_center(cell)):
			continue
		_draw_piece(cell_center(cell), int(_display[cell]), cell_size * GEM_SCALE, 1.0)
	if not active.is_empty():
		_draw_step(active)
	_draw_cursor()


## The visible rectangle in board space, derived from the viewport's canvas transform so
## it follows a zoom crop as well as the ordinary full-screen view. Under the normal
## camera the transform is identity and every cell is inside it, so this costs one rect
## test per cell and changes nothing about the game's appearance.
func _update_cull_rect() -> void:
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var viewport := get_viewport()
	if viewport == null:
		_cull_rect = screen
		return
	var inverse := viewport.canvas_transform.affine_inverse()
	var corners := [
		inverse * screen.position,
		inverse * (screen.position + Vector2(screen.size.x, 0.0)),
		inverse * (screen.position + Vector2(0.0, screen.size.y)),
		inverse * (screen.position + screen.size),
	]
	var low: Vector2 = corners[0]
	var high: Vector2 = corners[0]
	for corner: Vector2 in corners:
		low = Vector2(minf(low.x, corner.x), minf(low.y, corner.y))
		high = Vector2(maxf(high.x, corner.x), maxf(high.y, corner.y))
	# A couple of cells of margin, so a piece sliding in from outside is not popped in.
	var margin := cell_size * 2.0
	_cull_rect = Rect2(low - Vector2(margin, margin), (high - low) + Vector2(margin, margin) * 2.0)


func _visible(point: Vector2) -> bool:
	return _cull_rect.has_point(point)


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
		"bloom":
			for promotion: Dictionary in step["promotions"]:
				skip[promotion["cell"]] = true
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
	var corners := _corners(cell_center(cell), cell_size * SOCKET_SCALE)
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
			# A machine part, not a gem: steel plate, rivets, and the fuse about to blow
			# heats the rim. It still reports its colour, through the same glyph set the
			# gems use, drawn in its own hue so it reads on dark steel.
			var bomb_color := int(Pieces.color_of(piece))
			var counter := Pieces.counter_of(piece)
			var hot := counter <= 2
			var plate := Color("5c3a22") if hot else Color("2b3140")
			var face := Color("33211a") if hot else Color("1a1f2b")
			draw_colored_polygon(
				_corners(centre + Vector2(radius * 0.09, radius * 0.13), radius * 0.97),
				Color(0, 0, 0, 0.32 * alpha)
			)
			draw_colored_polygon(corners, plate)
			var inner := _corners(centre, radius * 0.84)
			draw_colored_polygon(inner, face)
			draw_polyline(_closed(inner), plate.lightened(0.30), 1.5)
			for index in [1, 3, 5]:
				var angle := deg_to_rad(60.0 * float(index))
				var rivet := centre + Vector2(cos(angle), sin(angle)) * radius * 0.90
				draw_circle(rivet, radius * 0.10, plate.lightened(0.38))
				draw_circle(rivet, radius * 0.04, Color(0.05, 0.07, 0.10, alpha))
			GemGlyphs.draw_mark(
				self, centre - Vector2(0.0, radius * 0.12), radius * 0.78,
				GemGlyphs.kind_for(bomb_color), Color(base.r, base.g, base.b, 0.95 * alpha)
			)
			_draw_centered_text(
				str(counter), centre + Vector2(radius * 0.50, radius * 0.44), 15,
				Color(1.0, 0.80, 0.36, alpha) if hot else Color(0.82, 0.86, 0.94, alpha)
			)
		_:
			GemPainter.draw(self, centre, radius, base, int(Pieces.color_of(piece)),
				alpha, _patterns_allowed())
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
		_draw_piece(position, piece, cell_size * FLIGHT_SCALE, 1.0)


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
		_draw_piece(position, piece, cell_size * FLIGHT_SCALE, 1.0)

	for cell: Vector2i in cells:
		draw_polyline(_closed(_corners(cell_center(cell), cell_size * REFUSE_SCALE)), amber, 2.0)


func _draw_clear(step: Dictionary, t: float) -> void:
	var radius := cell_size * GEM_SCALE * (1.0 - t * 0.85)
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
		_draw_piece(position, piece, cell_size * GEM_SCALE / squash, 1.0)


func _draw_drop(step: Dictionary, t: float) -> void:
	var eased := 1.0 - pow(1.0 - t, 2.0)
	for spawn: Dictionary in step["spawns"]:
		var cell: Vector2i = spawn["cell"]
		var target := cell_center(cell)
		var start := target - Vector2(0.0, cell_size * 4.0)
		_draw_piece(start.lerp(target, eased), int(spawn["piece"]), cell_size * GEM_SCALE, minf(1.0, t * 2.0))


func _draw_bloom(step: Dictionary, t: float) -> void:
	for promotion: Dictionary in step["promotions"]:
		var centre := cell_center(promotion["cell"])
		# The new piece pops in oversized, so the conversion is unmistakable.
		var piece: int = promotion["piece"]
		if not Pieces.is_empty(piece):
			_draw_piece(centre, piece, cell_size * GEM_SCALE * (0.55 + 0.78 * t), minf(1.0, t * 3.0))
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
		_draw_piece(thrown, piece, cell_size * GEM_SCALE * (1.0 - t), 1.0 - t)


## Juice knobs come from Settings; null means full juice (tests, tutorial).
func _motion() -> float:
	return (settings.motion_scale() if settings != null else 1.0) * playback_scale


func _shake_allowed() -> bool:
	return settings == null or settings.shake_enabled()


## Colour patterns: the accessibility marks, on unless switched off.
func _patterns_allowed() -> bool:
	return settings == null or settings.colour_patterns


func _flashes_allowed() -> bool:
	return settings == null or settings.flashes_enabled()
## The cursor is drawn by CursorPainter; the swap set is asked of the rules, so the
## outline cannot disagree with what a turn actually moves.
func _draw_cursor() -> void:
	if _cursor_painter == null:
		_cursor_painter = CursorPainter.new()
	_cursor_painter.cell_size = cell_size
	_cursor_painter.origin = _origin

	var swapped: Array[Vector2i] = []
	if cursor_special != HexGrid.NO_CELL and game != null:
		swapped = game.swapped_cells(cursor_special)
	else:
		var vertices := HexGrid.vertices()
		if cursor_vertex >= 0 and cursor_vertex < vertices.size():
			for cell: Vector2i in vertices[cursor_vertex]:
				swapped.append(cell)
	_cursor_painter.draw(self, cursor_vertex, cursor_special, cursor_legal, hint_vertex, swapped)
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
