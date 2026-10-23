extends SceneTree
const Arena = preload("res://scripts/arena_run.gd")
const Rules = preload("res://scripts/rules.gd")
const Bot = preload("res://scripts/opponent.gd")
const TEMP = "user://arena_test_awards.json"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var run = Arena.new()
	assert(run.begin_bout() and not run.begin_bout())
	run.record_exchange(Rules.resolve(0,0,0,0))
	assert(run.exchanges == 1 and run.history == [0])
	assert(not run.finish_bout(false).match_done)
	assert(run.finish_bout(false).is_empty() and run.score == [0,1])
	assert(run.tempo_start() >= 8 and run.begin_bout())
	run.record_exchange(Rules.resolve(0,0,0,0),24)
	run.finish_bout(true)
	assert(run.tempo_start() == 25)
	assert(run.tempo_start() >= 16 and run.begin_bout())
	assert(run.finish_bout(true).comeback)
	assert(not run.begin_bout() and run.next_stage())
	assert(run.stage == 1 and run.score == [0,0] and run.history.is_empty())
	for persona in range(3):
		var bot = Bot.new()
		bot.persona = persona
		bot.rng.seed = 87
		var history = [0,1,0,1,2,4,3]
		for ea in range(6):
			for eb in range(6):
				for i in range(10): assert(Rules.legal(bot.choose(ea,eb,history),ea))
		assert(history == [0,1,0,1,2,4,3])
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new(TEMP)
	game.start_arena()
	assert(game.state == "arena_intro")
	for stage in range(3):
		for won in [false,true,true]:
			game.start_game()
			assert(game.state == "battle" and game.bot.persona == stage)
			if game.arena.score == [1,1]: assert(game.current_beat_seconds() < 0.65)
			game.resume_time = 0
			game.present_result(Rules.resolve(1,0,1,0) if won else Rules.resolve(0,1,0,1))
			for i in range(18): game.update_ending(0.1)
			assert(game.state == "result" and not game.arena.bout_open)
			assert((game.recap_label.visible or game.route.visible) and game.score_label.visible)
		assert(game.arena.score == [2,1])
		if stage < 2:
			assert(game.arena.next_stage())
			game.show_arena_intro()
	assert(game.arena.finished and game.awards.unlocked.has("arena_clear"))
	assert(game.awards.unlocked.has("comeback"))
	game.start_arena()
	for i in range(2):
		game.start_game()
		game.present_result(Rules.resolve(0,1,0,1))
		for step in range(18): game.update_ending(0.1)
	assert(game.arena.score == [0,2])
	game.arena.reset_match()
	game.show_arena_intro()
	assert(game.arena.score == [0,0])
	game.start_practice()
	assert(game.arena == null and game.state == "battle")
	game.show_home()
	assert(game.fx.get_child_count() == 0 and not game.recap_label.visible)
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	print("PASS: arena BO3, comeback, all 3 rivals, retry, tempo, recap, achievements, legal AI and cleanup")
	quit()
