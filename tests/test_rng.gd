extends "res://tests/test_case.gd"

## Determinism tests for the replay backbone (docs/design.md §10.2).

const RngScript := preload("res://src/core/rng.gd")


func test_same_seed_gives_identical_sequences() -> void:
	var a := RngScript.new(12345)
	var b := RngScript.new(12345)
	for i in 64:
		assert_eq(a.next_u32(), b.next_u32(), "draw %d must match for the same seed" % i)


func test_different_seeds_diverge() -> void:
	var a := RngScript.new(1)
	var b := RngScript.new(2)
	var differences := 0
	for i in 32:
		if a.next_u32() != b.next_u32():
			differences += 1
	assert_ge(differences, 30, "different seeds should produce different streams")


func test_zero_seed_is_normalised() -> void:
	var rng := RngScript.new(0)
	var values := {}
	for i in 32:
		values[rng.next_u32()] = true
	assert_true(values.size() > 1, "a zero seed must not lock the generator")
	assert_ne(RngScript.to_state(0), 0, "zero is remapped to a non-zero state")


func test_no_state_collapse_over_many_draws() -> void:
	var rng := RngScript.new(0xDEADBEEF)
	var values := {}
	var max_streak := 0
	var streak := 0
	var previous := -1
	for i in 100000:
		var value := rng.next_u32()
		values[value] = true
		if value == previous:
			streak += 1
			max_streak = maxi(max_streak, streak)
		else:
			streak = 0
		previous = value
	assert_ge(values.size(), 60000, "100k draws should hit most of the 32-bit space")
	assert_true(max_streak < 3, "no long runs of identical values")


func test_next_int_stays_in_range() -> void:
	var rng := RngScript.new(99)
	var seen := {}
	for i in 5000:
		var value := rng.next_int(7)
		assert_ge(value, 0, "next_int is never negative")
		assert_true(value < 7, "next_int stays below the bound")
		seen[value] = true
	assert_eq(seen.size(), 7, "all buckets are reachable")


func test_next_int_handles_degenerate_bounds() -> void:
	var rng := RngScript.new(7)
	assert_eq(rng.next_int(0), 0, "bound 0 yields 0")
	assert_eq(rng.next_int(-5), 0, "negative bound yields 0")


func test_next_float_is_unit_interval() -> void:
	var rng := RngScript.new(4242)
	for i in 2000:
		var value := rng.next_float()
		assert_true(value >= 0.0 and value < 1.0, "next_float in [0, 1)")


func test_child_streams_are_reproducible_and_independent() -> void:
	var parent_a := RngScript.new(777)
	var parent_b := RngScript.new(777)
	var refill_a := parent_a.child("refill")
	var refill_b := parent_b.child("refill")
	var bombs_a := parent_a.child("bombs")

	for i in 16:
		assert_eq(refill_a.next_u32(), refill_b.next_u32(), "labelled streams reproduce")

	var refill := RngScript.new(777).child("refill")
	var bombs := RngScript.new(777).child("bombs")
	var same := true
	for i in 16:
		if refill.next_u32() != bombs.next_u32():
			same = false
			break
	assert_false(same, "different labels produce different streams")
	info("child stream sample: bombs=%d" % bombs_a.next_u32())


func test_shuffle_is_a_permutation_and_deterministic() -> void:
	var source := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var shuffled_a := RngScript.new(31337).shuffle(source.duplicate())
	var shuffled_b := RngScript.new(31337).shuffle(source.duplicate())
	assert_eq(shuffled_a, shuffled_b, "shuffle is deterministic for a seed")
	assert_eq(shuffled_a.size(), source.size(), "shuffle keeps the length")
	var sorted := shuffled_a.duplicate()
	sorted.sort()
	assert_eq(sorted, source, "shuffle keeps every element exactly once")
	assert_ne(shuffled_a, source, "shuffle actually reorders")


func test_pick_returns_members() -> void:
	var rng := RngScript.new(5)
	var options := ["a", "b", "c"]
	var seen := {}
	for i in 200:
		var value: Variant = rng.pick(options)
		assert_true(options.has(value), "pick returns an element of the array")
		seen[value] = true
	assert_eq(seen.size(), 3, "every option is reachable")
	assert_eq(rng.pick([]), null, "pick of an empty array is null")
