extends SceneTree

## Measures draw calls for a board at different fill levels, to answer whether the gem quads
## batch rather than assuming it. Windowed, because a renderer is required:
##
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-driver opengl3 \
##       --script res://tests/measure_draws.gd

const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const PieceScript := preload("res://src/core/piece.gd")
const GridScript := preload("res://src/core/hex_grid.gd")

var _view: BoardView
var _frame := 0
var _lines: Array[String] = []


func _initialize() -> void:
	_view = BoardView.new()
	root.add_child(_view)
	_view.set_game(GameScript.new(7, RulesetScript.new()))


func _process(_delta: float) -> bool:
	_frame += 1
	# Marginal cost: place N gems, sample, then N more. The slope is the per-gem draw cost.
	var steps := [0, 85, 85]
	var step_index := (_frame - 4) / 6
	if _frame < 4:
		return false
	if step_index >= steps.size():
		for line: String in _lines:
			print(line)
		quit(0)
		return false
	if (_frame - 4) % 14 == 0:
		_place(int(steps[step_index]))
		# stage 2: board hidden. If the draw count does not follow, it is not the board.
		_view.visible = step_index != 2
	elif (_frame - 4) % 14 == 10:
		print("  atlas slices=%d" % (_view.get("_atlas_textures") as Dictionary).size())
		var label := "%2d gems" % int(steps[step_index])
		if step_index == 1:
			label = "85 gems, board visible"
		elif step_index == 2:
			label = "85 gems, board HIDDEN"
		elif step_index == 3:
			label = "85 gems, visible again"
		_sample(label)
	return false


func _place(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var board: Board = _view.game.board
	var cells: Array = GridScript.all_cells()
	for cell: Vector2i in cells:
		board.set_piece(cell, PieceScript.EMPTY)
	for index in count:
		board.set_piece(cells[index], PieceScript.make(rng.randi_range(1, 7)))
	_view.sync_from_game()
	_view.queue_redraw()


func _clear_glyphs() -> void:
	# glyphs are read from the juice settings; no settings means patterns are drawn, so this
	# flips the view to the plain row of the atlas instead
	_view.settings = null
	_view.queue_redraw()


func _sample(label: String) -> void:
	_lines.append("%-44s draw %4d   objects %4d   primitives %5d" % [
		label,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])
