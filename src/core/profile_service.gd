class_name ProfileService
extends RefCounted

## Persistent player profile: lifetime stats, personal bests and a local
## leaderboard (docs/design.md §9).
##
## Deliberately engine-free and path-injectable so it can be tested headless;
## the game points it at DEFAULT_PATH, tests point it at a workspace file.

const VERSION := 1
const DEFAULT_PATH := "user://hexard_profile.json"
const LEADERBOARD_SIZE := 10

## Lifetime counters. Every key starts at zero and only ever accumulates.
const TOTAL_KEYS := [
	"games", "wins", "losses", "score", "combos", "cleared", "turns", "rounds",
	"pearls", "starflowers", "bombs_defused", "time_played", "best_level",
]

var totals: Dictionary = {}
## "mode|difficulty" -> {score, level, won, date}
var bests: Dictionary = {}
## "mode|difficulty" -> Array of run entries, highest score first
var boards: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	achievements.clear()
	totals = {}
	for key: String in TOTAL_KEYS:
		totals[key] = 0
	bests = {}
	boards = {}


## One table key per mode and difficulty, so a Marathon score never competes with
## a Timed one.
static func table_key(mode: String, difficulty: String) -> String:
	return "%s|%s" % [mode, difficulty.to_lower()]


# --- recording --------------------------------------------------------------

## Folds a finished run (`Game.summary()`) into the profile. Returns the table
## key it went into, so the caller can show the updated board.
func record_run(summary: RunSummary, stamp: String = "") -> String:
	var mode := summary.mode
	var difficulty := summary.difficulty
	var key := table_key(mode, difficulty)
	var score := summary.score
	var level := summary.level
	var won := summary.won

	totals["games"] += 1
	totals["wins"] += 1 if won else 0
	totals["losses"] += 0 if won else 1
	totals["score"] += score
	totals["combos"] += summary.combos
	totals["cleared"] += summary.cleared
	totals["turns"] += summary.turns
	totals["rounds"] += summary.rounds
	totals["pearls"] += summary.pearls
	totals["starflowers"] += summary.starflowers
	totals["bombs_defused"] += summary.bombs_defused
	totals["time_played"] += int(round(summary.elapsed))
	totals["best_level"] = maxi(int(totals["best_level"]), level)

	if not bests.has(key) or score > int(bests[key]["score"]):
		bests[key] = {
			"score": score, "level": level, "won": won,
			"reason": summary.reason, "date": stamp,
		}

	var entry := {
		"score": score,
		"level": level,
		"won": won,
		"reason": summary.reason,
		"mode": mode,
		"difficulty": difficulty,
		"turns": summary.turns,
		"seed": summary.seed_value,
		"date": stamp,
	}
	var board: Array = boards.get(key, [])
	board.append(entry)
	board.sort_custom(_higher_score_first)
	if board.size() > LEADERBOARD_SIZE:
		board.resize(LEADERBOARD_SIZE)
	boards[key] = board
	return key


static func _higher_score_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	if int(a["level"]) != int(b["level"]):
		return int(a["level"]) > int(b["level"])
	return str(a["date"]) > str(b["date"])


# --- queries ----------------------------------------------------------------

func games_played() -> int:
	return int(totals.get("games", 0))


func best_for(mode: String, difficulty: String) -> Dictionary:
	var key := table_key(mode, difficulty)
	if bests.has(key):
		return bests[key]
	return {"score": 0, "level": 0, "won": false, "reason": "", "date": ""}


func top_scores(mode: String, difficulty: String, limit: int = 5) -> Array:
	var board: Array = boards.get(table_key(mode, difficulty), [])
	var out: Array = []
	for entry: Dictionary in board:
		if out.size() >= limit:
			break
		out.append(entry)
	return out


## Every mode/difficulty pair that has at least one recorded run.
func played_tables() -> Array[String]:
	var keys: Array[String] = []
	for key: String in boards:
		keys.append(key)
	keys.sort()
	return keys


# --- persistence ------------------------------------------------------------

## Achievement ids that have been earned. Keys only: the value is always true, and
## a dictionary keeps lookup and persistence trivial.
var achievements: Dictionary = {}


func has_achievement(id: String) -> bool:
	return achievements.has(id)


## Earns an achievement. Returns true only the first time, so the caller can announce
## it once instead of on every run that satisfies it again.
func unlock(id: String) -> bool:
	if id.is_empty() or achievements.has(id):
		return false
	achievements[id] = true
	return true


func achievement_count() -> int:
	return achievements.size()


func to_dictionary() -> Dictionary:
	return {
		"version": VERSION,
		"totals": totals.duplicate(true),
		"bests": bests.duplicate(true),
		"boards": boards.duplicate(true),
		"achievements": achievements.duplicate(true),
	}


## A missing or corrupt file leaves a fresh profile in place rather than failing:
## losing a leaderboard is bad, refusing to start is worse.
func load_from(path: String = DEFAULT_PATH) -> bool:
	var data := JsonStore.read(path)
	if data.is_empty():
		return false
	apply_dictionary(data)
	return true


func apply_dictionary(data: Dictionary) -> void:
	reset()
	var loaded_achievements: Variant = data.get("achievements", null)
	if typeof(loaded_achievements) == TYPE_DICTIONARY:
		for key: Variant in loaded_achievements:
			if bool(loaded_achievements[key]):
				achievements[str(key)] = true
	var loaded_totals: Variant = data.get("totals", null)
	if typeof(loaded_totals) == TYPE_DICTIONARY:
		for key: String in TOTAL_KEYS:
			if loaded_totals.has(key):
				totals[key] = int(loaded_totals[key])
	var loaded_bests: Variant = data.get("bests", null)
	if typeof(loaded_bests) == TYPE_DICTIONARY:
		for key: String in loaded_bests:
			var entry: Variant = loaded_bests[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			bests[key] = {
				"score": int(entry.get("score", 0)),
				"level": int(entry.get("level", 0)),
				"won": bool(entry.get("won", false)),
				"reason": str(entry.get("reason", "")),
				"date": str(entry.get("date", "")),
			}
	var loaded_boards: Variant = data.get("boards", null)
	if typeof(loaded_boards) == TYPE_DICTIONARY:
		for key: String in loaded_boards:
			var rows: Variant = loaded_boards[key]
			if typeof(rows) != TYPE_ARRAY:
				continue
			var board: Array = []
			for row: Variant in rows:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				board.append(row)
			board.sort_custom(_higher_score_first)
			if board.size() > LEADERBOARD_SIZE:
				board.resize(LEADERBOARD_SIZE)
			boards[key] = board


func save_to(path: String = DEFAULT_PATH) -> bool:
	return JsonStore.write(path, to_dictionary())
