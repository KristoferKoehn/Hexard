class_name Rng
extends RefCounted

## Deterministic PRNG (xorshift32) used for every random board decision.
##
## Replays are the backbone of our test strategy (docs/design.md §10.2), so
## randomness must not depend on engine internals: this generator only uses
## integer add/xor/shift on values masked to 32 bits, which behaves
## identically on every platform and Godot version.
##
## Not for cryptography. Quality is far beyond what gem spawning needs.

const _MASK32 := 0xFFFFFFFF
const _FALLBACK_SEED := 0x9E3779B9
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619

var _state: int


func _init(seed_value: int = 1) -> void:
	_state = to_state(seed_value)


static func to_state(seed_value: int) -> int:
	var state := seed_value & _MASK32
	if state == 0:
		state = _FALLBACK_SEED
	return state


func next_u32() -> int:
	var x := _state
	x = (x ^ (x << 13)) & _MASK32
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & _MASK32
	if x == 0:
		x = _FALLBACK_SEED
	_state = x
	return x


## Uniform integer in [0, bound). Returns 0 for a non-positive bound.
func next_int(bound: int) -> int:
	if bound <= 0:
		return 0
	return next_u32() % bound


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## True with probability `chance` (clamped to [0, 1]).
func chance(probability: float) -> bool:
	return next_float() < clampf(probability, 0.0, 1.0)


func pick(values: Array) -> Variant:
	if values.is_empty():
		return null
	return values[next_int(values.size())]


## In-place Fisher-Yates; deterministic for a given state.
func shuffle(values: Array) -> Array:
	for i in range(values.size() - 1, 0, -1):
		var j := next_int(i + 1)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap
	return values


## An independent stream derived from this one and a label. Each concern
## (refill, specials, bombs) gets its own stream so that adding a new call
## site in one system cannot shift the sequence of another.
func child(label: String) -> Rng:
	var hash_value := _FNV_OFFSET
	for i in label.length():
		hash_value = ((hash_value ^ label.unicode_at(i)) * _FNV_PRIME) & _MASK32
	return Rng.new(hash_value ^ _state)


func state() -> int:
	return _state
