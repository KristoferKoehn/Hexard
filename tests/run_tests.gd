extends SceneTree

## Headless test runner (no plugin dependency).
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 0 when everything passes, 1 otherwise, so it works as a CI gate.
##
## NOTE: quit() called from _initialize() does not stop the main loop in
## Godot 4.7, so _process() returns true as the actual terminator while
## quit() records the exit code.

const TEST_SCRIPTS := [
	"res://tests/test_hex_grid.gd",
	"res://tests/test_rng.gd",
	"res://tests/test_board.gd",
	"res://tests/test_match.gd",
	"res://tests/test_scoring.gd",
	"res://tests/test_game.gd",
	"res://tests/test_specials.gd",
	"res://tests/test_modes.gd",
	"res://tests/test_tutorial.gd",
]


func _initialize() -> void:
	print("Hexard core tests — ", Time.get_datetime_string_from_system())
	var total := 0
	var failed := 0
	var assertions := 0
	var all_failures: Array[String] = []

	for path in TEST_SCRIPTS:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			# A parse error must fail the run loudly, never pass silently.
			total += 1
			failed += 1
			print("\n== %s ==" % path.get_file())
			print("  FAIL  <script did not compile>")
			all_failures.append("could not load or compile %s" % path)
			continue
		var suite = script.new()
		if not suite.has_method("run_all"):
			total += 1
			failed += 1
			all_failures.append("%s does not extend tests/test_case.gd" % path)
			continue
		var results: Array = suite.run_all()
		assertions += int(suite.get("assertions"))
		print("\n== %s ==" % path.get_file())
		for result: Dictionary in results:
			total += 1
			var messages: Array = result["failures"]
			var passed := messages.is_empty()
			if not passed:
				failed += 1
			print("  %s  %s" % ["PASS" if passed else "FAIL", result["name"]])
			for message: String in messages:
				print("        - %s" % message)
				all_failures.append("%s::%s — %s" % [path.get_file(), result["name"], message])

	print("\n%d tests, %d failed, %d assertions" % [total, failed, assertions])
	if failed == 0:
		print("RESULT: OK")
	else:
		print("RESULT: FAILED")
		for message in all_failures:
			print("  ! ", message)
	quit(1 if failed > 0 else 0)


func _process(_delta: float) -> bool:
	return true
