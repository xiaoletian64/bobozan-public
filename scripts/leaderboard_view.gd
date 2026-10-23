extends Control
func build(board, current_id: String) -> void:
	position = Vector2(210,175)
	size = Vector2(860,355)
	var scroll = ScrollContainer.new()
	scroll.size = size
	add_child(scroll)
	var list = VBoxContainer.new()
	list.custom_minimum_size.x = 835
	list.add_theme_constant_override("separation",6)
	scroll.add_child(list)
	if board.entries.is_empty():
		var empty = Label.new()
		empty.text = "还没有成绩\n开启一次无限闯关，留下你的第一条纪录。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(820,220)
		list.add_child(empty)
		return
	for i in range(board.entries.size()):
		var item = board.entries[i]
		var row = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color("315b57") if item.id == current_id else Color("25384d")
		style.set_corner_radius_all(8)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel",style)
		list.add_child(row)
		var text = Label.new()
		text.add_theme_font_size_override("font_size",20)
		var date = Time.get_date_string_from_unix_time(item.time)
		text.text = "%02d    %d 关    ·    %d 胜 %d 负    ·    %d 次交锋\n        %s  ·  %s%s" % [i+1,item.cleared,item.wins,item.losses,item.rounds,date,item.status,"  ·  本轮" if item.id == current_id else ""]
		row.add_child(text)
