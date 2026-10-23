extends SceneTree
var game
const PATH = "user://endless_capture_board.json"
func _initialize() -> void: run.call_deferred()
func snap(name: String) -> void:
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/endless-"+name+".png")
func run() -> void:
	for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(PATH+suffix)
	game = load("res://main.tscn").instantiate()
	game.leaderboard = load("res://scripts/local_leaderboard.gd").new(PATH)
	game.awards = load("res://scripts/achievements.gd").new("user://endless_capture_awards.json")
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	await snap("home")
	game.show_leaderboard()
	await snap("empty")
	game.start_endless()
	for stage in range(4):
		game.start_game()
		for bout in range(2):
			game.present_result(load("res://scripts/rules.gd").resolve(1,0,1,0))
			for i in range(18): game.update_ending(0.1)
			game.advance_arcade()
	await snap("stage5")
	game.start_game()
	for bout in range(2):
		game.present_result(load("res://scripts/rules.gd").resolve(0,1,0,1))
		for i in range(18): game.update_ending(0.1)
		if bout == 0: game.advance_arcade()
	await snap("result")
	game.show_leaderboard()
	await snap("leaderboard")
	game.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(PATH+suffix)
	DirAccess.remove_absolute("user://endless_capture_awards.json")
	quit()
