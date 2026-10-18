extends "res://tests/test_case.gd"

## Achievements: definitions, predicates, and the profile that remembers them.

const ProfileScript := preload("res://src/core/profile_service.gd")


func _summary() -> RunSummary:
	var summary := RunSummary.new()
	summary.mode = "Marathon"
	summary.difficulty = "normal"
	summary.reason = "bomb_exploded"
	return summary


func test_the_definitions_are_well_formed() -> void:
	var seen := {}
	for entry: Dictionary in Achievements.LIST:
		var id := str(entry.get("id", ""))
		assert_ne(id, "", "every achievement has an id")
		assert_false(seen.has(id), "ids are unique (%s)" % id)
		seen[id] = true
		assert_ne(str(entry.get("title", "")), "", "every achievement has a title (%s)" % id)
		assert_ne(str(entry.get("hint", "")), "", "and a hint that says how to earn it (%s)" % id)
	assert_eq(Achievements.count(), Achievements.LIST.size(), "the count matches the list")


func test_nothing_is_earned_by_an_empty_run() -> void:
	var fresh := _summary()
	for entry: Dictionary in Achievements.LIST:
		var id := str(entry["id"])
		if id == "first_steps":
			continue  # earned by any clearing at all, covered below
		assert_false(Achievements.meets(id, fresh, {}), "%s is not free" % id)


func test_each_achievement_fires_on_the_run_it_describes() -> void:
	var scoring := _summary()
	scoring.score = 10000
	scoring.level = 5
	scoring.combos = 5
	scoring.turns = 150
	assert_true(Achievements.meets("ten_thousand", scoring, {}), "score 10,000")
	assert_true(Achievements.meets("level_five", scoring, {}), "reach level 5")
	assert_true(Achievements.meets("combo_five", scoring, {}), "a 5-combo")
	assert_true(Achievements.meets("long_haul", scoring, {}), "150 turns")

	var specials := _summary()
	specials.starflowers = 1
	specials.pearls = 1
	specials.bombs_defused = 1
	assert_true(Achievements.meets("bloom", specials, {}), "a starflower")
	assert_true(Achievements.meets("pearl", specials, {}), "a pearl")
	assert_true(Achievements.meets("defuser", specials, {}), "a defused bomb")

	var ring := _summary()
	ring.reason = "pearl_ring"
	assert_true(Achievements.meets("pearl_ring", ring, {}), "the pearl ring ending")

	var survival := _summary()
	survival.mode = "Survival"
	survival.rounds = 5
	survival.won = true
	assert_true(Achievements.meets("survivor", survival, {}), "five rounds cleared")
	assert_true(Achievements.meets("survival_win", survival, {}), "and winning Survival")
	survival.won = false
	assert_false(Achievements.meets("survival_win", survival, {}), "clearing rounds is not winning")

	var clears := _summary()
	clears.cleared = 12
	assert_true(Achievements.meets("first_steps", clears, {}), "clearing gems earns first steps")
	assert_true(Achievements.meets("veteran", _summary(), {"games": 25}), "25 runs, from the totals")


func test_evaluate_reports_only_what_is_new() -> void:
	var summary := _summary()
	summary.score = 12000
	var first := Achievements.evaluate(summary, {}, {})
	assert_true(first.has("ten_thousand"), "the first pass earns it")
	var earned := {"ten_thousand": true}
	var second := Achievements.evaluate(summary, {}, earned)
	assert_false(second.has("ten_thousand"), "the second pass does not repeat it")


func test_unlocking_is_idempotent_and_persists() -> void:
	var profile := ProfileScript.new()
	assert_true(profile.unlock("bloom"), "the first unlock reports new")
	assert_false(profile.unlock("bloom"), "the second does not")
	assert_false(profile.unlock(""), "an empty id is not an achievement")
	assert_eq(profile.achievement_count(), 1, "only one is stored")

	var reloaded := ProfileScript.new()
	reloaded.apply_dictionary(profile.to_dictionary())
	assert_true(reloaded.has_achievement("bloom"), "it survives a save and load")
	assert_eq(reloaded.achievement_count(), 1, "without duplicating")

	var reset := ProfileScript.new()
	reset.unlock("bloom")
	reset.reset()
	assert_false(reset.has_achievement("bloom"), "a reset clears them")


func test_titles_are_human_and_unknown_ids_do_not_leak() -> void:
	var titles := Achievements.titles_for(["bloom", "not_a_real_achievement", "pearl"])
	assert_eq(titles.size(), 2, "unknown ids are skipped")
	assert_eq(titles[0], Achievements.title_of("bloom"), "ids map to their titles")
	assert_eq(Achievements.title_of("not_a_real_achievement"), "not_a_real_achievement",
		"an unknown id falls back to itself rather than crashing")
