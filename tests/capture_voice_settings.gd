extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.audio_settings_path = "user://voice_capture_unsaved.cfg"
	root.add_child(game)
	game.voice_kind = "female"
	game.rhythm_voice = game.voice_banks.female
	game.sound_on = true
	game.show_audio_settings()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/voice-settings.png")
	game.queue_free()
	await process_frame
	quit()
