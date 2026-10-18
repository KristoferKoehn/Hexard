class_name RunConfig
extends RefCounted

## What run is being played: a mode and a difficulty, which only ever travel together.
##
## Menu state, ruleset construction and the leaderboard key all need the pair. As two
## loose variables — `selected_mode` and `selected_difficulty` — any caller could
## change one and forget the other, and the menu's vocabulary (which modes and
## difficulties exist, in what order) was duplicated between the HUD and the controller.
##
## `key()` deliberately matches the format earlier versions wrote, so existing
## leaderboard files keep working.

const RulesetScript := preload("res://src/core/ruleset.gd")

const MODES: Array[int] = [
	RulesetScript.Mode.MARATHON,
	RulesetScript.Mode.TIMED,
	RulesetScript.Mode.SURVIVAL,
]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]

var mode: int = RulesetScript.Mode.MARATHON
var difficulty := "normal"


static func of(run_mode: int, run_difficulty: String = "normal") -> RunConfig:
	var config := RunConfig.new()
	config.mode = run_mode
	config.difficulty = run_difficulty if DIFFICULTIES.has(run_difficulty) else "normal"
	return config


static func from_ruleset(ruleset: Ruleset) -> RunConfig:
	return of(int(ruleset.mode), str(ruleset.difficulty))


## From the printed mode name that saved leaderboards use ("Marathon").
static func from_name(mode_text: String, run_difficulty: String = "normal") -> RunConfig:
	for candidate: int in MODES:
		if mode_name_of(candidate) == mode_text:
			return of(candidate, run_difficulty)
	return of(RulesetScript.Mode.MARATHON, run_difficulty)


static func mode_name_of(candidate: int) -> String:
	match candidate:
		RulesetScript.Mode.TIMED:
			return "Timed"
		RulesetScript.Mode.SURVIVAL:
			return "Survival"
		_:
			return "Marathon"


func mode_name() -> String:
	return mode_name_of(mode)


## Stable persistence key: "<ModeName>|<difficulty>".
func key() -> String:
	return "%s|%s" % [mode_name(), difficulty.to_lower()]


func label() -> String:
	return "%s · %s" % [mode_name(), difficulty.capitalize()]


## Cycling for the menu, so the ordering lives next to the vocabulary rather than in
## two parallel arrays inside the controller.
func next_mode(step: int) -> RunConfig:
	return of(MODES[posmod(MODES.find(mode) + step, MODES.size())], difficulty)


func next_difficulty(step: int) -> RunConfig:
	return of(mode, DIFFICULTIES[posmod(DIFFICULTIES.find(difficulty) + step, DIFFICULTIES.size())])
