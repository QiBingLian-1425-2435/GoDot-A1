extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
const InventoryRules = preload("res://features/inventory/base_inventory_rules.gd")
## Migrated reference behavior; called only through the owning composition/model.

static func _build_inventory(ctx) -> void:
	ctx._inventory = ctx._full_control(ctx._root, Control.MOUSE_FILTER_STOP)
	ctx._shade(ctx._inventory,Color(0.025,0.045,0.05,0.78))
	ctx._label(ctx._inventory,"⟦inventory_panel.001⟧",Rect2(64,35,600,57),36,ctx.INK)
	ctx._label(ctx._inventory,"⟦inventory_panel.002⟧",Rect2(67,94,700,25),17,ctx.MUTED)
	ctx._button(ctx._inventory,"⟦inventory_panel.003⟧",Rect2(1346,49,190,48),ctx.close_inventory,Color("526b70"),18)
	var equip = ctx._panel(ctx._inventory,Rect2(60,142,370,572),ctx.PANEL,Color("657672"),12)
	ctx._label(equip,"⟦inventory_panel.004⟧",Rect2(20,17,175,35),25,ctx.INK)
	ctx._player_name = ctx._label(equip,"⟦base_hud.025⟧",Rect2(177,22,170,27),17,ctx.MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	ctx._portrait = ctx.Portrait.new()
	ctx._portrait.position = Vector2(75,71)
	ctx._portrait.size = Vector2(220,320)
	equip.add_child(ctx._portrait)
	var equipment_layout = {"helmet":Rect2(20,80,82,82),"armor":Rect2(20,190,82,82),"backpack":Rect2(269,190,82,82),"weapon":Rect2(269,80,82,82)}
	var equip_names = {"helmet":"⟦inventory_panel.005⟧","armor":"⟦inventory_panel.006⟧","backpack":"⟦inventory_panel.007⟧","weapon":"⟦inventory_panel.008⟧"}
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
	var names = {"hp":"⟦base_hud.027⟧","stamina":"⟦base_hud.028⟧","hunger":"⟦base_hud.029⟧","thirst":"⟦base_hud.030⟧"}
	var i = 0
	for key in names:
		var x = 21 + (i % 2) * 172
		var y = 424 + (i / 2) * 48
		ctx._label(equip,names[key],Rect2(x,y,70,28),17,ctx.MUTED)
		ctx._inventory_stats[key] = ctx._label(equip,"100",Rect2(x+76,y,76,28),16,ctx.INK,HORIZONTAL_ALIGNMENT_RIGHT)
		i += 1
	var bag = ctx._panel(ctx._inventory,Rect2(452,142,540,572),ctx.PANEL,Color("657672"),12)
	ctx._label(bag,"⟦inventory_panel.007⟧",Rect2(20,17,200,35),25,ctx.INK)
	ctx._inventory_weight = ctx._label(bag,"⟦format.inventory_panel.001⟧",Rect2(268,22,251,27),17,ctx.GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	for index in range(24):
		var slot = ctx._make_slot(bag,"bag",index,Vector2(22+(index%6)*83,78+(index/6)*83),Vector2(76,76))
		ctx._bag_slots.append(slot)
	var filter:=OptionButton.new();filter.name="ItemTypeFilter";filter.position=Vector2(22,420);filter.size=Vector2(240,34)
	Texts.add_item(filter, "⟦inventory_panel.009⟧");filter.set_item_metadata(0,"all")
	for key in ctx.Items.TYPES:
		Texts.add_item(filter, ctx.Items.TYPES[key]);filter.set_item_metadata(filter.item_count-1,key)
	filter.item_selected.connect(func(index:int):ctx._inventory_filter=str(filter.get_item_metadata(index));ctx._update_inventory())
	bag.add_child(filter)
	var order:=OptionButton.new();order.name="ItemSortMode";order.position=Vector2(278,420);order.size=Vector2(240,34)
	for pair in [["⟦inventory_panel.010⟧","type"],["⟦inventory_panel.011⟧","rarity"],["⟦inventory_panel.012⟧","value"],["⟦inventory_panel.013⟧","density"]]:
		Texts.add_item(order, pair[0]);order.set_item_metadata(order.item_count-1,pair[1])
	order.item_selected.connect(func(index:int):ctx._sort_mode=str(order.get_item_metadata(index)))
	bag.add_child(order)
	ctx._button(bag,"⟦inventory_panel.014⟧",Rect2(22,468,152,44),func() -> void: ctx.action_requested.emit("sort",{"container":"bag","mode":ctx._sort_mode}),Color("496c6e"),17)
	ctx._credits_label = ctx._label(bag,"⟦inventory_panel.015⟧",Rect2(200,472,317,35),22,ctx.GOLD,HORIZONTAL_ALIGNMENT_RIGHT)
	ctx._label(bag,"⟦inventory_panel.016⟧",Rect2(22,529,500,25),14,Color("819891"))
	var stash = ctx._panel(ctx._inventory,Rect2(1014,142,526,572),ctx.PANEL,Color("657672"),12)
	ctx._label(stash,"⟦inventory_panel.017⟧",Rect2(20,17,280,35),25,ctx.INK)
	ctx._button(stash,"⟦inventory_panel.018⟧",Rect2(400,17,105,39),func() -> void: ctx.action_requested.emit("sort",{"container":"stash","mode":ctx._sort_mode}),Color("496c6e"),16)
	for index in range(48):
		var slot = ctx._make_slot(stash,"stash",index,Vector2(22+(index%8)*61,78+(index/8)*61),Vector2(55,55))
		ctx._stash_slots.append(slot)
	ctx._stash_note = ctx._label(stash,"⟦base_hud.002⟧",Rect2(22,468,484,30),15,ctx.MUTED)
	ctx._label(stash,"⟦inventory_panel.019⟧",Rect2(22,529,484,25),14,Color("819891"))
	var details = ctx._panel(ctx._inventory,Rect2(60,737,1480,100),Color(0.1,0.15,0.17,0.94),Color("4c615d"),10)
	ctx._details_name = ctx._label(details,"⟦inventory_panel.020⟧",Rect2(20,12,860,31),21,ctx.GOLD)
	ctx._details_text = ctx._label(details,"⟦inventory_panel.021⟧",Rect2(20,50,1435,40),15,ctx.MUTED)
	ctx._details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._inventory,"⟦inventory_panel.022⟧",Rect2(60,850,1200,28),15,Color("8da59d"))

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
				Texts.add_item(ctx._popup, "⟦inventory_panel.004⟧", 1)
			elif ctx.Items.definition(kind).usable:
				Texts.add_item(ctx._popup, "⟦inventory_panel.023⟧", 0)
			Texts.add_item(ctx._popup, "⟦inventory_panel.024⟧", 2)
			ctx._popup.set_item_disabled(ctx._popup.get_item_index(2),not ctx._stash_access)
			ctx._popup.add_separator()
			Texts.add_item(ctx._popup, "⟦inventory_panel.025⟧", 3)
			if ctx.Items.definition(kind).sellable:
				Texts.add_item(ctx._popup, Texts.format("⟦inventory_panel.026⟧", (int(ctx.Items.definition(kind).value)*int(payload.item.count))), 6)
		elif container == "stash":
			Texts.add_item(ctx._popup, "⟦inventory_panel.027⟧", 2)
		else:
			Texts.add_item(ctx._popup, "⟦inventory_panel.028⟧", 4)
		if container in ["bag","stash"] and int(payload.get("item",{}).get("count",1))>1:
			ctx._popup.add_separator()
			Texts.add_item(ctx._popup, "⟦inventory_panel.029⟧", 5)
		var transform = ctx._root.get_viewport_transform()
		ctx._popup.position = Vector2i(transform * Vector2(payload.position))
		ctx._popup.popup()
	elif action == "quick_transfer":
		ctx._quick_transfer(payload)
	else:
		if action == "transfer" and (payload.get("from","") == "stash" or payload.get("to","") == "stash") and not ctx._stash_access:
			ctx.toast("⟦inventory_panel.030⟧")
			return
		ctx.action_requested.emit(action,payload)

static func _quick_transfer(ctx, payload: Dictionary) -> void:
	var source = str(payload.get("from","bag"))
	if source == "equipment":
		ctx.action_requested.emit("unequip",{"slot":payload.index})
		return
	if not ctx._stash_access:
		ctx.toast("⟦inventory_panel.030⟧")
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
		6: ctx.action_requested.emit("sell",{"index":index,"uid":ctx._context_data.get("item",{}).get("uid",""),"count":int(ctx._context_data.get("item",{}).get("count",0))})
		5: ctx.action_requested.emit("split",{"container":str(ctx._context_data.get("from","bag")),"index":index})

static func _inspect(ctx, item: Dictionary) -> void:
	if item.is_empty():
		return
	var info = ctx._definition(item)
	Texts.bind(ctx._details_name, Texts.format("⟦format.inventory_panel.002⟧", [info.get("name",item.get("kind","")),info.rarity_name,info.type_name]), "text")
	ctx._details_name.modulate=info.rarity_color
	Texts.bind(ctx._details_text, Texts.format("⟦inventory_panel.031⟧", [info.description,float(info.weight),int(item.get("count",1)),int(info.value),int(info.value)*int(item.get("count",1)),float(info.value)/maxf(.001,float(info.weight))]), "text")

static func _update_inventory(ctx) -> void:
	var p = ctx._player()
	if p.is_empty():
		return
	Texts.bind(ctx._player_name, str(p.get("name","⟦base_hud.025⟧")), "text")
	var bag: Array = p.get("bag",[])
	var stash: Array = p.get("stash",[])
	var equipment: Dictionary = p.get("equipment",{})
	_update_slots(ctx,ctx._bag_slots,bag)
	_update_slots(ctx,ctx._stash_slots,stash)
	for key in ctx._equip_slots:
		var item: Dictionary = equipment.get(key,{})
		ctx._equip_slots[key].set_item(item,ctx._definition(item))
	ctx._portrait.equipment = equipment
	ctx._portrait.queue_redraw()
	for key in ctx._inventory_stats:
		Texts.bind(ctx._inventory_stats[key], Texts.format("⟦format.inventory_panel.003⟧", int(p.get(key,100))), "text")
	Texts.bind(ctx._inventory_weight, Texts.format("⟦format.inventory_panel.004⟧", [float(p.get("weight",ctx.Items.weight(bag))),float(p.get("max_weight",28.0))]), "text")
	var base_capacity: float = InventoryRules.base_capacity(p)
	var reduced: bool = float(p.get("max_weight",base_capacity)) < base_capacity - .05
	if reduced: Texts.bind(ctx._inventory_weight, Texts.format("⟦satiety.weight⟧", [float(p.get("weight",0)),float(p.max_weight)]), "text")
	Texts.bind(ctx._inventory_weight, Texts.format("⟦satiety.tip⟧", base_capacity), "tooltip_text")
	Texts.bind(ctx._inventory_stats.hunger, Texts.format("⟦satiety.tip⟧", base_capacity), "tooltip_text")
	ctx._inventory_weight.modulate = Color("ef9c7c") if float(p.get("weight",0.0)) > float(p.get("max_weight",28.0)) else Color.WHITE
	Texts.bind(ctx._credits_label, Texts.format("⟦inventory_panel.032⟧", str(p.get("credits",500))), "text")

static func _update_slots(ctx,slots:Array,items:Array) -> void:
	var indices:Array=[]
	if ctx._inventory_filter=="all":
		for i in range(items.size()):indices.append(i)
	else:
		for i in range(items.size()):
			if not items[i].is_empty() and ctx.Items.definition(items[i].kind).item_type==ctx._inventory_filter:indices.append(i)
		for i in range(items.size()):
			if items[i].is_empty():indices.append(i)
	for i in range(slots.size()):
		var valid:bool=i<indices.size()
		var index:int=int(indices[i]) if valid else -1
		var item:Dictionary=items[index] if valid else {}
		slots[i].slot_index=index;slots[i].locked=not valid
		slots[i].set_item(item,ctx._definition(item))
