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

var rotation_mode: RotationMode = RotationMode.STRICT
var difficulty := "normal"
var level_combo_thresholds: Array[int] = []
var scoring: ScoringRules
## Marathon/Timed refill the board from the top; Survival does not.
var refills_board := true

## M2 hooks, already plumbed so the resolver does not need reshaping.
var bonus_stars_enabled := false
var bombs_enabled := false


func _init() -> void:
	level_combo_thresholds = []
	for value: int in DEFAULT_COMBO_THRESHOLDS:
		level_combo_thresholds.append(value)
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
