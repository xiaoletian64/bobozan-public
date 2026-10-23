class_name BluetoothDuelSession
extends RefCounted
# Pure, transport-independent session. All timestamps are monotonic milliseconds.
signal outbound(packet: Dictionary)
signal event(kind: String, value: Dictionary)
const Rules = preload("res://scripts/rules.gd")
const Skins = preload("res://scripts/cosmetics/skin_catalog.gd")
var local_skin = Skins.BASE
var remote_skin = Skins.BASE
const Tempo = preload("res://scripts/tempo.gd")
const VERSION = 1
const RULESET = "bobo-1-cap5-cost0,1,0,3,1-triplet-ramp-v1"
var host = false
var session_id = ""
var state = "idle"
var now = 0
var offset = 0.0
var rtt = 0.0
var sync_samples: Array = []
var ping_sent = 0
var local_ready = false
var remote_ready = false
var round_id = 0
var energies = [0,0]
var start_at = 0
var release_at = 0
var phase = -1
var local_action = -1
var nonce = ""
var commitments: Dictionary = {}
var reveals: Dictionary = {}
var reveal_sent = false
var remote_verified = false
var result: Dictionary = {}
var deadline = 0
var last_received = 0
var last_heartbeat = 0
var stopped = false
func start(is_host: bool, clock_ms: int) -> void:
	host = is_host
	now = clock_ms
	last_received = now
	state = "handshake"
	deadline = now + 12000
	if host:
		session_id = Crypto.new().generate_random_bytes(16).hex_encode()
		send("hello",{"rules":RULESET,"skin":Skins.safe_id(local_skin)})
func send(type: String, data: Dictionary = {}) -> void:
	var p = data.duplicate(true)
	p.merge({"v":VERSION,"type":type,"session":session_id,"round":round_id},true)
	outbound.emit(p)
func fail(reason: String) -> void:
	if stopped: return
	stopped = true
	state = "interrupted"
	event.emit("interrupted",{"message":reason})
func cancel(reason: String = "对方离开了对局") -> void:
	if not stopped: send("cancel",{"message":reason})
	fail(reason)
func ready() -> void:
	if state != "lobby": return
	local_ready = true
	send("ready")
	maybe_sync()
func maybe_sync() -> void:
	if local_ready and remote_ready:
		state = "sync"
		deadline = now+12000
		if not host: ping()
func ping() -> void:
	ping_sent = now
	send("ping",{"t0":now})
func host_time() -> int:
	return now if host else roundi(now+offset)
func digest(action: int, salt: String, player: int) -> String:
	return (session_id+"|"+str(round_id)+"|"+str(player)+"|"+str(action)+"|"+salt).sha256_text()
func commit(action: int) -> void:
	if state != "collect" or phase != 2 or local_action != -1: return
	var player = 0 if host else 1
	if not Rules.legal(action,energies[player]): action = 2
	local_action = action
	nonce = Crypto.new().generate_random_bytes(24).hex_encode()
	commitments[player] = digest(action,nonce,player)
	send("commit",{"hash":commitments[player]})
	try_reveal()
func try_reveal() -> void:
	if commitments.size() != 2 or local_action < 0 or reveal_sent: return
	reveal_sent = true
	var player = 0 if host else 1
	reveals[player] = local_action
	send("reveal",{"action":local_action,"nonce":nonce})
	try_result()
func try_result() -> void:
	if reveals.size() != 2: return
	result = Rules.resolve(reveals[0],reveals[1],energies[0],energies[1])
	state = "verified"
	send("verified",{"hash":result_hash()})
	if host and remote_verified: schedule_release()
func result_hash() -> String:
	return ("%d|%d|%d|%d|%s|%s" % [result.a,result.b,result.ea,result.eb,str(result.hit_a),str(result.hit_b)]).sha256_text()
func schedule_release() -> void:
	if state != "verified": return
	release_at = now + maxi(120,ceili(rtt*1.5+60))
	state = "release"
	send("release",{"at":release_at,"hash":result_hash()})
func begin_round(at: int) -> void:
	round_id += 1
	start_at = at
	phase = -1
	local_action = -1
	reveal_sent = false
	remote_verified = false
	commitments.clear()
	reveals.clear()
	result.clear()
	state = "prepare"
	deadline = now + maxi(0,at-host_time())+12000
	if host: send("round",{"at":at,"energy":energies})
	event.emit("countdown",{"ms":maxi(0,start_at-host_time()),"round":round_id})
