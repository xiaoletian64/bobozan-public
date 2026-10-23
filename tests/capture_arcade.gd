extends SceneTree
var game
func _initialize() -> void: run.call_deferred()
func snap(name: String) -> void:
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/arcade-"+name+".png")
func finish() -> void:
	game.present_result(load("res://scripts/rules.gd").resolve(3,2,3,0))
	for i in range(18):
		game.update_ending(0.1)
		for f in game.fighters: f._process(0.1)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.awards = load("res://scripts/achievements.gd").new("user://arcade_capture.json")
	game.start_arena()
	await snap("route")
	game.begin_arcade_vs()
	await snap("vs")
	game.advance_arcade()
	for stage in range(3):
		finish()
		game.advance_arcade()
		finish()
		if stage == 0: await snap("advance")
		game.advance_arcade()
		if stage < 2:
			if stage == 1: await snap("boss")
			game.advance_arcade()
			game.advance_arcade()
	await snap("clear")
	game.show_home()
	await snap("home")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://arcade_capture.json"))
	quit()
