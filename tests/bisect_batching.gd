extends SceneTree

## Bisects what in a gem's drawing costs draw calls. Windowed:
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-driver opengl3 \
##       --script res://tests/bisect_batching.gd
##
## Hypothesis from the marginal measurement: 5.3 draws per gem, and GemPainter issues exactly
## five draw_colored_polygon calls. If a polygon is one draw call and a textured quad batches,
## the fix is to stop drawing gems out of polygons.

const COUNT := 85
const GemPainterScript := preload("res://src/view/gem_painter.gd")

var _painter: Node2D
var _frame := 0
var _lines: Array[String] = []
var _texture: ImageTexture


class Painter:
	extends Node2D
	enum Mode { POLYGONS, QUADS, GEM_FULL, GEM_NO_GLYPH }
	var mode := Mode.POLYGONS
	var count := 0
	var texture: Texture2D
	var GemPainterScript := preload("res://src/view/gem_painter.gd")

	func _draw() -> void:
		for index in count:
			var centre := Vector2(float(index % 17) * 44.0 + 30.0, float(index / 17) * 44.0 + 30.0)
			match mode:
				Mode.POLYGONS:
					draw_colored_polygon(_hex(centre, 18.0), Color(0.3, 0.6, 0.9, 1.0))
				Mode.QUADS:
					draw_texture_rect(texture, Rect2(centre - Vector2(18, 18), Vector2(36, 36)), false)
				Mode.GEM_FULL:
					GemPainterScript.draw(self, centre, 18.0, Color(0.3, 0.6, 0.9), (index % 7) + 1, 1.0, true)
				Mode.GEM_NO_GLYPH:
					GemPainterScript.draw(self, centre, 18.0, Color(0.3, 0.6, 0.9), (index % 7) + 1, 1.0, false)

	func _hex(centre: Vector2, radius: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in 6:
			var angle := deg_to_rad(60.0 * float(index))
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		return points


func _initialize() -> void:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.9, 1.0))
	_texture = ImageTexture.create_from_image(image)
	_painter = Painter.new()
	root.add_child(_painter)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		4:
			_configure(Painter.Mode.POLYGONS, "85 x draw_colored_polygon")
		8:
			_sample("85 x draw_colored_polygon")
		10:
			_configure(Painter.Mode.QUADS, "85 x draw_texture_rect")
		14:
			_sample("85 x draw_texture_rect")
		16:
			_configure(Painter.Mode.GEM_FULL, "85 x GemPainter + glyph")
		20:
			_sample("85 x GemPainter + glyph")
		22:
			_configure(Painter.Mode.GEM_NO_GLYPH, "85 x GemPainter, no glyph")
		26:
			_sample("85 x GemPainter, no glyph")
		30:
			for line: String in _lines:
				print(line)
			quit(0)
	return false


func _configure(mode: int, _label: String) -> void:
	var painter: Painter = _painter
	painter.mode = mode
	painter.count = COUNT
	painter.texture = _texture
	painter.queue_redraw()


func _sample(label: String) -> void:
	_lines.append("%-34s draw %4d   objects %4d   primitives %5d" % [
		label,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])
