class_name TutorialLibrary
extends RefCounted

## The tutorial's content: five canned demonstrations, each a rigged board plus the one
## move that shows the mechanic.
##
## These replace the scripted interactive tutorial. The point is to *show* what happens,
## so the setups are legal but artificial: a match-free background with one formation
## under test. The clip player replays the move through the real board renderer, which is
## why the demonstration cannot drift from the game.

const Grid := preload("res://src/core/hex_grid.gd")
const Pieces := preload("res://src/core/piece.gd")
const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")

const CENTRE := Vector2i(4, 4)
const SEED := 777

const CLIPS := [
	{
		"id": "clear",
		"title": "Spin to clear",
		"text": "Three gems of one colour meeting at a point clear away. Spin a trio so the third colour lines up.",
	},
	{
		"id": "stars",
		"title": "Bonus stars",
		"text": "Three bonus stars together blow away everything they touch.",
	},
	{
		"id": "flower",
		"title": "Flowers bloom",
		"text": "Six gems of one colour ringing a different centre bloom into a starflower.",
	},
	{
		"id": "turn",
		"title": "Turning a starflower",
		"text": "A starflower turns on its own, cycling all six of its neighbours.",
	},
	{
		"id": "pearl",
		"title": "Black pearls",
		"text": "Six starflowers ringing a centre make a black pearl.",
	},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for clip: Dictionary in CLIPS:
		out.append(str(clip["id"]))
	return out


static func clip(id: String) -> Dictionary:
	for entry: Dictionary in CLIPS:
		if str(entry["id"]) == id:
			return entry
	return {}


## A fresh rigged board for a clip. `gems_only` keeps specials out of the background so
## the demonstration is the only thing happening.
static func make_game(id: String) -> Game:
	var ruleset := RulesetScript.gems_only()
	ruleset.mode = RulesetScript.Mode.MARATHON
	# Demonstration boards always let the move through; the reference mode would refuse
	# a spin that clears nothing, and a few of these deliberately change nothing.
	ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var game := GameScript.new(SEED, ruleset)
	_paint_background(game)
	match id:
		"clear":
			game.board.set_piece(Vector2i(4, 4), Pieces.gem(Pieces.GemColor.RED))
			game.board.set_piece(Vector2i(4, 5), Pieces.gem(Pieces.GemColor.RED))
			game.board.set_piece(Vector2i(3, 4), Pieces.gem(Pieces.GemColor.BLUE))
			game.board.set_piece(Vector2i(3, 3), Pieces.gem(Pieces.GemColor.RED))
		"stars":
			_star_cluster(game)
		"flower":
			_flower_ring(game)
		"turn":
			_flower_with_colours(game)
		"pearl":
			_pearl_ring(game)
	return game


## The one move worth watching. `turn` is a piece turn; everything else is the first
## rotation the rules accept, which is by construction the one that demonstrates it.
static func play(game: Game, id: String) -> MoveResult:
	if id == "turn":
		return game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	var rotations := game.find_legal_rotations()
	if rotations.is_empty():
		return game.rotate(0, GameScript.CLOCKWISE)
	var move: Dictionary = rotations[0]
	return game.rotate(int(move["vertex"]), int(move["direction"]))


## Where the clip player should point its zoom.
static func focus_cell(id: String) -> Vector2i:
	match id:
		"stars":
			return Vector2i(4, 7)
		_:
			return CENTRE


static func _paint_background(game: Game) -> void:
	var palette: Array = Pieces.BASE_COLORS
	for cell: Vector2i in Grid.all_cells():
		game.board.set_piece(cell, Pieces.gem(palette[(2 * cell.x + cell.y) % palette.size()]))


static func _star_cluster(game: Game) -> void:
	var triangle := [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]
	var colors := [Pieces.GemColor.RED, Pieces.GemColor.GREEN, Pieces.GemColor.BLUE]
	for index in triangle.size():
		game.board.set_piece(triangle[index], Pieces.bonus_star(colors[index]))


static func _flower_ring(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))


static func _flower_with_colours(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))


static func _pearl_ring(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.YELLOW))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.starflower())
