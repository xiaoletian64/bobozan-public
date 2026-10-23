class_name SkinCatalog
extends RefCounted
# Stable save identifiers preserve previously earned ownership and equipment.
const BASE = "cloud"
const REWARD = "tiger"
const IDS = [BASE, REWARD]
const SKINS = {
	"cloud": {"name":"竹影 · 小熊猫", "tag":"基础款", "description":"青竹武道服、暖栗毛色与蓬松环尾。", "cloth":"386e62", "trim":"294b42", "dark":"443735", "hood":"bd6335", "source":"default"},
	"tiger": {"name":"赤焰 · 行者", "tag":"三日签到限定", "description":"赤色武道服、金色滚边与行者披巾。", "cloth":"823e3c", "trim":"c49a53", "dark":"382e32", "hood":"bd6335", "source":"checkin_3"}
}
static func safe_id(value: Variant) -> String:
	return value if value is String and SKINS.has(value) else BASE
static func get_skin(id: String) -> Dictionary:
	return SKINS[safe_id(id)]
