extends "res://tests/test_case.gd"

## The procedural synth (src/core/synth.gd). Testable headless precisely because
## it is floats and recipes with no AudioStream in sight.

const SynthScript := preload("res://src/core/synth.gd")
const RATE := 22050.0


func test_every_cue_class_has_a_usable_recipe() -> void:
	assert_gt(SynthScript.CUES.size(), 5, "there is a recipe per event class")
	for cue: String in SynthScript.CUES:
		var voice := SynthScript.voice_for(cue)
		assert_true(not voice.is_empty(), "%s makes a voice" % cue)
		assert_gt(float(voice["dur"]), 0.005, "%s has a real duration" % cue)
		assert_gt(float(voice["amp"]), 0.0, "%s is audible" % cue)
		assert_gt(float(voice["freq"]), 0.0, "%s has a pitch" % cue)


func test_an_unknown_cue_is_quiet_rather_than_crashing() -> void:
	assert_true(SynthScript.voice_for("no_such_cue").is_empty(), "no voice for an unknown cue")


func test_a_cue_actually_makes_sound_and_stays_in_range() -> void:
	var samples := SynthScript.render_offline("clear", 1, RATE, 4096)
	var peak := 0.0
	var energy := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
		energy += absf(value)
	assert_gt(peak, 0.01, "the cue is audible")
	assert_le(peak, 1.0, "and never leaves the legal sample range")
	assert_gt(energy, 0.0, "with real energy in it")


func test_cascade_depth_raises_the_pitch_and_nothing_else_does() -> void:
	var first := SynthScript.voice_for("clear", 1)
	var second := SynthScript.voice_for("clear", 2)
	var third := SynthScript.voice_for("clear", 3)
	assert_gt(float(second["freq"]), float(first["freq"]), "depth 2 is higher than depth 1")
	assert_gt(float(third["freq"]), float(second["freq"]), "depth 3 is higher still")
	var plain := SynthScript.voice_for("rotate", 1)
	var deep := SynthScript.voice_for("rotate", 4)
	assert_almost_eq(float(deep["freq"]), float(plain["freq"]), 0.001, "other cues ignore depth")


func test_a_voice_ends_and_then_falls_silent() -> void:
	var voice := SynthScript.voice_for("rotate")
	var frames := int(float(voice["dur"]) * RATE) + 4
	for _index in frames:
		SynthScript.sample(voice, RATE)
	assert_true(SynthScript.is_finished(voice), "the voice finished after its duration")
	assert_almost_eq(SynthScript.sample(voice, RATE), 0.0, 0.0001, "and is silent afterwards")


func test_the_noise_waveform_is_not_a_pure_tone() -> void:
	var samples := SynthScript.render_offline("explosion", 1, RATE, 512)
	var distinct := {}
	for value: float in samples:
		distinct[snappedf(value, 0.001)] = true
	assert_gt(distinct.size(), 20, "noise sweeps many distinct values")


func test_the_clear_cue_is_a_descending_hiss() -> void:
	var samples := SynthScript.render_offline("clear", 1, RATE, 2048)
	var quarter := int(samples.size() / 4)
	var early := _zero_crossings(samples, 0, quarter)
	var late := _zero_crossings(samples, samples.size() - quarter, samples.size())
	# A one-pole filter chasing a falling cutoff lets fewer and fewer sign changes
	# through, which is what makes it read as a descent rather than flat noise.
	assert_gt(early, 8, "the opening is bright (%d crossings)" % early)
	assert_gt(early, late, "and the hiss descends (%d -> %d crossings)" % [early, late])


func _zero_crossings(samples: PackedFloat32Array, from: int, to: int) -> int:
	var count := 0
	for index in range(from + 1, mini(to, samples.size())):
		if (samples[index - 1] < 0.0) != (samples[index] < 0.0):
			count += 1
	return count


func test_voices_are_independent() -> void:
	var a := SynthScript.voice_for("clear", 1)
	var b := SynthScript.voice_for("clear", 1)
	for _index in 32:
		SynthScript.sample(a, RATE)
	assert_gt(float(a["t"]), 0.0, "one voice advanced")
	assert_almost_eq(float(b["t"]), 0.0, 0.0001, "the other did not")


## The cascade ladder must raise the note, not the volume. Noise could not do this
## (no fundamental), which is why clear is a pluck: peak amplitude stays put as
## depth climbs while the fundamental rises.
func test_cascade_depth_does_not_make_the_clear_louder() -> void:
	var peaks := {}
	for depth: int in [1, 3, 5]:
		var samples := SynthScript.render_offline("clear", depth, RATE, 4096)
		var peak := 0.0
		for value: float in samples:
			peak = maxf(peak, absf(value))
		peaks[depth] = peak
		assert_gt(peak, 0.01, "depth %d is audible" % depth)
	var first: float = peaks[1]
	var last: float = peaks[5]
	assert_almost_eq(last, first, first * 0.2, "depth 5 is as loud as depth 1, not louder")


func test_the_cheat_cues_are_tellable_apart() -> void:
	for cue: String in ["accept", "lock"]:
		assert_true(Synth.CUES.has(cue), "there is a %s cue" % cue)
	var accept: Dictionary = Synth.CUES["accept"]
	var lock: Dictionary = Synth.CUES["lock"]
	assert_gt(float(accept["freq"]), float(lock["freq"]), "accept is brighter than lock")
	assert_ne(int(accept["wave"]), int(lock["wave"]), "and a different timbre, not just a note")
	assert_gt(float(accept["slide"]), 0.0, "accept rises")
	assert_lt(float(lock["slide"]), 0.0, "lock falls")


func test_each_kind_of_clear_has_its_own_cue() -> void:
	# Distinct by pitch, timbre or contour - not merely a different note, because a player has
	# to tell a windfall from a pearl finish without looking at the board.
	var cues := ["clear", "star", "windfall", "wipe", "bloom", "pearl", "finish", "grand"]
	var seen := {}
	for cue: String in cues:
		assert_true(Synth.CUES.has(cue), "there is a %s cue" % cue)
		var recipe: Dictionary = Synth.CUES[cue]
		var signature := "%d/%.0f/%.0f" % [
			int(recipe["wave"]), float(recipe["freq"]), float(recipe["slide"])
		]
		assert_false(seen.has(signature),
			"%s is not a duplicate of %s" % [cue, seen.get(signature, "")])
		seen[signature] = cue
		var energy := 0.0
		var voice := Synth.voice_for(cue)
		for index in 300:
			energy += absf(Synth.sample(voice, 22050.0))
		assert_gt(energy, 0.0, "%s renders sound" % cue)
