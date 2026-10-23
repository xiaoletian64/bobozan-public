extends SceneTree
var game
var elapsed = 0.0
var last_stage = -1
func _initialize() -> void: setup.call_deferred()
func setup() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.awards = load("res://scripts/achievements.gd").new("user://arena_movie.json")
	game.sound_on = true
	game.start_arena()
func _process(delta: float) -> bool:
	if not is_instance_valid(game): return false
	elapsed += delta
	var stage = int(elapsed/2)
	if stage != last_stage:
		last_stage = stage
		match stage:
			1:
				game.start_game()
				game.resume_time = 0
				game.beat.text = "波\n●  ○  ○"
				game.pulse_ui(game.beat,1.15,0.3)
				game.speak("ready")
			2:
				game.present_result(load("res://scripts/rules.gd").resolve(0,0,0,0))
				game.refresh()
			3:
				game.present_result(load("res://scripts/rules.gd").resolve(4,3,1,3))
				game.refresh()
			4:
				game.arena.score = [1,1]
				game.pace_round = 16
				game.refresh()
				game.beat.text = "决胜局"
				game.pulse_ui(game.score_label,1.18,0.3)
			5: game.present_result(load("res://scripts/rules.gd").resolve(3,2,3,0))
			7:
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://arena_movie.json"))
				quit()
	if game.state == "ending": game.update_ending(delta)
	elif game.impact_remaining >= 0:
		game.impact_remaining -= delta
		if game.impact_remaining < 0: game.show_impact(false)
	game.update_toast(delta)
	return false
