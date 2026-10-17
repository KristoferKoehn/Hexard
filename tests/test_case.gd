extends RefCounted

## Minimal assertion harness — no plugin dependency, runs headless.
## Suites extend this with "res://tests/test_case.gd" and define test_* methods.

var failures: Array[String] = []
var assertions := 0
var _current_test := ""


## Runs every test_* method in a deterministic (alphabetical) order.
func run_all() -> Array[Dictionary]:
	var names: Array[String] = []
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()

	var results: Array[Dictionary] = []
	for test_name in names:
		_current_test = test_name
		failures = []
		callv(test_name, [])
		results.append({"name": test_name, "failures": failures.duplicate()})
	return results


# --- assertions -------------------------------------------------------------

func assert_true(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		_record("expected true: " + message)


func assert_false(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		_record("expected false: " + message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		_record("%s — expected %s, got %s" % [message, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	assertions += 1
	if actual == unexpected:
		_record("%s — value should not equal %s" % [message, str(unexpected)])


func assert_ge(actual: Variant, minimum: Variant, message: String) -> void:
	assertions += 1
	if actual < minimum:
		_record("%s — expected >= %s, got %s" % [message, str(minimum), str(actual)])


func assert_gt(actual: Variant, minimum: Variant, message: String) -> void:
	assertions += 1
	if actual <= minimum:
		_record("%s — expected > %s, got %s" % [message, str(minimum), str(actual)])


func assert_le(actual: Variant, maximum: Variant, message: String) -> void:
	assertions += 1
	if actual > maximum:
		_record("%s — expected <= %s, got %s" % [message, str(maximum), str(actual)])


func assert_lt(actual: Variant, maximum: Variant, message: String) -> void:
	assertions += 1
	if actual >= maximum:
		_record("%s — expected < %s, got %s" % [message, str(maximum), str(actual)])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_record("%s — expected %.6f ± %.6f, got %.6f" % [message, expected, tolerance, actual])


func fail(message: String) -> void:
	assertions += 1
	_record(message)


func info(message: String) -> void:
	print("       · ", message)


func _record(message: String) -> void:
	failures.append("%s: %s" % [_current_test, message])
