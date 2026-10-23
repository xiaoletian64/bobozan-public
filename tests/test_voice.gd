extends SceneTree
const FILE = "user://voice_test.cfg"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var config = ConfigFile.new()
	config.set_value("audio","enabled",false)
	config.set_value("unrelated","keep",17)
	assert(config.save(FILE) == OK)
	var game = load("res://main.tscn").instantiate()
	game.audio_settings_path = FILE
	root.add_child(game)
	assert(game.voice_kind == "female" and not game.sound_on)
	assert(game.rhythm_voice.ready[0].resource_path == "res://assets/audio/female/ready.wav")
	for kind in game.voice_banks:
		for cue in game.voice_banks[kind]:
			assert(game.voice_banks[kind][cue].back().get_length() < 0.34)
	game.select_voice("male")
	assert(not game.sound_on and game.voice_kind == "male")
	game.toggle_sound()
	assert(game.voice_kind == "male" and game.sound_on)
	game.load_audio_settings()
	assert(game.voice_kind == "male" and game.sound_on)
	config.load(FILE)
	assert(config.get_value("unrelated","keep") == 17)
	game.select_voice("female")
	game.round_no = 25
	game.state = "battle"
	game.speak("charge")
	assert(game.voice.stream.resource_path == "res://assets/audio/female/charge.wav")
	assert(game.voice.pitch_scale == 1.0)
	game.select_voice("male")
	game.speak("charge")
	assert(game.voice.stream.get_length() <= 0.34*0.85)
	game.show_audio_settings()
	game.preview_voice()
	var generation = game.preview_generation
	game.show_home()
	assert(game.preview_generation > generation and not game.voice.playing)
	await create_timer(0.65).timeout
	assert(not game.voice.playing)
	game.select_voice("female")
	game.queue_free()
	await process_frame
	var restored = load("res://main.tscn").instantiate()
	restored.audio_settings_path = FILE
	root.add_child(restored)
	assert(restored.voice_kind == "female")
	restored.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("PASS: female default and original audio, both tempo banks, voice/mute persistence, unrelated settings preserved, fast male fit, preview cancellation, restart")
	quit()
