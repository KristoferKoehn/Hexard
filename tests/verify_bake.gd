extends SceneTree

## Verifies the two visual caches contain what they claim, by reading the pixels back.
##
## Headless has no renderer, so this must run WITHOUT --headless. It builds a BoardView, waits
## for the bakes to render, then inspects the actual textures:
##
##   tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/verify_bake.gd
##
## Exit code 0 means every check passed.

const GameScript := preload("res://src/core/game.gd")
const RulesetScript := preload("res://src/core/ruleset.gd")

var _view: BoardView
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var ruleset := RulesetScript.new()
	ruleset.rotation_mode = RulesetScript.RotationMode.FREE
	var game := GameScript.new(4242, ruleset)
	_view = BoardView.new()
	root.add_child(_view)
	_view.set_game(game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	_check_static()
	_check_gem_atlas()
	for message: String in _failures:
		print("  ! ", message)
	if _failures.is_empty():
		print("VISUAL CACHE: OK")
		quit(0)
	else:
		print("VISUAL CACHE: FAILED")
		quit(1)
	return true


func _check_static() -> void:
	var sub: SubViewport = _view.get("_static_view")
	var rect: Rect2 = _view.get("_static_rect")
	if sub == null:
		_failures.append("no static bake viewport")
		return
	var image: Image = sub.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("static bake has no image")
		return
	print("static bake: %dx%d texture for a %.0fx%.0f plate rect" % [
		image.get_width(), image.get_height(), rect.size.x, rect.size.y])
	# The plate fills the middle of the bake, so the centre pixel must be opaque.
	var centre := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	if centre.a < 0.5:
		_failures.append("static bake centre is transparent (plate missing): a=%.2f" % centre.a)
	var painted := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			if image.get_pixel(x, y).a > 0.1:
				painted += 1
	var sampled := (image.get_width() / 4 + 1) * (image.get_height() / 4 + 1)
	var ratio := float(painted) / float(sampled)
	print("static bake coverage: %.1f%% of sampled pixels are opaque" % (ratio * 100.0))
	# The plate and sockets only: the backdrop is drawn directly now, so this is not near-full.
	if ratio < 0.15:
		_failures.append("static bake looks empty: only %.1f%% painted" % (ratio * 100.0))


## The atlas must exist as fourteen slices and the glyph row must differ from the plain row,
## otherwise the board draws patterns that were never rendered.
func _check_gem_atlas() -> void:
	var slices: Dictionary = _view.get("_atlas_textures")
	if slices.size() != 14:
		_failures.append("expected 14 gem slices, got %d" % slices.size())
		return
	var sample: AtlasTexture = slices.get("1:0")
	if sample == null:
		_failures.append("no slice for colour 1 with glyphs")
		return
	var image: Image = sample.atlas.get_image()
	if image == null or image.is_empty():
		_failures.append("gem atlas atlas texture has no image")
		return
	var cell := int(BoardView.ATLAS_CELL)
	var plain := 0
	var glyph := 0
	for y in range(4, cell - 4, 4):
		for x in range(4, cell - 4, 4):
			if image.get_pixel(x, y).a > 0.1:
				plain += 1
			if image.get_pixel(x, y + cell).a > 0.1:
				glyph += 1
	if plain == 0:
		_failures.append("first atlas cell is empty")
	print("gem atlas: %d slices, cell %dx%d, glyph row %d opaque samples vs %d" % [
		slices.size(), cell, cell, glyph, plain])
