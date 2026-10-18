class_name ClipPlayer
extends Control

## One "recording": the real board, zoomed into the cells that matter, replaying a
## canned move on loop.
##
## There is no video file. The clip builds its board from TutorialLibrary, plays the
## demonstration move through the real renderer and animation timeline, then resets. So
## the tutorial shows exactly what the game does - it cannot go stale, and it costs no
## assets.

const BoardViewScript := preload("res://src/view/board_view.gd")
const Library := preload("res://src/core/tutorial_library.gd")
const HexGridScript := preload("res://src/core/hex_grid.gd")

const CLIP_SIZE := Vector2(380, 214)
## Twenty percent less than the first pass: at 2.0 the formation filled the frame and
## the surrounding board - which is what gives the action its context - was cropped out.
const ZOOM := 1.44
## How long the finished state sits before the demonstration restarts.
const HOLD := 2.0
## Extra quiet after the board settles. The last animation step commits its pieces on the
## frame it ends, so restarting immediately after is right on top of the final frame.
const TAIL := 0.2
## Offsets between clips' loops, set by the section. Larger than one animation, so the
## demonstrations genuinely take turns.
const STAGGER := 1.15

var clip_id := ""
## Passed to the board so the clips obey the colour-pattern setting like the game does.
var settings: Settings
## Seconds to wait before this clip's first play. The section offsets each clip so their
## resolutions never land on the same frame: five boards rigging, resolving and animating
## together is a stutter, and it also reads as chaos rather than five lessons.
var start_delay := 0.0

var _sub: SubViewport
var _view: BoardViewScript
var _hold := 0.0
var _delay := 0.0
# The demonstration is deterministic, so it is resolved once and replayed: rebuilding the
# Game, re-rigging 85 cells and re-running the resolver on every loop was the frame spike
# each clip produced when it cleared.
var zoom := ZOOM
var _game: Game
var _snapshot := {}
var _result: MoveResult


func _ready() -> void:
	custom_minimum_size = CLIP_SIZE
	clip_contents = true

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = CLIP_SIZE
	container.size = CLIP_SIZE
	add_child(container)

	_sub = SubViewport.new()
	_sub.size = Vector2i(CLIP_SIZE)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_sub)

	_view = BoardViewScript.new()
	_view.settings = settings
	# Demonstrations are worth watching: same animation, taken slower.
	_view.playback_scale = 1.7
	_sub.add_child(_view)
	# Show the board before its turn rather than an empty panel: build it now, render the
	# pre-move state, and start the animation when the delay expires.
	zoom = ZOOM * Library.zoom_for(clip_id)
	_game = Library.make_game(clip_id)
	_snapshot = _pieces(_game)
	_result = Library.play(_game, clip_id)
	_restore()
	_view.set_game(_game)
	_view.sync_from_game()
	_select_subject(_result)
	# Framed before the first frame is shown: without this the viewport displays the
	# un-cropped region until the clip's turn comes round, which is what put every panel's
	# board in the bottom right corner on entry.
	_apply_zoom()
	_delay = maxf(start_delay, 0.0)
	# Nothing to show until the delay expires, so do not pay for a render target.
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Re-read the juice settings: the board draws the colour patterns.
func apply_settings(value: Settings) -> void:
	settings = value
	if _view != null:
		_view.settings = value
		_view.queue_redraw()


func _process(delta: float) -> void:
	if _view == null or not is_visible_in_tree():
		return
	if _delay > 0.0:
		_delay -= delta
		if _delay > 0.0:
			return
		_restart()
		return
	if _view.is_settled():
		_hold += delta
		if _hold < HOLD + TAIL:
			# Keep drawing through the tail so the finished frame stays visible; only then
			# stop paying for this render target.
			if _hold > HOLD:
				_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		_restart()
		return
	_hold = 0.0


func _restart() -> void:
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_restore()
	_view.set_game(_game)
	# The board is rigged in place after the view took its copy, so it has to re-read.
	_view.sync_from_game()
	var result := _result
	# Put the cursor on the trio being turned, so the board draws its swap outline around
	# exactly the cells the demonstration moves. Without it the clip has no outline at all:
	# nothing is selected, so nothing is highlighted.
	# A starflower turn has no trio: select the piece itself so the board outlines its six
	# neighbours. Otherwise outline the trio being turned.
	_select_subject(result)
	_view.cursor_legal = true
	_view.show_result(result)
	_hold = 0.0
	_apply_zoom()


## A camera crop rather than a scale on the container: translate the board so the focus
## cell is centred in the small viewport and magnify around it. BoardView keeps drawing
## at its normal size, which is what makes the demo identical to the game.
func _apply_zoom() -> void:
	if _sub == null or _view == null:
		return
	var centre := _view.cell_center(Library.focus_cell(clip_id))
	# Only this viewport culls, and it says exactly what it can see: the clip's own zoom
	# crop, plus a couple of cells so nothing pops in at the edge.
	var half := CLIP_SIZE * 0.5 / zoom
	_view.cull_rect = Rect2(centre - half, half * 2.0).grow(_view.cell_size * 2.0)
	_sub.canvas_transform = Transform2D(
		Vector2(ZOOM, 0.0), Vector2(0.0, ZOOM),
		CLIP_SIZE * 0.5 - centre * zoom
	)


## The vertex whose trio is exactly `cells`, so the outline lands on the move.
func _vertex_for(cells: Array) -> int:
	if cells.is_empty():
		return 0
	var vertices := HexGridScript.vertices()
	for index in vertices.size():
		var trio: Array = vertices[index]
		var all_present := true
		for cell: Vector2i in cells:
			if not trio.has(cell):
				all_present = false
				break
		if all_present:
			return index
	return 0


## Cell -> piece before the demonstration move, so a loop can put the board back without
## rebuilding it.
func _pieces(game: Game) -> Dictionary:
	var out := {}
	for cell: Vector2i in HexGridScript.all_cells():
		out[cell] = game.board.get_piece(cell)
	return out


func _restore() -> void:
	for cell: Vector2i in _snapshot:
		_game.board.set_piece(cell, int(_snapshot[cell]))


## What the outline should be on. Stated rather than derived: the clip replays a cached
## result, so its board is pre-move and asking the board what a piece would swap returns
## nothing.
##
## Only "turning a starflower" is about a piece, so it selects the starflower and outlines
## its ring. Every other clip is about a rotation, so the subject is the trio at that
## vertex - the ordinary cluster selection.
func _select_subject(result: MoveResult = null) -> void:
	if _view == null:
		return
	_view.cursor_legal = true
	if clip_id == "turn":
		_view.cursor_special = Library.CENTRE
		_view.cursor_cells = HexGridScript.neighbours(Library.CENTRE)
		_view.cursor_vertex = _vertex_for(HexGridScript.neighbours(Library.CENTRE))
		return
	_view.cursor_special = HexGridScript.NO_CELL
	if result == null:
		return
	_view.cursor_cells = result.rotation_cells.duplicate()
	_view.cursor_vertex = _vertex_for(result.rotation_cells)
