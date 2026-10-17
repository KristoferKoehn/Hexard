class_name ScoringRules
extends RefCounted

## Score table and formulas (docs/design.md §4). Values are data, not logic:
## the built-in defaults below match the design document, and a JSON file can
## override them for tuning without touching code.

const DEFAULT_PATH := "res://data/scoring.json"

const DEFAULTS := {
	# Colour clusters.
	"cluster_3": 5,
	"cluster_4": 10,
	"cluster_5": 25,
	"cluster_6_plus": 50,
	"cascade_multiplier": 1.5,
	"difficulty_easy": 0.5,
	"difficulty_normal": 1.0,
	"difficulty_hard": 2.0,
	# Special formations (M2).
	"flower_base": 1000,            # forming a starflower from a flower
	"starflower_match_base": 2500,  # clearing three starflowers together
	"pearl_base": 10000,            # forming a black pearl
	"star_cluster_base": 1000,      # clearing three bonus stars (area clear)
	"pearl_cluster_base": 50000,    # perfect finish: a cluster of three pearls
	"pearl_ring_base": 250000,      # perfect finish: a ring of six pearls
	"bomb_defuse_base": 200,
	"bomb_colour_wipe_base": 500,
	"flower_sweep_base": 500,       # Survival: flower sweeps a whole colour
}

## Keys that hold fractional values; everything else is a whole point value.
const FLOAT_KEYS := [
	"cascade_multiplier", "difficulty_easy", "difficulty_normal", "difficulty_hard",
]

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


## JSON numbers arrive as floats; whole-point keys are cast back to int.
static func _sanitise(raw: Dictionary) -> Dictionary:
	var clean := {}
	for key: String in raw:
		if not DEFAULTS.has(key):
			continue
		var value: Variant = raw[key]
		if typeof(value) == TYPE_FLOAT:
			clean[key] = float(value) if FLOAT_KEYS.has(key) else int(value)
		else:
			clean[key] = value
	return clean


# --- table access -----------------------------------------------------------

func points(key: String) -> int:
	if not values.has(key):
		push_warning("ScoringRules: unknown score key '%s'" % key)
		return 0
	return int(values[key])


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


## Same, taking the base value from the table by name.
func score_for(key: String, level: int, cascade_depth: int = 1, difficulty: String = "normal") -> int:
	return clear_score(points(key), level, cascade_depth, difficulty)
