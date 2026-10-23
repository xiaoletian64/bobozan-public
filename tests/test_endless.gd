extends SceneTree
const Arena = preload("res://scripts/arena_run.gd")
const Board = preload("res://scripts/local_leaderboard.gd")
const Rules = preload("res://scripts/rules.gd")
const PATH = "user://endless_test_board.json"
func _initialize() -> void: run.call_deferred()
func clean() -> void:
	for suffix in ["",".tmp",".bak"]: DirAccess.remove_absolute(PATH+suffix)
func run() -> void:
	clean()
	var endless = Arena.new(true)
	for stage in range(1000):
		assert(endless.rival_index() == stage%3)
		for bout in range(2):
			assert(endless.begin_bout())
			endless.record_exchange(Rules.resolve(1,0,1,0))
			var result = endless.finish_bout(true)
			assert(not result.cleared and not endless.finished)
		assert(endless.next_stage())
	assert(endless.cleared_stages == 1000 and endless.victories.size() == 3)
	assert(endless.tempo_start() == 25)
	assert(endless.begin_bout())
	for i in range(100): endless.record_exchange(Rules.resolve(2,2,0,0))
	assert(endless.history.size() == 24)
	endless.finish_bout(true)
	var board = Board.new(PATH)
	assert(board.entries.is_empty())
	endless.run_id = "long"
	assert(board.record(endless))
	assert(board.record(endless) and board.entries.size() == 1)
	assert(Board.new(PATH).entries[0].cleared == 1000)
	for i in range(25):
		var test = Arena.new(true)
		test.run_id = "entry-%02d" % i
		test.total_exchanges = 50-i
		test.cleared_stages = i
		assert(board.record(test))
	assert(board.entries.size() == 20 and board.entries[0].id == "long")
	var tie = Arena.new(true)
	tie.run_id = "tie"
	tie.cleared_stages = 1000
	tie.total_exchanges = 100
	assert(board.record(tie) and board.entries[0].id == "tie")
	tie.losses = 1
	assert(board.record(tie) and board.entries[0].id == "long")
	var invalid = Board.new("user://missing-endless-directory/board.json")
	assert(not invalid.record(endless) and not invalid.last_saved)
	var file = FileAccess.open(PATH,FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	assert(Board.new(PATH).entries.size() == 20) # Recover previous atomic backup.
	clean()
	var game = load("res://main.tscn").instantiate()
	game.leaderboard = Board.new(PATH)
	game.awards = load("res://scripts/achievements.gd").new("user://endless_awards_test.json")
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.start_endless()
	for stage in range(4):
		game.start_game()
		for bout in range(2):
			game.present_result(Rules.resolve(1,0,1,0))
			for i in range(18): game.update_ending(0.1)
			game.advance_arcade()
		assert(game.state == "arena_intro")
	assert(game.arena.cleared_stages == 4 and game.arena.stage == 4)
	game.start_game()
	for bout in range(2):
		game.present_result(Rules.resolve(0,1,0,1))
		for i in range(18): game.update_ending(0.1)
		if bout == 0: game.advance_arcade()
	assert(game.state == "endless_result" and game.arena.finished)
	assert(not game.arena.continue_match())
	assert(game.leaderboard.entries.size() == 1 and game.leaderboard.entries[0].cleared == 4)
	assert(game.leaderboard.entries[0].status == "败北")
	game.show_leaderboard()
	assert(game.state == "leaderboard" and is_instance_valid(game.leaderboard_view))
	game.show_home()
	game.start_arena()
	assert(not game.arena.endless and game.bot.challenge == 0)
	game.show_home()
	game.start_endless()
	game.start_game()
	game.present_result(Rules.resolve(0,0,0,0))
	game.show_home()
	assert(game.leaderboard.entries.size() == 2)
	assert(game.leaderboard.entries[1].status == "主动结束")
	game.queue_free()
	await process_frame
	clean()
	DirAccess.remove_absolute("user://endless_awards_test.json")
	print("PASS: 1000 endless stages, bounded memory/tempo, no continue, checkpoint dedup/top20/reload/backup/save failure, 4-stage UI, defeat, leaderboard, mode isolation, exit save")
	quit()
