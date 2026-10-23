extends SceneTree
var game
func _initialize() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)
	run.call_deferred()
func run() -> void:
	await process_frame
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new("user://flow_test_awards.json")
	game.start_game()
	game._process(0.01)
	game.select_move(0)
	assert(game.selected == 0)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var before = game.clock.elapsed
	game._process(0.6)
	assert(game.clock.elapsed == before)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(game.resume_time == 3.0)
	game._process(3.1)
	assert(game.clock.elapsed == before)
	game.energy = [3,0]
	game.selected = 3
	game.opponent_move = 2
	game.resolve_round()
	assert(game.state == "ending")
	for i in range(5): game._process(0.1)
	assert(game.state == "ending" and not game.impact_shown)
	game._process(0.1)
	assert(game.impact_shown and not game.fall_started)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var ending_before = game.ending_elapsed
	game._process(1.0)
	assert(game.ending_elapsed == ending_before)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._process(3.1)
	for i in range(12): game._process(0.1)
	assert(game.state == "result")
	game.start_game()
	assert(game.energy == [0,0] and game.state == "battle")
	game.show_home()
	assert(game.state == "home")
	game.start_demo()
	game.select_move(1)
	assert(game.fighters[0].phase == "wave")
	print("PASS: selection, background freeze, resume countdown, winning result, replay, home, demo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://flow_test_awards.json"))
	game.queue_free()
	await process_frame
	quit()
