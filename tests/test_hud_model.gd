extends "res://tests/test_case.gd"

## The HUD presentation model and its formatter. These are the first tests the
## status bar has ever had: it used to need a live Game and a CanvasLayer, because
## it read the game directly. Now it is a snapshot plus a pure function.

const RulesetScript := preload("res://src/core/ruleset.gd")
const GameScript := preload("res://src/core/game.gd")
const HudScript := preload("res://src/view/hud.gd")
const ModelScript := preload("res://src/view/hud_model.gd")

const ACCENT_HEX := "35e0f0"


func _model() -> HudModel:
	var model := ModelScript.new()
	model.mode = RulesetScript.Mode.MARATHON
	model.mode_name = "Marathon"
	model.difficulty = "normal"
	model.strict = true
	model.score = 12345
	model.level = 3
	model.combos_remaining = 17
	model.bombs = 2
	model.pearls = 1
	model.turn = 42
	model.seed_value = 777
	return model


func test_the_snapshot_copies_everything_the_bar_shows() -> void:
	var game := GameScript.new(4242, RulesetScript.strict_rotation())
	var model := ModelScript.from_game(game)
	assert_eq(model.mode, int(RulesetScript.Mode.MARATHON), "mode is carried over")
	assert_eq(model.difficulty, "normal", "difficulty is carried over")
	assert_true(model.strict, "strict rotation is reported")
	assert_eq(model.score, game.score, "score comes from the game")
	assert_eq(model.level, game.level, "level comes from the game")
	assert_eq(model.turn, game.turns, "turn comes from the game")
	assert_eq(model.seed_value, 4242, "the seed is carried for the debug readout")
	assert_false(model.finished, "a fresh run is not finished")
	assert_eq(model.pearls, 0, "and starts with no pearls")


func test_the_displayed_score_overrides_the_real_one() -> void:
	var game := GameScript.new(1, RulesetScript.strict_rotation())
	assert_eq(ModelScript.from_game(game, 99).score, 99, "the animation's score wins")
	assert_eq(ModelScript.from_game(game, -1).score, game.score, "and -1 means trust the core")


func test_free_rotation_is_reported_as_free() -> void:
	var game := GameScript.new(1, RulesetScript.free_rotation())
	assert_false(ModelScript.from_game(game).strict, "free rotation is not strict")


func test_each_mode_shows_its_own_field() -> void:
	var marathon := _model()
	var marathon_text := HudScript.format_status(marathon)
	assert_true(marathon_text.contains("BOMBS"), "marathon counts bombs")
	assert_false(marathon_text.contains("TIME"), "and has no clock")

	var timed := _model()
	timed.mode = RulesetScript.Mode.TIMED
	timed.clock = 12.5
	timed.max_clock = 50.0
	var timed_text := HudScript.format_status(timed)
	assert_true(timed_text.contains("TIME"), "timed shows the clock")
	assert_true(timed_text.contains("12.5"), "with its value")

	var survival := _model()
	survival.mode = RulesetScript.Mode.SURVIVAL
	survival.round = 4
	survival.frozen = 9
	var survival_text := HudScript.format_status(survival)
	assert_true(survival_text.contains("ROUND"), "survival shows the round")
	assert_true(survival_text.contains("FROZEN"), "and the frozen count")
	assert_true(survival_text.contains("4"), "with the round number")


func test_figures_are_accented_and_labels_are_quiet() -> void:
	var text := HudScript.format_status(_model())
	assert_true(text.contains("SCORE"), "the row names its figures")
	assert_true(text.contains("12345"), "and prints the score")
	assert_true(text.contains(ACCENT_HEX), "figures carry the accent colour")
	assert_true(text.contains("[STRICT]"), "the rotation mode is tagged")


func test_run_over_is_announced() -> void:
	var model := _model()
	model.finished = true
	assert_true(HudScript.format_status(model).contains("RUN OVER"), "a finished run says so")
	assert_false(HudScript.format_status(_model()).contains("RUN OVER"), "a live one does not")


func test_the_format_is_pure() -> void:
	var model := _model()
	assert_eq(HudScript.format_status(model), HudScript.format_status(model),
		"the same snapshot formats identically")
	var other := _model()
	other.score = 54321
	assert_ne(HudScript.format_status(model), HudScript.format_status(other),
		"and a different score changes the row")
