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
			_rig_ring(game, Pieces.GemColor.RED, Pieces.gem(Pieces.GemColor.RED))
		"turn":
			_rig_turn(game)
		"pearl":
			_rig_ring(game, Pieces.GemColor.RED, Pieces.starflower())
	return game


## The cell the demonstration rotates its piece into.
static func slot_cell(id: String) -> Vector2i:
	match id:
		"stars":
			return _star_triangle()[2]
		"turn":
			return CENTRE
		_:
			return Grid.cyclic_order(Grid.neighbours(CENTRE))[0]


## The one move worth watching: the rotation that carries the missing piece into its slot.
## Found once per clip and cached, because it is a property of the rig rather than of the
## board it runs on.
static func play(game: Game, id: String) -> MoveResult:
	if id == "turn":
		return game.rotate_piece(CENTRE, GameScript.CLOCKWISE)
	if not _moves.has(id):
		_moves[id] = _find_completing_move(id)
	var move: Dictionary = _moves.get(id, {})
	if not move.is_empty():
		return game.rotate(int(move["vertex"]), int(move["direction"]))
	var rotations := game.find_legal_rotations()
	if rotations.is_empty():
		return game.rotate(0, GameScript.CLOCKWISE)
	return game.rotate(int(rotations[0]["vertex"]), int(rotations[0]["direction"]))


## Only trios that contain the missing slot can complete it, so this is twelve candidates
## rather than the whole board.
static func _find_completing_move(id: String) -> Dictionary:
	var slot := slot_cell(id)
	var vertices := Grid.vertices()
	for vertex_index in vertices.size():
		if not (vertices[vertex_index] as Array).has(slot):
			continue
		for direction in [GameScript.CLOCKWISE, GameScript.COUNTER_CLOCKWISE]:
			# A fresh game per candidate: rotate() resolves and mutates, and there is no
			# cheap undo for score, bombs or run state.
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
static func _rig_ring(game: Game, _ring_color: int, ring_piece: int) -> void:
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	game.board.set_piece(CENTRE, Pieces.gem(Pieces.GemColor.BLUE))
	for index in ring.size():
		game.board.set_piece(ring[index], ring_piece if index > 0 else Pieces.gem(Pieces.GemColor.BLUE))
	_place_arriving_piece(game, ring[0], ring, ring_piece)


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


static func _rig_turn(game: Game) -> void:
	game.board.set_piece(CENTRE, Pieces.starflower())
	var ring := Grid.cyclic_order(Grid.neighbours(CENTRE))
	for index in ring.size():
		game.board.set_piece(ring[index], Pieces.gem(index + 1))


static var _moves := {}


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
