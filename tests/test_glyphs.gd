extends "res://tests/test_case.gd"

## Gem glyphs: the accessibility marks that make the board readable without hue.

const SettingsScript := preload("res://src/core/settings.gd")

const COLORS := [
	Piece.GemColor.RED, Piece.GemColor.ORANGE, Piece.GemColor.YELLOW,
	Piece.GemColor.GREEN, Piece.GemColor.CYAN, Piece.GemColor.BLUE,
	Piece.GemColor.VIOLET,
]


func test_every_colour_gets_its_own_shape_category() -> void:
	var seen := {}
	for color: int in COLORS:
		var kind := GemGlyphs.kind_for(color)
		assert_ne(kind, GemGlyphs.Kind.NONE, "colour %d has a mark" % color)
		assert_false(seen.has(kind), "two colours must not share a glyph (kind %d)" % kind)
		seen[kind] = color
	assert_eq(seen.size(), COLORS.size(), "seven colours, seven distinct marks")


func test_colourless_and_unknown_pieces_get_no_mark() -> void:
	assert_eq(GemGlyphs.kind_for(Piece.GemColor.NONE), GemGlyphs.Kind.NONE, "no colour, no glyph")
	assert_eq(GemGlyphs.kind_for(99), GemGlyphs.Kind.NONE, "an unknown colour is not a crash")


func test_the_mark_contrasts_with_the_gem() -> void:
	# Light gems get a dark mark and dark gems a light one, decided from luminance so
	# no hue ends up with an unreadable mark.
	var dark_mark := GemGlyphs.mark_color(Color("fae353"))   # yellow
	var light_mark := GemGlyphs.mark_color(Color("2f58c8"))  # blue
	assert_lt(GemGlyphs.luminance(dark_mark), 0.5, "yellow carries a dark mark")
	assert_gt(GemGlyphs.luminance(light_mark), 0.5, "blue carries a light mark")


func test_the_palette_is_a_lightness_ladder() -> void:
	# The ladder is what carries the palette through red-green colour blindness, so
	# assert it exists rather than trusting the hex values by eye.
	var ladder := {
		Piece.GemColor.BLUE: Color("2f58c8"), Piece.GemColor.RED: Color("d73337"),
		Piece.GemColor.VIOLET: Color("ad67dc"), Piece.GemColor.GREEN: Color("43b966"),
		Piece.GemColor.ORANGE: Color("fc9a10"), Piece.GemColor.CYAN: Color("34dde5"),
		Piece.GemColor.YELLOW: Color("fae353"),
	}
	var previous := -1.0
	for color: int in [
		Piece.GemColor.BLUE, Piece.GemColor.RED, Piece.GemColor.VIOLET,
		Piece.GemColor.GREEN, Piece.GemColor.ORANGE, Piece.GemColor.CYAN,
		Piece.GemColor.YELLOW,
	]:
		var luminance := GemGlyphs.luminance(ladder[color])
		assert_gt(luminance, previous, "colour %d is lighter than the one before it" % color)
		if previous >= 0.0:
			# Order alone is not enough: two neighbours a thousandth apart would still
			# be indistinguishable in greyscale.
			assert_ge(luminance - previous, 0.03, "colour %d is measurably lighter" % color)
		previous = luminance


func test_glyphs_are_on_by_default_and_round_trip() -> void:
	var settings := SettingsScript.new()
	assert_true(settings.colour_patterns, "accessibility marks are on by default")
	var data := settings.to_dictionary()
	assert_true(bool(data["colour_patterns"]), "and are saved")
	settings.colour_patterns = false
	var reloaded := SettingsScript.new()
	reloaded.apply_dictionary(settings.to_dictionary())
	assert_false(reloaded.colour_patterns, "switching them off survives a save")
