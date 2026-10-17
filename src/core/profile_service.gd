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
func record_run(summary: Dictionary, stamp: String = "") -> String:
	var mode := str(summary.get("mode", "Marathon"))
	var difficulty := str(summary.get("difficulty", "normal"))
	var key := table_key(mode, difficulty)
	var score := int(summary.get("score", 0))
	var level := int(summary.get("level", 1))
	var won := bool(summary.get("won", false))

	totals["games"] += 1
	totals["wins"] += 1 if won else 0
	totals["losses"] += 0 if won else 1
	totals["score"] += score
	totals["combos"] += int(summary.get("combos", 0))
	totals["cleared"] += int(summary.get("cleared", 0))
	totals["turns"] += int(summary.get("turns", 0))
	totals["rounds"] += int(summary.get("rounds", 0))
	totals["pearls"] += int(summary.get("pearls", 0))
	totals["starflowers"] += int(summary.get("starflowers", 0))
	totals["bombs_defused"] += int(summary.get("bombs_defused", 0))
	totals["time_played"] += int(round(float(summary.get("elapsed", 0.0))))
	totals["best_level"] = maxi(int(totals["best_level"]), level)

	if not bests.has(key) or score > int(bests[key]["score"]):
		bests[key] = {
			"score": score, "level": level, "won": won,
			"reason": str(summary.get("reason", "")), "date": stamp,
		}

	var entry := {
		"score": score,
		"level": level,
		"won": won,
		"reason": str(summary.get("reason", "")),
		"mode": mode,
		"difficulty": difficulty,
		"turns": int(summary.get("turns", 0)),
		"seed": int(summary.get("seed", 0)),
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

func to_dictionary() -> Dictionary:
	return {
		"version": VERSION,
		"totals": totals.duplicate(true),
		"bests": bests.duplicate(true),
		"boards": boards.duplicate(true),
	}


## A missing or corrupt file leaves a fresh profile in place rather than failing:
## losing a leaderboard is bad, refusing to start is worse.
func load_from(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	apply_dictionary(parsed)
	return true


func apply_dictionary(data: Dictionary) -> void:
	reset()
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
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ProfileService: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	file.close()
	return true
