extends "res://tests/test_case.gd"

## Settings (audio levels, juice toggles, rebinds) and the profile service
## (stats, personal bests, local leaderboard).

const SettingsScript := preload("res://src/core/settings.gd")
const ProfileScript := preload("res://src/core/profile_service.gd")

const SCRATCH := "res://.test_scratch.json"


func _clean_scratch() -> void:
	var absolute := ProjectSettings.globalize_path(SCRATCH)
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(absolute)


func _summary(
	score: int, level: int = 1, won: bool = false, mode: String = "Marathon",
	difficulty: String = "normal", reason: String = "bomb_exploded", turns: int = 10
) -> RunSummary:
	var summary := RunSummary.new()
	summary.mode = mode
	summary.difficulty = difficulty
	summary.score = score
	summary.level = level
	summary.won = won
	summary.reason = reason
	summary.turns = turns
	summary.combos = 3
	summary.cleared = 40
	summary.elapsed = 12.5
	summary.bombs_defused = 1
	summary.seed_value = 99
	return summary


# --- settings ---------------------------------------------------------------

func test_settings_defaults_are_complete_and_sane() -> void:
	var settings := SettingsScript.new()
	for action: String in SettingsScript.DEFAULT_BINDINGS:
		assert_true(settings.keys_for(action).size() > 0, "%s has a default key" % action)
		assert_true(SettingsScript.ACTION_LABELS.has(action), "%s has a label" % action)
	assert_eq(settings.action_for_key(KEY_X), "rotate_cw", "X rotates clockwise")
	assert_eq(settings.action_for_key(KEY_Z), "rotate_ccw", "Z rotates anticlockwise")
	assert_eq(settings.action_for_key(KEY_W), "cursor_up", "W is also cursor up")
	assert_true(settings.shake_enabled(), "shake is on by default")
	assert_true(settings.flashes_enabled(), "flashes are on by default")
	assert_almost_eq(settings.motion_scale(), 1.0, 0.001, "full motion by default")
	assert_gt(settings.sfx_gain(), 0.0, "sound is audible by default")


func test_reducing_motion_disables_shake_and_flashes() -> void:
	var settings := SettingsScript.new()
	settings.reduced_motion = true
	assert_false(settings.shake_enabled(), "reduced motion wins over the shake toggle")
	assert_false(settings.flashes_enabled(), "and over flashes")
	assert_almost_eq(settings.motion_scale(), 0.35, 0.001, "animations are shortened")
	settings.screen_shake = false
	assert_false(settings.shake_enabled(), "shake off stays off")


func test_mute_silences_everything() -> void:
	var settings := SettingsScript.new()
	settings.muted = true
	assert_almost_eq(settings.sfx_gain(), 0.0, 0.001, "muted means silent")
	settings.muted = false
	settings.master_volume = 0.5
	settings.sfx_volume = 0.5
	assert_almost_eq(settings.sfx_gain(), 0.25, 0.001, "levels multiply")


func test_rebinding_moves_the_key() -> void:
	var settings := SettingsScript.new()
	settings.set_binding("rotate_cw", [KEY_C])
	assert_eq(settings.action_for_key(KEY_C), "rotate_cw", "C now rotates clockwise")
	assert_eq(settings.action_for_key(KEY_X), "", "and X is free")
	assert_eq(settings.keys_for("rotate_cw").size(), 1, "the old key was replaced")


func test_taking_a_key_away_from_another_action_is_deliberate() -> void:
	var settings := SettingsScript.new()
	settings.set_binding("hint", [KEY_X])
	assert_eq(settings.action_for_key(KEY_X), "hint", "the key moved to hint")
	assert_false(settings.keys_for("rotate_cw").has(KEY_X), "and left rotate_cw")
	assert_eq(settings.action_for_key(KEY_H), "", "set_binding replaces the action's other keys")


func test_adding_a_binding_keeps_the_old_ones() -> void:
	var settings := SettingsScript.new()
	settings.add_binding("rotate_cw", KEY_C)
	var keys := settings.keys_for("rotate_cw")
	assert_true(keys.has(KEY_X), "X still rotates")
	assert_true(keys.has(KEY_C), "and now C does too")
	settings.add_binding("rotate_cw", KEY_C)
	assert_eq(settings.keys_for("rotate_cw").size(), keys.size(), "adding twice is a no-op")


