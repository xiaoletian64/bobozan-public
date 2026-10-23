class_name ArcadeRoute
extends Control
var endless_stage = -1
var stage = 0
var cleared = false
var progress = 1.0
const NAMES = ["赤练", "青岚", "墨尾 · 擂主"]
const COLORS = [Color("f0a570"),Color("72d6bf"),Color("d6a8ff")]
func setup(index: int, done: bool = false) -> void:
	endless_stage = -1
	stage = index
	cleared = done
	progress = 0
	show()
	queue_redraw()
func setup_endless(index: int) -> void:
	setup(1)
	endless_stage = index
func _process(delta: float) -> void:
	if progress < 1:
		progress = minf(1,progress+delta*2.5)
		queue_redraw()
func _draw() -> void:
	var font = get_theme_default_font()
	for i in range(3):
		var center = Vector2(170+i*300,42)
		var beaten = cleared or i < stage
		var active = not cleared and i == stage
		var rival_id = maxi(0,endless_stage+i-1)%3 if endless_stage >= 0 else i
		var color = COLORS[rival_id] if active or beaten else Color("a0a9bb")
		if i < 2:
			draw_line(center+Vector2(50,0),center+Vector2(250,0),Color("43556b"),3)
			if i < stage or cleared: draw_line(center+Vector2(50,0),center+Vector2(50+200*progress,0),COLORS[i],3)
		draw_circle(center,34,color.darkened(0.72))
		draw_arc(center,35,0,TAU,48,color,3 if active else 1)
		# A small red-panda portrait using the same silhouette as the fighters.
		draw_circle(center+Vector2(-15,-13),9,color)
		draw_circle(center+Vector2(15,-13),9,color)
		draw_circle(center,23,color)
		draw_circle(center+Vector2(-9,4),9,Color("fff0da"))
		draw_circle(center+Vector2(9,4),9,Color("fff0da"))
		draw_circle(center+Vector2(-9,0),3,Color("202736"))
		draw_circle(center+Vector2(9,0),3,Color("202736"))
		draw_circle(center+Vector2(0,9),3,Color("202736"))
		if beaten:
			var stamp = center+Vector2(23,-20)
			draw_circle(stamp,15,Color("71dfbb"))
			draw_line(stamp+Vector2(-7,0),stamp+Vector2(-2,5),Color("142c30"),3)
			draw_line(stamp+Vector2(-2,5),stamp+Vector2(7,-6),Color("142c30"),3)
		var title = ("已击败 · " if beaten else ("挑战中 · " if active else "待挑战 · "))+NAMES[i]
		if endless_stage >= 0:
			title = ("起点" if endless_stage == 0 and i == 0 else "第 %d 关 · %s" % [endless_stage+i,NAMES[rival_id]])
		var width = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
		draw_string(font,center+Vector2(-width/2,66),title,HORIZONTAL_ALIGNMENT_LEFT,-1,19,color)
