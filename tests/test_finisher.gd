extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new("user://finisher_test.json")
	for winner in [0,1]:
		for strong in [false,true]:
			game.start_game()
			game.present_result(load("res://scripts/rules.gd").resolve(3 if strong else 1,0,3,3) if winner == 0 else load("res://scripts/rules.gd").resolve(0,3 if strong else 1,3,3))
			assert(game.fighters[winner].finishing)
			assert(game.fx.heavy == strong)
			game.fx.seek_finisher(0.4)
			assert(game.fx.blade.scale.x > 0 if winner == 0 else game.fx.blade.scale.x < 0)
			game.fx.seek_finisher(0.55)
			assert(game.fx.core.position.is_equal_approx(game.fighters[1-winner].position+Vector3(0,1.2,0)))
			for i in range(6): game.update_ending(0.1)
			assert(game.impact_shown and not game.fall_started)
			game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			var before = game.ending_elapsed
			game._process(1)
			assert(game.ending_elapsed == before)
			assert(game.fx.process_mode == Node.PROCESS_MODE_DISABLED)
			game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			game._process(3.1)
			assert(not game.fighters[winner].is_processing())
			game._process(0.1)
			assert(game.fall_started and game.fighters[winner].is_processing())
			for i in range(10): game.update_ending(0.1)
			assert(game.state == "result")
			game.show_home()
			assert(game.fx.get_child_count() == 0)
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://finisher_test.json"))
	print("PASS: both finisher directions, ordinary/strong, target contact, pause during hit-stop, reset cleanup")
	quit()
