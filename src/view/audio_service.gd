class_name AudioService
extends Node

## Drives the procedural synth (src/core/synth.gd) into an
## AudioStreamGenerator, and turns game events into cues (docs/design.md §8).
##
## Headless has no audio device, so everything degrades to a no-op: the node still
## exists and receives cues, it just never gets a playback to push into.

const SynthScript := preload("res://src/core/synth.gd")

const MIX_RATE := 22050.0
const BUFFER_SECONDS := 0.15
## Voices overlapping this many at once start to smear; oldest are dropped.
const MAX_VOICES := 12
## Master trim so a pile-up of cues cannot clip before the soft limiter.
const HEADROOM := 0.45

var settings: Settings

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = BUFFER_SECONDS
	_player = AudioStreamPlayer.new()
	_player.stream = generator
	_player.bus = "Master"
	add_child(_player)
	_player.play()
	# Null in headless (no audio driver): every cue then quietly does nothing.
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func is_available() -> bool:
	return _playback != null


## Plays one cue. `depth` is the cascade step for clear cues; other cues ignore it.
func play_cue(cue: String, depth: int = 1) -> void:
	if _gain() <= 0.0:
		return
	var voice := SynthScript.voice_for(cue, depth)
	if voice.is_empty():
		return
	if _voices.size() >= MAX_VOICES:
		_voices.pop_front()
	_voices.append(voice)


func _gain() -> float:
	if settings == null:
		return 1.0
	return settings.sfx_gain()


## Maps a completed move onto its cues. Kept here rather than in the controller so
## the rules core stays free of presentation concerns.
func play_move(result: MoveResult) -> void:
	if result == null:
		return
	if not result.committed:
		if result.rotation_cells.size() > 0:
			play_cue("refuse")
		return
	if result.bomb_exploded:
		play_cue("explosion")
		return
	play_cue("rotate")
	if result.bombs_defused > 0:
		play_cue("defuse")
	elif result.bombs_ticked.size() > 0:
		play_cue("bomb_tick")

	# Clears are deliberately NOT played here: they belong to the animation steps,
	# so a cascade sounds as it lands instead of all at once on the turn.



## Called as each animation step begins. Cascade depth drives the pitch, so the
## ladder climbs through a chain and resets when the board settles.
func on_step(kind: String, step: Dictionary) -> void:
	if kind == "clear":
		if settings != null and settings.muted:
			return
		var depth := int(step.get("depth", 1))
		for group in step.get("groups", []):
			play_cue(_cue_for(group), depth)
	elif kind == "blast":
		play_cue("explosion")


func _cue_for(group) -> String:
	if group.has_formation("bonus_star_cluster"):
		return "star"
	if group.has_formation("flower") or group.has_formation("starflower_cluster"):
		return "bloom"
	if group.has_formation("pearl_built") or group.has_formation("pearl_cluster") \
			or group.has_formation("pearl_ring"):
		return "pearl"
	return "clear"


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var gain := _gain()
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for index in frames:
		var mixed := 0.0
		for voice: Dictionary in _voices:
			mixed += SynthScript.sample(voice, MIX_RATE)
		mixed = _soft_clip(mixed * HEADROOM * gain)
		var frame := Vector2(mixed, mixed)
		buffer[index] = frame
	# Retire finished voices after mixing this block.
	var live: Array = []
	for voice: Dictionary in _voices:
		if not SynthScript.is_finished(voice):
			live.append(voice)
	_voices = live
	_playback.push_buffer(buffer)


## Rounded saturation: keeps a stack of cues from turning into clipping crackle.
static func _soft_clip(value: float) -> float:
	return value / (1.0 + absf(value))
