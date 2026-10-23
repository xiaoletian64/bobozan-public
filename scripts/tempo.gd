class_name DuelTempo
extends RefCounted
# Equal triplets. First five rounds are relaxed; rounds 6–25 tighten smoothly.
const ID = "triplet-ramp-v1"
const BASE_BEAT = 0.90
const MIN_BEAT = 0.34
static func beat_seconds(round_number: int) -> float:
	var progress = clampf(float(round_number-5)/20.0,0.0,1.0)
	return lerpf(BASE_BEAT,MIN_BEAT,progress)
static func animation_speed(round_number: int) -> float:
	return BASE_BEAT/beat_seconds(round_number)
