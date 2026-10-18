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
const ZOOM := 1.6
## How long the finished state sits before the demonstration restarts.
const HOLD := 2.0
## Offsets between clips' loops, set by the section. Larger than one animation, so the
## demonstrations genuinely take turns.
const STAGGER := 1.15

var clip_id := ""
## Seconds to wait before this clip's first play. The section offsets each clip so their
## resolutions never land on the same frame: five boards rigging, resolving and animating
## together is a stutter, and it also reads as chaos rather than five lessons.
var start_delay := 0.0

var _sub: SubViewport
var _view: BoardViewScript
var _hold := 0.0
var _delay := 0.0


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
	# Demonstrations are worth watching: same animation, taken slower.
	_view.playback_scale = 1.7
	_sub.add_child(_view)
	_delay = maxf(start_delay, 0.0)
	# Nothing to show until the delay expires, so do not pay for a render target.
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED


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
		# Idle between demonstrations: stop re-rendering this viewport entirely. Four of
		# five clips are idle at any moment, so this is most of the section's cost.
		_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_hold += delta
		if _hold >= HOLD:
			_restart()
		return
	_hold = 0.0


func _restart() -> void:
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var game := Library.make_game(clip_id)
	_view.set_game(game)
	# The board is rigged in place after the view took its copy, so it has to re-read.
	_view.sync_from_game()
	var result := Library.play(game, clip_id)
	# Put the cursor on the trio being turned, so the board draws its swap outline around
	# exactly the cells the demonstration moves. Without it the clip has no outline at all:
	# nothing is selected, so nothing is highlighted.
	_view.cursor_vertex = _vertex_for(result.rotation_cells)
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
	_sub.canvas_transform = Transform2D(
		Vector2(ZOOM, 0.0), Vector2(0.0, ZOOM),
		CLIP_SIZE * 0.5 - centre * ZOOM
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
