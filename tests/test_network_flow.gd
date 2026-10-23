extends SceneTree
const Main = preload("res://main.tscn")
const Session = preload("res://scripts/network/duel_session.gd")
var a
var b
var wire: Array = []
var now = 100
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	a = Main.instantiate(); b = Main.instantiate()
	root.add_child(a); root.add_child(b)
	a.set_process(false);b.set_process(false)
	for game in [a,b]:
		game.sound_on = false
		game.awards = preload("res://scripts/achievements.gd").new("user://network_flow_test.json")
		game.online = true
		game.state = "bluetooth"
		game.session = Session.new()
		game.session.event.connect(func(kind,p): game.on_session(kind,p))
	a.session.outbound.connect(func(p): wire.append({"to":b.session,"p":JSON.parse_string(JSON.stringify(p)),"at":now+30}))
	b.session.outbound.connect(func(p): wire.append({"to":a.session,"p":JSON.parse_string(JSON.stringify(p)),"at":now+30}))
	a.session.local_skin = "tiger"
	b.session.local_skin = "cloud"
	b.session.start(false,now+317);a.session.start(true,now)
	for i in range(1800):
		now += 10
		for game in [a,b]:
			game.session.advance(now if game == a else now+317)
			if game.session.state == "lobby": game.session.ready()
			if game.state == "battle" and not game.input_locked():
				game.select_move(0 if game.session.round_id == 1 or game == b else 1)
			if game.state == "ending": game.update_ending(0.01)
		var due = wire.filter(func(item): return item.at <= now)
		wire = wire.filter(func(item): return item.at > now)
		for item in due: item.to.receive(item.p)
		if a.state == "result" and b.state == "result": break
	assert(a.state == "result" and b.state == "result")
	assert(a.pending_result.hit_b and b.pending_result.hit_a)
	assert(a.completed_rounds == 2 and b.completed_rounds == 2)
	assert(b.fighters[1].skin_id == "tiger" and a.fighters[1].skin_id == "cloud")
	assert(a.energy[0] == b.energy[1] and b.energy[0] == a.energy[1])
	a.show_home();b.show_home()
	assert(not a.online and a.session == null)
	a.start_game()
	a.online = true
	a.session = Session.new()
	a.session.event.connect(a.on_session)
	a.session.start(true,Time.get_ticks_msec())
	a._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(a.session.stopped and not a.online and a.state == "bluetooth")
	assert(a.completed_rounds == 0 and not a.actions.visible)
	a.show_home()
	print("PASS: two game scenes, lobby, ready, synchronized selection, guest perspective, finisher, result, disconnect, background interruption without loss")
	quit()
