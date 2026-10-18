class_name Achievements
extends RefCounted

## What a run earned, in one place (docs/design.md §9).
##
## Deliberately data-driven and engine-free: the definitions are a plain list, and
## whether one is met is a pure question about a RunSummary plus the lifetime totals.
## That means the whole achievement set can be tested without playing a game, and a
## new one is a row rather than a code path.
##
## Predicates are a match on the id rather than lambdas in the table: GDScript cannot
## put a capturing closure in a const, and a table of ids is easier to extend safely.

const LIST := [
	{
		"id": "first_steps",
		"title": "First Steps",
		"hint": "Clear your first gems.",
	},
	{
		"id": "combo_five",
		"title": "Chain Reaction",
		"hint": "Reach a 5-combo in one run.",
	},
	{
		"id": "ten_thousand",
		"title": "Five Figures",
		"hint": "Score 10,000 in a single run.",
	},
	{
		"id": "level_five",
		"title": "Rising Tide",
		"hint": "Reach level 5.",
	},
	{
		"id": "bloom",
		"title": "Bloom",
		"hint": "Make a starflower.",
	},
	{
		"id": "pearl",
		"title": "Black Pearl",
		"hint": "Make a pearl.",
	},
	{
		"id": "pearl_ring",
		"title": "The Grand One",
		"hint": "Finish a run with a ring of six black pearls.",
	},
	{
		"id": "defuser",
		"title": "Bomb Disposal",
		"hint": "Defuse a bomb.",
	},
	{
		"id": "survivor",
		"title": "Survivor",
		"hint": "Clear five rounds in Survival.",
	},
	{
		"id": "survival_win",
		"title": "Last One Standing",
		"hint": "Win a Survival run.",
	},
	{
		"id": "long_haul",
		"title": "Long Haul",
		"hint": "Play 150 turns in one run.",
	},
	{
		"id": "veteran",
		"title": "Veteran",
		"hint": "Finish 25 runs.",
	},
]


## Ids earned by this run that were not earned before. `totals` is the lifetime
## counters from ProfileService, so achievements that are about accumulation (run
## count, total clears) work on the same footing as single-run ones.
static func evaluate(summary: RunSummary, totals: Dictionary, already: Dictionary) -> Array[String]:
	var earned: Array[String] = []
	if summary == null:
		return earned
	for entry: Dictionary in LIST:
		var id := str(entry["id"])
		if already.has(id):
			continue
		if meets(id, summary, totals):
			earned.append(id)
	return earned


## Does this run satisfy the achievement? Pure: no side effects, no storage.
static func meets(id: String, summary: RunSummary, totals: Dictionary) -> bool:
	var cleared := int(totals.get("cleared", 0))
	var games := int(totals.get("games", 0))
	match id:
		"first_steps":
			return cleared > 0 or summary.cleared > 0
		"combo_five":
			return summary.combos >= 5
		"ten_thousand":
			return summary.score >= 10000
		"level_five":
			return summary.level >= 5
		"bloom":
			return summary.starflowers > 0
		"pearl":
			return summary.pearls > 0
		"pearl_ring":
			return summary.reason == "pearl_ring" or summary.reason == "pearl_cluster"
		"defuser":
			return summary.bombs_defused > 0
		"survivor":
			return summary.rounds >= 5
		"survival_win":
			return summary.won and summary.mode == "Survival"
		"long_haul":
			return summary.turns >= 150
		"veteran":
			return games >= 25
		_:
			return false


static func title_of(id: String) -> String:
	for entry: Dictionary in LIST:
		if str(entry["id"]) == id:
			return str(entry["title"])
	return id


static func hint_of(id: String) -> String:
	for entry: Dictionary in LIST:
		if str(entry["id"]) == id:
			return str(entry["hint"])
	return ""


## Titles for a set of ids, for the result screen. Unknown ids are skipped rather than
## printed raw, so a renamed achievement cannot leak an internal name into the UI.
static func titles_for(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		for entry: Dictionary in LIST:
			if str(entry["id"]) == id:
				out.append(str(entry["title"]))
				break
	return out


## Every achievement with its earned flag, for the list screen. Kept here rather
## than in the panel so the panel stays a renderer and this stays testable.
static func all_with_state(earned: Dictionary) -> Array:
	var out: Array = []
	for entry: Dictionary in LIST:
		var id := str(entry["id"])
		out.append({
			"id": id,
			"title": str(entry["title"]),
			"hint": str(entry["hint"]),
			"earned": earned.has(id),
		})
	return out


static func count() -> int:
	return LIST.size()
