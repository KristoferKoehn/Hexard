class_name MoveTimeline
extends RefCounted

## Turns a MoveResult into the queue of animation steps the view plays.
##
## This is the pure half of the board view's animation: given a result and a motion
## scale, decide *what happens in what order*. The view still owns the state machine
## (which step is active, committing pieces to the presentation board), but the
## planning had grown inside a Node2D where none of it could be tested — and the
## ordering rules are exactly what has needed fixing: cascade steps must play in
## depth order, a bloom must land before the ring it grew from is destroyed, and a
## dying bomb must go last.
##
## Timing lives here too, because the plan is where durations are decided;
## `reduced_motion` shortens all of it through `motion_scale`.

const SPIN_TIME := 0.11
const CLEAR_TIME := 0.14
const FALL_TIME := 0.17
const DROP_TIME := 0.15
const STEP_GAP := 0.045
const PROMOTE_TIME := 0.22
const BLAST_TIME := 0.42
const SHATTER_TIME := 0.34
## A refused spin turns out and straight back; the snap-back is quicker than the
## turn, so it reads as a refusal rather than a move.
const BOUNCE_TIME := 0.22


## The steps to play for `result`. A refused spin yields a single bounce; everything
## else plays spin, then per cascade depth: bloom → clear → fall → drop, then the
## bomb if one went off.
static func plan(result: MoveResult, motion_scale: float = 1.0) -> Array:
	var steps: Array = []
	if result == null:
		return steps

	if not result.committed:
		if result.rotation_cells.size() > 0:
			steps.append({
				"kind": "bounce", "cells": result.rotation_cells.duplicate(),
				"dir": result.direction, "duration": BOUNCE_TIME * motion_scale,
			})
		return steps

	if result.rotation_cells.size() > 0:
		steps.append({
			"kind": "spin", "cells": result.rotation_cells.duplicate(),
			"dir": result.direction, "duration": SPIN_TIME * motion_scale,
		})

	for depth: int in depths(result):
		# The centre of a flower becomes the flower BEFORE the ring is destroyed:
		# same step, but the bloom plays first so the player sees the conversion land
		# while the gems it grew from are still on the board.
		var promotes := entries_at_depth(result.promotions, depth)
		if not promotes.is_empty():
			steps.append({
				"kind": "bloom", "promotions": promotes,
				"duration": PROMOTE_TIME * motion_scale,
			})

		var cleared := cells_at_depth(result, depth)
		if not cleared.is_empty():
			steps.append({
				"kind": "clear", "cells": cleared, "duration": CLEAR_TIME * motion_scale,
				"score": score_at_depth(result, depth), "depth": depth,
				"groups": groups_at_depth(result, depth),
			})

		var falls := entries_at_depth(result.gravity_moves, depth)
		if not falls.is_empty():
			steps.append({"kind": "fall", "moves": falls, "duration": FALL_TIME * motion_scale})

		var drops := entries_at_depth(result.spawns, depth)
		if not drops.is_empty():
			steps.append({"kind": "drop", "spawns": drops, "duration": DROP_TIME * motion_scale})

		steps.append({"kind": "wait", "duration": STEP_GAP * motion_scale})

	# A dying bomb takes the board with it, after the moves that led to it.
	if result.bomb_exploded and result.exploded_cells.size() > 0:
		var origin: Vector2i = result.exploded_cells[0]
		steps.append({"kind": "blast", "cell": origin, "duration": BLAST_TIME * motion_scale})
		steps.append({
			"kind": "shatter", "cells": result.exploded_cells.duplicate(),
			"centre": origin, "duration": SHATTER_TIME * motion_scale,
		})
	return steps


## A bounce changes nothing on the board, so it must not count as the board being
## unsettled — otherwise a refused spin would lock input for a fifth of a second.
static func settles(steps: Array) -> bool:
	if steps.is_empty():
		return false
	return str(steps[0].get("kind", "")) != "bounce"


# --- pure helpers over a MoveResult -----------------------------------------

## Cascade depths present in this move, in order. Promotions count too, so a
## promotion can never be dropped from the plan.
static func depths(result: MoveResult) -> Array[int]:
	var seen := {}
	for group in result.clear_groups:
		seen[int(group.cascade_depth)] = true
	for promotion: Dictionary in result.promotions:
		seen[int(promotion.get("depth", 1))] = true
	if seen.is_empty():
		seen[1] = true
	var out: Array[int] = []
	for depth: int in seen:
		out.append(depth)
	out.sort()
	return out


static func cells_at_depth(result: MoveResult, depth: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for group in result.clear_groups:
		if int(group.cascade_depth) != depth:
			continue
		for cell: Vector2i in group.cells:
			out.append(cell)
	return out


static func groups_at_depth(result: MoveResult, depth: int) -> Array:
	var out: Array = []
	for group in result.clear_groups:
		if int(group.cascade_depth) == depth:
			out.append(group)
	return out


## What one cascade step is worth: the sum of the groups that cleared in it.
static func score_at_depth(result: MoveResult, depth: int) -> int:
	var total := 0
	for group in result.clear_groups:
		if int(group.cascade_depth) == depth:
			total += int(group.score)
	return total


static func entries_at_depth(entries: Array, depth: int) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		if int(entry.get("depth", 0)) == depth:
			out.append(entry)
	return out
