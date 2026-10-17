class_name ScoringRules
extends RefCounted

## Score table and formulas (docs/design.md §4).
##
## The names below are the single source of truth for the table's keys; the
## values live in the built-in defaults and can be overridden by data/scoring.json
## so balance can be tuned without touching code.

const DEFAULT_PATH := "res://data/scoring.json"

# --- keys -------------------------------------------------------------------
const CLUSTER_3 := "cluster_3"
const CLUSTER_4 := "cluster_4"
const CLUSTER_5 := "cluster_5"
const CLUSTER_6_PLUS := "cluster_6_plus"
const FLOWER_BASE := "flower_base"
const FLOWER_SWEEP_BASE := "flower_sweep_base"
const STARFLOWER_MATCH_BASE := "starflower_match_base"
const PEARL_BASE := "pearl_base"
const STAR_CLUSTER_BASE := "star_cluster_base"
const PEARL_CLUSTER_BASE := "pearl_cluster_base"
const PEARL_RING_BASE := "pearl_ring_base"
const BOMB_DEFUSE_BASE := "bomb_defuse_base"
const BOMB_COLOUR_WIPE_BASE := "bomb_colour_wipe_base"
const CASCADE_MULTIPLIER := "cascade_multiplier"
const DIFFICULTY_EASY := "difficulty_easy"
const DIFFICULTY_NORMAL := "difficulty_normal"
const DIFFICULTY_HARD := "difficulty_hard"

const DEFAULTS := {
	CLUSTER_3: 5,
	CLUSTER_4: 10,
	CLUSTER_5: 25,
	CLUSTER_6_PLUS: 50,
	CASCADE_MULTIPLIER: 1.5,
	DIFFICULTY_EASY: 0.5,
	DIFFICULTY_NORMAL: 1.0,
	DIFFICULTY_HARD: 2.0,
	FLOWER_BASE: 1000,            # forming a starflower from a flower
	STARFLOWER_MATCH_BASE: 2500,  # clearing three starflowers together
	PEARL_BASE: 10000,            # forming a black pearl
	STAR_CLUSTER_BASE: 1000,      # clearing three bonus stars (area clear)
	PEARL_CLUSTER_BASE: 50000,    # perfect finish: a cluster of three pearls
	PEARL_RING_BASE: 250000,      # perfect finish: a ring of six pearls
	BOMB_DEFUSE_BASE: 200,
	BOMB_COLOUR_WIPE_BASE: 500,
	FLOWER_SWEEP_BASE: 500,       # Survival: a flower sweeps a whole colour
}

## Keys that hold fractional values; everything else is a whole point value.
const FLOAT_KEYS := [CASCADE_MULTIPLIER, DIFFICULTY_EASY, DIFFICULTY_NORMAL, DIFFICULTY_HARD]

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


# --- formulas ---------------------------------------------------------------

func points(key: String) -> int:
	if not values.has(key):
		push_warning("ScoringRules: unknown score key '%s'" % key)
		return 0
	return int(values[key])


func base_for_cluster(size: int) -> int:
	if size <= 3:
		return points(CLUSTER_3)
	if size == 4:
		return points(CLUSTER_4)
	if size == 5:
		return points(CLUSTER_5)
	return points(CLUSTER_6_PLUS)


func cascade_multiplier(depth: int) -> float:
	if depth <= 1:
		return 1.0
	return pow(float(values[CASCADE_MULTIPLIER]), depth - 1)


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
