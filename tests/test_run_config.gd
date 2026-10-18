extends "res://tests/test_case.gd"

## RunConfig: the mode+difficulty pair as a value.

const RulesetScript := preload("res://src/core/ruleset.gd")


func test_defaults_and_validation() -> void:
	var config := RunConfig.of(RulesetScript.Mode.MARATHON)
	assert_eq(config.mode, int(RulesetScript.Mode.MARATHON), "marathon by default")
	assert_eq(config.difficulty, "normal", "normal by default")
	var nonsense := RunConfig.of(RulesetScript.Mode.TIMED, "impossible")
	assert_eq(nonsense.difficulty, "normal", "an unknown difficulty falls back rather than propagating")


func test_the_key_matches_what_saved_leaderboards_use() -> void:
	# Existing profile files key their tables as "<ModeName>|<difficulty>". If this
	# format ever changes, everyone's records become invisible.
	assert_eq(RunConfig.of(RulesetScript.Mode.MARATHON, "normal").key(), "Marathon|normal", "marathon key")
	assert_eq(RunConfig.of(RulesetScript.Mode.TIMED, "hard").key(), "Timed|hard", "timed key")
	assert_eq(RunConfig.of(RulesetScript.Mode.SURVIVAL, "easy").key(), "Survival|easy", "survival key")


func test_mode_names_and_labels() -> void:
	assert_eq(RunConfig.of(RulesetScript.Mode.SURVIVAL).mode_name(), "Survival", "mode name")
	assert_eq(RunConfig.of(RulesetScript.Mode.TIMED, "hard").label(), "Timed · Hard", "label title-cases the difficulty")


func test_cycling_wraps_in_both_directions() -> void:
	var marathon := RunConfig.of(RulesetScript.Mode.MARATHON)
	assert_eq(marathon.next_mode(1).mode, int(RulesetScript.Mode.TIMED), "marathon -> timed")
	assert_eq(marathon.next_mode(2).mode, int(RulesetScript.Mode.SURVIVAL), "marathon -> survival")
	assert_eq(marathon.next_mode(3).mode, int(RulesetScript.Mode.MARATHON), "and wraps round")
	assert_eq(marathon.next_mode(-1).mode, int(RulesetScript.Mode.SURVIVAL), "backwards wraps too")

	var normal := RunConfig.of(RulesetScript.Mode.MARATHON, "normal")
	assert_eq(normal.next_difficulty(1).difficulty, "hard", "normal -> hard")
	assert_eq(normal.next_difficulty(-1).difficulty, "easy", "normal -> easy")
	assert_eq(normal.next_difficulty(3).difficulty, "normal", "and wraps round")
	assert_eq(normal.next_difficulty(1).mode, int(RulesetScript.Mode.MARATHON), "mode is untouched")


func test_conversions_round_trip() -> void:
	var ruleset := RulesetScript.for_run(RunConfig.of(RulesetScript.Mode.TIMED, "hard"))
	var back := RunConfig.from_ruleset(ruleset)
	assert_eq(back.mode, int(RulesetScript.Mode.TIMED), "ruleset carries the mode")
	assert_eq(back.difficulty, "hard", "and the difficulty")

	var named := RunConfig.from_name("Survival", "easy")
	assert_eq(named.mode, int(RulesetScript.Mode.SURVIVAL), "a printed name converts back")
	assert_eq(RunConfig.from_name("Nonsense").mode, int(RulesetScript.Mode.MARATHON),
		"an unknown name is marathon rather than nothing")
