extends SceneTree

## Isolates how Godot batches textured quads, so the gem cost is measured rather than guessed.
## Windowed:
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-driver opengl3 \
##       --script res://tests/measure_batching.gd
##
## Three cases, 85 quads each:
##   A  one texture for every quad
##   B  14 AtlasTextures over one shared sheet (what the gem atlas does)
##   C  14 separate textures

const COUNT := 85
const COLS := 14
const CELL := 96


class QuadPainter:
	extends Node2D
	var textures: Array = []
	var count := 0
	var modulated := false

	func _draw() -> void:
		if textures.is_empty():
			return
		for index in count:
			var texture: Texture2D = textures[index % textures.size()]
			var x := float(index % 17) * 40.0
			var y := float(index / 17) * 40.0
			if modulated:
				draw_texture_rect(texture, Rect2(x, y, 32, 32), false,
					Color(1.0, 1.0, 1.0, 1.0))
			else:
				draw_texture_rect(texture, Rect2(x, y, 32, 32), false)


var _painter: QuadPainter
var _frame := 0
var _lines: Array[String] = []
var _sheet: ImageTexture
var _slices: Array = []
var _separate: Array = []


func _initialize() -> void:
	var image := Image.create(CELL * COLS, CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.9, 1.0))
	_sheet = ImageTexture.create_from_image(image)
	for col in COLS:
		var slice := AtlasTexture.new()
		slice.atlas = _sheet
		slice.region = Rect2(col * CELL, 0, CELL, CELL)
		_slices.append(slice)
		var own := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		own.fill(Color(0.9, 0.4, 0.2).lerp(Color(0.2, 0.9, 0.4), float(col) / float(COLS)))
		_separate.append(ImageTexture.create_from_image(own))
	_painter = QuadPainter.new()
	root.add_child(_painter)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		4:
			_painter.textures = [_sheet]
			_painter.count = COUNT
			_painter.queue_redraw()
		8:
			_sample("A  one texture, 85 quads")
		10:
			_painter.textures = _slices
			_painter.count = COUNT
			_painter.queue_redraw()
		14:
			_sample("B  14 AtlasTextures, one sheet")
		16:
			_painter.textures = _separate
			_painter.count = COUNT
			_painter.queue_redraw()
		20:
			_sample("C  14 separate textures")
		22:
			_painter.textures = _slices
			_painter.modulated = true
			_painter.queue_redraw()
		26:
			_sample("D  14 AtlasTextures + per-quad modulate")
		24:
			for line: String in _lines:
				print(line)
			quit(0)
	return false


func _sample(label: String) -> void:
	_lines.append("%-40s draw %4d   objects %4d   primitives %5d" % [
		label,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])
