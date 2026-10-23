extends SceneTree
var game
var age = 0.0
var captured = false
func _initialize() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.start_demo.call_deferred()
func _process(delta: float) -> bool:
	age += delta
	if age > 2.0 and not captured:
		captured = true
		capture()
	return false
func capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/character-preview.png")
	game.start_game()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/battle-preview.png")
	quit()
