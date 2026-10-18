class_name NeonStyle
extends RefCounted

## The neon palette and the two control styles built from it, in one place.
##
## The HUD and the settings screen had drifted into two copies of the same seven
## colours and two *different* button styles, so a screen could not be re-themed
## without editing both and comparing them by eye.

const ACCENT := Color("35e0f0")
const TEXT := Color("d9eef9")
const DIM := Color("6f8496")
const PANEL := Color("0b101c")
const BORDER := Color("1d3b4d")
const AMBER := Color("ffd166")
const GOOD := Color("8ef0a0")

const PANEL_STYLE := Color("102438")
const PRESSED_STYLE := Color("0d2b3a")


## Dark fill, hairline border, brightening to the accent on hover and press.
static func style_button(button: Button, font_size: int = 18) -> void:
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", box(PANEL, BORDER))
	button.add_theme_stylebox_override("hover", box(PANEL_STYLE, ACCENT))
	button.add_theme_stylebox_override("pressed", box(PRESSED_STYLE, ACCENT))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(ACCENT, 0.55)))


static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(1)
	style.border_color = border
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.anti_aliasing = true
	return style


## The plate a screen sits on: rounded, rimmed, padded.
static func panel_box(radius: int = 46) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(radius)
	style.set_border_width_all(2)
	style.border_color = ACCENT
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	style.anti_aliasing = true
	return style


## A label in the house style. `outline` gives text the glow the board uses.
static func label(text: String, font_size: int, color: Color, outline: int = 0) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	if outline > 0:
		control.add_theme_color_override("font_outline_color", Color(0.09, 0.60, 0.76, 0.85))
		control.add_theme_constant_override("outline_size", outline)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control