func receive(p: Dictionary) -> void:
	if stopped: return
	if p.get("v") != VERSION or not p.get("type") is String or not p.get("session") is String:
		fail("联机协议不兼容，请双方更新至同一版本")
		return
	var type: String = p.type
	if type == "hello" and not host and state == "handshake":
		if p.get("rules") != RULESET or p.session.length() != 32:
			fail("双方规则版本不一致")
			return
		session_id = p.session
		remote_skin = Skins.safe_id(p.get("skin"))
		state = "lobby"
		send("hello_ack",{"rules":RULESET,"skin":Skins.safe_id(local_skin)})
		event.emit("lobby",{"code":session_id.substr(0,6).to_upper()})
		return
	if p.session != session_id: return
	last_received = now
	if type == "cancel":
		fail("对方暂停或离开，本局已中断；请重新准备")
		return
	if type == "heartbeat": return
	if type == "hello_ack" and host and state == "handshake":
		if p.get("rules") != RULESET:
			fail("双方规则版本不一致")
			return
		remote_skin = Skins.safe_id(p.get("skin"))
		state = "lobby"
		event.emit("lobby",{"code":session_id.substr(0,6).to_upper()})
	elif type == "ready" and state == "lobby":
		remote_ready = true
		maybe_sync()
	elif type == "ping" and host and state == "sync" and number(p.get("t0")):
		send("pong",{"t0":p.t0,"t1":now})
	elif type == "pong" and not host and state == "sync":
		if not number(p.get("t0")) or not number(p.get("t1")) or int(p.t0) != ping_sent: return
		var elapsed = now-int(p.t0)
		if elapsed < 0 or elapsed > 2000:
			fail("蓝牙延迟过高，请靠近后重试")
			return
		sync_samples.append({"rtt":elapsed,"offset":float(p.t1)-(float(p.t0)+now)/2.0})
		if sync_samples.size() < 7: ping()
		else:
			sync_samples.sort_custom(func(a,b): return a.rtt < b.rtt)
			offset = (sync_samples[0].offset+sync_samples[1].offset+sync_samples[2].offset)/3.0
			rtt = sync_samples[2].rtt
			send("synced",{"rtt":rtt})
	elif type == "synced" and host and state == "sync":
		if not number(p.get("rtt")) or p.rtt < 0 or p.rtt > 2000:
			fail("时钟校准失败")
			return
		rtt = p.rtt
		begin_round(now+3000)
	elif type == "round" and not host and state in ["sync","between"]:
		if not number(p.get("round")) or int(p.round) != round_id+1 or not number(p.get("at")) or not matching_energy(p.get("energy")):
			fail("回合状态不同步")
			return
		if int(p.at) < host_time()+100:
			fail("准备消息迟到，请重新连接")
			return
		begin_round(int(p.at))
	elif p.get("round") != round_id: return
	elif type == "commit" and state in ["prepare","collect"]:
		var peer = 1 if host else 0
		if not p.get("hash") is String or p.hash.length() != 64:
			fail("出招承诺无效")
			return
		if commitments.has(peer) and commitments[peer] != p.hash:
			fail("对方锁定后更改了出招")
			return
		commitments[peer] = p.hash
		try_reveal()
	elif type == "reveal" and state == "collect":
		var peer = 1 if host else 0
		if commitments.size() != 2 or not number(p.get("action")) or int(p.action) != p.action or not p.get("nonce") is String or p.nonce.length() != 48:
			fail("收到无效出招数据")
			return
		var a = int(p.action)
		if not Rules.legal(a,energies[peer]) or digest(a,p.nonce,peer) != commitments[peer]:
			fail("对方出招校验失败")
			return
		reveals[peer] = a
		try_result()
	elif type == "verified" and state == "verified":
		if p.get("hash") != result_hash():
			fail("双方结算不一致")
			return
		remote_verified = true
		if host: schedule_release()
	elif type == "release" and not host and state == "verified":
		if p.get("hash") != result_hash() or not number(p.get("at")) or int(p.at) < host_time()+50:
			fail("同步出招超时，请重新连接")
			return
		release_at = int(p.at)
		state = "release"
func advance(clock_ms: int) -> void:
	now = clock_ms
	if stopped or state == "idle": return
	if now-last_heartbeat > 1500:
		last_heartbeat = now
		if session_id != "": send("heartbeat")
	if now-last_received > 10000:
		fail("与对方连接中断，本局不会判负")
		return
	if state in ["handshake","sync","prepare","collect","verified","release"] and now > deadline:
		fail("等待对方超时，本局已中断")
		return
	if state in ["prepare","collect"]:
		var t = host_time()-start_at
		if t >= 0 and phase < 0:
			phase = 0
			event.emit("beat",{"step":0,"round":round_id,"energy":energies})
		if t >= roundi(beat_seconds()*1000) and phase < 1:
			phase = 1
			event.emit("beat",{"step":1})
		if t >= roundi(beat_seconds()*2000) and phase < 2:
			phase = 2
			state = "collect"
			event.emit("lock",{})
	if state == "release" and host_time() >= release_at:
		energies = [result.ea,result.eb]
		state = "finished" if result.hit_a or result.hit_b else "between"
		event.emit("resolved",result.duplicate(true))
	if host and state == "between":
		begin_round(release_at+roundi(beat_seconds()*1000))
func beat_seconds() -> float:
	# Leave enough lead time for the next-round packet on slower links.
	return maxf(Tempo.beat_seconds(round_id),rtt/2000.0+0.18)
func progress() -> float:
	return clampf(float(host_time()-start_at)/(beat_seconds()*2000.0),0,1)
static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func matching_energy(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for i in range(2):
		if not number(value[i]) or value[i] != energies[i]: return false
	return true
