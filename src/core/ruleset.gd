class_name Ruleset
extends RefCounted

## Tunable rules for a run (docs/design.md §3.1, §5, §11).

const ScoringRulesScript := preload("res://src/core/scoring_rules.gd")
const Pieces := preload("res://src/core/piece.gd")

enum RotationMode {
	## Reference behaviour: spin until a match or revert; no move is consumed
	## when nothing clears. This is the default — clearing is what moves the
	## board, which is what makes flowers and pearls an achievement.
	STRICT,
	## One 60-degree step per press; a non-matching position persists.
	## Friendlier, and a deliberate deviation from the reference.
	FREE,
}

const MAX_LEVEL := 7
## Combos needed to leave levels 1..6 (docs/design.md §5.1). A var so tests and
## future difficulty settings can rescale progression.
const DEFAULT_COMBO_THRESHOLDS := [50, 60, 70, 80, 90, 100]

## Refill spawn tables, indexed by level - 1 (docs/design.md §5.2). Bonus stars
## arrive at level 2, bombs at level 3; bombs get more frequent and shorter-fused
## as the level climbs. Chances are per refilled cell.
const DEFAULT_BONUS_STAR_CHANCE := [0.0, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
const DEFAULT_BOMB_CHANCE := [0.0, 0.0, 0.05, 0.05, 0.06, 0.06, 0.06]
const DEFAULT_BOMB_COUNTER := [0, 0, 9, 8, 7, 6, 5]

var rotation_mode: RotationMode = RotationMode.STRICT
var difficulty := "normal"
var level_combo_thresholds: Array[int] = []
var scoring: ScoringRules
## Marathon/Timed refill the board from the top; Survival does not.
var refills_board := true

var bonus_star_chance: Array[float] = []
var bomb_chance: Array[float] = []
var bomb_start_counters: Array[int] = []


func _init() -> void:
	level_combo_thresholds = []
	for value: int in DEFAULT_COMBO_THRESHOLDS:
		level_combo_thresholds.append(value)

	bonus_star_chance = []
	for value: float in DEFAULT_BONUS_STAR_CHANCE:
		bonus_star_chance.append(value)

	bomb_chance = []
	for value: float in DEFAULT_BOMB_CHANCE:
		bomb_chance.append(value)

	bomb_start_counters = []
	for value: int in DEFAULT_BOMB_COUNTER:
		bomb_start_counters.append(value)

	scoring = ScoringRulesScript.load_default()


static func strict_rotation() -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.rotation_mode = RotationMode.STRICT
	return ruleset


## Opt-in, friendlier rotation: non-clearing spins keep their position.
static func free_rotation() -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.rotation_mode = RotationMode.FREE
	return ruleset


## A ruleset with no specials spawning at all: every refill is a plain gem.
## Used by tests that are about something else, and handy as a calm practice mode.
static func gems_only() -> Ruleset:
	var ruleset := Ruleset.new()
	for index in ruleset.bonus_star_chance.size():
		ruleset.bonus_star_chance[index] = 0.0
		ruleset.bomb_chance[index] = 0.0
	return ruleset


func max_level() -> int:
	return level_combo_thresholds.size() + 1


## Combos required to advance from `level`. 0 at max level.
func combos_to_advance(level: int) -> int:
	if level < 1 or level > level_combo_thresholds.size():
		return 0
	return level_combo_thresholds[level - 1]


func colors_for_level(level: int) -> Array:
	return Pieces.colors_for_level(level)


func difficulty_multiplier() -> float:
	return scoring.difficulty_multiplier(difficulty)


func _table_entry(table: Array, level: int, fallback: Variant) -> Variant:
	if table.is_empty():
		return fallback
	return table[clampi(level - 1, 0, table.size() - 1)]


func bonus_star_chance_at(level: int) -> float:
	return float(_table_entry(bonus_star_chance, level, 0.0))


func bomb_chance_at(level: int) -> float:
	return float(_table_entry(bomb_chance, level, 0.0))


func bomb_counter_at(level: int) -> int:
	return int(_table_entry(bomb_start_counters, level, 0))
