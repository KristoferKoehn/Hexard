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
const GEM_RADIUS := 17.0
## Fraction of the screen the orbit ellipse covers, and how much it drifts vertically.
const ORBIT_X := 0.44
const ORBIT_Y := 0.38

var _angle := 0.0


func _ready() -> void:
	# Behind the menu panel, but still inside the HUD's own draw order.
	z_index = -1


func _process(delta: float) -> void:
	if not visible:
		return
	_angle = fmod(_angle + delta * SPIN, TAU)
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
		_draw_gem(at, GEM_RADIUS * depth, base, color, 0.30 * depth + 0.12)


func _draw_gem(centre: Vector2, radius: float, base: Color, color: int, alpha: float) -> void:
	var corners := _corners(centre, radius)
	draw_colored_polygon(corners, Color(base.r, base.g, base.b, alpha * 0.9))
	draw_colored_polygon(_corners(centre - Vector2(0.0, radius * 0.26), radius * 0.48),
		Color(1, 1, 1, alpha * 0.22))
	# The glyph comes along, faintly: it is the game's own visual language, not decoration.
	GemGlyphs.draw_mark(self, centre, radius, GemGlyphs.kind_for(color),
		GemGlyphs.mark_color(base) * Color(1, 1, 1, 0.55))


func _corners(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 6:
		var angle := deg_to_rad(60.0 * float(index))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
