extends Control
const Texts = preload("res://features/localization/game_text.gd")

signal action_requested(action: String, payload: Dictionary)
signal inspected(item: Dictionary)

var container_name := "bag"
var slot_index: Variant = 0
var item: Dictionary = {}
var definition: Dictionary = {}
var accent := Color("8bc1b7")
var slot_label := ""
var locked := false
var selected := false
var _hovered := false
var _font: Font

func _ready() -> void:
	Texts.watch_draw(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(40, 40)
	_font = ThemeDB.fallback_font
	mouse_entered.connect(func() -> void:
		_hovered = true
		inspected.emit(item)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())
	queue_redraw()

func set_item(value: Dictionary, info: Dictionary = {}) -> void:
	item = value.duplicate()
	definition = info
	if item.is_empty():
		Texts.bind(self, slot_label, "tooltip_text")
	else:
		Texts.bind(self, str(info.get("name",item.get("kind","")))+"\n"+preload("res://features/inventory/item_catalog.gd").details(item)+"⟦item_slot.001⟧", "tooltip_text")
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if locked or item.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			action_requested.emit("context", {"from": container_name, "index": slot_index, "position": get_global_mouse_position(), "item": item})
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			inspected.emit(item)
			if event.ctrl_pressed:
				action_requested.emit("quick_transfer", {"from": container_name, "index": slot_index})
			elif event.double_click:
				if container_name == "equipment":
					action_requested.emit("unequip", {"slot": slot_index})
				elif container_name == "bag":
					var kind := str(item.get("kind", ""))
					if kind in ["rifle", "pistol", "helmet", "armor", "backpack"]:
						action_requested.emit("equip", {"index": slot_index})
					else:
						action_requested.emit("use", {"index": slot_index})
			accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item.is_empty() or locked:
		return null
	var preview: Control = get_script().new()
	preview.item = item.duplicate()
	preview.definition = definition
	preview.custom_minimum_size = Vector2(76, 76)
	preview.size = Vector2(76, 76)
	preview.modulate.a = 0.9
	set_drag_preview(preview)
	return {"duckov_item": true, "from": container_name, "index": slot_index, "uid": item.get("uid", -1)}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not locked and data is Dictionary and data.get("duckov_item", false)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	action_requested.emit("transfer", {"from": data.from, "index": data.index, "to": container_name, "target": slot_index})

func _draw() -> void:
	var bg := Color("30383d")
	if _hovered:
		bg = Color("43575c")
	if locked:
		bg = Color("242b30")
	draw_style_box(_box(bg, definition.get("rarity_color",Color("778589")) if not item.is_empty() else Color("596064"), 2 if not item.is_empty() else 1), Rect2(Vector2.ZERO, size))
	if not item.is_empty():
		var col: Color = definition.get("color", Color("b8c1bb"))
		draw_rect(Rect2(4, size.y - 5, size.x - 8, 2), definition.get("rarity_color",col))
		draw_string(_font, Vector2(5,17), Texts.resolve(["⟦item_slot.002⟧","⟦item_slot.003⟧","⟦item_slot.004⟧","⟦item_slot.005⟧","⟦item_slot.006⟧","⟦item_slot.007⟧"][int(definition.get("rarity",0))]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, definition.get("rarity_color",col))
		_draw_icon(str(item.get("kind", "")), Rect2(Vector2(10, 8), size - Vector2(20, 21)), col)
		var count := int(item.get("count", 1))
		if count > 1:
			var count_text := str(count)
			var width := _font.get_string_size(Texts.resolve(count_text), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_rect(Rect2(size.x - width - 12, size.y - 25, width + 9, 21), Color(0.08, 0.11, 0.13, 0.88))
			draw_string(_font, Vector2(size.x - width - 8, size.y - 9), Texts.resolve(count_text), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f4f2db"))
	elif not slot_label.is_empty():
		var width := _font.get_string_size(Texts.resolve(slot_label), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(_font, Vector2((size.x - width) * 0.5, size.y * 0.57), Texts.resolve(slot_label), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9da9a8"))
	if selected:
		draw_style_box(_box(Color.TRANSPARENT, accent, 3), Rect2(Vector2.ZERO, size))

func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	return style

func _draw_icon(kind: String, area: Rect2, tint: Color) -> void:
	var center := area.get_center()
	var s := minf(area.size.x, area.size.y) / 56.0
	draw_set_transform(center, -0.22 if kind in ["rifle", "pistol", "ammo"] else 0.0, Vector2.ONE * s)
	var dark := Color("1c252b")
	var metal := Color("a7b3b2")
	match kind:
		"rifle":
			draw_colored_polygon(PackedVector2Array([Vector2(-29,-4),Vector2(-18,-9),Vector2(-12,-6),Vector2(14,-6),Vector2(14,3),Vector2(-13,3),Vector2(-23,11),Vector2(-29,10)]), Color("8d826b"))
			draw_rect(Rect2(-14,-7,30,11), metal)
			draw_rect(Rect2(10,-5,22,5), dark)
			draw_rect(Rect2(-7,4,7,14), Color("747f79"))
			draw_rect(Rect2(4,-11,13,3), dark)
			draw_line(Vector2(-3,-3),Vector2(13,-3),Color("d9ded0"),2)
		"pistol":
			draw_colored_polygon(PackedVector2Array([Vector2(-20,-12),Vector2(23,-12),Vector2(23,-2),Vector2(-1,-2),Vector2(-7,21),Vector2(-19,21),Vector2(-14,-2),Vector2(-20,-2)]), metal)
			draw_rect(Rect2(-12,0,8,16),Color("625b4e"))
			draw_rect(Rect2(-20,-14,42,4), dark)
		"ammo":
			for j in range(4):
				var x := -21 + j * 12
				draw_rect(Rect2(x,-10,8,30), Color("b8944e"))
				draw_colored_polygon(PackedVector2Array([Vector2(x,-10),Vector2(x+4,-21),Vector2(x+8,-10)]), Color("e3c081"))
				draw_line(Vector2(x+2,-8),Vector2(x+2,16),Color("e8ce91"),2)
		"medkit":
			draw_style_box(_box(Color("bd665a"),Color("df9c7c"),2),Rect2(-23,-19,46,39))
			draw_rect(Rect2(-7,-12,14,26),Color("f2eed7"))
			draw_rect(Rect2(-14,-5,28,12),Color("f2eed7"))
			draw_arc(Vector2(0,-20),9,PI,TAU,12,Color("a54942"),4)
		"bandage":
			draw_style_box(_box(Color("dbd9c1"),Color("ede8d3"),2),Rect2(-19,-21,38,42))
			draw_rect(Rect2(-19,-8,38,16),Color("b4b69d"))
			draw_rect(Rect2(-4,-7,8,14),Color("e4e4cc"))
			draw_rect(Rect2(-7,-3,14,6),Color("e4e4cc"))
		"water":
			draw_style_box(_box(Color("7db9cf"),Color("a7d0d9"),2),Rect2(-13,-18,26,43))
			draw_rect(Rect2(-8,-25,16,9),Color("c5dfdb"))
			draw_rect(Rect2(-13,-6,26,14),Color("d8e7de"))
			draw_line(Vector2(-7,12),Vector2(-7,20),Color("c4e0e4"),3)
		"canned_food":
			draw_rect(Rect2(-19,-20,38,40), Color("c2a76e"))
			draw_rect(Rect2(-19,-9,38,20), Color("a3a85d"))
			draw_style_box(_box(Color("c9cdba"),Color("e4dfca"),2),Rect2(-19,-24,38,9))
			draw_ellipse(Vector2(0,-20),Vector2(8,2),dark)
			draw_circle(Vector2(0,0),8,Color("e5bf6b"))
			draw_rect(Rect2(-19,19,38,5),metal)
		"scrap":
			for j in range(3):
				draw_set_transform(center + Vector2(j * 6 - 6,j * 5 - 5)*s, -0.35+j*0.35,Vector2.ONE*s)
				draw_rect(Rect2(-18,-13,36,26),Color("8e9690").darkened(j*0.1))
				draw_line(Vector2(-13,-9),Vector2(13,-9),Color("c0c3af"),2)
		"helmet":
			draw_arc(Vector2(0,8),24,PI,TAU,22,Color("a1ad88"),18)
			draw_rect(Rect2(-26,4,52,10),Color("738268"))
			draw_line(Vector2(-15,-12),Vector2(-7,-17),Color("d0d5ad"),4)
		"armor":
			draw_colored_polygon(PackedVector2Array([Vector2(-22,-23),Vector2(-9,-23),Vector2(-6,-13),Vector2(6,-13),Vector2(9,-23),Vector2(22,-23),Vector2(25,24),Vector2(-25,24)]), Color("859781"))
			draw_rect(Rect2(-16,-4,32,23), Color("637968"))
			draw_line(Vector2(-13,4),Vector2(13,4),Color("a3b39a"),3)
			draw_line(Vector2(0,-8),Vector2(0,20),dark,2)
		"backpack":
			draw_style_box(_box(Color("a89466"),Color("d0bd83"),2),Rect2(-22,-23,44,47))
			draw_style_box(_box(Color("8c815a"),Color("b9a774"),2),Rect2(-16,0,32,19))
			draw_rect(Rect2(-24,-6,6,24),Color("726e51"))
			draw_rect(Rect2(18,-6,6,24),Color("726e51"))
			draw_arc(Vector2(0,-23),9,PI,TAU,10,Color("897649"),4)
		"juice","energy_bar","biscuits":
			draw_style_box(_box(tint,tint.lightened(.3),2),Rect2(-16,-23,32,46))
			draw_rect(Rect2(-16,-5,32,12),Color("eee1b8"))
		"medical_box":
			draw_style_box(_box(tint,tint.lightened(.3),2),Rect2(-25,-18,50,36))
			draw_rect(Rect2(-4,-12,8,24),Color.WHITE);draw_rect(Rect2(-12,-4,24,8),Color.WHITE)
		"glowstick":
			draw_line(Vector2(-14,22),Vector2(14,-22),tint,10);draw_circle(Vector2(14,-22),6,tint.lightened(.3))
		"lockpick":
			draw_line(Vector2(-21,18),Vector2(12,-17),metal,5);draw_line(Vector2(12,-17),Vector2(21,-17),metal,5)
		"smoke_grenade","battery":
			draw_style_box(_box(tint,metal,2),Rect2(-15,-19,30,40));draw_rect(Rect2(-8,-25,16,7),metal)
		"beacon","circuit_board","encrypted_core":
			draw_style_box(_box(tint,metal,2),Rect2(-21,-19,42,38));draw_rect(Rect2(-9,-9,18,18),dark)
			for i in range(4):draw_line(Vector2(-18,-14+i*9),Vector2(-9,-14+i*9),metal,2)
		"pocket_watch","tape","optical_parts":
			draw_circle(Vector2.ZERO,23,tint);draw_circle(Vector2.ZERO,13,dark);draw_line(Vector2.ZERO,Vector2(8,-9),metal,3)
		"gold_statue":
			draw_circle(Vector2(0,-15),10,tint);draw_colored_polygon(PackedVector2Array([Vector2(0,-8),Vector2(-15,15),Vector2(15,15)]),tint);draw_rect(Rect2(-22,16,44,8),tint)
		_:
			draw_style_box(_box(tint,tint.lightened(0.2),2),Rect2(-20,-18,40,36))
	draw_set_transform(Vector2.ZERO)

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * i / 20.0
		points.append(center + Vector2(cos(angle)*radius.x,sin(angle)*radius.y))
	draw_colored_polygon(points,color)