func test_clearing_a_binding_leaves_no_key() -> void:
	var settings := SettingsScript.new()
	settings.clear_binding("toggle_rotation")
	assert_eq(settings.keys_for("toggle_rotation").size(), 0, "the action has no keys")
	assert_eq(settings.action_for_key(KEY_T), "", "and T is unbound")


func test_settings_round_trip_through_a_file() -> void:
	_clean_scratch()
	var settings := SettingsScript.new()
	settings.master_volume = 0.25
	settings.sfx_volume = 0.4
	settings.muted = true
	settings.reduced_motion = true
	settings.set_binding("rotate_ccw", [KEY_C, KEY_V])
	assert_true(settings.save_to(SCRATCH), "saved")

	var loaded := SettingsScript.new()
	assert_true(loaded.load_from(SCRATCH), "loaded")
	assert_almost_eq(loaded.master_volume, 0.25, 0.001, "master volume survived")
	assert_almost_eq(loaded.sfx_volume, 0.4, 0.001, "sfx volume survived")
	assert_true(loaded.muted, "mute survived")
	assert_true(loaded.reduced_motion, "reduced motion survived")
	assert_eq(loaded.action_for_key(KEY_V), "rotate_ccw", "the new binding survived")
	assert_eq(loaded.keys_for("rotate_ccw").size(), 2, "both keys survived")
	_clean_scratch()


func test_a_missing_or_broken_settings_file_keeps_the_defaults() -> void:
	_clean_scratch()
	var settings := SettingsScript.new()
	assert_false(settings.load_from(SCRATCH), "no file means defaults, not an error")
	assert_eq(settings.action_for_key(KEY_X), "rotate_cw", "defaults are intact")

	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var broken := SettingsScript.new()
	assert_false(broken.load_from(SCRATCH), "broken file reports failure")
	assert_eq(broken.action_for_key(KEY_Z), "rotate_ccw", "and defaults survive")
	_clean_scratch()


func test_out_of_range_volumes_are_clamped() -> void:
	var settings := SettingsScript.new()
	settings.apply_dictionary({"master_volume": 5.0, "sfx_volume": -3.0})
	assert_almost_eq(settings.master_volume, 1.0, 0.001, "loud is clamped")
	assert_almost_eq(settings.sfx_volume, 0.0, 0.001, "negative is clamped")
	assert_gt(SettingsScript.key_name(KEY_ESCAPE).length(), 0, "keys can be named for the UI")


# --- profile ----------------------------------------------------------------

func test_a_fresh_profile_is_empty() -> void:
	var profile := ProfileScript.new()
	assert_eq(profile.games_played(), 0, "no games yet")
	assert_eq(profile.best_for("Marathon", "normal")["score"], 0, "no best yet")
	assert_eq(profile.top_scores("Marathon", "normal").size(), 0, "empty leaderboard")
	assert_eq(profile.played_tables().size(), 0, "no tables")
	for key: String in ProfileScript.TOTAL_KEYS:
		assert_true(profile.totals.has(key), "total %s exists" % key)


func test_recording_a_run_updates_stats_best_and_board() -> void:
	var profile := ProfileScript.new()
	var key := profile.record_run(_summary(1234, 3), "2026-01-01T10:00")
	assert_eq(key, "Marathon|normal", "keyed by mode and difficulty")
	assert_eq(profile.games_played(), 1, "one game played")
	assert_eq(profile.totals["score"], 1234, "score accumulated")
	assert_eq(profile.totals["combos"], 3, "combos accumulated")
	assert_eq(profile.totals["cleared"], 40, "cleared accumulated")
	assert_eq(profile.totals["bombs_defused"], 1, "defuses accumulated")
	assert_eq(profile.totals["best_level"], 3, "level tracked")

	assert_eq(profile.best_for("Marathon", "normal")["score"], 1234, "best recorded")
	assert_eq(profile.top_scores("Marathon", "normal").size(), 1, "board has the run")
	var entry: Dictionary = profile.top_scores("Marathon", "normal")[0]
	assert_eq(entry["seed"], 99, "and keeps the replay seed")
	assert_eq(entry["date"], "2026-01-01T10:00", "with its timestamp")

	profile.record_run(_summary(50, 1), "2026-01-01T11:00")
	assert_eq(profile.best_for("Marathon", "normal")["score"], 1234, "a worse run is not a best")
	assert_eq(profile.top_scores("Marathon", "normal").size(), 2, "but still goes on the board")
	assert_eq(profile.top_scores("Marathon", "normal")[0]["score"], 1234, "ordered by score")


