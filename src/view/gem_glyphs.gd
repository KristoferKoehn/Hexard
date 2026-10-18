class_name GemGlyphs
extends RefCounted

## A distinct mark per gem colour, so the board is readable without relying on hue
## alone (docs/design.md §8 — colour-blind accessibility).
##
## One *shape category* per hue: dot, bars, dot grid, slash, triangle, square,
## chevron. None differs from another only by rotation or size, none needs fine
## detail that vanishes at gem size, and each is a handful of primitives.
##
## The mark's colour is chosen from the gem's luminance rather than fixed, so light
## gems (yellow, cyan) get a dark mark and dark gems (blue, violet) get a light one.

const Pieces := preload("res://src/core/piece.gd")

enum Kind { NONE, DOT, BARS, DOT_GRID, SLASH, TRIANGLE, SQUARE, CHEVRON }

const DARK_MARK := Color(0.05, 0.06, 0.09, 0.60)
const LIGHT_MARK := Color(1.0, 1.0, 1.0, 0.66)
## Gems above this (linear) luminance get a dark mark. Tuned so mid-green and
## orange take a dark mark while violet and red take a light one.
const LIGHT_GEM_THRESHOLD := 0.32


static func kind_for(color: int) -> int:
	match color:
		Pieces.GemColor.RED:
			return Kind.DOT
		Pieces.GemColor.ORANGE:
			return Kind.BARS
		Pieces.GemColor.YELLOW:
			return Kind.DOT_GRID
		Pieces.GemColor.GREEN:
			return Kind.SLASH
		Pieces.GemColor.CYAN:
			return Kind.TRIANGLE
		Pieces.GemColor.BLUE:
			return Kind.SQUARE
		Pieces.GemColor.VIOLET:
			return Kind.CHEVRON
		_:
			return Kind.NONE


## WCAG relative luminance: the channels are linearised first. Using the raw
## gamma-encoded values makes a saturated blue read as bright as a deep red, which is
## both wrong for contrast decisions and hides the palette's lightness ladder.
static func luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


static func _linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


static func mark_color(base: Color) -> Color:
	return DARK_MARK if luminance(base) > LIGHT_GEM_THRESHOLD else LIGHT_MARK


## Draws the mark for `color` centred on a gem of the given base colour.
static func draw(canvas: CanvasItem, centre: Vector2, radius: float, color: int, base: Color) -> void:
	var kind := kind_for(color)
	if kind == Kind.NONE or radius <= 1.0:
		return
	var mark := mark_color(base)
	# Nudged down-right so the mark never sits under the bevel highlight.
	var at := centre + Vector2(radius * 0.04, radius * 0.07)

	match kind:
		Kind.DOT:
			canvas.draw_circle(at, radius * 0.30, mark)
		Kind.BARS:
			var width := radius * 0.34
			for step in [-1, 0, 1]:
				var y := at.y + float(step) * radius * 0.26
				canvas.draw_line(
					Vector2(at.x - width, y), Vector2(at.x + width, y), mark, radius * 0.11
				)
		Kind.DOT_GRID:
			for dx in [-1, 1]:
				for dy in [-1, 1]:
					canvas.draw_circle(
						Vector2(at.x + float(dx) * radius * 0.20, at.y + float(dy) * radius * 0.20),
						radius * 0.13, mark
					)
		Kind.SLASH:
			canvas.draw_line(
				Vector2(at.x - radius * 0.32, at.y + radius * 0.32),
				Vector2(at.x + radius * 0.32, at.y - radius * 0.32),
				mark, radius * 0.13
			)
		Kind.TRIANGLE:
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(at.x, at.y - radius * 0.34),
				Vector2(at.x - radius * 0.32, at.y + radius * 0.24),
				Vector2(at.x + radius * 0.32, at.y + radius * 0.24),
			]), mark)
		Kind.SQUARE:
			var half := radius * 0.28
			canvas.draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), mark, false, radius * 0.11)
		Kind.CHEVRON:
			canvas.draw_line(
				Vector2(at.x - radius * 0.30, at.y - radius * 0.20),
				Vector2(at.x, at.y + radius * 0.12), mark, radius * 0.12
			)
			canvas.draw_line(
				Vector2(at.x, at.y + radius * 0.12),
				Vector2(at.x + radius * 0.30, at.y - radius * 0.20), mark, radius * 0.12
			)
