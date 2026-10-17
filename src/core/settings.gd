class_name Settings
extends RefCounted

## Player settings: audio levels, juice toggles, and key bindings
## (docs/design.md §8 "juice toggles", §9 meta).
##
## Kept engine-free like the rest of the core so it can be unit-tested headless.
## The save path is injectable because user:// is not writable in every sandbox;
## tests point it at a workspace file.

const VERSION := 1
const DEFAULT_PATH := "user://hexard_settings.json"

## Every rebindable action and its default keys. Several keys per action, because
## the defaults cover both arrows/WASD and X/E-style layout independence.
const DEFAULT_BINDINGS := {
	"cursor_up": [KEY_UP, KEY_W],
	"cursor_down": [KEY_DOWN, KEY_S],
	"cursor_left": [KEY_LEFT, KEY_A],
	"cursor_right": [KEY_RIGHT, KEY_D],
	"rotate_cw": [KEY_X, KEY_E],
	"rotate_ccw": [KEY_Z, KEY_Q],
	"turn_special": [KEY_F],
	"hint": [KEY_H],
	"new_board": [KEY_R],
	"toggle_rotation": [KEY_T],
	"restart": [KEY_R],
	"menu": [KEY_M],
	"quit": [KEY_ESCAPE],
}

## Order the settings screen lists them in, with the text it shows.
const ACTION_LABELS := {
	"cursor_up": "Cursor up",
	"cursor_down": "Cursor down",
	"cursor_left": "Cursor left",
	"cursor_right": "Cursor right",
	"rotate_cw": "Rotate clockwise",
	"rotate_ccw": "Rotate anticlockwise",
	"turn_special": "Turn starflower / pearl",
	"hint": "Hint",
	"new_board": "New board",
	"toggle_rotation": "Rotation mode",
	"restart": "Play again",
	"menu": "Back to menu",
	"quit": "Quit",
}

var master_volume := 0.8
var sfx_volume := 0.9
var muted := false

## Juice (docs/design.md §8). Reduced motion wins over the other two.
var screen_shake := true
var flashes := true
var reduced_motion := false

var bindings: Dictionary = {}


func _init() -> void:
	reset_bindings()


func reset_bindings() -> void:
	bindings = {}
	for action: String in DEFAULT_BINDINGS:
		var keys: Array[int] = []
		for key: int in DEFAULT_BINDINGS[action]:
			keys.append(key)
		bindings[action] = keys


# --- derived ----------------------------------------------------------------

## Shake is off entirely under reduced motion: that is the point of the setting.
func shake_enabled() -> bool:
	return screen_shake and not reduced_motion


func flashes_enabled() -> bool:
	return flashes and not reduced_motion


## Multiplier applied to animation durations. Reduced motion makes every step
## short and mechanical rather than springy.
func motion_scale() -> float:
	return 0.35 if reduced_motion else 1.0


## Final gain for one-shot sound effects, after mute and both levels.
func sfx_gain() -> float:
	if muted:
		return 0.0
	return clampf(master_volume, 0.0, 1.0) * clampf(sfx_volume, 0.0, 1.0)


# --- bindings ---------------------------------------------------------------

func keys_for(action: String) -> Array[int]:
	var out: Array[int] = []
	if not bindings.has(action):
		return out
	for key: int in bindings[action]:
		out.append(key)
	return out


## Which action owns this key, or "" when it is unbound.
func action_for_key(code: int) -> String:
	for action: String in bindings:
		for key: int in bindings[action]:
			if key == code:
				return action
	return ""


## Rebinds an action. A key can only mean one thing, so taking a key away from
## another action is deliberate rather than a conflict the user has to hunt down.
func set_binding(action: String, keys: Array) -> void:
	if not bindings.has(action):
		return
	var clean: Array[int] = []
	for key: int in keys:
		var taken_by := action_for_key(key)
		if taken_by != "" and taken_by != action:
			_remove_key(taken_by, key)
		if not clean.has(key):
			clean.append(key)
	bindings[action] = clean


## Adds one key to an action, without dropping the ones it already has.
func add_binding(action: String, key: int) -> void:
	var keys := keys_for(action)
	if not keys.has(key):
		keys.append(key)
	set_binding(action, keys)


func clear_binding(action: String) -> void:
	if bindings.has(action):
		bindings[action] = [] as Array[int]


func _remove_key(action: String, key: int) -> void:
	var keys := keys_for(action)
	keys.erase(key)
	bindings[action] = keys


# --- persistence ------------------------------------------------------------

func to_dictionary() -> Dictionary:
	var bound := {}
	for action: String in bindings:
		var keys: Array = []
		for key: int in bindings[action]:
			keys.append(key)
		bound[action] = keys
	return {
		"version": VERSION,
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"muted": muted,
		"screen_shake": screen_shake,
		"flashes": flashes,
		"reduced_motion": reduced_motion,
		"bindings": bound,
	}


## Loads settings from `path`. A missing or broken file leaves the defaults alone,
## which is what a first launch and a corrupted file both want.
func load_from(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	apply_dictionary(parsed)
	return true


func apply_dictionary(data: Dictionary) -> void:
	master_volume = clampf(_number(data, "master_volume", master_volume), 0.0, 1.0)
	sfx_volume = clampf(_number(data, "sfx_volume", sfx_volume), 0.0, 1.0)
	muted = bool(data.get("muted", muted))
	screen_shake = bool(data.get("screen_shake", screen_shake))
	flashes = bool(data.get("flashes", flashes))
	reduced_motion = bool(data.get("reduced_motion", reduced_motion))
	var bound: Variant = data.get("bindings", null)
	if typeof(bound) == TYPE_DICTIONARY:
		for action: String in DEFAULT_BINDINGS:
			if not bound.has(action):
				continue
			var keys: Array = []
			for key: Variant in bound[action]:
				var code := int(key)
				if code > 0:
					keys.append(code)
			bindings[action] = keys


func save_to(path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	file.close()
	return true


func _number(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


## Human-readable key name for the settings screen ("Z", "Esc", "F1").
static func key_name(code: int) -> String:
	var special := {
		KEY_ESCAPE: "Esc", KEY_SPACE: "Space", KEY_ENTER: "Enter", KEY_TAB: "Tab",
		KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right",
		KEY_BACKSPACE: "Backspace", KEY_DELETE: "Del", KEY_HOME: "Home", KEY_END: "End",
	}
	if special.has(code):
		return special[code]
	var text := OS.get_keycode_string(code)
	return text if text.length() > 0 else "Key %d" % code
