class_name Ruleset
extends RefCounted

## Tunable rules for a run (docs/design.md §3.1, §5, §6, §11).

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

enum Mode {
	## Endless: always refills, bombs and specials escalate with level.
	MARATHON,
	## Marathon plus a countdown that clears and starflowers buy back.
	TIMED,
	## No refills during a round; locked leftovers pile up until you clear the
	## board or suffocate.
	SURVIVAL,
}

const MAX_LEVEL := 7
## Combos needed to leave levels 1..6 (docs/design.md §5.1). A var so tests and
## future difficulty settings can rescale progression.
const DEFAULT_COMBO_THRESHOLDS := [50, 60, 70, 80, 90, 100]

## Refill spawn tables, indexed by level - 1 (docs/design.md §5.2). Bonus stars
## arrive at level 2, bombs at level 3; bombs get more frequent and shorter-fused
## as the level climbs. Chances are per refilled cell.
const DEFAULT_BONUS_STAR_CHANCE := [0.0, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
## Ten percent rarer than the first pass, because the soak showed bombs ending 24 of 26
## marathon runs: a mode with one dominant failure mode is a design smell, and this is
## the smallest lever on it. Fuse lengths are unchanged, so a bomb that arrives is still
## as dangerous - it just arrives less often.
const DEFAULT_BOMB_CHANCE := [0.0, 0.0, 0.045, 0.045, 0.054, 0.054, 0.054]
const DEFAULT_BOMB_COUNTER := [0, 0, 9, 8, 7, 6, 5]

# --- Timed mode (docs/design.md §6.2) ---------------------------------------
const TIMED_CAP := 120.0
const TIMED_STARFLOWER_BONUS := 10.0
const TIMED_PER_GEM := 0.25
const TIMED_PER_COMBO := 1.0
const TIMED_START := {"easy": 60.0, "normal": 50.0, "hard": 40.0}

# --- Survival mode (docs/design.md §6.3) ------------------------------------
const SURVIVAL_ROUNDS_TO_WIN := 50
## Points per gem cleared in a Survival round, paid when the round ends.
const SURVIVAL_ROUND_BONUS_PER_GEM := 10

var rotation_mode: RotationMode = RotationMode.STRICT
var mode: Mode = Mode.MARATHON
var difficulty := "normal"
var level_combo_thresholds: Array[int] = []
var scoring: ScoringRules

var bonus_star_chance: Array[float] = []
var bomb_chance: Array[float] = []
var bomb_start_counters: Array[int] = []

## Survival and Timed do not refill mid-round; Marathon always does.
var refills_board: bool:
	get:
		return mode != Mode.SURVIVAL

## Survival has no bonus stars, starflowers or pearls (docs/design.md §6.3).
var spawns_specials: bool:
	get:
		return mode != Mode.SURVIVAL


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
static func gems_only() -> Ruleset:
	var ruleset := Ruleset.new()
	for index in ruleset.bonus_star_chance.size():
		ruleset.bonus_star_chance[index] = 0.0
		ruleset.bomb_chance[index] = 0.0
	return ruleset


## A configured run: mode plus difficulty, the two knobs a player picks.
static func for_run(config: RunConfig) -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.mode = config.mode
	ruleset.difficulty = config.difficulty
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
	if not spawns_specials:
		return 0.0
	return float(_table_entry(bonus_star_chance, level, 0.0))


func bomb_chance_at(level: int) -> float:
	if mode == Mode.SURVIVAL:
		return 0.0
	var base := float(_table_entry(bomb_chance, level, 0.0))
	match difficulty:
		"easy":
			return base * 0.6
		"hard":
			return base * 1.4
	return base


func bomb_counter_at(level: int) -> int:
	var base := int(_table_entry(bomb_start_counters, level, 0))
	if base <= 0:
		return 0
	match difficulty:
		"easy":
			return base + 2
		"hard":
			return maxi(base - 1, 2)
	return base


## Seconds on the clock when a Timed run starts.
func timed_start_seconds() -> float:
	return float(TIMED_START.get(difficulty, TIMED_START["normal"]))
