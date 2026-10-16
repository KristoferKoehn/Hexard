extends SceneTree

## Long soak run: thousands of random moves across rotation modes, asserting the
## board invariants the whole way (docs/design.md §10.3).
##
##   godot --headless --path . --script res://tests/soak.gd
##   godot --headless --path . --script res://tests/soak.gd -- 20000
##
## Not part of the default suite (run_tests.ps1 -Soak); it exists to shake out
## rare resolver/gravity states that a few hundred moves never reach.

const Grid := preload("res://src/core/hex_grid.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const RngScript := preload("res://src/core/rng.gd")

const DEFAULT_MOVES := 10000
const PROGRESS_EVERY := 2500

var _total := DEFAULT_MOVES
var _failures: Array[String] = []
var _report: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_total = maxi(int(args[0]), 10)

	print("Hexard soak: %d random moves across 3 configurations" % _total)
	var share := int(_total / 3.0)
	_run_configuration("marathon-free", share, RulesetScript.RotationMode.FREE, true)
	_run_configuration("marathon-strict", share, RulesetScript.RotationMode.STRICT, true)
	_run_configuration("survival-like", _total - share * 2, RulesetScript.RotationMode.FREE, false)

	for line: String in _report:
		print("  ", line)
	if _failures.is_empty():
		print("SOAK RESULT: OK")
		quit(0)
	else:
		for message: String in _failures:
			print("  ! ", message)
		print("SOAK RESULT: FAILED")
		quit(1)


func _process(_delta: float) -> bool:
	return true


func _run_configuration(label: String, moves: int, mode: int, refills: bool) -> void:
	var ruleset := RulesetScript.new()
	ruleset.rotation_mode = mode
	ruleset.refills_board = refills

	var run_seed := 9001 + moves
	var game := GameScript.new(run_seed, ruleset)
	var rng := RngScript.new(run_seed * 7 + 3)
	var vertices := Grid.vertices()

	var committed := 0
	var cleared := 0
	var best_level := 1
	for step in moves:
		var vertex_index := rng.next_int(vertices.size())
		var direction := 1 if rng.next_int(2) == 0 else -1
		var result = game.rotate(vertex_index, direction)
		if result.committed:
			committed += 1
			cleared += result.cleared_count
		best_level = maxi(best_level, game.level)

		if step % PROGRESS_EVERY == 0 and step > 0:
			print("    %s: %d/%d moves ..." % [label, step, moves])

		if game.board.invariant_violations().size() > 0:
			_failures.append("%s step %d: floating pieces" % [label, step])
			print(game.board.to_ascii())
			for violation: String in game.board.invariant_violations():
				print("      ", violation)
			print("      turn log tail: ", game.commands().slice(maxi(game.commands().size() - 4, 0)))
			break
		if game.score < 0:
			_failures.append("%s step %d: negative score" % [label, step])
			break
		if refills and game.tile_count() != 85:
			_failures.append("%s step %d: board not full (%d)" % [label, step, game.tile_count()])
			break
		if MatchFinder.has_any_match(game.board):
			_failures.append("%s step %d: board left unstable" % [label, step])
			break

	_report.append(
		"%s: %d moves, %d committed, %d gems cleared, %d shuffles, score %d, level %d" % [
			label, moves, committed, cleared, game.shuffle_count, game.score, best_level,
		]
	)
