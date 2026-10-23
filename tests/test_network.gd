extends SceneTree
const Session = preload("res://scripts/network/duel_session.gd")
var a
var b
var wire: Array = []
var failures: Array = []
var outcomes: Array = []
var now = 100
var latency = 30
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--latency="): latency = int(arg.split("=")[1])
	a = Session.new(); b = Session.new()
	a.outbound.connect(func(p): wire.append({"to":b,"p":JSON.parse_string(JSON.stringify(p)),"at":now+latency}))
	b.outbound.connect(func(p): wire.append({"to":a,"p":JSON.parse_string(JSON.stringify(p)),"at":now+latency}))
	a.event.connect(func(kind,p): handle(a,kind,p))
	b.event.connect(func(kind,p): handle(b,kind,p))
	b.start(false,now+317)
	a.start(true,now)
	for i in range(30000):
		now += 10
		a.advance(now); b.advance(now+317)
		var due = wire.filter(func(item): return item.at <= now)
		wire = wire.filter(func(item): return item.at > now)
		for item in due: item.to.receive(item.p)
		if outcomes.size() >= 70 or not failures.is_empty(): break
	assert(failures.is_empty(),str(failures))
	assert(outcomes.size() == 70,"Thirty-five synchronized rounds expected, got "+str(outcomes.size()))
	assert(a.energies == b.energies)
	assert(abs(b.offset+317) < 11)
	for i in range(0,70,2): assert(outcomes[i] == outcomes[i+1])
	# Tampered reveal must not reach rules or award a win.
	var bad = Session.new()
	bad.start(true,0);bad.session_id = "a".repeat(32);bad.state = "collect";bad.round_id = 1;bad.phase = 2
	bad.commitments = {0:"a".repeat(64),1:"b".repeat(64)}
	bad.receive({"v":1,"type":"reveal","session":bad.session_id,"round":1,"action":3,"nonce":"0".repeat(48)})
	assert(bad.stopped)
	var timeout = Session.new();timeout.start(true,0);timeout.advance(10001);assert(timeout.stopped)
	print("PASS: two peers, 317ms clock offset, %dms wire latency, 35 matching rounds, tampered reveal and timeout rejection" % latency)
	quit()
func handle(s,kind: String,p: Dictionary) -> void:
	if kind == "lobby": s.ready()
	elif kind == "lock": s.commit(0 if s.round_id < 3 else 1)
	elif kind == "resolved": outcomes.append(p)
	elif kind == "interrupted": failures.append(p)
