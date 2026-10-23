class_name Opponent
extends RefCounted
const Rules = preload("res://scripts/rules.gd")
# 0: aggressive, 1: energy hoarder, 2: habit reader. Only public state/past moves enter here.
var persona = 0
var challenge = 0.0
var rng = RandomNumberGenerator.new()
func choose(own_energy: int, other_energy: int, history: Array) -> int:
	var prediction = [3.0,2.0,1.8,1.0,0.7]
	var memory = (0.55 if persona == 0 else (0.85 if persona == 1 else 1.5))*(1.0+clampf(challenge,0,1)*0.4)
	for i in range(maxi(0,history.size()-8),history.size()):
		var move = int(history[i])
		if move >= 0 and move < 5: prediction[move] += memory
	# Learn transitions from earlier rounds, not the move currently being selected.
	if history.size() > 2:
		for i in range(maxi(0,history.size()-12),history.size()-1):
			if history[i] == history.back(): prediction[int(history[i+1])] += memory*2.5
	var total = 0.0
	for i in range(5):
		if not Rules.legal(i,other_energy): prediction[i] = 0.0
		total += prediction[i]
	var biases = [[1.0,2.0,0.8,1.4,0.9],[1.7,0.6,1.0,2.0,1.1],[1.0,1.0,1.0,1.0,1.0]][clampi(persona,0,2)]
	var weights: Array[float] = []
	var sum = 0.0
	for action in range(5):
		if not Rules.legal(action,own_energy):
			weights.append(0.0)
			continue
		var utility = 0.0
		for counter in range(5):
			var result = Rules.resolve(action,counter,own_energy,other_energy)
			var payoff = (5.5 if result.hit_b else 0.0)-(6.0 if result.hit_a else 0.0)
			payoff += 0.32*(result.ea-own_energy)-0.16*(result.eb-other_energy)
			utility += prediction[counter]/total*payoff
		# Against repeated free guards, build toward the move that actually breaks them.
		if prediction[2]/total > 0.5:
			if action == 0 and own_energy < 3: utility += 1.1
			if action == 1: utility -= 1.4
		if persona == 1 and action == 0 and own_energy < 3: utility += 0.45
		var temperature = 1.25 if persona == 0 else (1.1 if persona == 1 else 0.85)
		temperature *= 1.0-clampf(challenge,0,1)*0.2
		var weight = exp(clampf(utility/temperature,-12,12))*biases[action]
		weights.append(weight)
		sum += weight
	var roll = rng.randf()*sum
	for i in range(5):
		roll -= weights[i]
		if weights[i] > 0 and roll <= 0: return i
	return 2
