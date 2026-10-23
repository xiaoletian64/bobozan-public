extends Node3D
const Rules = preload("res://scripts/rules.gd")
const Actor = preload("res://scripts/fighter.gd")
const Clock = preload("res://scripts/beat_clock.gd")
const Tempo = preload("res://scripts/tempo.gd")
const Bot = preload("res://scripts/opponent.gd")
const Arena = preload("res://scripts/arena_run.gd")
const Recap = preload("res://scripts/round_recap.gd")
var arena
var leaderboard = preload("res://scripts/local_leaderboard.gd").new()
var leaderboard_view: Control
var pace_round = 1
var recent_rounds: Array = []
var recap_label: Label
var score_label: Label
var ui_pulses: Dictionary = {}
var route: Control
var cinematic_action = ""
var cinematic_remaining = 0.0
var cinematic_paused = false
var cinematic_pause_button: Button
var entrance_tween: Tween
const Awards = preload("res://scripts/achievements.gd")
const FX = preload("res://scripts/arena_fx.gd")
const Session = preload("res://scripts/network/duel_session.gd")
const Skins = preload("res://scripts/cosmetics/skin_catalog.gd")
const Profile = preload("res://scripts/cosmetics/skin_profile.gd")
const Wardrobe = preload("res://scripts/cosmetics/wardrobe.gd")
var skin_profile = Profile.new()
var wardrobe: Control
var preview_skin = Skins.BASE
const Bridge = preload("res://scripts/network/ble_bridge.gd")
var software_preview = false
var online = false
var session
var bridge
var ota_bridge
var peers: Dictionary = {}
var early_packets: Array = []
var fighters: Array = []
var clock = Clock.new()
var bot = Bot.new()
var energy = [0,0]
var history: Array = []
var selected = 2
var opponent_move = 0
var state = "home"
var round_no = 1
var sound_on = true
var suspended = false
var resume_time = 0.0
var demo_time = 0.0
var demo_index = -1
var root: Control
var header: Label
var info: Label
var beat: Label
var footer: Label
var actions: HBoxContainer
var menu: GridContainer
var sound_button: Button
var buttons: Array = []
var player: AudioStreamPlayer
var tones: Array = []
var rhythm_voice: Dictionary = {}
var voice_banks: Dictionary = {}
var voice_kind = "female"
var audio_settings_path = "user://settings.cfg"
var preview_generation = 0
var voice: AudioStreamPlayer
var platforms: Array = []
var awards = Awards.new()
var fx: Node3D
var camera: Camera3D
var timeline: ProgressBar
var milestone: Label
var toast: Label
var achievement_text: Label
var flash: ColorRect
var completed_rounds = 0
var impact_remaining = -1.0
var ending_elapsed = 0.0
var pending_result: Dictionary = {}
var toast_queue: Array[String] = []
var toast_remaining = 0.0
var impact_shown = false
var fall_started = false
func _ready() -> void:
	software_preview = OS.has_feature("debug") and "Software" in RenderingServer.get_video_adapter_name()
	if software_preview: get_viewport().scaling_3d_scale = 0.5
	build_stage()
	build_ui()
	build_audio()
	bridge = Bridge.new()
	add_child(bridge)
	bridge.message.connect(on_bridge)
	ota_bridge = Bridge.new()
	add_child(ota_bridge)
	ota_bridge.message.connect(func(value):
		if value.get("event") == "bridge_ready": ota_bridge.command("open_update")
		elif value.get("event") == "error" and state == "audio_settings": footer.text = "无法打开更新服务，请使用新版完整安装包重试")
	load_audio_settings()
	sound_button.text = "音效：开" if sound_on else "音效：关"
	show_home()
	if "--demo" in OS.get_cmdline_user_args(): start_demo()
	if "--battle" in OS.get_cmdline_user_args(): start_game()
