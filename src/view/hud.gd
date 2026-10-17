class_name Hud
extends CanvasLayer

## Dev HUD: score, level, combos to the next level, turn, bombs, pearls, seed
## and one status line. Labels are created in code so the scene stays trivial.

const RulesetScript := preload("res://src/core/ruleset.gd")
const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")

const INFO_FONT_SIZE := 22
const MESSAGE_FONT_SIZE := 18

var _info: Label
var _message: Label
var _controls: Label


func _ready() -> void:
	# Everything below the board: the board occupies roughly y 84..588 at the
	# default 1280x720 window (see BoardView.cell_size).
	_info = _make_label(Vector2(18, 14), INFO_FONT_SIZE, Color("eef1f7"))
	_message = _make_label(Vector2(18, 626), MESSAGE_FONT_SIZE, Color("ffd166"))
	_controls = _make_label(Vector2(18, 678), 15, Color(0.75, 0.79, 0.87))
	_controls.text = "arrows/WASD: move   ·   Z/X or click: rotate   ·   F: turn a starflower/pearl   ·   H: hint   ·   R: new board   ·   T: rotation mode   ·   Esc: quit"


func _make_label(position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


func update_from_game(game: RefCounted) -> void:
	if _info == null or game == null:
		return
	var mode := "STRICT" if _is_strict(game) else "FREE"
	var over := "" if int(game.state) == 0 else "   RUN OVER"
	_info.text = (
		"SCORE %d   LEVEL %d   COMBOS TO NEXT %d   TURN %d   BOMBS %d   PEARLS %d   SEED %d   [%s]%s"
		% [
			game.score, game.level, game.combos_remaining(), game.turns,
			_count(game.board, Pieces.Kind.BOMB), _count(game.board, Pieces.Kind.PEARL),
			game.seed_value, mode, over,
		]
	)


func set_message(text: String) -> void:
	if _message != null:
		_message.text = text


func _count(board, kind: int) -> int:
	var total := 0
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if not Pieces.is_empty(piece) and Pieces.kind_of(piece) == kind:
			total += 1
	return total


func _is_strict(game: RefCounted) -> bool:
	var ruleset: Variant = game.ruleset
	return int(ruleset.rotation_mode) == int(RulesetScript.RotationMode.STRICT)
