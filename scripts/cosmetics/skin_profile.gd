class_name SkinProfile
extends RefCounted
const Catalog = preload("res://scripts/cosmetics/skin_catalog.gd")
const FILE = "user://cosmetics_v1.json"
var storage_path: String
var days: Array[String] = []
var equipped = Catalog.BASE
# Server ownership is intentionally not accepted from local save data.
func _init(path: String = FILE) -> void:
	storage_path = path
	if not FileAccess.file_exists(path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != 1: return
	if data.get("days") is Array:
		for day in data.days:
			if valid_day(day) and not days.has(day): days.append(day)
		days.sort()
	equipped = Catalog.safe_id(data.get("equipped"))
	if not owns(equipped): equipped = Catalog.BASE
static func valid_day(value: Variant) -> bool:
	if not value is String or value.length() != 10: return false
	if value.substr(4,1) != "-" or value.substr(7,1) != "-": return false
	for part in value.split("-"):
		if not part.is_valid_int(): return false
	var year = int(value.substr(0,4))
	var month = int(value.substr(5,2))
	var day = int(value.substr(8,2))
	if year < 1970 or year > 9999 or month < 1 or month > 12: return false
	var leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	var lengths = [31,29 if leap else 28,31,30,31,30,31,31,30,31,30,31]
	return day >= 1 and day <= lengths[month-1]

func owns(id: String) -> bool:
	return id == Catalog.BASE or (id == Catalog.REWARD and days.size() >= 3)
func can_check_in(day: String = Time.get_date_string_from_system()) -> bool:
	return valid_day(day) and (days.is_empty() or day > days.back())
func check_in(day: String = Time.get_date_string_from_system()) -> Dictionary:
	if not valid_day(day): return {"ok":false,"message":"日期无法识别，请检查设备时间"}
	if days.has(day): return {"ok":false,"message":"今天已签到，明天再来吧"}
	if not days.is_empty() and day < days.back(): return {"ok":false,"message":"设备日期早于上次签到，请检查时间"}
	days.append(day)
	if not save():
		days.pop_back()
		return {"ok":false,"message":"保存失败，请重试；本次尚未计入签到"}
	return {"ok":true,"unlocked":days.size() == 3,"message":"行者皮肤已解锁，快来试穿！" if days.size() == 3 else "签到成功 · 已累计 %d 天" % days.size()}
func equip(id: String) -> bool:
	if not Catalog.SKINS.has(id) or not owns(id): return false
	var previous = equipped
	equipped = id
	if save(): return true
	equipped = previous
	return false
func save() -> bool:
	var temporary = storage_path+".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify({"version":1,"days":days,"equipped":equipped}))
	file.flush()
	var success = file.get_error() == OK
	file.close()
	if not success: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(storage_path)) == OK
