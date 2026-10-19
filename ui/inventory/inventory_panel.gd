extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _build_inventory(ctx) -> void:
	ctx._inventory = ctx._full_control(ctx._root, Control.MOUSE_FILTER_STOP)
	ctx._shade(ctx._inventory,Color(0.025,0.045,0.05,0.78))
	ctx._label(ctx._inventory,"鸭鸭的行囊",Rect2(64,35,600,57),36,ctx.INK)
	ctx._label(ctx._inventory,"装备  /  随身背包  /  基地仓库",Rect2(67,94,700,25),17,ctx.MUTED)
	ctx._button(ctx._inventory,"关闭  [Tab]",Rect2(1346,49,190,48),ctx.close_inventory,Color("526b70"),18)
	var equip = ctx._panel(ctx._inventory,Rect2(60,142,370,572),ctx.PANEL,Color("657672"),12)
	ctx._label(equip,"装备",Rect2(20,17,175,35),25,ctx.INK)
	ctx._player_name = ctx._label(equip,"鸭鸭",Rect2(177,22,170,27),17,ctx.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	ctx._portrait = ctx.Portrait.new()
	ctx._portrait.position = Vector2(75,71)
	ctx._portrait.size = Vector2(220,320)
	equip.add_child(ctx._portrait)
	var equipment_layout = {"helmet":Rect2(20,80,82,82),"armor":Rect2(20,190,82,82),"backpack":Rect2(269,190,82,82),"weapon":Rect2(269,80,82,82)}
	var equip_names = {"helmet":"头部","armor":"护甲","backpack":"背包","weapon":"武器"}
	for key in equipment_layout:
		var slot: Control = ctx.Slot.new()
		slot.position = equipment_layout[key].position
		slot.size = equipment_layout[key].size
		slot.container_name = "equipment"
		slot.slot_index = key
		slot.slot_label = equip_names[key]
		slot.action_requested.connect(ctx._slot_action)
		slot.inspected.connect(ctx._inspect)
		equip.add_child(slot)
		ctx._equip_slots[key] = slot
		ctx._label(equip,equip_names[key],Rect2(slot.position.x,slot.position.y+87,82,23),15,ctx.MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	ctx._line(equip,Vector2(20,404),Vector2(330,1))
	var names = {"hp":"生命","stamina":"耐力","hunger":"能量","thirst":"水分"}
	var i = 0
	for key in names:
		var x = 21 + (i % 2) * 172
		var y = 424 + (i / 2) * 48
		ctx._label(equip,names[key],Rect2(x,y,60,28),17,ctx.MUTED)
		ctx._inventory_stats[key] = ctx._label(equip,"100",Rect2(x+62,y,82,28),19,ctx.INK,HORIZONTAL_ALIGNMENT_RIGHT)
		i += 1
	var bag = ctx._panel(ctx._inventory,Rect2(452,142,540,572),ctx.PANEL,Color("657672"),12)
	ctx._label(bag,"背包",Rect2(20,17,200,35),25,ctx.INK)
	ctx._inventory_weight = ctx._label(bag,"0.0 / 28.0 kg",Rect2(268,22,251,27),17,ctx.GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	for index in range(24):
		var slot = ctx._make_slot(bag,"bag",index,Vector2(22+(index%6)*83,78+(index/6)*83),Vector2(76,76))
		ctx._bag_slots.append(slot)
	ctx._label(bag,"随身物品会带入行动。1 / 2 换枪，4 医疗，5 饮水。",Rect2(22,421,496,26),15,ctx.MUTED)
	ctx._button(bag,"整理背包",Rect2(22,468,152,44),func() -> void: ctx.action_requested.emit("sort",{"container":"bag"}),Color("496c6e"),17)
	ctx._credits_label = ctx._label(bag,"资金  500",Rect2(200,472,317,35),22,ctx.GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	ctx._label(bag,"拖动换位    Ctrl 点击快速存取    双击使用 / 装备",Rect2(22,529,500,25),14,Color("819891"))
	var stash = ctx._panel(ctx._inventory,Rect2(1014,142,526,572),ctx.PANEL,Color("657672"),12)
	ctx._label(stash,"基地仓库",Rect2(20,17,280,35),25,ctx.INK)
	ctx._button(stash,"整理",Rect2(400,17,105,39),func() -> void: ctx.action_requested.emit("sort",{"container":"stash"}),Color("496c6e"),16)
	for index in range(48):
		var slot = ctx._make_slot(stash,"stash",index,Vector2(22+(index%8)*61,78+(index/8)*61),Vector2(55,55))
		ctx._stash_slots.append(slot)
	ctx._stash_note = ctx._label(stash,"安全区仓库 · 拖动存取物品",Rect2(22,468,484,30),15,ctx.MUTED)
	ctx._label(stash,"仓库容量 48 格",Rect2(22,529,484,25),14,Color("819891"))
	var details = ctx._panel(ctx._inventory,Rect2(60,737,932,100),Color(0.1,0.15,0.17,0.94),Color("4c615d"),10)
	ctx._details_name = ctx._label(details,"准备好再出发",Rect2(20,12,860,31),21,ctx.GOLD)
	ctx._details_text = ctx._label(details,"将鼠标移至物品查看详情。右键可使用、装备或丢弃。",Rect2(20,50,888,35),15,ctx.MUTED)
	ctx._details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._inventory,"基地是安全的。仓库与装备自动保存到当前存档。",Rect2(60,850,1200,28),15,Color("8da59d"))

static func _make_slot(ctx, parent: Control, container: String, index: int, pos: Vector2, slot_size: Vector2) -> Control:
	var slot: Control = ctx.Slot.new()
	slot.position = pos
	slot.size = slot_size
	slot.container_name = container
	slot.slot_index = index
	slot.action_requested.connect(ctx._slot_action)
	slot.inspected.connect(ctx._inspect)
	parent.add_child(slot)
	return slot

static func _build_popup(ctx) -> void:
	ctx._popup = PopupMenu.new()
	ctx._popup.add_theme_font_override("font",ctx._font)
	ctx._popup.add_theme_font_size_override("font_size",18)
	ctx._popup.add_theme_stylebox_override("panel",ctx._style(Color("24393d"),Color("6c8982"),8,1))
	ctx._popup.id_pressed.connect(ctx._context_selected)
	ctx._root.add_child(ctx._popup)

static func _slot_action(ctx, action: String, payload: Dictionary) -> void:
	if action == "context":
		ctx._context_data = payload
		ctx._popup.clear()
		var container = str(payload.get("from","bag"))
		var kind = str(payload.get("item",{}).get("kind",""))
		if container == "bag":
			if kind in ["rifle","pistol","helmet","armor","backpack"]:
				ctx._popup.add_item("装备",1)
			elif kind in ["medkit","bandage","water","canned_food"]:
				ctx._popup.add_item("使用",0)
			ctx._popup.add_item("移入仓库",2)
			ctx._popup.set_item_disabled(ctx._popup.get_item_index(2),not ctx._stash_access)
			ctx._popup.add_separator()
			ctx._popup.add_item("丢弃",3)
		elif container == "stash":
			ctx._popup.add_item("放入背包",2)
		else:
			ctx._popup.add_item("卸下装备",4)
		if container in ["bag","stash"] and int(payload.get("item",{}).get("count",1))>1:
			ctx._popup.add_separator()
			ctx._popup.add_item("拆分一半",5)
		var transform = ctx._root.get_viewport_transform()
		ctx._popup.position = Vector2i(transform * Vector2(payload.position))
		ctx._popup.popup()
	elif action == "quick_transfer":
		ctx._quick_transfer(payload)
	else:
		if action == "transfer" and (payload.get("from","") == "stash" or payload.get("to","") == "stash") and not ctx._stash_access:
			ctx.toast("请先靠近基地仓库")
			return
		ctx.action_requested.emit(action,payload)

static func _quick_transfer(ctx, payload: Dictionary) -> void:
	var source = str(payload.get("from","bag"))
	if source == "equipment":
		ctx.action_requested.emit("unequip",{"slot":payload.index})
		return
	if not ctx._stash_access:
		ctx.toast("请先靠近基地仓库")
		return
	var destination = "stash" if source == "bag" else "bag"
	ctx.action_requested.emit("transfer",{"from":source,"index":payload.index,"to":destination})

static func _context_selected(ctx, id: int) -> void:
	var index: Variant = ctx._context_data.get("index",0)
	match id:
		0: ctx.action_requested.emit("use",{"index":index})
		1: ctx.action_requested.emit("equip",{"index":index})
		2: ctx._quick_transfer(ctx._context_data)
		3: ctx.action_requested.emit("drop",{"index":index})
		4: ctx.action_requested.emit("unequip",{"slot":index})
		5: ctx.action_requested.emit("split",{"container":str(ctx._context_data.get("from","bag")),"index":index})

static func _inspect(ctx, item: Dictionary) -> void:
	if item.is_empty():
		return
	var info = ctx._definition(item)
	ctx._details_name.text = str(info.get("name",item.get("kind","")))
	ctx._details_text.text = "%s     %.2f kg × %d" % [info.get("description",""),float(info.get("weight",0.0)),int(item.get("count",1))]

static func _update_inventory(ctx) -> void:
	var p = ctx._player()
	if p.is_empty():
		return
	ctx._player_name.text = str(p.get("name","鸭鸭"))
	var bag: Array = p.get("bag",[])
	var stash: Array = p.get("stash",[])
	var equipment: Dictionary = p.get("equipment",{})
	for i in range(ctx._bag_slots.size()):
		var item: Dictionary = bag[i] if i < bag.size() else {}
		ctx._bag_slots[i].set_item(item,ctx._definition(item))
	for i in range(ctx._stash_slots.size()):
		var item: Dictionary = stash[i] if i < stash.size() else {}
		ctx._stash_slots[i].set_item(item,ctx._definition(item))
	for key in ctx._equip_slots:
		var item: Dictionary = equipment.get(key,{})
		ctx._equip_slots[key].set_item(item,ctx._definition(item))
	ctx._portrait.equipment = equipment
	ctx._portrait.queue_redraw()
	for key in ctx._inventory_stats:
		ctx._inventory_stats[key].text = "%d / 100" % int(p.get(key,100))
	ctx._inventory_weight.text = "%.1f / %.1f kg" % [float(p.get("weight",ctx.Items.weight(bag))),float(p.get("max_weight",28.0))]
	ctx._inventory_weight.modulate = Color("ef9c7c") if float(p.get("weight",0.0)) > float(p.get("max_weight",28.0)) else Color.WHITE
	ctx._credits_label.text = "资金  %s" % str(p.get("credits",500))
