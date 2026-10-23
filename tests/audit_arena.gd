extends SceneTree
const Rules = preload("res://scripts/rules.gd")
const Bot = preload("res://scripts/opponent.gd")
func _initialize() -> void:
	for persona in range(3):
		for policy in ["random_legal","charge_then_wave","charge_three_then_super","always_guard"]:
			var bot = Bot.new()
			bot.persona = persona
			var rng = RandomNumberGenerator.new()
			rng.seed = 9021
			bot.rng.seed = 4106
			var rounds: Array[int] = []
			var reached = {6:0,10:0,15:0,25:0}
			var wins = 0
			var unresolved = 0
			for match_id in range(1000):
				var energy = [0,0]
				var history: Array = []
				var length = 100
				for round_id in range(1,101):
					if reached.has(round_id): reached[round_id] += 1
					var action = 2
					match policy:
						"random_legal":
							var legal: Array[int] = []
							for i in range(5):
								if Rules.legal(i,energy[0]): legal.append(i)
							action = legal[rng.randi_range(0,legal.size()-1)]
						"charge_then_wave": action = 0 if energy[0] == 0 else 1
						"charge_three_then_super": action = 0 if energy[0] < 3 else 3
					var opponent = bot.choose(energy[1],energy[0],history)
					var result = Rules.resolve(action,opponent,energy[0],energy[1])
					history.append(action)
					energy = [result.ea,result.eb]
					if result.hit_a or result.hit_b:
						wins += int(result.hit_b)
						length = round_id
						break
					if round_id == 100: unresolved += 1
				rounds.append(length)
			rounds.sort()
			print(JSON.stringify({"persona":persona,"policy":policy,"matches":1000,"median_rounds":rounds[500],"p90_rounds":rounds[900],"wins":wins,"reached_rounds":reached,"unfinished_at_100":unresolved}))
	quit()
