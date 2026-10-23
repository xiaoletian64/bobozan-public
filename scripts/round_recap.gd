class_name RoundRecap
extends RefCounted
const Rules = preload("res://scripts/rules.gd")
static func explain(result: Dictionary) -> String:
	if result.hit_a:
		if result.a == 0: return "你在攒能量时，被对方的%s抓住了。下次先看对方还有多少气。" % Rules.NAMES[result.b]
		if result.a == 2: return "普通防被强化波击穿。对手有 3 点能量时，要留意强化防。"
		return "你的普通波被强化波压过。可以试着提前出波，或留气强化防。"
	if result.hit_b:
		if result.b == 0: return "对手在攒，你的%s先到一步，拿下一分。" % Rules.NAMES[result.a]
		if result.b == 2: return "你的强化波击穿了普通防，拿下一分。"
		return "你的强化波压过了普通波，拿下一分。"
	return "双方接住了这一招，继续观察能量与出招习惯。"
static func trace(recent: Array) -> String:
	var yours: Array[String] = []
	var theirs: Array[String] = []
	for item in recent:
		yours.append(Rules.NAMES[item.a])
		theirs.append(Rules.NAMES[item.b])
	return "最近交锋  ·  你："+" / ".join(yours)+"    对手："+" / ".join(theirs)
