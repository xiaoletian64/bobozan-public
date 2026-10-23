class_name ArenaRun
extends RefCounted
const RIVALS = [
	{"name":"赤练 · 急性子","habit":"有气就想出波，出手很主动。","hint":"先接住他的波，再抓住空能量的机会。","skin":"tiger"},
	{"name":"青岚 · 蓄力派","habit":"爱留能量，等一发强化波。","hint":"盯住 3 点能量；普通防挡不住强化波。","skin":"cloud"},
	{"name":"墨尾 · 老狐狸","habit":"会留意你重复使用的招式。","hint":"同一套路别一直用，试着打破自己的习惯。","skin":"tiger"}
]
var endless = false
var run_id = ""
var started_at = 0
var cleared_stages = 0
var continues = 0
var total_exchanges = 0
var comebacks = 0
var wins = 0
var losses = 0
var victories: Array = []
var stage = 0
var score = [0,0]
var exchanges = 0
var next_pace = 1
var history: Array = []
var recent: Array = []
var bout_open = false
var finished = false
var had_deficit = false
func _init(infinite: bool = false) -> void:
	endless = infinite
	run_id = Crypto.new().generate_random_bytes(12).hex_encode()
	started_at = int(Time.get_unix_time_from_system())
func rival_index() -> int: return stage % RIVALS.size()
func rival() -> Dictionary: return RIVALS[rival_index()]
func begin_bout() -> bool:
	if finished or bout_open or maxi(score[0],score[1]) >= 2: return false
	bout_open = true
	return true
func tempo_start() -> int:
	var floor_round = 16 if score == [1,1] else (8 if score[0]+score[1] > 0 else 1)
	return maxi(next_pace,maxi(floor_round,1+mini(stage,6)*4))
func record_exchange(result: Dictionary, pace: int = 0) -> void:
	if not bout_open: return
	exchanges += 1
	total_exchanges += 1
	next_pace = maxi(next_pace,maxi(pace,exchanges)+1)
	history.append(result.a)
	if history.size() > 24: history.pop_front()
	recent.append({"a":result.a,"b":result.b})
	if recent.size() > 3: recent.pop_front()
func finish_bout(won: bool) -> Dictionary:
	if not bout_open: return {}
	bout_open = false
	score[0 if won else 1] += 1
	if won: wins += 1
	else: losses += 1
	if score[0] < score[1]: had_deficit = true
	var match_done = maxi(score[0],score[1]) >= 2
	if match_done and score[0] == 2:
		cleared_stages += 1
		victories.append({"name":rival().name,"score":score.duplicate()})
		if endless and victories.size() > 3: victories.pop_front()
		if had_deficit: comebacks += 1
	finished = match_done and ((endless and score[1] == 2) or (not endless and score[0] == 2 and stage == RIVALS.size()-1))
	return {"match_done":match_done,"won":score[0] == 2,"cleared":finished and not endless,"comeback":match_done and score[0] == 2 and had_deficit}
func next_stage() -> bool:
	if bout_open or score[0] != 2 or finished: return false
	stage += 1
	reset_match()
	return true
func reset_match() -> void:
	score = [0,0]
	exchanges = 0
	next_pace = 1
	history.clear()
	recent.clear()
	bout_open = false
	finished = false
	had_deficit = false

func continue_match() -> bool:
	if endless or bout_open or score[1] != 2 or finished: return false
	continues += 1
	reset_match()
	return true
