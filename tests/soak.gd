extends SceneTree

## Long soak run: thousands of random moves across rotation modes, asserting the board
## invariants the whole way (docs/design.md §10.3).
##
##   godot --headless --path . --script res://tests/soak.gd
##   godot --headless --path . --script res://tests/soak.gd -- 18000 4
##   (args: total moves, seeds per configuration)
##
## Not part of the default suite (run_tests.ps1 -Soak); it exists to shake out rare
## resolver/gravity/special-piece states that a few hundred moves never reach. A run
## that ends (bomb, pearl finish) is restarted, so the soak keeps exploring.
##
## Seeds matter for anything statistical. A single seed makes every comparison a
## different random walk rather than a measurement: changing one probability reshuffles
## the whole walk from the first bomb onward, so a delta between two single-seed soaks
## mixes the change with luck. Several seeds, aggregated, at least give a mean and a
## spread, and the total move budget is divided between them so the wall time does not
## change.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const MatchFinder := preload("res://src/core/match_finder.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")
const RngScript := preload("res://src/core/rng.gd")

const DEFAULT_MOVES := 10000
const DEFAULT_SEEDS := 3
const PROGRESS_EVERY := 2500
## Below this, a trial is too short to contain a run or two and the aggregate lies.
const MIN_MOVES_PER_SEED := 150
## Spread the trial seeds apart so successive trials do not share early draws.
const SEED_STRIDE := 7919

var _total := DEFAULT_MOVES
var _seeds := DEFAULT_SEEDS
var _failures: Array[String] = []
var _report: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_total = maxi(int(args[0]), 10)
	if args.size() > 1:
		_seeds = maxi(int(args[1]), 1)

	print("Hexard soak: %d moves across 3 configurations, %d seed(s) each" % [_total, _seeds])
	var share := int(_total / 3.0)
	_aggregate("marathon-free", share, RulesetScript.RotationMode.FREE, RulesetScript.Mode.MARATHON)
	_aggregate("marathon-strict", share, RulesetScript.RotationMode.STRICT, RulesetScript.Mode.MARATHON)
	_aggregate("survival", _total - share * 2, RulesetScript.RotationMode.FREE,
		RulesetScript.Mode.SURVIVAL)

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


## Runs `seeds` independent trials and reports the mean of each rate, with the per-seed
## lines underneath so an outlier is visible rather than averaged away.
func _aggregate(label: String, moves: int, rotation: int, run_mode: int) -> void:
	var per_seed := maxi(int(moves / float(_seeds)), MIN_MOVES_PER_SEED)
	var committed := 0
	var cleared := 0
	var special_moves := 0
	var shuffles := 0
	var runs := 0
	var finished := 0
	var defused := 0
	var explosions := 0
	var best_level := 1
	var endings := {}

	for trial in _seeds:
		var stats := _run_one(label, per_seed, rotation, run_mode, trial)
		committed += int(stats["committed"])
		cleared += int(stats["cleared"])
		special_moves += int(stats["special"])
		shuffles += int(stats["shuffles"])
		runs += int(stats["runs"])
		finished += int(stats["finished"])
		defused += int(stats["defused"])
		explosions += int(stats["explosions"])
		best_level = maxi(best_level, int(stats["best_level"]))
		for reason: String in stats["endings"]:
			endings[reason] = int(endings.get(reason, 0)) + int(stats["endings"][reason])
		_report.append(
			"    %s seed %d: %d moves, %d committed, %d cleared, %d finished runs, %d explosions, %d defused, level %d"
			% [label, trial + 1, per_seed, int(stats["committed"]), int(stats["cleared"]),
				int(stats["finished"]), int(stats["explosions"]), int(stats["defused"]),
				int(stats["best_level"])]
		)

	var trials := float(maxi(_seeds, 1))
	# Rates divide by FINISHED runs: `runs` also counts the game still in progress at the
	# end of a trial, which earlier made 14 explosions in 18 runs read as 0.78 per run
	# when every single finished run had exploded.
	var run_count := maxi(finished, 1)
	_report.append(
		"%s: %d seeds x %d moves | committed %.0f, cleared %.0f, special %.0f per trial | %d finished of %d runs | %d explosions (%.2f/finished), %d defused (%.2f/finished) | level %d | endings %s"
		% [
			label, _seeds, per_seed, committed / trials, cleared / trials, special_moves / trials,
			finished, runs, explosions, float(explosions) / float(run_count),
			defused, float(defused) / float(run_count), best_level, str(endings),
		]
	)


