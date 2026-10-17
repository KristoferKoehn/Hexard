class_name Tutorial
extends RefCounted

## A short, scripted, hands-on tutorial (docs/design.md §7.4).
##
## Each step rigs the board so the mechanic under discussion is one move away,
## then watches the resulting MoveResult for the goal. Rigging is legitimate
## here — the point is to *show* the mechanic, and every setup is a legal board
## (a match-free background plus the formation under test).

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")

## An interior cell with all six neighbours: the stage for rings.
const CENTRE := Vector2i(4, 4)
const SEED := 777

var game: Game
var step_index := 0
var complete := false
## Where the player should look: the controller moves the cursor here.
var suggested_vertex := 0

var _steps: Array = []


func _init(run_seed: int = SEED) -> void:
	_steps = [
		{
			"id": "clear",
			"title": "Spin to clear",
			"instruction": "Move the cursor and spin with Z or X. Three gems of one colour meeting at a point clear away.",
		},
		{
			"id": "stars",
			"title": "Bonus stars",
			"instruction": "Bonus stars multiply a clear. Three of them together blow away everything they touch. Make any spin.",
		},
		{
			"id": "starflower",
			"title": "Flowers bloom",
			"instruction": "Six gems of one colour ringing a different centre bloom into a starflower. Make any spin to finish this ring.",
		},
		{
			"id": "turn",
			"title": "Turning a starflower",
			"instruction": "A starflower can be turned on its own: press F (or click it) to cycle all six neighbours.",
		},
		{
			"id": "pearl",
			"title": "Black pearls",
			"instruction": "Six starflowers ringing a centre make a black pearl. Three pearls, or six in a ring, end the run in a perfect finish.",
		},
	]

	var ruleset := RulesetScript.gems_only()
	ruleset.mode = RulesetScript.Mode.MARATHON
	# Forgiving rotation: in a tutorial every spin should do something.
	ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	game = GameScript.new(run_seed, ruleset)
	_setup_step()


# --- queries ----------------------------------------------------------------

func step_title() -> String:
	if complete:
		return "Tutorial complete"
	return str(_current()["title"])


func instruction() -> String:
	if complete:
		return "That is every mechanic. Pick a mode from the menu and build toward a pearl ring."
	return str(_current()["instruction"])


func step_number() -> int:
	return mini(step_index + 1, _steps.size())


func step_count() -> int:
	return _steps.size()


func goal_id() -> String:
	if complete:
		return ""
	return str(_current()["id"])


## The vertex the player should be looking at for this step.
func hint_vertex() -> int:
	return suggested_vertex


# --- evaluation -------------------------------------------------------------

## Feed the result of the player's move. Returns true when the step advanced.
func evaluate(result: MoveResult) -> bool:
	if complete or result == null or not result.committed:
		return false
	if not _goal_met(str(_current()["id"]), result):
		return false

	step_index += 1
	if step_index >= _steps.size():
		complete = true
		return true
	_setup_step()
	return true


func _goal_met(goal: String, result: MoveResult) -> bool:
	match goal:
		"clear":
			return result.cleared_count >= 3
		"stars":
			return _has_formation(result, "bonus_star_cluster")
		"starflower":
			return _has_promotion(result, "starflower")
		"turn":
			return result.committed and result.piece_cell != Vector2i(-1, -1)
		"pearl":
			return _has_promotion(result, "pearl")
	return false


func _has_formation(result: MoveResult, name: String) -> bool:
	for group in result.clear_groups:
		if group.has_formation(name):
			return true
	return false


func _has_promotion(result: MoveResult, kind: String) -> bool:
	for promotion: Dictionary in result.promotions:
		if str(promotion.get("kind", "")) == kind:
			return true
	return false


# --- board rigging ----------------------------------------------------------

func _current() -> Dictionary:
	return _steps[mini(step_index, _steps.size() - 1)]


func _setup_step() -> void:
	_paint_background()
	match str(_current()["id"]):
		"clear":
			_setup_clear()
		"stars":
			_setup_bonus_stars()
		"starflower":
			_setup_flower()
		"turn":
			_setup_starflower()
		"pearl":
			_setup_pearl_ring()


## A triple with a stranger in it: spinning the vertex beside it brings a
## matching gem in, so the very first spin always clears something.
func _setup_clear() -> void:
	game.board.set_piece(Vector2i(4, 4), Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(Vector2i(4, 5), Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(Vector2i(3, 4), Pieces.gem(Pieces.GemColor.BLUE))
	game.board.set_piece(Vector2i(3, 3), Pieces.gem(Pieces.GemColor.RED))
	suggested_vertex = _vertex_near(Vector2i(4, 4))


## Fills the board with a pattern that cannot match: the colour index is
## (2q + r) mod 5, and no vertex's three cells share that value.
func _paint_background() -> void:
	var palette: Array = Pieces.BASE_COLORS
	game.board.clear_locks()
	for cell: Vector2i in Grid.all_cells():
		game.board.set_piece(cell, Pieces.gem(palette[(2 * cell.x + cell.y) % palette.size()]))


func _setup_bonus_stars() -> void:
	# A star cluster sitting ready to go off on the player's next spin.
	var triangle := [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]
	var colors := [Pieces.GemColor.RED, Pieces.GemColor.GREEN, Pieces.GemColor.BLUE]
	for index in triangle.size():
		game.board.set_piece(triangle[index], Pieces.bonus_star(colors[index]))
	suggested_vertex = _vertex_near(triangle[0])


func _setup_flower() -> void:
	# Six red gems already ringing a blue centre: any spin lets it bloom.
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))
	suggested_vertex = _vertex_near(CENTRE)


func _setup_starflower() -> void:
	# A starflower whose neighbours are six different colours, so turning it is
	# the only thing that happens.
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))
	suggested_vertex = _vertex_near(CENTRE)


func _setup_pearl_ring() -> void:
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.YELLOW))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.starflower())
	suggested_vertex = _vertex_near(CENTRE)


## A rotation vertex that touches `cell`, so the cursor has something to point at.
func _vertex_near(cell: Vector2i) -> int:
	var vertices := Grid.vertices()
	for index in vertices.size():
		if (vertices[index] as Array).has(cell):
			return index
	return 0
