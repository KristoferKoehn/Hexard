class_name AudioService
extends Node

## Turns game events into cues (docs/design.md §8) by playing pre-rendered streams.
##
## This used to drive an AudioStreamGenerator and mix every sample in GDScript: for each
## frame the generator asked for, it looped the frames, looped the live voices and called
## Synth.sample() once per sample per voice. At 22050 Hz that is a few thousand interpreted
## calls every frame whenever a cue was still sounding - which is always, during play - and
## on the web build (GDScript compiled to wasm) it was a steady several-millisecond cost
## per frame. Rendering each cue once at startup removes it completely: playback is then
## the audio server's job, and there is no per-frame work here at all.
##
## Depth is a playback pitch multiplier rather than a re-rendered stream, so the cascade
## ladder still climbs and costs nothing.

const SynthScript := preload("res://src/core/synth.gd")

const MIX_RATE := 22050
const MAX_VOICES := 12
## Trim so a pile-up of cues cannot clip before the mixer does.
const HEADROOM := 0.45
## Tail after the recipe's own duration, so the decay is not cut off.
const TAIL := 0.08

var settings: Settings

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0


func _ready() -> void:
	for index in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)
	for cue: String in SynthScript.CUES:
		_streams[cue] = _render(cue)


func is_available() -> bool:
	return not _players.is_empty()


## Plays one cue. `depth` is the cascade step for clear cues and anything else ignores it.
func play_cue(cue: String, depth: int = 1) -> void:
	if _players.is_empty() or not _streams.has(cue):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[cue]
	# The ladder was previously a per-sample frequency multiplier; on a rendered stream the
	# same thing is a playback rate.
	if cue == "clear" and depth > 1:
		player.pitch_scale = pow(SynthScript.DEPTH_STEP, float(depth - 1))
	else:
		player.pitch_scale = 1.0
	player.volume_db = linear_to_db(maxf(HEADROOM * _gain(), 0.0001))
	player.play()


func _gain() -> float:
	if settings == null:
		return 1.0
	return settings.sfx_gain()


## Renders one recipe into a 16-bit mono stream. Done once per cue at startup: a dozen cues
## at well under a second each is far cheaper than mixing every frame forever.
func _render(cue: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var voice := SynthScript.voice_for(cue)
	if voice.is_empty():
		stream.data = PackedByteArray()
		return stream
	var frames := int((float(voice.get("dur", 0.2)) + TAIL) * float(MIX_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for index in frames:
		var value := clampf(SynthScript.sample(voice, float(MIX_RATE)), -1.0, 1.0)
		data.encode_s16(index * 2, int(value * 32767.0))
	stream.data = data
	return stream


## Maps a completed move onto its cues. Kept here rather than in the controller so the rules
## core stays free of presentation concerns.
func play_move(result: MoveResult) -> void:
	if result == null:
		return
	if not result.committed:
		if result.rotation_cells.size() > 0:
			play_cue("refuse")
		return
	if result.bomb_exploded:
		# The blast cue belongs to the animation step; playing it here too fired it twice.
		return
	play_cue("rotate")
	# Only the spin's own clear counts. A cascade clearing a second colour is a cascade, not
	# a multi-colour play, so it must not earn the chime.
	if distinct_colours(result, true) >= 2:
		play_cue("multi")
	if result.bombs_defused > 0:
		play_cue("defuse")
	elif result.bombs_ticked.size() > 0:
		play_cue("bomb_tick")


## Called as each animation step begins. Cascade depth drives the pitch, so the ladder
## climbs through a chain and resets when the board settles.
func on_step(kind: String, step: Dictionary) -> void:
	if kind == "clear":
		if settings != null and settings.muted:
			return
		var depth := int(step.get("depth", 1))
		for group in step.get("groups", []):
			play_cue(_cue_for(group), depth)
	elif kind == "blast":
		play_cue("explosion")


## Distinct gem colours this move cleared. Two or more earns the chime.
##
## `first_clear_only` restricts the count to the clear the spin itself made (cascade depth 0
## or 1), which is what the chime is for. Static so it can be tested without an audio device.
static func distinct_colours(result: MoveResult, first_clear_only: bool = false) -> int:
	var seen := {}
	for group in result.clear_groups:
		if first_clear_only and int(group.cascade_depth) > 1:
			continue
		var color := int(group.gem_color)
		if color > 0:
			seen[color] = true
	return seen.size()


func _cue_for(group) -> String:
	# Each kind of clear gets its own sound. Order matters where a group can carry more than
	# one formation: the biggest thing that happened wins.
	if group.has_formation("pearl_ring"):
		return "grand"
	if group.has_formation("pearl_cluster"):
		return "finish"
	if group.has_formation("starflower_cluster"):
		return "windfall"
	if group.has_formation("bomb_colour_wipe"):
		return "wipe"
	if group.has_formation("bonus_star_cluster"):
		return "star"
	if group.has_formation("flower"):
		return "bloom"
	if group.has_formation("pearl_built"):
		return "pearl"
	return "clear"