## One trial. Returns counts; the invariants are asserted here, because a broken board
## mid-trial is the thing the soak exists to catch.
func _run_one(label: String, moves: int, rotation: int, run_mode: int, trial: int) -> Dictionary:
	var ruleset := RulesetScript.new()
	ruleset.rotation_mode = rotation
	ruleset.mode = run_mode
	var refills := run_mode != RulesetScript.Mode.SURVIVAL

	var run_seed := 9001 + moves + trial * SEED_STRIDE
	var game := GameScript.new(run_seed, ruleset)
	var rng := RngScript.new(run_seed * 7 + 3)
	var vertices := Grid.vertices()
	var tag := "%s seed %d" % [label, trial + 1]

	var committed := 0
	var cleared := 0
	var defused := 0
	var finished_runs := 0
	var best_level := 1
	var runs := 1
	var endings := {}
	var special_moves := 0

	for step in moves:
		if step % PROGRESS_EVERY == 0 and step > 0:
			print("    %s: %d/%d moves ..." % [tag, step, moves])

		if game.state == GameScript.State.FINISHED:
			# Tally the ending HERE, from the state the game actually settled into.
			# Counting it from the move's result missed deaths that happen during
			# settle, which made the run count and the endings tally disagree by 4 in
			# an earlier soak - and every "bombs end every run" claim rested on it.
			runs += 1
			finished_runs += 1
			_record_ending(endings, game.finish_reason)
			game = GameScript.new(run_seed * 1000 + runs, ruleset)
			continue

		# Every so often, turn a starflower or pearl instead of a trio: this is what
		# exercises the ring and Y-rotation paths.
		var special := _find_special_cell(game.board)
		var result
		if special != Vector2i(-1, -1) and step % 5 == 0:
			special_moves += 1
			result = game.rotate_piece(special, 1 if rng.next_int(2) == 0 else -1)
		else:
			result = game.rotate(rng.next_int(vertices.size()), 1 if rng.next_int(2) == 0 else -1)

		if result.committed:
			committed += 1
			cleared += result.cleared_count
			defused += result.bombs_defused
		best_level = maxi(best_level, game.level)

		if game.board.invariant_violations().size() > 0:
			_failures.append("%s step %d: floating pieces" % [tag, step])
			print(game.board.to_ascii())
			for violation: String in game.board.invariant_violations():
				print("      ", violation)
			break
		if game.score < 0:
			_failures.append("%s step %d: negative score" % [tag, step])
			break
		if refills and game.state == GameScript.State.PLAYING and game.tile_count() != 85:
			_failures.append("%s step %d: board not full (%d)" % [tag, step, game.tile_count()])
			break
		if game.state == GameScript.State.PLAYING and MatchFinder.has_any_match(game.board):
			_failures.append("%s step %d: board left unstable" % [tag, step])
			break

	# The final game may have ended on the last move and never been replaced.
	if game.state == GameScript.State.FINISHED:
		runs += 1
		finished_runs += 1
		_record_ending(endings, game.finish_reason)

	return {
		"committed": committed, "cleared": cleared, "special": special_moves,
		"shuffles": game.shuffle_count, "runs": runs, "finished": finished_runs,
		"defused": defused,
		"explosions": int(endings.get("bomb_exploded", 0)),
		"endings": endings, "best_level": best_level,
	}


func _record_ending(endings: Dictionary, reason: String) -> void:
	endings[reason] = int(endings.get(reason, 0)) + 1


func _find_special_cell(board: Board) -> Vector2i:
	for cell: Vector2i in Grid.all_cells():
		var piece: int = board.get_piece(cell)
		if Pieces.is_starflower(piece) or Pieces.is_pearl(piece):
			return cell
	return Vector2i(-1, -1)
