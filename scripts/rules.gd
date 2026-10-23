class_name DuelRules
extends RefCounted
const NAMES = ["攒", "波", "防", "强化波", "强化防"]
const COSTS = [0, 1, 0, 3, 1]
const CAP = 5
static func legal(action: int, energy: int) -> bool:
	return action >= 0 and action < COSTS.size() and energy >= COSTS[action]
static func power(action: int) -> int:
	return 2 if action == 3 else (1 if action == 1 else 0)
static func hits(attack: int, defend: int) -> bool:
	var p = power(attack)
	if p == 0 or defend == 4: return false
	if defend == 2: return p == 2
	return p > power(defend)
static func resolve(a: int, b: int, ea: int, eb: int) -> Dictionary:
	if not legal(a, ea): a = 2
	if not legal(b, eb): b = 2
	return {"a": a, "b": b, "ea": mini(CAP, ea + (1 if a == 0 else -COSTS[a])), "eb": mini(CAP, eb + (1 if b == 0 else -COSTS[b])), "hit_a": hits(b,a), "hit_b": hits(a,b)}