func test_bests_improve_and_wins_are_counted() -> void:
	var profile := ProfileScript.new()
	profile.record_run(_summary(100), "a")
	profile.record_run(_summary(500, 4, true, "Marathon", "normal", "pearl_ring"), "b")
	assert_eq(profile.best_for("Marathon", "normal")["score"], 500, "the better run wins")
	assert_true(profile.best_for("Marathon", "normal")["won"], "and its verdict is kept")
	assert_eq(profile.best_for("Marathon", "normal")["reason"], "pearl_ring", "with the reason")
	assert_eq(profile.totals["wins"], 1, "one win")
	assert_eq(profile.totals["losses"], 1, "one loss")


func test_tables_do_not_mix_modes_or_difficulties() -> void:
	var profile := ProfileScript.new()
	profile.record_run(_summary(1000, 2, false, "Marathon", "normal"))
	profile.record_run(_summary(300, 1, false, "Timed", "normal"))
	profile.record_run(_summary(50, 1, false, "Marathon", "hard"))
	assert_eq(profile.best_for("Marathon", "normal")["score"], 1000, "Marathon normal")
	assert_eq(profile.best_for("Timed", "normal")["score"], 300, "Timed normal")
	assert_eq(profile.best_for("Marathon", "hard")["score"], 50, "Marathon hard")
	assert_eq(profile.best_for("Marathon", "easy")["score"], 0, "an unplayed table is zero")
	assert_eq(profile.played_tables().size(), 3, "three tables played")
	assert_eq(profile.games_played(), 3, "three games total")


func test_the_leaderboard_is_capped_and_ordered() -> void:
	var profile := ProfileScript.new()
	for index in 15:
		profile.record_run(_summary(index * 100), "run %d" % index)
	var board := profile.top_scores("Marathon", "normal", 100)
	assert_eq(board.size(), ProfileScript.LEADERBOARD_SIZE, "the board is capped")
	assert_eq(board[0]["score"], 1400, "highest first")
	assert_eq(board[board.size() - 1]["score"], 500, "and the lowest scores fall off")
	assert_eq(profile.top_scores("Marathon", "normal", 3).size(), 3, "the limit is honoured")


func test_profile_round_trips_through_a_file() -> void:
	_clean_scratch()
	var profile := ProfileScript.new()
	profile.record_run(_summary(900, 2, true, "Survival", "hard"), "x")
	profile.record_run(_summary(100, 1), "y")
	assert_true(profile.save_to(SCRATCH), "saved")

	var loaded := ProfileScript.new()
	assert_true(loaded.load_from(SCRATCH), "loaded")
	assert_eq(loaded.games_played(), 2, "games survived")
	assert_eq(loaded.totals["score"], 1000, "totals survived")
	assert_eq(loaded.best_for("Survival", "hard")["score"], 900, "bests survived")
	assert_eq(loaded.best_for("Marathon", "normal")["score"], 100, "every table survived")
	assert_eq(loaded.top_scores("Marathon", "normal").size(), 1, "boards survived")
	_clean_scratch()


func test_a_broken_profile_file_starts_a_fresh_one() -> void:
	_clean_scratch()
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	var profile := ProfileScript.new()
	assert_false(profile.load_from(SCRATCH), "a non-object file is rejected")
	assert_eq(profile.games_played(), 0, "and the profile is clean")
	_clean_scratch()
