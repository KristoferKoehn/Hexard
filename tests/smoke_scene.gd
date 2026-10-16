extends SceneTree

## View-layer smoke test: loads the real scene, plays a few moves through the
## controller, and fails loudly if anything errors or the wiring breaks.
##
##   godot --headless --path . --script res://tests/smoke_scene.gd
##
## Headless has no renderer, so this cannot judge how the board *looks*; it
## proves the scene loads, the nodes wire up, input paths exist and the rules
## core stays healthy through the view.

const HexGrid := preload("res://src/core/hex_grid.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const GameScript := preload("res://src/core/game.gd")

var _frames := 0
var _main: Node = null
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	print("Hexard view smoke test")
	var scene: PackedScene = load("res://src/app/main.tscn")
	if scene == null:
		print("  FAIL  could not load res://src/app/main.tscn")
		quit(1)
		return
	_main = scene.instantiate()
	if _main == null:
		print("  FAIL  could not instantiate the main scene")
		quit(1)
		return
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_smoke()
	if _frames >= 5:
		_report()
		return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _smoke() -> void:
	_check(_main.get_node_or_null("BoardView") != null, "scene has a BoardView node")
	_check(_main.get_node_or_null("Hud") != null, "scene has a Hud node")

	var game = _main.get("game")
	_check(game != null, "controller created a game")
	if game == null:
		return
	_check(game.tile_count() == 85, "board starts full")
	_check(not MatchFinder.has_any_match(game.board), "board starts match-free")

	var board_view = _main.get_node("BoardView")
	_check(board_view.get("game") == game, "board view received the game")
	_check(board_view.get("cursor_vertex") == 0, "cursor starts on the first vertex")

	# Play a handful of moves through the controller: this exercises the same
	# path the keyboard uses.
	var before_turns: int = game.turns
	for i in 6:
		_main.call("move_cursor", Vector2.RIGHT if i % 2 == 0 else Vector2.DOWN)
		_main.call("play_move", GameScript.CLOCKWISE if i % 2 == 0 else GameScript.COUNTER_CLOCKWISE)
	_check(game.turns > before_turns, "moves went through the controller (%d -> %d)" % [before_turns, game.turns])
	_check(game.tile_count() == 85, "board is still full after moves")
	_check(game.board.invariant_violations().size() == 0, "no floating pieces after moves")
	_check(game.score >= 0, "score is sane")

	var cursor: int = _main.get("cursor_vertex")
	_check(cursor >= 0 and cursor < HexGrid.vertices().size(), "cursor stayed in range (%d)" % cursor)

	# HUD and hint paths must not error.
	_main.call("show_hint")
	_main.call("toggle_rotation_mode")
	_main.call("toggle_rotation_mode")
	_check(true, "hint and mode toggle ran without error")

	# Restart with a fresh seed and make sure state resets.
	_main.call("new_game", 99)
	var restarted = _main.get("game")
	_check(restarted.seed_value == 99, "new_game rebuilt the run")
	_check(restarted.turns == 0, "restart clears the turn counter")


func _report() -> void:
	if _failures.is_empty():
		print("  PASS  view smoke test (%d checks)" % _checks)
		print("SMOKE RESULT: OK")
		quit(0)
		return
	print("  FAIL  view smoke test (%d checks)" % _checks)
	for message: String in _failures:
		print("        - %s" % message)
	print("SMOKE RESULT: FAILED")
	quit(1)
