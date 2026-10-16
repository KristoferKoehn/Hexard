extends "res://tests/test_case.gd"

## Score table and formulas (docs/design.md §4).

const ScoringRulesScript := preload("res://src/core/scoring_rules.gd")


func test_built_in_table_matches_the_design_doc() -> void:
	var rules := ScoringRulesScript.new()
	assert_eq(rules.values["cluster_3"], 5, "3-cluster base")
	assert_eq(rules.values["cluster_4"], 10, "4-cluster base")
	assert_eq(rules.values["cluster_5"], 25, "5-cluster base")
	assert_eq(rules.values["cluster_6_plus"], 50, "6+ cluster base")
	assert_eq(rules.values["cascade_multiplier"], 1.5, "cascade step multiplier")
	assert_eq(rules.difficulty_multiplier("easy"), 0.5, "easy scores less")
	assert_eq(rules.difficulty_multiplier("normal"), 1.0, "normal is the reference")
	assert_eq(rules.difficulty_multiplier("hard"), 2.0, "hard scores double")


func test_base_value_by_cluster_size() -> void:
	var rules := ScoringRulesScript.new()
	assert_eq(rules.base_for_cluster(3), 5, "3 clears are worth 5")
	assert_eq(rules.base_for_cluster(4), 10, "4 clears are worth 10")
	assert_eq(rules.base_for_cluster(5), 25, "5 clears are worth 25")
	assert_eq(rules.base_for_cluster(6), 50, "6 clears are worth 50")
	assert_eq(rules.base_for_cluster(9), 50, "bigger clears stay at the 6+ tier")
	assert_eq(rules.base_for_cluster(2), 5, "degenerate sizes fall back to the 3-tier")


func test_score_scales_with_level() -> void:
	var rules := ScoringRulesScript.new()
	assert_eq(rules.clear_score(5, 1), 5, "level 1 pays the base value")
	assert_eq(rules.clear_score(5, 2), 10, "level 2 doubles it (matches the reference)")
	assert_eq(rules.clear_score(5, 7), 35, "level 7 pays seven times")


func test_cascade_multiplier_curve() -> void:
	var rules := ScoringRulesScript.new()
	assert_eq(rules.cascade_multiplier(1), 1.0, "the first clear has no bonus")
	assert_eq(rules.cascade_multiplier(2), 1.5, "one extra step is x1.5")
	assert_eq(rules.cascade_multiplier(3), 2.25, "two extra steps is x2.25")
	assert_eq(rules.clear_score(5, 1, 2), 8, "5 x 1.5 rounds to 8")
	assert_eq(rules.clear_score(5, 1, 3), 11, "5 x 2.25 rounds to 11")


func test_difficulty_multiplier_applies() -> void:
	var rules := ScoringRulesScript.new()
	assert_eq(rules.clear_score(10, 1, 1, "easy"), 5, "easy halves the payout")
	assert_eq(rules.clear_score(10, 1, 1, "normal"), 10, "normal is unchanged")
	assert_eq(rules.clear_score(10, 1, 1, "hard"), 20, "hard doubles it")
	assert_eq(rules.clear_score(10, 1, 1, "nonsense"), 10, "unknown difficulty is neutral")


func test_overrides_replace_defaults() -> void:
	var rules := ScoringRulesScript.new({"cluster_3": 7, "cascade_multiplier": 2.0})
	assert_eq(rules.values["cluster_3"], 7, "override wins")
	assert_eq(rules.base_for_cluster(3), 7, "and is used by the formula")
	assert_eq(rules.cascade_multiplier(3), 4.0, "cascade override is respected")
	assert_eq(rules.values["cluster_4"], 10, "untouched keys keep their default")


func test_json_table_loads_and_matches_defaults() -> void:
	# data/scoring.json is the tunable copy of the same numbers; if the two ever
	# disagree, tuning silently stops working, so assert they agree.
	var loaded := ScoringRulesScript.load_default()
	var builtin := ScoringRulesScript.new()
	for key: String in builtin.values:
		assert_eq(loaded.values[key], builtin.values[key], "data/scoring.json value for '%s'" % key)
	assert_eq(loaded.base_for_cluster(3), 5, "loaded table is usable")


func test_missing_file_falls_back_to_defaults() -> void:
	var rules := ScoringRulesScript.load_default("res://data/does_not_exist.json")
	assert_eq(rules.values["cluster_3"], 5, "defaults survive a missing file")
	assert_eq(rules.clear_score(5, 1), 5, "and the formula still works")
