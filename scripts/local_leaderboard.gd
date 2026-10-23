class_name LocalLeaderboard
extends RefCounted
const FILE = "user://endless_board_v1.json"
const LIMIT = 20
var entries: Array = []
var path: String
var last_saved = true
var using_backup = false
func _init(storage: String = FILE) -> void:
	path = storage
	if not read_file(path): using_backup = read_file(path+".bak")
func read_file(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path): return false
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(file_path)) != OK: return false
	var data = parser.data
	if not data is Dictionary or not data.get("entries") is Array: return false
	entries.clear()
	for item in data.entries:
		if not item is Dictionary or not item.get("id") is String: continue
		if item.id.is_empty() or item.id.length() > 64: continue
		var valid = true
		for key in ["cleared","wins","losses","rounds","time"]:
			if not (item.get(key) is int or item.get(key) is float): valid = false
			elif not is_finite(float(item[key])) or float(item[key]) < 0: valid = false
		if not valid: continue
		if entries.any(func(e): return e.id == item.id): continue
		entries.append({"id":item.id,"cleared":int(item.cleared),"wins":int(item.wins),"losses":int(item.losses),"rounds":int(item.rounds),"time":int(item.time),"status":str(item.get("status","阶段记录")).left(12)})
	sort_entries()
	return true
func sort_entries() -> void:
	entries.sort_custom(func(a,b):
		if a.cleared != b.cleared: return a.cleared > b.cleared
		if a.losses != b.losses: return a.losses < b.losses
		if a.rounds != b.rounds: return a.rounds < b.rounds
		if a.time != b.time: return a.time < b.time
		return a.id < b.id)
	if entries.size() > LIMIT: entries.resize(LIMIT)
func record(run, status: String = "阶段记录") -> bool:
	if not run.endless or run.total_exchanges == 0: return true
	entries = entries.filter(func(e): return e.id != run.run_id)
	entries.append({"id":run.run_id,"cleared":run.cleared_stages,"wins":run.wins,"losses":run.losses,"rounds":run.total_exchanges,"time":run.started_at,"status":status})
	sort_entries()
	last_saved = save()
	return last_saved
func rank_of(id: String) -> int:
	for i in range(entries.size()):
		if entries[i].id == id: return i+1
	return 0
func save() -> bool:
	var temp = path+".tmp"
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"version":1,"entries":entries}))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	if not ok: return false
	if FileAccess.file_exists(path) and not using_backup:
		# Keep the last good file if the atomic replacement fails.
		if DirAccess.copy_absolute(path,path+".bak") != OK: return false
	var renamed = DirAccess.rename_absolute(temp,path) == OK
	if renamed: using_backup = false
	return renamed
