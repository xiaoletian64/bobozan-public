extends SceneTree
const Awards = preload("res://scripts/achievements.gd")
const PATH = "user://test_achievements_isolated.json"
func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var a = Awards.new(PATH)
	assert(a.record(9).is_empty())
	assert(a.record(10).size() == 1)
	assert(a.record(19).is_empty())
	assert(a.record(20).size() == 1)
	assert(a.record(20).is_empty())
	assert(a.record(1).is_empty()) # A new match never adds its rounds to a previous match.
	assert(a.record(29).is_empty())
	assert(a.record(30).size() == 1)
	assert(a.record(30,true).size() == 1)
	assert(a.record(31,true).is_empty())
	var b = Awards.new(PATH)
	assert(b.best_rounds == 31 and b.unlocked.size() == 4)
	assert(b.record(20,true).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("PASS: 10/20/30 thresholds, no repeats, no cross-match addition, first win, local persistence")
	quit()
