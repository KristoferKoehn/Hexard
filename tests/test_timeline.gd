extends "res://tests/test_case.gd"

## MoveTimeline: what plays, in what order. These are the rules that have broken
## before — cascade grouping, bloom-before-clear, bomb last — and until this class
## existed they could only be observed by watching the game.

const MoveResultScript := preload("res://src/core/move_result.gd")


func _result(depth_clears: Dictionary = {}, promotions: Array = []) -> MoveResult:
	## depth_clears: {depth: [score, cell-count]}
	var result := MoveResultScript.new()
	result.committed = true
	# A real committed move always has the trio that was turned, so the plan starts
	# with a spin step; omitting it made these tests assert against an impossible move.
	result.rotation_cells.assign([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)])
	result.direction = 1
	for depth: int in depth_clears:
		var spec: Array = depth_clears[depth]
		var group := ClearGroup.new()
		group.cascade_depth = depth
		group.score = int(spec[0])
		for index in int(spec[1]):
			group.cells.append(Vector2i(depth, index))
		result.clear_groups.append(group)
	for promotion: Dictionary in promotions:
		result.promotions.append(promotion)
	return result


func _kinds(steps: Array) -> Array[String]:
	var out: Array[String] = []
	for step: Dictionary in steps:
		out.append(str(step["kind"]))
	return out


func _first_index(steps: Array, kind: String) -> int:
	for index in steps.size():
		if str(steps[index]["kind"]) == kind:
			return index
	return -1


func test_a_refused_spin_plans_one_bounce_and_does_not_settle() -> void:
	var result := MoveResultScript.new()
	result.committed = false
	result.rotation_cells.assign([Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1)])
	var steps := MoveTimeline.plan(result)
	assert_eq(steps.size(), 1, "a refusal is a single step")
	assert_eq(str(steps[0]["kind"]), "bounce", "which is the bounce")
	assert_false(MoveTimeline.settles(steps), "and does not count as the board moving")


func test_a_clearing_move_spins_then_clears_in_depth_order() -> void:
	var steps := MoveTimeline.plan(_result({1: [50, 3], 2: [80, 4]}))
	var kinds := _kinds(steps)
	assert_eq(kinds[0], "spin", "the spin comes first")
	assert_eq(kinds[1], "clear", "then the first clear")
	assert_true(MoveTimeline.settles(steps), "a committed move unsettles the board")

	var first := _first_index(steps, "clear")
	var second := steps.slice(first + 1).find_custom(func(s: Dictionary) -> bool: return str(s["kind"]) == "clear")
	assert_gt(second, -1, "the cascade produced a second clear step")
	var second_step: Dictionary = steps[first + 1 + second]
	assert_eq(int(steps[first]["depth"]), 1, "the first clear is depth 1")
	assert_eq(int(second_step["depth"]), 2, "and the cascade step is depth 2")


func test_the_score_carried_by_a_clear_step_is_that_depths_total() -> void:
	var result := _result({1: [50, 3]})
	var second := ClearGroup.new()
	second.cascade_depth = 1
	second.score = 25
	second.cells.append(Vector2i(9, 9))
	result.clear_groups.append(second)
	var clear_step: Dictionary = MoveTimeline.plan(result)[1]
	assert_eq(str(clear_step["kind"]), "clear", "the second step clears")
	assert_eq(int(clear_step["score"]), 75, "and carries the sum for its depth")
	assert_eq(int(clear_step["groups"].size()), 2, "with both groups attached")


func test_a_bloom_lands_before_the_ring_it_grew_from_is_destroyed() -> void:
	var promotion := {"cell": Vector2i(5, 5), "piece": 0, "kind": "starflower", "depth": 1}
	var steps := MoveTimeline.plan(_result({1: [10, 3]}, [promotion]))
	var bloom := _first_index(steps, "bloom")
	var clear := _first_index(steps, "clear")
	assert_gt(bloom, -1, "the promotion gets its own step")
	assert_gt(clear, -1, "and the clear still happens")
	assert_lt(bloom, clear, "the bloom plays before the ring is destroyed")


func test_a_promotion_without_a_clear_still_gets_a_step() -> void:
	var promotion := {"cell": Vector2i(5, 5), "piece": 0, "kind": "pearl", "depth": 1}
	var steps := MoveTimeline.plan(_result({}, [promotion]))
	assert_gt(_first_index(steps, "bloom"), -1, "the bloom is not dropped for lack of a clear")


func test_a_bomb_plays_last() -> void:
	var result := _result({1: [10, 3]})
	result.bomb_exploded = true
	result.exploded_cells.assign([Vector2i(4, 4), Vector2i(4, 5)])
	var kinds := _kinds(MoveTimeline.plan(result))
	assert_eq(kinds[kinds.size() - 2], "blast", "the blast comes second to last")
	assert_eq(kinds[kinds.size() - 1], "shatter", "and the debris finishes the sequence")


func test_reduced_motion_shortens_every_step() -> void:
	var result := _result({1: [10, 3]})
	var full: Dictionary = MoveTimeline.plan(result)[0]
	var short: Dictionary = MoveTimeline.plan(result, 0.35)[0]
	assert_almost_eq(float(short["duration"]), float(full["duration"]) * 0.35, 0.001,
		"durations scale with the motion setting")


func test_the_helpers_agree_with_the_plan() -> void:
	var result := _result({2: [40, 2]})
	assert_eq(MoveTimeline.cells_at_depth(result, 2).size(), 2, "cells at a depth")
	assert_eq(MoveTimeline.groups_at_depth(result, 2).size(), 1, "groups at a depth")
	assert_eq(MoveTimeline.score_at_depth(result, 2), 40, "score at a depth")
	assert_eq(MoveTimeline.cells_at_depth(result, 1).size(), 0, "and nothing at an empty depth")
