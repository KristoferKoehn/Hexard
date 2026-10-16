class_name ScoringRules
extends RefCounted

## Score table and formulas (docs/design.md §4). Values are data, not logic:
## the built-in defaults below match the design document, and a JSON file can
## override them for tuning without touching code.

const Grid := preload("res://src/core/hex_grid.gd")

const DEFAULT_PATH := "res://data/scoring.json"

const DEFAULTS := {
	"cluster_3": 5,
	"cluster_4": 10,
	"cluster_5": 25,
	"cluster_6_plus": 50,
	"cascade_multiplier": 1.5,
	"difficulty_easy": 0.5,
	"difficulty_normal": 1.0,
	"difficulty_hard": 2.0,
}

var values: Dictionary = {}


func _init(overrides: Dictionary = {}) -> void:
	values = DEFAULTS.duplicate()
	for key: String in overrides:
		values[key] = overrides[key]


## Loads the shipped table; falls back to built-in defaults when the file is
## missing or unreadable so the game can never fail to boot over a score table.
static func load_default(path: String = DEFAULT_PATH) -> ScoringRules:
	if not FileAccess.file_exists(path):
		return ScoringRules.new()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ScoringRules.new()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ScoringRules: %s is not a JSON object; using defaults" % path)
		return ScoringRules.new()
	return ScoringRules.new(_sanitise(parsed))


## JSON numbers arrive as floats; the table is integer counts and factors.
static func _sanitise(raw: Dictionary) -> Dictionary:
	var clean := {}
	for key: String in raw:
		if not DEFAULTS.has(key):
			continue
		var value: Variant = raw[key]
		if typeof(value) == TYPE_FLOAT:
			if key.begins_with("difficulty") or key == "cascade_multiplier":
				clean[key] = float(value)
			else:
				clean[key] = int(value)
		else:
			clean[key] = value
	return clean


# --- table access -----------------------------------------------------------

func base_for_cluster(size: int) -> int:
	if size <= 3:
		return int(values["cluster_3"])
	if size == 4:
		return int(values["cluster_4"])
	if size == 5:
		return int(values["cluster_5"])
	return int(values["cluster_6_plus"])


func cascade_multiplier(depth: int) -> float:
	if depth <= 1:
		return 1.0
	return pow(float(values["cascade_multiplier"]), depth - 1)


func difficulty_multiplier(difficulty: String = "normal") -> float:
	var key := "difficulty_" + difficulty
	if not values.has(key):
		return 1.0
	return float(values[key])


## base x level x difficulty x cascade, rounded to a whole point value.
func clear_score(base: int, level: int, cascade_depth: int = 1, difficulty: String = "normal") -> int:
	var raw := float(base) * float(maxi(level, 1))
	raw *= difficulty_multiplier(difficulty)
	raw *= cascade_multiplier(cascade_depth)
	return roundi(raw)
