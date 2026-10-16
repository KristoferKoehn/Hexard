class_name ClearGroup
extends RefCounted

## One clear event: the connected group of same-coloured pieces removed in a
## single step of a move, plus how it scored. See docs/design.md §3.2, §4.

var cells: Array[Vector2i] = []
var gem_color := 0
var cascade_depth := 1
var base_score := 0
var score := 0

## Reserved for M2: bonus stars inside this group multiply the clear.
var bonus_stars := 0


func size() -> int:
	return cells.size()


func describe() -> String:
	return "clear(color=%d, cells=%d, depth=%d, base=%d, score=%d)" % [
		gem_color, cells.size(), cascade_depth, base_score, score,
	]
