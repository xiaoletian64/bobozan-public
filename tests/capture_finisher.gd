extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound_on = false
	game.sound_button.text = "音效：关"
	game.awards = load("res://scripts/achievements.gd").new("user://finisher_preview.json")
	for winner in [0,1]:
		game.start_game()
		game.online = true
		game.info.text = "你  ·  青绿                         好友  ·  暖橙"
		game.footer.text = "双人斩杀演出预览 · 强化波破防 · 非蓝牙实机录像"
		game.present_result(load("res://scripts/rules.gd").resolve(3,2,3,0) if winner == 0 else load("res://scripts/rules.gd").resolve(2,3,0,3))
		game.refresh()
		for f in game.fighters: f.set_process(false)
		for i in range(48):
			for f in game.fighters: f._process(0.01)
			game.update_ending(0.01)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/finisher-direction-%d.png" % winner)
		for i in range(10):
			for f in game.fighters:
				if not game.impact_shown: f._process(0.01)
			game.update_ending(0.01)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/finisher-impact-%d.png" % winner)
		for i in range(100):
			game.update_ending(0.01)
			for f in game.fighters: f._process(0.01)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/panda-fall-%d.png" % winner)
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://finisher_preview.json"))
	quit()
