extends SceneTree
const R = preload("res://scripts/rules.gd")
const AI = preload("res://scripts/opponent.gd")
const Clock = preload("res://scripts/beat_clock.gd")
func _initialize() -> void:
	var count = 0
	for ea in range(6):
		for eb in range(6):
			for a in range(5):
				for b in range(5):
					var x = R.resolve(a,b,ea,eb)
					var y = R.resolve(b,a,eb,ea)
					assert(x.ea >= 0 and x.ea <= R.CAP)
					assert(x.eb >= 0 and x.eb <= R.CAP)
					assert(x.ea == y.eb and x.hit_a == y.hit_b)
					assert(not (x.hit_a and x.hit_b))
					count += 1
	assert(R.resolve(1,0,1,0).hit_b)
	assert(not R.resolve(1,2,1,0).hit_b)
	assert(not R.resolve(1,1,1,1).hit_b)
	assert(R.resolve(3,2,3,0).hit_b)
	assert(R.resolve(3,1,3,1).hit_b)
	assert(not R.resolve(3,4,3,1).hit_b)
	assert(R.resolve(3,0,0,0).a == 2)
	var bot = AI.new()
	bot.rng.seed = 123
	for e in range(6):
		for other in range(6):
			for i in range(100): assert(R.legal(bot.choose(e,other,[2,0]),e))
	var clock = Clock.new()
	assert(clock.advance(0.0) == [0])
	assert(clock.advance(0.90) == [1])
	assert(clock.advance(0.50) == []) # Old 1.4s lock point must stay open.
	assert(clock.advance(0.399) == [])
	assert(clock.advance(0.001) == [2])
	assert(clock.advance(0.9) == [0])
	assert(clock.advance(5.4) == [1,2,0,1,2,0])
	print("PASS: ",count," symmetric rule combinations, 3600 legal AI decisions, beat ordering, canonical outcomes")
	quit()
