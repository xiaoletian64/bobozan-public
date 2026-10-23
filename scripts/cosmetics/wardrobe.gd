class_name WardrobeView
extends Control
signal skin_selected(id: String)
signal equip_requested(id: String)
signal checkin_requested
const Catalog = preload("res://scripts/cosmetics/skin_catalog.gd")
func text_at(value: String, at: Vector2, width: float, size_px: int, color: Color = Color("e8eeef")) -> Label:
	var label = Label.new()
	label.text = value
	label.position = at
	label.size.x = width
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",color)
	add_child(label)
	return label
func card(at: Vector2, extent: Vector2, color: Color) -> Panel:
	var panel = Panel.new()
	panel.position = at
	panel.size = extent
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel",style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel
func action(value: String, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	var b = Button.new()
	b.text = value
	b.position = at
	b.size = extent
	b.pressed.connect(callback)
	add_child(b)
	return b
func build(profile, selected: String, message: String = "") -> void:
	var data = Catalog.get_skin(selected)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card(Vector2(665,170),Vector2(530,427),Color("172d3e"))
	text_at("角色衣柜  /  "+("01" if selected == Catalog.BASE else "02"),Vector2(112,168),400,15,Color("95b7bd"))
	text_at(data.name,Vector2(112,194),450,34)
	text_at(data.tag+"  ·  "+("已拥有" if profile.owns(selected) else "可试穿"),Vector2(115,244),450,18,Color("efc783"))
	text_at("每天见一面",Vector2(697,194),460,28)
	text_at("累计签到 3 天，领取「赤焰 · 行者」",Vector2(697,241),460,20,Color("bacdd1"))
	for i in range(3):
		var done = profile.days.size() > i
		var x = 697+i*154
		card(Vector2(x,287),Vector2(140,95),Color("315751") if done else Color("253e4e"))
		text_at("第 %d 天" % (i+1),Vector2(x+20,298),110,18)
		text_at("已签到" if done else ("行者皮肤" if i == 2 else "来打个招呼"),Vector2(x+20,340),115,18,Color("edc888") if i == 2 else Color("bacdd1"))
	var today = Time.get_date_string_from_system()
	var date_reversed = not profile.days.is_empty() and today < profile.days.back()
	var checkin = action("今日签到" if profile.can_check_in() else ("请检查设备日期" if date_reversed else "今日已签到"),Vector2(697,405),Vector2(462,58),func(): checkin_requested.emit())
	checkin.disabled = not profile.can_check_in()
	var note = message if not message.is_empty() else "已累计 %d 天 · 中断不清零" % profile.days.size()
	text_at(note,Vector2(697,477),468,17,Color("efc783"))
	text_at("皮肤只改变外观，不影响对决强度。",Vector2(697,546),460,17,Color("95b7bd"))
	for i in range(Catalog.IDS.size()):
		var id = Catalog.IDS[i]
		var b = action(Catalog.get_skin(id).name,Vector2(112+i*251,520),Vector2(239,57),func(): skin_selected.emit(id))
		b.toggle_mode = true
		b.button_pressed = selected == id
	var equipped = profile.equipped == selected
	var owned = profile.owns(selected)
	var equip = action("已装备" if equipped else ("装备皮肤" if owned else "累计签到 3 天解锁"),Vector2(112,591),Vector2(490,54),func(): equip_requested.emit(selected))
	equip.disabled = equipped or not owned
