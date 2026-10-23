extends SceneTree
# 在 106 上无头渲染 iOS 全套图标：绝对路径，不依赖项目目录。
const OUT := "/tmp/iconwork/"
func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("/tmp/iconwork/icon.svg")
	assert(svg.length() > 0)
	var base := Image.new()
	assert(base.load_svg_from_string(svg, 2.0) == OK)  # 1024
	base.convert(Image.FORMAT_RGB8)
	var sizes := [1024, 180, 167, 152, 120, 87, 80, 76, 58, 40, 29, 20]
	for s in sizes:
		var im: Image = base.duplicate()
		im.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var err := im.save_png(OUT + "icon-%d.png" % s)
		assert(err == OK, "save %d failed" % s)
		print("saved icon-%d.png" % s)
	quit()
