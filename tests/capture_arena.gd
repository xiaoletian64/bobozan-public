extends SceneTree
var game
func _initialize() -> void: run.call_deferred()
func snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/arena-"+name+".png")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new("user://arena_capture.json")
	game.start_arena()
	await create_timer(0.4).timeout
	await snap("intro")
	game.start_game()
	game.arena.score = [1,1]
	game.pace_round = 16
	game.energy = [3,3]
	game.resume_time = 0
	game.beat.text = "波\n●  ●  ○"
	game.refresh()
	await snap("decider")
	game.present_result(load("res://scripts/rules.gd").resolve(3,2,3,0))
	for i in range(18):
		game.update_ending(0.1)
		for f in game.fighters: f._process(0.1)
	game.update_toast(0.1)
	await snap("result")
	game.show_achievements()
	await snap("achievements")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://arena_capture.json"))
	quit()
