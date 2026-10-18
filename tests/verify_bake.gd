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
	if ratio < 0.3:
		_failures.append("static bake looks empty: only %.1f%% painted" % (ratio * 100.0))


func _check_gem_atlas() -> void:
	var sub: SubViewport = _view.get("_gem_view")
	var textures: Dictionary = _view.get("_gem_textures")
	var ready_flag: bool = _view.get("_gem_ready")
	if sub == null:
		_failures.append("no gem atlas viewport")
		return
	print("gem atlas: %d slices, ready=%s, viewport=%dx%d" % [
		textures.size(), str(ready_flag), sub.size.x, sub.size.y])
	if textures.size() != 14:
		_failures.append("expected 14 gem slices, got %d" % textures.size())
	var sheet: Image = sub.get_texture().get_image()
	if sheet == null:
		_failures.append("gem atlas has no image")
		return
	# Each cell must contain pixels, and the glyph and plain rows must differ.
	var cell: int = BoardView.GEM_ATLAS_CELL
	var empty := 0
	var differing := 0
	for col in BoardView.GEM_ATLAS_COLS:
		var plain := _cell_coverage(sheet, col, 1, cell)
		var glyph := _cell_coverage(sheet, col, 0, cell)
		if glyph < 0.02:
			empty += 1
		var diff := _cell_difference(sheet, col, 0, col, 1, cell)
		if diff > 0.01:
			differing += 1
		print("  colour %d: plain %.1f%%  glyph %.1f%%  difference %.2f" % [
			col, plain * 100.0, glyph * 100.0, diff])
	if empty > 0:
		_failures.append("%d gem cells are empty" % empty)
	if differing == 0:
		_failures.append("glyph and plain rows are identical - patterns are not drawn")


## Fraction of the cell's sampled pixels that are opaque.
func _cell_coverage(image: Image, col: int, row: int, cell: int) -> float:
	var painted := 0
	var sampled := 0
	for y in range(row * cell + 4, (row + 1) * cell - 4, 4):
		for x in range(col * cell + 4, (col + 1) * cell - 4, 4):
			sampled += 1
			if image.get_pixel(x, y).a > 0.1:
				painted += 1
	return float(painted) / maxf(float(sampled), 1.0)


## Mean absolute difference between the same cell in two rows.
func _cell_difference(image: Image, col_a: int, row_a: int, col_b: int, row_b: int, cell: int) -> float:
	var total := 0.0
	var sampled := 0
	for y in range(cell / 4, cell - cell / 4, 4):
		for x in range(cell / 4, cell - cell / 4, 4):
			var a := image.get_pixel(col_a * cell + x, row_a * cell + y)
			var b := image.get_pixel(col_b * cell + x, row_b * cell + y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			sampled += 1
	return total / maxf(float(sampled), 1.0)
