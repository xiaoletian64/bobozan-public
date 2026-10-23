class_name DuelAchievements
extends RefCounted
const FILE = "user://achievements_v1.json"
const FEATS = {"catch_super":"接住大招", "comeback":"逆风翻盘", "fast_finish":"疾速决胜", "arena_clear":"三擂通关"}
const GOALS = [
	{"id":"round10", "name":"渐入佳境", "rounds":10},
	{"id":"round20", "name":"见招拆招", "rounds":20},
	{"id":"round30", "name":"巅峰拉锯", "rounds":30}
]
var unlocked: Dictionary = {}
var best_rounds = 0
var storage_path = FILE
func _init(path: String = FILE) -> void:
	storage_path = path
	if FileAccess.file_exists(path):
		var value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary:
			if value.get("unlocked", {}) is Dictionary: unlocked = value.get("unlocked", {})
			best_rounds = maxi(0, int(value.get("best_rounds", 0)))
func record(completed: int, won: bool = false) -> Array[String]:
	var fresh: Array[String] = []
	var changed = completed > best_rounds
	best_rounds = maxi(best_rounds, completed)
	for goal in GOALS:
		if completed >= goal.rounds and not unlocked.has(goal.id):
			unlocked[goal.id] = true
			fresh.append(goal.name + " · 单局 " + str(goal.rounds) + " 回合")
	if won and not unlocked.has("first_win"):
		unlocked["first_win"] = true
		fresh.append("初露锋芒 · 首次获胜")
	if changed or not fresh.is_empty(): save()
	return fresh
func record_feat(id: String) -> Array[String]:
	var fresh: Array[String] = []
	if not FEATS.has(id) or unlocked.has(id): return fresh
	unlocked[id] = true
	fresh.append(FEATS[id])
	save()
	return fresh
func save() -> void:
	var file = FileAccess.open(storage_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"best_rounds":best_rounds,"unlocked":unlocked}))
func summary() -> String:
	var lines = ["个人最长交锋：%d 回合" % best_rounds]
	for id in FEATS:
		lines.append(("◆ 已解锁  " if unlocked.has(id) else "◇ 未解锁  ") + FEATS[id]+"  /  "+{"catch_super":"强化防接住强化波","comeback":"从 0 : 1 落后到赢下一擂","fast_finish":"在最高节奏拿下一分","arena_clear":"连续闯过三位对手"}[id])
	for goal in GOALS:
		lines.append(("◆ 已解锁  " if unlocked.has(goal.id) else "◇ 未解锁  ") + goal.name + "  /  单局完成 %d 回合" % goal.rounds)
	lines.append(("◆ 已解锁  " if unlocked.has("first_win") else "◇ 未解锁  ") + "初露锋芒  /  赢下一局")
	return "\n".join(lines)
