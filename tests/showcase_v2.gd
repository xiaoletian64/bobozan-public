extends SceneTree
var game
var elapsed = 0.0
var mark = -1
var capture_index = 0
const TEMP = "user://showcase_temporary_awards.json"
func _initialize() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)
	setup.call_deferred()
func setup() -> void:
	await process_frame
	game.set_process(false)
	game.awards = load("res://scripts/achievements.gd").new(TEMP)
	game.start_demo()
	game.fighters[0].act("ready")
	game.footer.text = "v0.2 效果演示 · 程序化角色 / 口令与终结特效"
func _process(delta: float) -> bool:
	if not is_instance_valid(game) or not game.is_node_ready(): return false
	elapsed += delta
	var stage = int(elapsed/1.7)
	if stage != mark:
		mark = stage
		if stage < 4:
			game.fighters[0].act(["ready","charge","wave","guard"][stage])
			game.speak(["ready","charge","wave","guard"][stage])
			game.info.text = ["准备 · 双臂起势","攒 · 掌心聚气","波 · 推掌发射","防 · 交臂护盾"][stage]
		elif stage == 4:
			game.start_game()
			game._process(0.001)
			game.energy = [3,0]
			game.selected = 3
			game.opponent_move = 2
			game.refresh()
			game.footer.text = "v0.2 效果演示 · 第二声后留出选招余量，1.80 秒锁定"
		elif stage == 7:
			game.show_achievements()
			game.footer.text = "成就示意 · 单局 10 / 20 / 30 回合，不影响战力"
		elif stage == 9:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
			quit()
	if stage >= 4 and stage < 7: game._process(delta)
	if capture_index == 0 and elapsed > 2.2:
		capture_index += 1
		capture("character-v2.png")
	elif capture_index == 1 and elapsed > 9.15:
		capture_index += 1
		capture("finisher-v2.png")
	elif capture_index == 2 and elapsed > 12.3:
		capture_index += 1
		capture("achievements-v2.png")
	return false
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+name)
