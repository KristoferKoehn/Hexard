class_name ResolveContext
extends RefCounted

## Everything one cascade pass needs, threaded through the formation handlers
## (Parameter Object pattern).
##
## Before this existed, eight handlers took the same five arguments in the same
## order — `board, ruleset, result, level, depth` — and `_clear()` took ten. Every
## new rule meant editing every signature, and a transposed argument type-checked
## fine because most of them were ints.
##
## `depth` is advanced by `resolve()` as the chain grows, so a handler never passes
## it along; it can also carry per-pass caches later (the solid-cell set is the
## obvious candidate).

var board: Board
var ruleset: Ruleset
var rng: Rng
var result: MoveResult
var level: int
## 1 for the clear the player's spin made, 2 for the first cascade, and so on.
var depth := 1
## False in Survival, where cleared cells stay empty for the rest of the round.
var refill := true


func _init(
	p_board: Board, p_ruleset: Ruleset, p_rng: Rng, p_result: MoveResult,
	p_level: int, p_refill: bool = true
) -> void:
	board = p_board
	ruleset = p_ruleset
	rng = p_rng
	result = p_result
	level = p_level
	refill = p_refill
