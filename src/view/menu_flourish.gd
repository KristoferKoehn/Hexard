class_name MenuFlourish
extends Node2D

## Ambient decoration for the main menu: gems orbiting the screen edge, slowly.
##
## Drawn on the menu layer behind the panel, so it cannot fight the layout, and built
## from the real palette and glyph set rather than invented art: the menu shows what the
## game actually looks like. One orbit every ~40 seconds, far below the threshold where
## motion becomes something to switch off.

const BoardViewScript := preload("res://src/view/board_view.gd")

const COUNT := 12
## Radians per second. Slow enough to read as drift, not as animation.
const SPIN := 0.055
const GEM_RADIUS := 21.0
## Fraction of the screen the orbit ellipse covers, and how much it drifts vertically.
const ORBIT_X := 0.44
const ORBIT_Y := 0.38

var _angle := 0.0
var _draw_clock := 0.0
## Follows the colour-patterns setting: the accessibility marks belong on every gem the
## player can see, including the ones on the menu.
var show_glyphs := true


func _ready() -> void:
	# Behind the menu panel, but still inside the HUD's own draw order.
	z_index = -1


func _process(delta: float) -> void:
	if not visible:
		return
	_angle = fmod(_angle + delta * SPIN, TAU)
	# The orbit turns 0.055 rad/s, which is under a pixel per frame at these radii. Redrawing
	# every frame buys nothing visible and costs a full canvas pass, so it runs at a third.
	_draw_clock += delta
	if _draw_clock < 1.0 / 20.0:
		return
	_draw_clock = 0.0
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var area := Vector2(get_viewport_rect().size)
	var centre := area * 0.5
	var order: Array = BoardViewScript.GEM_COLORS.keys()
	for index in COUNT:
		var angle := _angle + TAU * float(index) / float(COUNT)
		var at := centre + Vector2(cos(angle) * area.x * ORBIT_X, sin(angle) * area.y * ORBIT_Y)
		var color := int(order[index % order.size()])
		var base: Color = BoardViewScript.GEM_COLORS[color]
		# The far side of the orbit sits a little back: size and alpha both fall off.
		var depth := 0.72 + 0.28 * (sin(angle) * 0.5 + 0.5)
		# Opaque enough to read as gems: the first pass at 0.2-0.4 alpha looked like
		# dust on the screen. Depth still separates the near and far sides.
		_draw_gem(at, GEM_RADIUS * depth, base, color, 0.70 * depth + 0.28)


func _draw_gem(centre: Vector2, radius: float, base: Color, color: int, alpha: float) -> void:
	# The board's own gem, dimmed: a backdrop has to look like the game it advertises.
	GemPainter.draw(self, centre, radius, base, color, alpha, show_glyphs)