func build_stage() -> void:
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("101b2b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("bed5ef")
	e.ambient_light_energy = 0.4
	env.environment = e
	add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 0.65
	light.shadow_enabled = not software_preview
	add_child(light)
	camera = Camera3D.new()
	camera.position = Vector3(0,4.0,9.8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.8
	add_child(camera)
	camera.look_at(Vector3(0,0.9,0))
	fx = FX.new()
	add_child(fx)
	for i in range(2):
		var f = Actor.new()
		f.tint = Color("64e6c6") if i == 0 else Color("ffb16d")
		f.skin_id = skin_profile.equipped if i == 0 else Skins.BASE
		f.position.x = -2.25 if i == 0 else 2.25
		f.rotation.y = PI/3 if i == 0 else -PI/3
		f.projectile_direction = Vector3(0.5 if i == 0 else -0.5,0,0.866)
		add_child(f)
		fighters.append(f)
		var platform = MeshInstance3D.new()
		var mesh = CylinderMesh.new()
		mesh.top_radius = 1.45
		mesh.bottom_radius = 1.55
		mesh.height = 0.18
		platform.mesh = mesh
		platform.position = Vector3(f.position.x,-0.16,0)
		platform.material_override = Actor.material(Color("263c4b"))
		add_child(platform)
		platforms.append(platform)
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.27
	floor_mesh.material_override = Actor.material(Color("162536"))
	add_child(floor_mesh)
func label_at(text: String, pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size",font_size)
	root.add_child(l)
	return l
func button(text: String, callback: Callable, parent: Node) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(252 if parent == menu else 176,82)
	b.add_theme_font_size_override("font_size",22)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
func build_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var theme = Theme.new()
	theme.default_font_size = 22
	var font = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font.variation_opentype = {"wght": 550.0}
	font.variation_embolden = 0.55
	theme.default_font = font
	for type in ["normal","hover","pressed","disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("243d4b") if type != "pressed" else Color("397b70")
		if type == "disabled": style.bg_color = Color("1d2936")
		style.set_corner_radius_all(14)
		style.set_border_width_all(1)
		style.border_color = Color("547078")
		theme.set_stylebox(type,"Button",style)
	root.theme = theme
	header = label_at("",Vector2(40,24),Vector2(1200,55),34)
	info = label_at("",Vector2(80,91),Vector2(1120,42),24)
	beat = label_at("",Vector2(440,195),Vector2(400,150),44)
	footer = label_at("",Vector2(40,650),Vector2(1200,45),18)
	milestone = label_at("",Vector2(260,508),Vector2(760,38),18)
	score_label = label_at("",Vector2(330,135),Vector2(620,35),21)
	recap_label = label_at("",Vector2(130,453),Vector2(1020,90),18)
	recap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recap_label.hide()
	route = preload("res://scripts/arcade_route.gd").new()
	route.position = Vector2(170,425)
	route.size = Vector2(940,115)
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(route)
	route.hide()
	toast = label_at("",Vector2(250,475),Vector2(780,30),18)
	toast.add_theme_color_override("font_color",Color("f7d88b"))
	achievement_text = label_at("",Vector2(280,195),Vector2(720,225),23)
	achievement_text.hide()
	timeline = ProgressBar.new()
	timeline.position = Vector2(450,177)
	timeline.size = Vector2(380,6)
	timeline.max_value = 1.0
	timeline.show_percentage = false
	var track = StyleBoxFlat.new()
	track.bg_color = Color("263e4c")
	track.set_corner_radius_all(3)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("67dec5")
	fill.set_corner_radius_all(3)
	timeline.add_theme_stylebox_override("background",track)
	timeline.add_theme_stylebox_override("fill",fill)
	timeline.size = Vector2(380,6)
	root.add_child(timeline)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1,0.85,0.55,0)
	root.add_child(flash)
	actions = HBoxContainer.new()
	actions.position = Vector2(184,558)
	actions.add_theme_constant_override("separation",12)
	root.add_child(actions)
	for i in range(5):
		var b = button(Rules.NAMES[i]+"\n"+("+1" if i == 0 else ("免费" if i == 2 else "−"+str(Rules.COSTS[i]))),func(): select_move(i),actions)
		b.toggle_mode = true
		buttons.append(b)
	menu = GridContainer.new()
	menu.position = Vector2(514,370)
	menu.add_theme_constant_override("h_separation",12)
	menu.add_theme_constant_override("v_separation",12)
	root.add_child(menu)
	sound_button = button("音效：开",toggle_sound,root)
	sound_button.position = Vector2(1060,16)
	sound_button.custom_minimum_size = Vector2(170,82)
	var home = button("首页",show_home,root)
	home.position = Vector2(35,16)
	home.custom_minimum_size = Vector2(110,82)
func clear_menu() -> void:
	menu.columns = 1
	menu.position.x = 514
	for c in menu.get_children():
		c.hide()
		c.queue_free()
	menu.size = Vector2.ZERO
func show_home() -> void:
	if arena != null and arena.endless and not arena.finished: leaderboard.record(arena,"主动结束")
	arena = null
	leave_online()
	reset_presentation()
	state = "home"
	suspended = false
	resume_time = 0
	fighters[0].show()
	fighters[1].show()
	fighters[0].position.x = -4.1
	fighters[1].position.x = 4.1
	fighters[0].rotation.y = PI/3
	for f in fighters:
		f.set_process(true)
		f.scale = Vector3.ONE * 1.15
		f.act("idle")
	for p in platforms: p.show()
	platforms[0].position.x = -4.1
	platforms[1].position.x = 4.1
	header.text = "波 波 赞"
	info.text = "掌 心 对 决   /   童年的默契，现在出招"
	beat.text = "波 · 波 · 攒！"
	beat.add_theme_font_size_override("font_size",28)
	footer.text = "离线练习  ·  附近双人  ·  无广告"
	actions.hide()
	clear_menu()
	button("街机闯关",start_arena,menu)
	button("无限闯关",start_endless,menu)
	button("本机排行榜",show_leaderboard,menu)
	button("蓝牙双人",show_bluetooth,menu)
	button("玩法说明",show_help,menu)
	button("角色与签到",show_wardrobe,menu)
	button("交锋成就",show_achievements,menu)
	button("声音与设置",show_audio_settings,menu)
	menu.columns = 2
	menu.position = Vector2(398,265)
	beat.text = ""
	for item in menu.get_children(): item.custom_minimum_size = Vector2(236,82)
func show_wardrobe(id: String = "", message: String = "") -> void:
	leave_online()
	reset_presentation()
	state = "wardrobe"
	suspended = false
	resume_time = 0
	clear_menu()
	actions.hide()
	preview_skin = skin_profile.equipped if id.is_empty() else Skins.safe_id(id)
	fighters[0].apply_skin(preview_skin)
	fighters[0].show()
	fighters[0].position.x = -2.0
	fighters[0].rotation.y = 0.25
	fighters[0].scale = Vector3.ONE*1.28
	fighters[0].act("ready")
	fighters[1].hide()
	platforms[0].show()
	platforms[0].position.x = -2.0
	platforms[1].hide()
	camera.size = 9.8
	header.text = "我的角色"
	info.text = "同一个你，每一次都焕然一新"
	beat.text = ""
	footer.text = "签到记录与已装备皮肤保存在本机"
	wardrobe = Wardrobe.new()
	root.add_child(wardrobe)
	wardrobe.build(skin_profile,preview_skin,message)
	wardrobe.skin_selected.connect(show_wardrobe)
	wardrobe.equip_requested.connect(func(chosen):
		var ok = skin_profile.equip(chosen)
		show_wardrobe(chosen,"已装备，下场对决见！" if ok else "装备未保存，请重试"))
	wardrobe.checkin_requested.connect(func():
		var result = skin_profile.check_in()
		show_wardrobe(Skins.REWARD if result.get("unlocked",false) else preview_skin,result.message))
func show_help() -> void:
	clear_menu()
	beat.text = "两拍选择，末拍同时出招"
	info.text = "攒 +1  /  波 −1  /  防 免费  /  强化波 −3  /  强化防 −1"
	footer.text = "强化波破普通防与普通波，强化防挡全部；一次命中拿一分；能量上限 5"
	button("单局练习",start_practice,menu)
func start_demo() -> void:
	arena = null
	reset_presentation()
	state = "demo"
	clear_menu()
	fighters[1].hide()
	fighters[0].position.x = 0
	fighters[0].rotation.y = 0.25
	fighters[0].projectile_direction = Vector3(0,0,1)
	fighters[0].scale = Vector3.ONE * 1.3
	camera.size = 7.8
	platforms[0].position.x = 0
	platforms[1].hide()
	header.text = "动作展台 / 小熊猫武者"
	info.text = "准备 → 攒 → 波 → 防 → 强化 → 受击 → 胜利"
	beat.text = ""
	actions.show()
	for b in buttons: b.disabled = false
	footer.text = "点击动作可单独预览；自动轮播包含倒地与胜利。"
	demo_time = 0
	demo_index = -1
func pulse_ui(control: Control, amount: float, duration: float) -> void:
	if ui_pulses.has(control) and ui_pulses[control].is_valid(): ui_pulses[control].kill()
	control.pivot_offset = control.size*0.5
	control.scale = Vector2.ONE*amount
	var tween = control.create_tween()
	tween.tween_property(control,"scale",Vector2.ONE,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ui_pulses[control] = tween
func start_practice() -> void:
	arena = null
	bot.persona = 0
	bot.challenge = 0
	start_game()
func start_arena() -> void:
	leave_online()
	arena = Arena.new()
	show_arena_intro()
func start_endless() -> void:
	leave_online()
	arena = Arena.new(true)
	show_arena_intro()
func show_leaderboard() -> void:
	reset_presentation()
	state = "leaderboard"
	actions.hide()
	clear_menu()
	for f in fighters: f.hide()
	for platform in platforms: platform.hide()
	header.text = "无限闯关 · 本机排行榜"
	info.text = "保留前 20 条 · 通关数优先，同关数按败局更少、交锋更少排序"
	info.add_theme_font_size_override("font_size",20)
	beat.text = ""
	leaderboard_view = preload("res://scripts/leaderboard_view.gd").new()
	root.add_child(leaderboard_view)
	leaderboard_view.build(leaderboard,arena.run_id if arena != null and arena.endless else "")
	menu.position = Vector2(382,558)
	menu.columns = 2
	if leaderboard.last_saved: button("挑战新纪录",start_endless,menu)
	else: button("重试保存成绩",func():
		leaderboard.last_saved = leaderboard.save()
		show_leaderboard(),menu)
	button("回到首页",show_home,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
	footer.text = "仅记录这台设备的真实对局 · 不含全球排名 · 卸载会清除记录"
	if not leaderboard.last_saved: footer.text = "成绩暂未写入磁盘，请检查存储空间；当前列表仍可查看"
func show_endless_result() -> void:
	var cause = recap_label.text
	reset_presentation()
	state = "endless_result"
	actions.hide()
	clear_menu()
	for f in fighters: f.hide()
	for platform in platforms: platform.hide()
	header.text = "无限挑战结束 · 闯过 %d 关" % arena.cleared_stages
	var rank = leaderboard.rank_of(arena.run_id)
	info.text = "本轮第 %d 名 · 本机排行榜" % rank if rank > 0 else "本轮未进入本机前 20 名"
	beat.text = "%d 关" % arena.cleared_stages
	beat.add_theme_font_size_override("font_size",68)
	achievement_text.position = Vector2(160,340)
	achievement_text.size = Vector2(960,100)
	achievement_text.add_theme_font_size_override("font_size",22)
	achievement_text.text = "止步第 %d 关 · %s\n%d 胜 %d 负 · %d 次交锋 · 翻盘 %d 次" % [arena.stage+1,arena.rival().name,arena.wins,arena.losses,arena.total_exchanges,arena.comebacks]
	achievement_text.show()
	recap_label.text = cause
	recap_label.show()
	menu.position = Vector2(382,558)
	menu.columns = 2
	button("再冲一次",start_endless,menu)
	button("查看排行榜",show_leaderboard,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
	footer.text = "成绩已保存 · 无限模式不续关，每次重新出发都是一条新纪录" if leaderboard.last_saved else "成绩保存失败，当前仍保留在内存，请检查存储空间"
	if rank == 0 and leaderboard.last_saved: footer.text = "本轮已结算，未进入前 20 名 · 再试一次，挑战更高关数"
func setup_run_route(next_index: int = -1) -> void:
	var index = arena.stage if next_index < 0 else next_index
	if arena.endless: route.setup_endless(index)
	else: route.setup(index)
func show_arena_intro() -> void:
	reset_presentation()
	state = "arena_intro"
	suspended = false
	resume_time = 0
	clear_menu()
	actions.hide()
	bot.persona = arena.rival_index()
	bot.challenge = minf(float(arena.stage)/12.0,1.0) if arena.endless else 0.0
	for i in range(2):
		fighters[i].show()
		fighters[i].position.x = -4.1 if i == 0 else 4.1
		fighters[i].scale = Vector3.ONE*0.98
		fighters[i].act("ready")
		platforms[i].show()
		platforms[i].position.x = fighters[i].position.x
	entrance_tween = create_tween().set_parallel(true)
	for f in fighters:
		entrance_tween.tween_property(f,"scale",Vector3.ONE*1.10,0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fighters[1].apply_skin(arena.rival().skin)
	header.text = "第 %d 擂 / %s" % [arena.stage+1,arena.rival().name]
	info.text = "三位对手 · 每场三局两胜 · 一次命中拿一分"
	beat.add_theme_font_size_override("font_size",22)
	beat.text = arena.rival().habit+"\n\n"+arena.rival().hint
	setup_run_route()
	menu.position = Vector2(382,558)
	menu.columns = 2
	button("挑战擂主" if arena.rival_index() == 2 else "开始挑战",begin_arcade_vs,menu)
	button("先来一局练习",start_practice,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
	if arena.rival_index() == 2:
		header.text = "最终对决 / 墨尾"
		beat.text = "你的套路，我已经看穿了。\n\n"+arena.rival().hint
		fighters[1].act("boss_ready")
		fx.ring(fighters[1].position,Color("d6a8ff"),1.8,0.8)
	footer.text = "闯过三位对手，挑战无续关通关 · 回首页会结束本轮"
	if arena.endless:
		header.text = "无限闯关 · 第 %d 关 / %s" % [arena.stage+1,arena.rival().name]
		header.add_theme_font_size_override("font_size",28)
		info.text = "已闯过 %d 关 · 每关三局两胜 · 输掉整关后结算" % arena.cleared_stages
		footer.text = "对手轮换，节奏与判断逐步加强；最高速度有上限 · 回首页结算已获成绩"
	set_arena_colors()
func set_arena_colors() -> void:
	if arena == null: return
	var color = [Color("614338"),Color("254f4d"),Color("44315b")][arena.rival_index()]
	for platform in platforms: platform.material_override.albedo_color = color
func begin_arcade_vs() -> void:
	if arena == null or state not in ["arena_intro","arcade_vs"]: return
	state = "arcade_vs"
	beat.text = "VS"
	beat.add_theme_font_size_override("font_size",76)
	info.text = ("第 %d 关 · 守关者登场" % [arena.stage+1] if arena.endless else "最终擂主登场") if arena.rival_index() == 2 else ["赤练：接招！别眨眼。","青岚：这一口气，留给关键时刻。"][arena.rival_index()]
	pulse_ui(beat,1.4,0.32)
	if entrance_tween != null and entrance_tween.is_valid(): entrance_tween.kill()
	entrance_tween = create_tween().set_parallel(true)
	for i in range(2):
		entrance_tween.tween_property(fighters[i],"position:x",-3.4 if i == 0 else 3.4,0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		entrance_tween.tween_property(platforms[i],"position:x",-3.4 if i == 0 else 3.4,0.4)
	queue_arcade_transition("fight",1.6)
func queue_arcade_transition(action: String, seconds: float) -> void:
	cinematic_action = action
	cinematic_remaining = seconds
	cinematic_paused = false
	clear_menu()
	menu.columns = 2
	menu.position = Vector2(382,558)
	button("立即继续",advance_arcade,menu)
	cinematic_pause_button = button("暂停转场",toggle_arcade_pause,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
func toggle_arcade_pause() -> void:
	if cinematic_action.is_empty(): return
	cinematic_paused = not cinematic_paused
	if is_instance_valid(cinematic_pause_button): cinematic_pause_button.text = "继续转场" if cinematic_paused else "暂停转场"
	for f in fighters: f.set_process(not cinematic_paused)
	route.set_process(not cinematic_paused)
	fx.process_mode = Node.PROCESS_MODE_DISABLED if cinematic_paused else Node.PROCESS_MODE_INHERIT
	if entrance_tween != null and entrance_tween.is_valid():
		if cinematic_paused: entrance_tween.pause()
		else: entrance_tween.play()
	for tween in ui_pulses.values():
		if tween.is_valid():
			if cinematic_paused: tween.pause()
			else: tween.play()
func advance_arcade() -> void:
	if cinematic_paused: toggle_arcade_pause()
	var action = cinematic_action
	cinematic_action = ""
	if arena == null: return
	match action:
		"fight", "bout": start_game()
		"vs": begin_arcade_vs()
		"next":
			if arena.next_stage():
				show_arena_intro()
				queue_arcade_transition("vs",2.2)
		"clear": show_arcade_clear()
func continue_arcade() -> void:
	if arena != null and arena.continue_match():
		show_arena_intro()
		queue_arcade_transition("vs",2.2)
func show_arcade_clear() -> void:
	if arena == null or not arena.finished: return
	reset_presentation()
	state = "arcade_clear"
	actions.hide()
	clear_menu()
	for f in fighters: f.hide()
	for platform in platforms: platform.hide()
	header.text = "全胜通关 · 新擂主诞生" if arena.losses == 0 else ("无续关通关 · 新擂主诞生" if arena.continues == 0 else "三擂通关 · 新擂主诞生")
	info.text = "从第一声波，到最后一击，你打通了整条路线。"
	beat.text = ""
	route.position.y = 170
	route.setup(2,true)
	var lines: Array[String] = []
	for victory in arena.victories: lines.append("击败 %s    %d : %d" % [victory.name,victory.score[0],victory.score[1]])
	lines.append("小局 %d 胜 %d 负    ·    交锋 %d 次" % [arena.wins,arena.losses,arena.total_exchanges])
	lines.append("逆风翻盘 %d 次    ·    续关 %d 次" % [arena.comebacks,arena.continues])
	achievement_text.position = Vector2(200,320)
	achievement_text.size = Vector2(880,200)
	achievement_text.add_theme_font_size_override("font_size",24)
	achievement_text.text = "\n".join(lines)
	achievement_text.show()
	menu.position = Vector2(382,558)
	menu.columns = 2
	button("再闯一轮",start_arena,menu)
	button("回到首页",show_home,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
	footer.text = "下一次，试着不输一小局。" if arena.losses > 0 else "这一轮，一路全胜。"
func start_game() -> void:
	if arena != null and not arena.bout_open:
		if not arena.begin_bout(): return
	reset_presentation()
	state = "battle"
	if online and session != null: fighters[1].apply_skin(session.remote_skin)
	elif arena != null: fighters[1].apply_skin(arena.rival().skin)
	set_arena_colors()
	completed_rounds = 0
	timeline.show()
	milestone.show()
	clear_menu()
	fighters[0].show()
	fighters[1].show()
	fighters[0].position.x = -2.25
	fighters[1].position.x = 2.25
	fighters[0].rotation.y = PI/3
	fighters[0].projectile_direction = Vector3(0.5,0,0.866)
	for f in fighters:
		f.scale = Vector3.ONE
		f.set_process(true)
		f.body.position = Vector3.ZERO
		f.body.rotation = Vector3.ZERO
		f.act("ready")
	for p in platforms: p.show()
	platforms[0].position.x = -2.25
	platforms[1].position.x = 2.25
	energy = [0,0]
	history.clear()
	recent_rounds.clear()
	round_no = 1
	selected = 2
	opponent_move = bot.choose(0,0,history)
	pace_round = arena.tempo_start() if arena != null else 1
	clock.reset(pace_round)
	resume_time = 1.2 if arena != null else 0.0
	suspended = false
	actions.show()
	beat.add_theme_font_size_override("font_size",44)
	footer.text = "两拍选招，光条走满锁定 · 小局之间继续加速" if arena != null else "波 · 波 · 攒！  /  第 6 回合起逐渐加速，光条走满锁定"
	refresh()
func select_move(i: int) -> void:
	if state == "demo":
		fighters[0].act(["charge","wave","guard","super","strong_guard"][i])
		demo_time = 0
		info.text = "单独预览："+Rules.NAMES[i]
		return
	if state != "battle" or suspended or resume_time > 0 or input_locked(): return
	if Rules.legal(i,energy[0]):
		selected = i
		pulse_ui(buttons[i],1.07,0.14)
	refresh()
func refresh() -> void:
	header.text = "第 %02d 回合  /  %.1f× 节奏" % [round_no,Tempo.BASE_BEAT/current_beat_seconds()]
	info.text = "你   %s     ·     能量 %d / 5                         电脑     ·     能量 %d / 5" % ["●".repeat(energy[0]),energy[0],energy[1]]
	if online: info.text = info.text.replace("电脑","对方")
	elif arena != null:
		if arena.endless: header.add_theme_font_size_override("font_size",28)
		info.text = info.text.replace("电脑",arena.rival().name)
		header.text = ("无限 · 第 %d 关 / %s" if arena.endless else "第 %d 擂 / %s") % [arena.stage+1,arena.rival().name]
		score_label.text = "你  %d : %d  对手    ·    %s" % [arena.score[0],arena.score[1],"决胜局" if arena.score == [1,1] else "三局两胜"]
		score_label.show()
	var next_goal = 10 if completed_rounds < 10 else (20 if completed_rounds < 20 else 30)
	milestone.text = "本局已交锋 %d 回合   ·   %s" % [completed_rounds, "下一枚徽章 %d 回合" % next_goal if completed_rounds < 30 else "巅峰拉锯已达成"]
	if arena != null:
		milestone.text = "本场 %d 次交锋  ·  %.1f× 节奏  ·  %s" % [arena.exchanges,Tempo.BASE_BEAT/current_beat_seconds(),"决胜时刻，稳住再出招" if arena.score == [1,1] else "先拿两分，挑战下一擂"]
	for i in range(5):
		buttons[i].disabled = state != "battle" or suspended or resume_time > 0 or input_locked() or not Rules.legal(i,energy[0])
		buttons[i].button_pressed = selected == i
func _process(delta: float) -> void:
	if not cinematic_action.is_empty():
		if not cinematic_paused:
			cinematic_remaining = maxf(0,cinematic_remaining-delta)
			update_toast(delta)
		footer.text = "转场已暂停 · 点击继续或立即跳过" if cinematic_paused else "%.1f 秒后继续 · 可跳过，也可暂停查看" % cinematic_remaining
		if cinematic_remaining <= 0 and not cinematic_paused: advance_arcade()
		return
	if online and session != null: session.advance(Time.get_ticks_msec())
	if state == "demo":
		demo_time += delta
		if demo_time >= 1.8 or demo_index == -1:
			demo_time = 0
			demo_index = (demo_index+1)%8
			fighters[0].act(["ready","charge","wave","guard","super","strong_guard","lose","win"][demo_index])
			info.text = ["准备：两拍蓄势","攒：掌心聚气","波：双掌推出","防：交臂格挡","强化波：破防","强化防：能量护盾","受击：倒地","获胜：举手欢呼"][demo_index]
	if suspended: return
	update_toast(delta)
	if state == "ending":
		if resume_time > 0:
			resume_time = maxf(0,resume_time-delta)
			beat.text = ("准备 %d" if state == "battle" and clock.tick == -1 else "继续倒数 %d") % ceili(resume_time)
			if resume_time == 0:
				fx.process_mode = Node.PROCESS_MODE_INHERIT
				for f in fighters: f.set_process(not impact_shown or fall_started)
			return
		update_ending(delta)
		return
	if state != "battle": return
	if resume_time > 0:
		resume_time = maxf(0,resume_time-delta)
		beat.text = ("准备 %d" if state == "battle" and clock.tick == -1 else "继续倒数 %d") % ceili(resume_time)
		if resume_time == 0:
			fx.process_mode = Node.PROCESS_MODE_INHERIT
			for f in fighters: f.set_process(true)
			beat.text = "波" if clock.tick % 3 != 2 else "出招"
			refresh()
		return
	timeline.value = session.progress() if online and session != null else clock.selection_progress()
	if impact_remaining >= 0:
		impact_remaining -= delta
		if impact_remaining < 0: show_impact(false)
	if online: return
	for step in clock.advance(minf(delta,0.1)):
		if step == 0:
			round_no = completed_rounds + 1
			pace_round = clock.round_number
			selected = 2
			opponent_move = bot.choose(energy[1],energy[0],arena.history if arena != null else history)
			for f in fighters:
				f.animation_speed = Tempo.BASE_BEAT/current_beat_seconds()
				fx.ring(f.position+Vector3(0,0.015,0),f.tint,1.35,current_beat_seconds()*0.6)
		if step < 2:
			beat.text = "波\n" + ("●  ○  ○" if step == 0 else "●  ●  ○")
			for f in fighters: f.act("ready")
			speak("ready")
			pulse_ui(beat,1.09 if step == 0 else 1.15,current_beat_seconds()*0.45)
		else:
			pulse_ui(buttons[selected],1.08,0.18)
			resolve_round()
		refresh()
func resolve_round() -> void:
	var result = Rules.resolve(selected,opponent_move,energy[0],energy[1])
	present_result(result)
func present_result(result: Dictionary) -> void:
	pending_result = result
	recent_rounds.append({"a":result.a,"b":result.b})
	if recent_rounds.size() > 3: recent_rounds.pop_front()
	if arena != null: arena.record_exchange(result,pace_round)
	energy = [result.ea,result.eb]
	history.append(result.a)
	completed_rounds += 1
	toast_queue.append_array(awards.record(completed_rounds))
	var anim = ["charge","wave","guard","super","strong_guard"]
	fighters[0].act(anim[result.a])
	fighters[1].act(anim[result.b])
	beat.text = Rules.NAMES[result.a]+"  /  "+Rules.NAMES[result.b]
	speak(anim[result.a])
	pulse_ui(beat,1.16,0.20)
	for i in range(2):
		var move = result.a if i == 0 else result.b
		if move == 0: fx.gather(fighters[i].position+Vector3(0,1.15,0),fighters[i].tint,current_beat_seconds()*0.8)
	if result.hit_a or result.hit_b:
		var winner = 0 if result.hit_b else 1
		for f in fighters: f.animation_speed = 1.0
		fighters[winner].finishing = true
		fx.begin_finisher(fighters[winner].position, fighters[1-winner].position, fighters[winner].tint, (result.a if winner == 0 else result.b) == 3)
		state = "ending"
		ending_elapsed = 0.0
		impact_shown = false
		fall_started = false
		impact_remaining = -1.0
	else:
		impact_remaining = 0.55*current_beat_seconds()/Tempo.BASE_BEAT
func show_impact(finisher: bool) -> void:
	var r = pending_result
	if r.is_empty(): return
	var at = Vector3(0,1.2,0)
	var color = Color("e6e7cb")
	if r.hit_a or r.hit_b:
		var loser = 1 if r.hit_b else 0
		at = fighters[loser].position + Vector3(0,1.2,0)
		color = fighters[1-loser].tint
	elif Rules.power(r.a) > 0 and Rules.power(r.b) == 0:
		at = fighters[1].position+Vector3(0,1.2,0)
	elif Rules.power(r.b) > 0 and Rules.power(r.a) == 0:
		at = fighters[0].position+Vector3(0,1.2,0)
	elif Rules.power(r.a) == 0 and Rules.power(r.b) == 0: return
	for i in range(2):
		if Rules.power(r.a if i == 0 else r.b) > 0:
			fighters[i].projectile_spent = true
			fighters[i].orb.hide()
	var strong = finisher and (r.a == 3 or r.b == 3)
	var blocked = not finisher and (Rules.power(r.a) == 0 or Rules.power(r.b) == 0)
	if blocked:
		var defender = 1 if Rules.power(r.a) > 0 else 0
		fighters[defender].block_impact()
		fx.deflect(at,fighters[defender].tint)
		if defender == 0 and r.a == 4 and r.b == 3: toast_queue.append_array(awards.record_feat("catch_super"))
	else: fx.burst(at,color,strong)
	if strong: fx.ring(at-Vector3(0,1.15,0),color,2.3,0.55)
	if not finisher:
		beat.text = "对波 · 抵消" if Rules.power(r.a) > 0 and Rules.power(r.b) > 0 else ("强化防 · 接住了！" if r.a == 4 and r.b == 3 else "格挡！")
		pulse_ui(beat,1.10,0.18)
func update_ending(delta: float) -> void:
	if state != "ending": return
	ending_elapsed += minf(delta,0.1)
	fx.seek_finisher(ending_elapsed)
	if ending_elapsed < 0.55: return
	var won = pending_result.hit_b
	var loser = 1 if won else 0
	if not impact_shown:
		impact_shown = true
		show_impact(true)
		beat.text = "KO · 破防！" if pending_result.a == 3 or pending_result.b == 3 else "KO · 决胜！"
		beat.add_theme_font_size_override("font_size",32)
		if arena != null and not arena.endless and arena.stage == 2 and won and arena.score[0] == 1:
			beat.text = "终擂 · 决胜！"
			fx.ring(fighters[0].position,Color("f7d88b"),2.6,0.75)
		flash.color.a = 0.22
		for f in fighters: f.set_process(false)
		play_tone(3)
	# Local 140 ms hit-stop; rules and global Engine.time_scale stay untouched.
	if ending_elapsed >= 0.69 and not fall_started:
		fall_started = true
		for f in fighters: f.set_process(true)
		fighters[loser].act("lose")
		fighters[1-loser].act("win")
	camera.size = lerpf(camera.size,8.7,minf(delta*6,1))
	camera.h_offset = sin(ending_elapsed*90)*maxf(0,1.0-ending_elapsed)*0.12
	flash.color.a = maxf(0,flash.color.a-delta*1.0)
	if ending_elapsed >= 1.65:
		show_bout_result(won)
func show_bout_result(won: bool) -> void:
	state = "result"
	camera.h_offset = 0
	header.text = "拿下一分！" if won else "这一分失守"
	beat.text = "胜利" if won else "惜败"
	info.text = "本小局 %d 次交锋 · 看清这一分怎么赢、怎么输" % completed_rounds
	toast_queue.append_array(awards.record(completed_rounds,won))
	if won and pace_round >= 25 and arena != null: toast_queue.append_array(awards.record_feat("fast_finish"))
	actions.hide()
	timeline.hide()
	milestone.hide()
	recap_label.text = Recap.explain(pending_result)+"\n"+Recap.trace(recent_rounds)
	recap_label.show()
	clear_menu()
	menu.columns = 2
	menu.position = Vector2(382,558)
	if arena != null:
		var result = arena.finish_bout(won)
		if arena.endless:
			leaderboard.record(arena,"败北" if arena.finished else "阶段记录")
			if arena.finished:
				show_endless_result()
				return
		score_label.text = "你  %d : %d  %s" % [arena.score[0],arena.score[1],arena.rival().name]
		score_label.show()
		pulse_ui(score_label,1.18,0.3)
		if result.get("comeback",false): toast_queue.append_array(awards.record_feat("comeback"))
		if result.get("cleared",false):
			header.text = "三擂通关 · 今天你是擂主"
			toast_queue.append_array(awards.record_feat("arena_clear"))
			queue_arcade_transition("clear",3.2)
		elif result.get("match_done",false):
			if result.won:
				header.text = "拿下这一擂！"
				recap_label.hide()
				setup_run_route(arena.stage+1)
				queue_arcade_transition("next",3.2)
			else:
				header.text = "这一擂失守，再摸清他的习惯"
				info.text = "本轮已续关 %d 次 · 继续挑战将计入一次续关" % arena.continues
				button("续关 · 再战本擂",continue_arcade,menu)
		else:
			header.text = "1 : 1 · 下一分定胜负" if arena.score == [1,1] else ("领先一分，稳住！" if won else "落后一分，还能扳回来")
			queue_arcade_transition("bout",3.8)
	else:
		button("重新连接" if online else "再来一局",show_bluetooth if online else start_game,menu)
	if cinematic_action.is_empty(): button("回到首页",show_home,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(252,70)
	footer.text = "胜负已经结算，准备好再继续。"
func reset_presentation() -> void:
	if ota_bridge != null: ota_bridge.close()
	if is_instance_valid(leaderboard_view):
		leaderboard_view.hide()
		leaderboard_view.queue_free()
		leaderboard_view = null
	if header: header.add_theme_font_size_override("font_size",34)
	if info: info.add_theme_font_size_override("font_size",24)
	cinematic_action = ""
	cinematic_paused = false
	if route:
		route.hide()
		route.position.y = 425
		route.set_process(true)
	for platform in platforms: platform.material_override.albedo_color = Color("263c4b")
	if achievement_text:
		achievement_text.position = Vector2(280,195)
		achievement_text.size = Vector2(720,225)
	if entrance_tween != null and entrance_tween.is_valid(): entrance_tween.kill()
	for control in ui_pulses:
		if ui_pulses[control].is_valid(): ui_pulses[control].kill()
		if is_instance_valid(control): control.scale = Vector2.ONE
	ui_pulses.clear()
	if score_label: score_label.hide()
	if recap_label: recap_label.hide()
	preview_generation += 1
	if voice: voice.stop()
	if is_instance_valid(wardrobe):
		wardrobe.hide()
		wardrobe.queue_free()
		wardrobe = null
	for i in range(fighters.size()):
		fighters[i].apply_skin(skin_profile.equipped if i == 0 else Skins.BASE)
	if not is_instance_valid(fx): return
	fx.process_mode = Node.PROCESS_MODE_INHERIT
	fx.clear()
	camera.size = 9.8
	camera.h_offset = 0
	flash.color.a = 0
	impact_remaining = -1
	pending_result = {}
	toast_queue.clear()
	toast.text = ""
	toast_remaining = 0
	achievement_text.hide()
	menu.position.y = 370
	timeline.hide()
	milestone.hide()
	for f in fighters:
		f.set_process(true)
		f.animation_speed = 1.0
func update_toast(delta: float) -> void:
	toast_remaining -= delta
	if toast_remaining <= 0:
		if not toast_queue.is_empty():
			toast.position.y = 410 if state == "result" else 475
			toast.text = "◆ 成就达成  " + toast_queue.pop_front()
			toast_remaining = 3.2
		else: toast.text = ""
func show_achievements() -> void:
	reset_presentation()
	state = "achievements"
	clear_menu()
	menu.position.y = 550
	for f in fighters: f.hide()
	for p in platforms: p.hide()
	beat.text = ""
	header.text = "交锋成就"
	info.text = "接住大招、逆风翻盘、闯过三擂，留下你的高光"
	achievement_text.position.y = 170
	achievement_text.size.y = 350
	achievement_text.add_theme_font_size_override("font_size",19)
	achievement_text.text = awards.summary()
	achievement_text.show()
	footer.text = "成就本地保存，不影响战力；旧的回合徽章继续保留。"
	button("回到首页",show_home,menu)
func build_audio() -> void:
	voice = AudioStreamPlayer.new()
	add_child(voice)
	player = AudioStreamPlayer.new()
	add_child(player)
	voice.volume_db = -1.0
	# Short, soft impact with filtered noise; no oscillator over the spoken beats.
	var rng = RandomNumberGenerator.new()
	rng.seed = 108
	var sample = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var data = PackedByteArray()
	data.resize(4410*2)
	var low = 0.0
	for i in range(4410):
		var t = float(i)/22050.0
		low = lerpf(low,rng.randf_range(-1,1),0.12)
		var envelope = minf(t/0.004,1.0)*exp(-t*35.0)
		data.encode_s16(i*2,int(clampf(low*envelope*10000,-32767,32767)))
	sample.data = data
	tones.append(sample)
	voice_banks = {"female":{},"male":{}}
	for cue in ["ready","charge","wave","guard"]:
		voice_banks.female[cue] = [load("res://assets/audio/female/%s.wav" % cue)]
		var versions: Array = []
		for index in range(6): versions.append(load("res://assets/audio/rhythm/%s-%d.wav" % [cue,index]))
		voice_banks.male[cue] = versions
	rhythm_voice = voice_banks[voice_kind]
func current_beat_seconds() -> float:
	return session.beat_seconds() if online and session != null else Tempo.beat_seconds(pace_round if arena != null else round_no)
func play_tone(_i: int) -> void:
	if sound_on:
		player.stream = tones[0]
		player.volume_db = -8.0
		player.play()
func speak(cue: String) -> void:
	if not sound_on: return
	# One caller per Bluetooth pair avoids two unsynchronised speakers shouting.
	if online and session != null and not session.host: return
	var short_cue = "wave" if cue == "super" else ("guard" if cue == "strong_guard" else cue)
	if not rhythm_voice.has(short_cue): return
	var interval = current_beat_seconds() if state in ["battle","ending"] else Tempo.BASE_BEAT
	# Fit each spoken syllable into its beat, without raising vocal pitch.
	var versions: Array = rhythm_voice[short_cue]
	var clip = versions.back()
	for candidate in versions:
		if candidate.get_length() <= interval*0.85:
			clip = candidate
			break
	voice.pitch_scale = 1.0
	voice.stream = clip
	voice.play()
func load_audio_settings() -> void:
	var config = ConfigFile.new()
	sound_on = true
	voice_kind = "female"
	if config.load(audio_settings_path) == OK:
		sound_on = bool(config.get_value("audio","enabled",true))
		var saved = config.get_value("audio","voice","female")
		if saved is String and voice_banks.has(saved): voice_kind = saved
	rhythm_voice = voice_banks[voice_kind]
func save_audio_settings() -> bool:
	var config = ConfigFile.new()
	config.load(audio_settings_path)
	config.set_value("audio","enabled",sound_on)
	config.set_value("audio","voice",voice_kind)
	return config.save(audio_settings_path) == OK
func select_voice(kind: String) -> void:
	if not voice_banks.has(kind): return
	preview_generation += 1
	voice.stop()
	voice_kind = kind
	rhythm_voice = voice_banks[kind]
	var saved = save_audio_settings()
	if state == "audio_settings":
		show_audio_settings()
		if not saved: footer.text = "本次切换已生效，设置保存失败，请稍后重试"
func preview_voice() -> void:
	if not sound_on: return
	preview_generation += 1
	var generation = preview_generation
	for cue in ["ready","ready","charge"]:
		if generation != preview_generation or state != "audio_settings" or not sound_on: return
		speak(cue)
		await get_tree().create_timer(0.60).timeout
func check_app_update() -> void:
	if not OS.has_feature("android"):
		footer.text = "请在 Android 安装包内检查更新"
		return
	preview_generation += 1
	voice.stop()
	footer.text = "正在打开应用更新…"
	ota_bridge.open()
func show_audio_settings() -> void:
	leave_online()
	reset_presentation()
	state = "audio_settings"
	suspended = false
	resume_time = 0
	clear_menu()
	actions.hide()
	for f in fighters: f.hide()
	for p in platforms: p.hide()
	header.text = "声音与设置"
	info.text = "两种口令音色，选择你熟悉的那一种"
	beat.text = "当前："+("初版女声" if voice_kind == "female" else "男声")
	beat.add_theme_font_size_override("font_size",28)
	footer.text = "音色选择自动保存 · 两种音色都支持逐回合加速"
	menu.columns = 2
	menu.position = Vector2(398,295)
	var female = button("初版女声",func(): select_voice("female"),menu)
	var male = button("男声",func(): select_voice("male"),menu)
	female.toggle_mode = true
	male.toggle_mode = true
	female.button_pressed = voice_kind == "female"
	male.button_pressed = voice_kind == "male"
	button("试听：波波攒",preview_voice,menu).disabled = not sound_on
	button("音效：开" if sound_on else "音效：关",toggle_sound,menu)
	if not OS.has_feature("ios"): button("检查应用更新",check_app_update,menu)
	button("隐私与关于",show_privacy,menu)
	button("回到首页",show_home,menu)
	for item in menu.get_children(): item.custom_minimum_size = Vector2(236,70)
func toggle_sound() -> void:
	preview_generation += 1
	sound_on = not sound_on
	save_audio_settings()
	sound_button.text = "音效：开" if sound_on else "音效：关"
	if not sound_on:
		player.stop()
		voice.stop()
	if state == "audio_settings": show_audio_settings()
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not cinematic_action.is_empty():
		if not cinematic_paused: toggle_arcade_pause()
		if voice: voice.stop()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "audio_settings":
		preview_generation += 1
		if voice: voice.stop()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and online and session != null:
		session.cancel("对方切换到后台，本局已中断")
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state in ["battle","ending"]:
		suspended = true
		fx.process_mode = Node.PROCESS_MODE_DISABLED
		if player: player.stop()
		if voice: voice.stop()
		for f in fighters: f.set_process(false)
		if beat: beat.text = "已暂停"
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and suspended:
		suspended = false
		resume_time = 3.0

func input_locked() -> bool:
	if online: return session == null or session.state != "prepare" or session.phase < 0 or session.phase >= 2
	return clock.tick % 3 == 2
func leave_online() -> void:
	if session != null and not session.stopped and session.state != "finished": session.cancel()
	session = null
	online = false
	if bridge != null: bridge.close()
func show_bluetooth() -> void:
	arena = null
	leave_online()
	reset_presentation()
	state = "bluetooth"
	actions.hide()
	clear_menu()
	for f in fighters: f.hide()
	for p in platforms: p.hide()
	header.text = "附近双人对决"
	info.text = "一人创建房间，另一人加入；苹果与安卓使用相同玩法"
	beat.text = "正在启动蓝牙模块…"
	beat.add_theme_font_size_override("font_size",22)
	footer.text = "两台手机靠近并保持前台 · 无需账号或互联网 · 离开或断连不判负"
	peers.clear()
	early_packets.clear()
	bridge.open()
func on_bridge(p: Dictionary) -> void:
	match p.get("event",""):
		"bridge_ready":
			beat.text = "选择创建或加入房间"
			button("创建房间",func(): start_discovery("host"),menu)
			button("加入房间",func(): start_discovery("scan"),menu)
		"status":
			if state == "bluetooth": info.text = p.get("message","")
		"peer":
			if state != "bluetooth" or peers.has(p.id): return
			peers[p.id] = true
			if peers.size() <= 2:
				button(p.name,func():
					clear_menu()
					beat.text = "正在连接…"
					bridge.command("connect",{"id":p.id}),menu)
		"connected":
			online = true
			session = Session.new()
			session.local_skin = skin_profile.equipped
			session.outbound.connect(func(packet): bridge.command("send",{"packet":packet}))
			session.event.connect(on_session)
			session.start(p.get("host",false),Time.get_ticks_msec())
			beat.text = "正在核对双方规则…"
			for packet in early_packets: session.receive(packet)
			early_packets.clear()
		"packet":
			if p.get("packet") is Dictionary:
				if session != null: session.receive(p.packet)
				elif state == "bluetooth" and early_packets.size() < 8: early_packets.append(p.packet)
		"error", "disconnected":
			if session != null: session.fail(p.get("message","连接中断"))
			else: connection_error(p.get("message","连接中断"))
func start_discovery(command: String) -> void:
	clear_menu()
	peers.clear()
	beat.text = "等待对方加入" if command == "host" else "搜索附近玩家"
	button("重新选择",show_bluetooth,menu)
	bridge.command(command)
func connection_error(message: String) -> void:
	online = false
	if bridge != null: bridge.command("disconnect")
	reset_presentation()
	for f in fighters: f.act("idle")
	state = "bluetooth"
	actions.hide()
	timeline.hide()
	beat.text = "连接已停止"
	info.text = message
	clear_menu()
	button("重试",show_bluetooth,menu)
	button("回到首页",show_home,menu)
func on_session(kind: String, p: Dictionary) -> void:
	match kind:
		"lobby":
			clear_menu()
			beat.text = "房间校验码 " + p.code
			info.text = "确认两台手机显示相同校验码，然后双方准备"
			button("准备对战",func():
				clear_menu()
				beat.text = "等待双方准备…"
				session.ready(),menu)
		"countdown":
			if state != "battle":
				start_game()
				round_no = p.round
				beat.text = "准备 · 第 %d 回合" % round_no
			footer.text = "蓝牙对战 · 两拍选择，光条走满锁定 · 默认防守"
			refresh()
		"beat":
			if p.step == 0:
				round_no = p.round
				selected = 2
				for f in fighters:
					f.animation_speed = Tempo.BASE_BEAT/current_beat_seconds()
					fx.ring(f.position+Vector3(0,0.015,0),f.tint,1.35,current_beat_seconds()*0.6)
			beat.text = "波\n" + ("●  ○  ○" if p.step == 0 else "●  ●  ○")
			for f in fighters: f.act("ready")
			speak("ready")
			refresh()
		"lock":
			beat.text = "已锁定 · 同步出招"
			session.commit(selected)
			refresh()
		"resolved":
			var result = p.duplicate(true)
			if not session.host:
				result = {"a":p.b,"b":p.a,"ea":p.eb,"eb":p.ea,"hit_a":p.hit_b,"hit_b":p.hit_a}
			present_result(result)
			refresh()
		"interrupted": connection_error(p.message)
func show_privacy() -> void:
	reset_presentation()
	state = "privacy"
	actions.hide()
	clear_menu()
	for f in fighters: f.hide()
	for p in platforms: p.hide()
	header.text = "隐私与关于"
	info.text = "波波赞 · 本地游玩与附近蓝牙对战"
	beat.text = ""
	achievement_text.text = "无需注册，无广告或分析追踪。\n成就、排行榜与声音设置仅保存在本机，卸载会清除。\n蓝牙仅在创建或搜索房间时使用，交换临时房间与对局数据。\n不读取联系人或照片，不使用蓝牙推算位置；不向外部服务器上传对局数据。\n手动检查更新时，会连接更新服务器获取版本与安装包。\n音效可关闭；离开联机对局会中断，不计输赢。\n口令由 Kokoro 中文模型本地生成，游戏内不调用语音服务。"
	achievement_text.add_theme_font_size_override("font_size",20)
	achievement_text.show()
	menu.position.y = 470
	footer.text = "使用 Godot Engine（MIT）与 Noto Sans SC（OFL）；许可随应用附带。"
	button("回到首页",show_home,menu)
