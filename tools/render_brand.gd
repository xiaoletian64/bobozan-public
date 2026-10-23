extends SceneTree
func _initialize() -> void:
	var icon = Image.new()
	assert(icon.load_svg_from_string(FileAccess.get_file_as_string("res://assets/icon.svg")) == OK)
	icon.convert(Image.FORMAT_RGB8)
	assert(icon.save_png("res://assets/icon.png") == OK)
	quit()
