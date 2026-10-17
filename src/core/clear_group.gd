class_name ClearGroup
extends RefCounted

## One clear event: the connected group of same-coloured pieces removed in a
## single step of a move, plus how it scored. See docs/design.md §3.2, §4.
##
## Special formations (M2) reuse this shape so the view has one thing to animate:
## the cells it affected, what it scored, and which formations were involved.

var cells: Array[Vector2i] = []
var gem_color := 0
var cascade_depth := 1
var base_score := 0
var score := 0

## Bonus stars inside this group; each one doubles the clear (×2, ×4, ×8…).
var bonus_stars := 0
var multiplier := 1

## What produced this clear: "cluster", "flower", "bonus_star_cluster",
## "starflower_cluster", "pearl_cluster", "pearl_ring", "bomb_colour_wipe".
var formations: Array[String] = []


func size() -> int:
	return cells.size()


func has_formation(name: String) -> bool:
	return formations.has(name)


## Typed arrays cannot be assigned from untyped literals in GDScript, so
## formations are set through here rather than by direct assignment.
func set_formations(names: Array) -> void:
	formations.assign(names)


func describe() -> String:
	return "clear(%s, cells=%d, depth=%d, base=%d, x%d, score=%d)" % [
		",".join(formations), cells.size(), cascade_depth, base_score, multiplier, score,
	]
