class_name Synth
extends RefCounted

## Procedural sound: recipe table plus per-sample voice math (docs/design.md §8).
##
## Deliberately engine-free so it can be unit-tested headless: no AudioStream, no
## nodes, just floats. AudioService is the thin driver that pushes these samples
## into an AudioStreamGenerator. That split is the only reason the synth is
## testable at all — in headless mode there is no audio device.

enum Wave { SINE, TRIANGLE, SQUARE, SAW, NOISE }

## Envelope: a very short attack then an exponential decay, so hits feel percussive
## rather than like tones being switched on.
const ATTACK := 0.004
const DECAY_CURVE := 4.0

## One recipe per event class. `freq` is the fundamental in Hz, `dur` in seconds,
## `amp` is relative loudness before the settings gain, and `slide` bends the
## pitch over the note (negative falls, positive rises).
const CUES := {
	"rotate":     {"wave": Wave.TRIANGLE, "freq": 660.0, "dur": 0.06, "amp": 0.22, "slide": 0.0},
	"refuse":     {"wave": Wave.SQUARE, "freq": 240.0, "dur": 0.10, "amp": 0.16, "slide": -90.0},
	# Clears are a short plucked tone, not noise. Noise has no fundamental, so
	# raising its filter cutoff only made successive clears brighter and louder
	# instead of higher - the cascade ladder needs real pitch. A triangle pluck with
	# a small downward bend has a clear fundamental that the depth multiplier can
	# climb, while the fast decay keeps it percussive.
	"clear":      {"wave": Wave.TRIANGLE, "freq": 540.0, "dur": 0.16, "amp": 0.26, "slide": -110.0},
	"star":       {"wave": Wave.SINE, "freq": 1180.0, "dur": 0.34, "amp": 0.26, "slide": 0.0},
	"bloom":      {"wave": Wave.TRIANGLE, "freq": 440.0, "dur": 0.30, "amp": 0.26, "slide": 520.0},
	"pearl":      {"wave": Wave.SINE, "freq": 240.0, "dur": 0.55, "amp": 0.32, "slide": -60.0},
	"bomb_tick":  {"wave": Wave.SQUARE, "freq": 180.0, "dur": 0.07, "amp": 0.24, "slide": 0.0},
	"defuse":     {"wave": Wave.SINE, "freq": 700.0, "dur": 0.22, "amp": 0.26, "slide": -420.0},
	"explosion":  {"wave": Wave.NOISE, "freq": 700.0, "dur": 0.75, "amp": 0.55, "slide": -560.0},
	"ui":         {"wave": Wave.SQUARE, "freq": 880.0, "dur": 0.05, "amp": 0.14, "slide": 0.0},
	# Two or more colours cleared by one spin: a brighter, longer chime so a
	# multi-colour turn is audibly distinct from the ordinary hiss.
	"multi":      {"wave": Wave.SINE, "freq": 1568.0, "dur": 0.55, "amp": 0.42, "slide": 0.0},
}

## Cascades climb in pitch so a chain sounds like it is going somewhere: one
## semitone-and-a-bit per depth step.
const DEPTH_STEP := 1.1225


## A fresh voice for a cue, or {} if the cue is unknown.
## `depth` is the cascade step (1 for the first clear) and only bends "clear".
static func voice_for(cue: String, depth: int = 1) -> Dictionary:
	if not CUES.has(cue):
		push_warning("Synth: unknown cue '%s'" % cue)
		return {}
	var recipe: Dictionary = CUES[cue]
	var pitch := 1.0
	if cue == "clear" and depth > 1:
		pitch = pow(DEPTH_STEP, float(depth - 1))
	return {
		"wave": int(recipe["wave"]),
		"freq": float(recipe["freq"]) * pitch,
		"slide": float(recipe["slide"]) * pitch,
		"dur": float(recipe["dur"]),
		"amp": float(recipe["amp"]),
		"phase": 0.0,
		"lp": 0.0,
		"t": 0.0,
		"seed": 0x2545F49 + int(recipe["freq"]),
	}


static func is_finished(voice: Dictionary) -> bool:
	return voice.is_empty() or float(voice["t"]) >= float(voice["dur"])


## Advances one voice by one sample at `rate` and returns its current value.
static func sample(voice: Dictionary, rate: float) -> float:
	if is_finished(voice):
		return 0.0
	var t := float(voice["t"])
	var dur := float(voice["dur"])
	var phase := float(voice["phase"])
	var freq := float(voice["freq"]) + float(voice["slide"]) * (t / dur)

	var value := 0.0
	match int(voice["wave"]):
		Wave.SINE:
			value = sin(phase)
		Wave.TRIANGLE:
			value = 1.0 - 4.0 * absf(fmod(phase / TAU + 0.75, 1.0) - 0.5)
		Wave.SQUARE:
			value = 1.0 if sin(phase) >= 0.0 else -1.0
		Wave.SAW:
			value = 2.0 * fmod(phase / TAU, 1.0) - 1.0
		Wave.NOISE:
			# One-pole low-pass whose cutoff follows freq+slide, so noise can be
			# pitched: a descending cutoff turns white noise into a falling hiss.
			voice["seed"] = _next_seed(int(voice["seed"]))
			var raw := float(int(voice["seed"]) & 0xFFFF) / 32767.5 - 1.0
			var cutoff := clampf(freq, 60.0, rate * 0.45)
			var alpha := 1.0 - exp(-TAU * cutoff / rate)
			voice["lp"] = float(voice["lp"]) + alpha * (raw - float(voice["lp"]))
			value = float(voice["lp"]) * 2.2

	voice["phase"] = fmod(phase + TAU * freq / rate, TAU * 1024.0)
	voice["t"] = t + 1.0 / rate
	return value * _envelope(t, dur) * float(voice["amp"])


## Attack then exponential decay, reaching silence exactly at `dur`.
static func _envelope(t: float, dur: float) -> float:
	if dur <= 0.0:
		return 0.0
	var attack := minf(ATTACK, dur)
	var rise := 1.0 if attack <= 0.0 else minf(t / attack, 1.0)
	var fall := exp(-DECAY_CURVE * (t / dur))
	return rise * fall


static func _next_seed(seed_value: int) -> int:
	var x := seed_value
	x = x ^ (x << 13)
	x = x ^ (x >> 17)
	x = x ^ (x << 5)
	return x & 0x7FFFFFFF


## Renders a cue offline. Used by tests to prove a recipe actually makes sound and
## stays inside the legal sample range without needing an audio device.
static func render_offline(cue: String, depth: int, rate: float, frames: int) -> PackedFloat32Array:
	var voice := voice_for(cue, depth)
	var out := PackedFloat32Array()
	out.resize(frames)
	for index in frames:
		out[index] = sample(voice, rate)
	return out
