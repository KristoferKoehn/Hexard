class_name GemPainter
extends RefCounted

## The single definition of what a gem looks like.
##
## BoardView draws the board's gems with this, and the menu backdrop draws the same
## thing, so the menu cannot show a game that does not exist. The first version of the
## menu flourish hand-rolled a flat hexagon with one highlight, which is why it did not
## look like the board: five layers are what make a gem read as a bevelled stone.
##
## One light, from the top left: cast shadow underneath, darkened rim, the face inset
## inside it, a specular patch up-left, an inner shadow down-right. `alpha` dims the
## whole piece for backdrops; the board passes 1.0.

const GemGlyphsScript := preload("res://src/view/gem_glyphs.gd")


static func draw(
	canvas: CanvasItem, centre: Vector2, radius: float, base: Color, color: int,
	alpha: float = 1.0, with_glyph: bool = true
) -> void:
	if radius <= 0.5:
		return
	var face := Color(base.r, base.g, base.b, alpha)
	canvas.draw_colored_polygon(
		corners(centre + Vector2(radius * 0.09, radius * 0.13), radius * 0.97),
		Color(0, 0, 0, 0.32 * alpha)
	)
	canvas.draw_colored_polygon(corners(centre, radius), base.darkened(0.34))
	canvas.draw_colored_polygon(
		corners(centre - Vector2(radius * 0.03, radius * 0.04), radius * 0.86), face
	)
	canvas.draw_colored_polygon(
		corners(centre - Vector2(radius * 0.13, radius * 0.27), radius * 0.44),
		Color(1, 1, 1, 0.30 * alpha)
	)
	canvas.draw_colored_polygon(
		corners(centre + Vector2(radius * 0.17, radius * 0.31), radius * 0.28),
		Color(0, 0, 0, 0.18 * alpha)
	)
	if with_glyph:
		GemGlyphsScript.draw(canvas, centre, radius, color, base)


## A flat-top hexagon at an arbitrary centre, which the grid's own corners() cannot
## express (it takes a cell and derives its centre).
static func corners(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 6:
		var angle := deg_to_rad(60.0 * float(index))
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
