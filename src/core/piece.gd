class_name Piece
extends RefCounted

## Piece taxonomy and the packed integer encoding used by Board.
##
## id = kind | (gem_color << 4) | (bomb_counter << 8)
##
## Keeping pieces as plain ints makes Board storage cheap and keeps game
## state trivially hashable for replays and golden tests.
##
## NOTE: the colour enum is GemColor, not Color — `Color` is a built-in
## Godot type and shadowing it breaks external enum resolution.

enum Kind { GEM, BONUS_STAR, STARFLOWER, PEARL, BOMB }

## NONE means "no colour" (starflower, pearl, empty). See docs/design.md §3.5.
enum GemColor { NONE, RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, VIOLET }

const EMPTY := 0
const _KIND_MASK := 0x0F
const _COLOR_MASK := 0x0F
const _COUNTER_MASK := 0xFF

const COLOR_NAMES := {
	GemColor.NONE: "none",
	GemColor.RED: "red",
	GemColor.ORANGE: "orange",
	GemColor.YELLOW: "yellow",
	GemColor.GREEN: "green",
	GemColor.CYAN: "cyan",
	GemColor.BLUE: "blue",
	GemColor.VIOLET: "violet",
}

const KIND_NAMES := {
	Kind.GEM: "gem",
	Kind.BONUS_STAR: "bonus_star",
	Kind.STARFLOWER: "starflower",
	Kind.PEARL: "pearl",
	Kind.BOMB: "bomb",
}

## Colours in play per level (docs/design.md §5.2). Level 1 starts with five.
const BASE_COLORS := [GemColor.RED, GemColor.YELLOW, GemColor.GREEN, GemColor.CYAN, GemColor.VIOLET]
const LATE_COLORS := {4: GemColor.ORANGE, 5: GemColor.BLUE}


# --- construction -----------------------------------------------------------

static func make(kind: Kind, gem_color: GemColor = GemColor.NONE, counter: int = 0) -> int:
	var id := int(kind) | (int(gem_color) << 4)
	if kind == Kind.BOMB:
		id |= (counter & _COUNTER_MASK) << 8
	return id


static func gem(gem_color: GemColor) -> int:
	return make(Kind.GEM, gem_color)


static func bonus_star(gem_color: GemColor) -> int:
	return make(Kind.BONUS_STAR, gem_color)


static func starflower() -> int:
	return make(Kind.STARFLOWER, GemColor.NONE)


static func pearl() -> int:
	return make(Kind.PEARL, GemColor.NONE)


static func bomb(gem_color: GemColor, counter: int) -> int:
	return make(Kind.BOMB, gem_color, counter)


# --- inspection -------------------------------------------------------------

static func kind_of(id: int) -> Kind:
	return (id & _KIND_MASK) as Kind


static func color_of(id: int) -> GemColor:
	return ((id >> 4) & _COLOR_MASK) as GemColor


static func counter_of(id: int) -> int:
	return (id >> 8) & _COUNTER_MASK


static func with_counter(id: int, counter: int) -> int:
	return (id & 0x00FF) | ((counter & _COUNTER_MASK) << 8)


static func is_empty(id: int) -> bool:
	return id == EMPTY


static func is_bonus_star(id: int) -> bool:
	return kind_of(id) == Kind.BONUS_STAR


static func is_starflower(id: int) -> bool:
	return kind_of(id) == Kind.STARFLOWER


static func is_pearl(id: int) -> bool:
	return kind_of(id) == Kind.PEARL


static func is_bomb(id: int) -> bool:
	return kind_of(id) == Kind.BOMB


## Gems, bonus stars and bombs carry a colour that participates in matching.
static func has_color(id: int) -> bool:
	var kind := kind_of(id)
	return kind == Kind.GEM or kind == Kind.BONUS_STAR or kind == Kind.BOMB


## Colours available for new gems at a given level.
static func colors_for_level(level: int) -> Array:
	var colors: Array = BASE_COLORS.duplicate()
	for required_level: int in LATE_COLORS:
		if level >= required_level:
			colors.append(LATE_COLORS[required_level])
	return colors


static func describe(id: int) -> String:
	if is_empty(id):
		return "empty"
	var text: String = KIND_NAMES[kind_of(id)]
	if has_color(id):
		text += ":" + str(COLOR_NAMES[color_of(id)])
	if is_bomb(id):
		text += "(%d)" % counter_of(id)
	return text
