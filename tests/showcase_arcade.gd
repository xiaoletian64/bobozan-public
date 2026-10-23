extends SceneTree
var game
var elapsed = 0.0
var marker = -1
func _initialize() -> void: setup.call_deferred()
func setup() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new("user://arcade_movie.json")
	game.start_arena()
func score() -> void:
	game.present_result(load("res://scripts/rules.gd").resolve(3,2,3,0))
func instant_bout() -> void:
	game.start_game()
	score()
	for i in range(18): game.update_ending(0.1)
func _process(delta: float) -> bool:
	if not is_instance_valid(game): return false
	elapsed += delta
	var step = int(elapsed/2)
	if marker != step:
		marker = step
		match step:
			1: game.begin_arcade_vs()
			2:
				instant_bout()
				game.advance_arcade()
				score()
			5:
				if game.state == "arena_intro": game.advance_arcade()
			7:
				instant_bout()
				game.advance_arcade()
				instant_bout()
				game.advance_arcade()
			10:
				instant_bout()
				game.advance_arcade()
				score()
			14:
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://arcade_movie.json"))
				quit()
	if game.state == "ending": game.update_ending(delta)
	elif not game.cinematic_action.is_empty(): game._process(delta)
	return false
