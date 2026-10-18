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
	{
		"id": "pearl_bloom",
		"title": "A pearl from a flower",
		"text": "Bloom a flower whose centre is already a starflower and the centre becomes a black pearl.",
	},
	{
		"id": "colour_wipe",
		"title": "Clearing a bomb",
		"text": "A bomb is defused when its own colour clears. With a bonus star of that colour in the group, every gem of that colour is wiped with it.",
	},
	{
		"id": "flower_cluster",
		"title": "Three starflowers",
		"text": "Three starflowers together pay a windfall and clear.",
	},
	{
		"id": "pearl_finish",
		"title": "The perfect finish",
		"text": "Three black pearls together end the run in a perfect finish.",
	},
	{
		"id": "bombs",
		"title": "Bombs",
		"text": "A bomb clears with its own colour, and its fuse ticks down every move. Clear it before it reaches zero.",
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


## A fresh rigged board for a clip. Every formation is built ONE PIECE SHORT: the ring (or
## triangle) is missing exactly one member, and a matching piece sits in a trio that shares
## that slot, so a single rotation carries it in. The first version rigged complete
## formations, which meant any move at all resolved them and the demonstrated rotation was
## unrelated to what happened on screen.
static func make_game(id: String) -> Game:
	var ruleset := RulesetScript.gems_only()
	ruleset.mode = RulesetScript.Mode.MARATHON
	ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var game := GameScript.new(SEED, ruleset)
	_paint_background(game)
	match id:
		"clear":
			_rig_clear(game)
		"stars":
			_rig_stars(game)
		"flower":
			_rig_ring(game, Pieces.gem(Pieces.GemColor.ORANGE), Pieces.gem(Pieces.GemColor.BLUE))
		"turn":
			_rig_turn(game)
		"pearl":
			_rig_ring(game, Pieces.starflower(), Pieces.gem(Pieces.GemColor.BLUE))
		"bombs":
			_rig_bombs(game)
		"pearl_bloom":
			# Ring of five reds around a starflower: the sixth is rotated in, and blooming a
			# flower whose centre is already a starflower makes a pearl.
			_rig_ring(game, Pieces.gem(Pieces.GemColor.ORANGE), Pieces.starflower())
		"colour_wipe":
			_rig_triangle(game, Pieces.bomb(Pieces.GemColor.RED, 3),
				Pieces.bonus_star(Pieces.GemColor.RED), Pieces.gem(Pieces.GemColor.RED))
		"flower_cluster":
			_rig_triangle(game, Pieces.starflower(), Pieces.starflower(), Pieces.starflower())
		"pearl_finish":
			_rig_triangle(game, Pieces.pearl(), Pieces.pearl(), Pieces.pearl())
	return game


## The cell the demonstration rotates its piece into.
static func slot_cell(id: String) -> Vector2i:
	match id:
		"stars":
			return _star_triangle()[2]
		"colour_wipe", "flower_cluster", "pearl_finish":
			return Grid.vertices()[_vertex_near(CENTRE)][2]
		"turn":
			return CENTRE
		_:
			return Grid.cyclic_order(Grid.neighbours(CENTRE))[0]


## The demonstration move per clip, found once by searching the rig and then written down:
## the rig is a fixture, so searching it at runtime was ~950ms of blocked frames on the
## first visit for an answer that never changes.
const BOMB_CELL := Vector2i(4, 4)

const DEMO_MOVES := {
	"clear": {"vertex": 38, "direction": 1},
	"stars": {"vertex": 37, "direction": 1},
	"flower": {"vertex": 35, "direction": 1},
	"pearl": {"vertex": 35, "direction": 1},
	"pearl_bloom": {"vertex": 35, "direction": 1},
	"colour_wipe": {"vertex": 37, "direction": 1},
	"flower_cluster": {"vertex": 37, "direction": 1},
	"pearl_finish": {"vertex": 37, "direction": 1},
}


## The one move worth watching: the rotation that carries the missing piece into its slot.
static func play(game: Game, id: String) -> MoveResult:
	if id == "turn":
		return game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	if id == "bombs":
		# NOTE: an already-monochrome triangle is not a reachable board state, so this rig is
		# wrong; the one-short replacement hangs inside the completing-move search and is
		# documented rather than shipped.
		return game.rotate(_vertex_near(BOMB_CELL), GameScript.CLOCKWISE)
	if DEMO_MOVES.has(id):
		var move: Dictionary = DEMO_MOVES[id]
		return game.rotate(int(move["vertex"]), int(move["direction"]))
	var rotations := game.find_legal_rotations()
	if rotations.is_empty():
		return game.rotate(0, GameScript.CLOCKWISE)
	return game.rotate(int(rotations[0]["vertex"]), int(rotations[0]["direction"]))


## The rotation that completes this clip's rig. Only trios containing the missing slot can
## do it, so this is twelve candidates rather than the whole board; callers cache the answer.
static func find_completing_move(id: String) -> Dictionary:
	var slot := slot_cell(id)
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		if not (vertices[vertex_index] as Array).has(slot):
			continue
		for direction in [GameScript.CLOCKWISE, GameScript.COUNTER_CLOCKWISE]:
			var probe := make_game(id)
			var result := probe.rotate(vertex_index, direction)
			if result.committed and _goal_met(id, result):
				return {"vertex": vertex_index, "direction": direction}
	return {}


## Did this move produce the thing the clip is about? Pure, so the tests can use it.
static func _goal_met(id: String, result: MoveResult) -> bool:
	match id:
		"clear":
			return result.cleared_count >= 3
		"stars":
			for group in result.clear_groups:
				if group.has_formation("bonus_star_cluster"):
					return true
			return false
		"flower":
			return _has_promotion(result, "starflower")
		"pearl":
			return _has_promotion(result, "pearl")
		"bombs":
			return result.bombs_defused > 0
		"pearl_bloom":
			return _has_promotion(result, "pearl")
		"colour_wipe":
			for group in result.clear_groups:
				if group.has_formation("bomb_colour_wipe"):
					return true
			return false
		"flower_cluster":
			return result.cleared_count > 0
		"pearl_finish":
			return result.finished
	return false


static func _has_promotion(result: MoveResult, kind: String) -> bool:
	for promotion: Dictionary in result.promotions:
		if str(promotion.get("kind", "")) == kind:
			return true
	return false


## Zoom for a clip, relative to the section default. The pearl promotion changes the
## centre and all six neighbours at once, so it needs to be seen further back.
static func zoom_for(id: String) -> float:
	return 0.9 if id == "pearl" else 1.0


## Cells a clip's outline should cover, when that is not simply the trio it rotates. These
## clips are about a formation, so the formation is outlined and the rotation happens
## elsewhere on the board.
static func subject_cells(id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match id:
		"pearl_bloom":
			return Grid.neighbours(CENTRE)
		"bombs":
			for cell: Vector2i in Grid.vertices()[_vertex_near(CENTRE)]:
				out.append(cell)
	return out


## Where the clip player points its zoom.
static func focus_cell(id: String) -> Vector2i:
	match id:
		"stars":
			return _star_triangle()[2]
		"clear":
			return Vector2i(4, 4)
		_:
			return CENTRE


## A rotation vertex that touches `cell`, so a clip has something to point at.
static func _vertex_near(cell: Vector2i) -> int:
	var vertices := Grid.vertices()
	for index in vertices.size():
		if (vertices[index] as Array).has(cell):
			return index
	return 0


static func _rig_clear(game: Game) -> void:
	game.board.set_piece(Vector2i(4, 4), Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(Vector2i(4, 5), Pieces.gem(Pieces.GemColor.RED))
	game.board.set_piece(Vector2i(3, 4), Pieces.gem(Pieces.GemColor.BLUE))
	game.board.set_piece(Vector2i(3, 3), Pieces.gem(Pieces.GemColor.RED))


static func _star_triangle() -> Array[Vector2i]:
	var vertex: Array = Grid.vertices()[_vertex_near(CENTRE)]
	var out: Array[Vector2i] = []
	for cell: Vector2i in vertex:
		out.append(cell)
	return out


static func _rig_stars(game: Game) -> void:
	var triangle := _star_triangle()
	game.board.set_piece(triangle[0], Pieces.bonus_star(Pieces.GemColor.RED))
	game.board.set_piece(triangle[1], Pieces.bonus_star(Pieces.GemColor.BLUE))
	game.board.set_piece(triangle[2], Pieces.gem(Pieces.GemColor.GREEN))
	_place_arriving_piece(game, triangle[2], triangle, Pieces.bonus_star(Pieces.GemColor.GREEN))


## Five ring cells of `ring_piece`, an odd cell at the slot, and `arriving` placed one
## rotation away in a trio that shares the slot.
static func _rig_ring(game: Game, ring_piece: int, centre_piece: int = -1) -> void:
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	if centre_piece < 0:
		centre_piece = Pieces.gem(Pieces.GemColor.BLUE)
	game.board.set_piece(CENTRE, centre_piece)
	for index in ring.size():
		game.board.set_piece(ring[index], ring_piece if index > 0 else Pieces.gem(Pieces.GemColor.BLUE))
	_place_arriving_piece(game, ring[0], ring, ring_piece)


## Two members of a vertex triangle in place, the third slot empty of the target kind, and
## one copy of it sitting in a trio that shares that slot: one rotation completes the shape.
static func _rig_triangle(game: Game, first: int, second: int, arriving: int) -> void:
	var trio: Array = Grid.vertices()[_vertex_near(CENTRE)]
	game.board.set_piece(trio[0], first)
	game.board.set_piece(trio[1], second)
	game.board.set_piece(trio[2], Pieces.gem(Pieces.GemColor.BLUE))
	_place_arriving_piece(game, trio[2], trio, arriving)


## Puts a copy of `piece` in a trio that shares `slot` and does not already hold it, so one
## rotation can carry it in.
static func _place_arriving_piece(game: Game, slot: Vector2i, avoid: Array, piece: int) -> void:
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		var trio: Array = vertices[vertex_index]
		if not trio.has(slot):
			continue
		for cell: Vector2i in trio:
			if cell == slot or avoid.has(cell) or cell == CENTRE:
				continue
			if Pieces.color_of(piece) == Pieces.color_of(game.board.get_piece(cell)) \
				and Pieces.kind_of(piece) == Pieces.kind_of(game.board.get_piece(cell)):
				continue
			game.board.set_piece(cell, piece)
			return


## A bomb sitting in a monochrome triangle of its own colour: any rotation of that trio
## leaves it monochrome, so the first move of the clip clears the group and defuses the bomb.
static func _rig_bombs(game: Game) -> void:
	var trio: Array = Grid.vertices()[_vertex_near(BOMB_CELL)]
	game.board.set_piece(trio[0], Pieces.bomb(Pieces.GemColor.BLUE, 3))
	for index in [1, 2]:
		game.board.set_piece(trio[index], Pieces.gem(Pieces.GemColor.BLUE))


static func _rig_turn(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))


static func _paint_background(game: Game) -> void:
	var palette: Array = Pieces.BASE_COLORS
	for cell: Vector2i in Grid.all_cells():
		game.board.set_piece(cell, Pieces.gem(palette[(2 * cell.x + cell.y) % palette.size()]))


static func _unused_star_cluster(game: Game) -> void:
	var triangle := [Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 7)]
	var colors := [Pieces.GemColor.RED, Pieces.GemColor.GREEN, Pieces.GemColor.BLUE]
	for index in triangle.size():
		game.board.set_piece(triangle[index], Pieces.bonus_star(colors[index]))


static func _unused_flower_ring(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.BLUE))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.gem(Pieces.GemColor.RED))


static func _unused_flower_with_colours(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))


static func _unused_pearl_ring(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.YELLOW))
	for cell: Vector2i in Grid.neighbours(CENTRE):
		game.board.set_piece(cell, Pieces.starflower())
