class_name BeatClock
extends RefCounted
const Tempo = preload("res://scripts/tempo.gd")
const MARKERS = [0.0, 0.90, 1.80]
const ROUND_SECONDS = 2.70
var elapsed = 0.0
var tick = -1
var round_number = 1
var round_start = 0.0
func reset(start_round: int = 1) -> void:
	elapsed = 0.0
	tick = -1
	round_number = maxi(1,start_round)
	round_start = 0.0
func advance(delta: float) -> Array[int]:
	elapsed += maxf(delta,0.0)
	var events: Array[int] = []
	while true:
		var next = tick+1
		var phase = next % 3
		var interval = Tempo.beat_seconds(round_number)
		var next_round = phase == 0 and next > 0
		var at = round_start+(3.0*interval if next_round else phase*interval)
		if elapsed+0.000001 < at: break
		if next_round:
			round_start = at
			round_number += 1
		tick = next
		events.append(phase)
	return events
func selection_progress() -> float:
	if tick >= 0 and tick % 3 == 2: return 1.0
	return clampf((elapsed-round_start)/(2.0*Tempo.beat_seconds(round_number)),0,1)
