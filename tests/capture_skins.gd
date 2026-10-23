extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.sound_on = false
	game.sound_button.text = "音效：关"
	game.skin_profile = load("res://scripts/cosmetics/skin_profile.gd").new("user://skin_preview.json")
	game.skin_profile.days.clear()
	game.skin_profile.equipped = "cloud"
	game.show_wardrobe("cloud")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/panda-cloud.png")
	game.show_wardrobe("tiger")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/panda-reward.png")
	game.skin_profile.days.assign(["2026-01-01","2026-01-03","2026-01-05"])
	game.show_wardrobe("tiger","行者皮肤已解锁，快来试穿！")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/panda-unlocked.png")
	game.skin_profile.equipped = "cloud"
	game.start_demo()
	game.set_process(false)
	game.fighters[0].act("ready")
	game.header.text = "竹影 · 小熊猫"
	game.info.text = "游戏内 3D 角色 · 青竹武道服 / 奶白面颊 / 蓬松环尾"
	game.footer.text = "实际引擎渲染 · 支持攒、波、防、强化与决胜动作"
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/panda-character.png")
	game.queue_free()
	await process_frame
	quit()
