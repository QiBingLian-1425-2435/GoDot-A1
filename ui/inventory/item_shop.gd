extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
const Items=preload("res://features/inventory/item_catalog.gd")
const Trade=preload("res://features/inventory/item_trade.gd")
static func open_craft(ctx,mode:String) -> void:
	ctx._dialog_panel("⟦base_hud.024⟧" if mode=="craft" else "⟦base_hud.023⟧",Vector2(1000,710))
	ctx._shop_mode=mode;ctx._shop_kind=""
	var list:=ItemList.new();list.name="ShopItems";list.position=Vector2(30,100);list.size=Vector2(440,475);list.add_theme_font_size_override("font_size",20)
	ctx._dialog.add_child(list)
	for kind in Trade.RECIPES if mode=="craft" else Items.DEFS:
		if mode!="craft" and not Trade.available(kind):continue
		var info:=Items.definition(kind);var index:=Texts.add_item(list, Texts.format("⟦format.item_shop.001⟧", [info.rarity_name,info.name]))
		list.set_item_custom_fg_color(index,info.rarity_color);list.set_item_metadata(index,kind)
	ctx._shop_details=ctx._label(ctx._dialog,"⟦item_shop.001⟧",Rect2(500,100,465,350),19,ctx.INK);ctx._shop_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	list.item_selected.connect(func(index:int):ctx._shop_kind=str(list.get_item_metadata(index));refresh(ctx))
	ctx._button(ctx._dialog,"⟦item_shop.002⟧" if mode=="craft" else "⟦item_shop.003⟧",Rect2(510,458,420,50),func():
		if ctx._shop_kind.is_empty():return
		ctx.action_requested.emit("craft_item" if mode=="craft" else "buy",{"kind":ctx._shop_kind,"count":1}),ctx.GREEN,21)
	if mode!="craft":
		ctx._button(ctx._dialog,"⟦item_shop.004⟧",Rect2(510,520,420,46),func():
			if ctx._shop_kind.is_empty():return
			ctx.action_requested.emit("buy",{"kind":ctx._shop_kind,"count":int(Items.definition(ctx._shop_kind).stack)}),ctx.TEAL,19)
	ctx._label(ctx._dialog,"⟦item_shop.005⟧" if mode!="craft" else "⟦item_shop.006⟧",Rect2(30,588,935,38),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog,"⟦item_shop.007⟧",Rect2(350,643,300,45),ctx._close_dialog,ctx.TEAL,20)
	if list.item_count>0:list.select(0);ctx._shop_kind=str(list.get_item_metadata(0));refresh(ctx)
static func refresh_craft(ctx) -> void:
	if not is_instance_valid(ctx._shop_details) or ctx._shop_kind.is_empty():return
	var kind:String=ctx._shop_kind;var info:=Items.definition(kind);var p:Dictionary=ctx._player()
	var text:=Texts.format("⟦item_shop.008⟧", [info.name,info.rarity_name,info.type_name,info.description,int(p.get("credits",0))])
	if ctx._shop_mode=="craft":
		text+="⟦item_shop.009⟧"
		for material in Trade.RECIPES.get(kind,{}):
			var held:=0
			for item in p.get("bag",[]):
				if item.get("kind")==material:held+=int(item.count)
			text+=Texts.format("⟦format.item_shop.002⟧", [Items.definition(material).name,held,int(Trade.RECIPES[kind][material])])
	else:text+=Texts.format("⟦item_shop.010⟧", [info.buy_price,info.stack,int(info.buy_price)*int(info.stack),str(info.value) if info.sellable else "⟦item_shop.011⟧"])
	Texts.bind(ctx._shop_details, text, "text")

# Shop controls only preview confirmed inventory and submit intents.
static func open(ctx,mode:String) -> void:
	if mode=="craft":open_craft(ctx,mode);return
	ctx._dialog_panel("⟦base_hud.023⟧",Vector2(1480,710))
	ctx._label(ctx._dialog,"⟦shop.backpack⟧",Rect2(1000,88,450,44),24,ctx.INK)
	var bag_list:=ItemList.new();bag_list.name="ShopBackpack";bag_list.position=Vector2(1000,145);bag_list.size=Vector2(450,430);bag_list.add_theme_font_size_override("font_size",19);ctx._dialog.add_child(bag_list);bag_list.hide();create_grid(ctx,"BackpackGrid",Vector2(1000,145))
	ctx._shop_mode="buy";ctx._shop_kind=""
	ctx._dialog.set_meta("revision",int(ctx._state.get("world_revision",0)))
	ctx._dialog.set_meta("selection",{})
	ctx._dialog.set_meta("rows",[])
	var tabs:=OptionButton.new();tabs.name="ShopMode";tabs.position=Vector2(30,88);tabs.size=Vector2(200,44)
	Texts.add_item(tabs, "⟦item_shop.012⟧");Texts.add_item(tabs, "⟦item_shop.013⟧");ctx._dialog.add_child(tabs)
	var filter:=OptionButton.new();filter.name="ShopFilter";filter.position=Vector2(250,88);filter.size=Vector2(220,44)
	Texts.add_item(filter, "⟦item_shop.014⟧");Texts.add_item(filter, "⟦item_catalog.062⟧");ctx._dialog.add_child(filter)
	var list:=ItemList.new();list.name="ShopItems";list.position=Vector2(30,145);list.size=Vector2(440,430);list.add_theme_font_size_override("font_size",20);ctx._dialog.add_child(list);list.hide();create_grid(ctx,"ProductGrid",Vector2(30,145))
	ctx._shop_details=ctx._label(ctx._dialog,"⟦item_shop.001⟧",Rect2(500,145,465,295),19,ctx.INK);ctx._shop_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"⟦item_shop.015⟧",Rect2(500,450,65,40),19,ctx.INK)
	var quantity:=SpinBox.new();quantity.name="ShopQuantity";quantity.position=Vector2(565,450);quantity.size=Vector2(140,44);quantity.min_value=1;quantity.max_value=1;quantity.step=1;quantity.value=1;ctx._dialog.add_child(quantity)
	ctx._button(ctx._dialog,"1",Rect2(720,450,75,44),func():quantity.value=1,ctx.TEAL,19)
	ctx._button(ctx._dialog,"⟦item_shop.016⟧",Rect2(810,450,120,44),func():quantity.value=maxi(1,int(ctx._dialog.get_meta("maximum",0))),ctx.TEAL,19)
	var confirm=ctx._button(ctx._dialog,"⟦item_shop.003⟧",Rect2(510,515,420,50),func():submit(ctx),ctx.GREEN,21);confirm.name="ShopConfirm"
	var status:Label=ctx._label(ctx._dialog,"⟦item_shop.017⟧",Rect2(30,578,935,58),18,ctx.INK);status.name="ShopStatus";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog,"⟦item_shop.007⟧",Rect2(350,643,300,45),ctx._close_dialog,ctx.TEAL,20)
	tabs.item_selected.connect(func(index:int):
		ctx._shop_mode="buy" if index==0 else "sell";filter.visible=index==0;clear_selection(ctx);refresh(ctx))
	filter.item_selected.connect(func(_index:int):clear_selection(ctx);refresh(ctx))
	list.item_selected.connect(func(index:int):
		ctx._dialog.set_meta("selection",list.get_item_metadata(index).duplicate());ctx._shop_kind=str(list.get_item_metadata(index).kind);quantity.set_value_no_signal(1);refresh(ctx))
	quantity.value_changed.connect(func(_value:float):refresh(ctx))
	refresh(ctx)
	if list.item_count>0:
		list.select(0);list.item_selected.emit(0)

static func clear_selection(ctx) -> void:
	ctx._shop_kind="";ctx._dialog.set_meta("selection",{});ctx._dialog.get_node("ShopItems").deselect_all()

static func capacity(bag:Array,kind:String) -> int:
	var limit:int=Items.definition(kind).stack
	var room:=0
	for item in bag:
		if item.is_empty():room+=limit
		elif item.get("kind")==kind:room+=maxi(0,limit-int(item.count))
	return mini(limit,room)

static func submit(ctx) -> void:
	refresh(ctx)
	if not is_instance_valid(ctx._dialog):return
	var button:Button=ctx._dialog.get_node("ShopConfirm")
	if button.disabled:return
	var selection:Dictionary=ctx._dialog.get_meta("selection",{})
	var quantity:SpinBox=ctx._dialog.get_node("ShopQuantity")
	if quantity.get_line_edit().has_focus():quantity.apply()
	refresh(ctx)
	if button.disabled:return
	var payload:Dictionary={"count":int(quantity.value)}
	if ctx._shop_mode=="sell":payload.merge({"index":selection.index,"uid":selection.uid})
	else:payload.kind=selection.kind
	ctx.action_requested.emit(ctx._shop_mode,payload)

static func refresh(ctx) -> void:
	if ctx._shop_mode=="craft":refresh_craft(ctx);return
	if not is_instance_valid(ctx._dialog) or not ctx._dialog.has_node("ShopItems"):return
	if ctx._state.get("world","bunker")!="bunker" or int(ctx._state.get("world_revision",0))!=int(ctx._dialog.get_meta("revision",-1)):
		ctx._close_dialog();return
	var p:Dictionary=ctx._player()
	var bag:Array=p.get("bag",[])
	var bag_list:ItemList=ctx._dialog.get_node("ShopBackpack")
	if bag!=ctx._dialog.get_meta("bag_preview",[]):
		clear_grid(ctx,"BackpackGrid")
		bag_list.clear()
		for index in range(bag.size()):
			var item:Dictionary=bag[index]
			var line=Texts.format("⟦shop.bag_empty⟧",index+1) if item.is_empty() else Texts.format("⟦shop.bag_item⟧",[index+1,Items.definition(item.kind).name,int(item.count)])
			add_cell(ctx,"BackpackGrid",item,index,Callable())
			var row:=Texts.add_item(bag_list,line)
			if not item.is_empty():bag_list.set_item_custom_fg_color(row,Items.definition(item.kind).rarity_color)
		ctx._dialog.set_meta("bag_preview",bag.duplicate(true))
	var list:ItemList=ctx._dialog.get_node("ShopItems")
	var filter:OptionButton=ctx._dialog.get_node("ShopFilter")
	var rows:Array=[]
	if ctx._shop_mode=="buy":
		for kind in Items.DEFS:
			if Trade.available(kind) and (filter.selected==0 or Items.definition(kind).item_type=="material"):rows.append({"kind":kind})
	else:
		for index in range(bag.size()):
			var item:Dictionary=bag[index]
			if not item.is_empty() and Items.definition(item.kind).item_type=="material":rows.append({"kind":item.kind,"index":index,"uid":item.uid,"count":int(item.count)})
	var selection:Dictionary=ctx._dialog.get_meta("selection",{})
	var selected:=-1
	for i in range(rows.size()):
		if rows[i].kind==selection.get("kind") and (ctx._shop_mode=="buy" or (rows[i].uid==selection.get("uid") and rows[i].index==selection.get("index"))):selected=i
	if rows!=ctx._dialog.get_meta("rows",[]):
		clear_grid(ctx,"ProductGrid")
		list.clear()
		for row in rows:
			var info:=Items.definition(row.kind)
			var index:=Texts.add_item(list, Texts.format("⟦format.item_shop.003⟧", [info.rarity_name,info.name,Texts.format("⟦item_shop.018⟧", [row.count,row.index+1]) if ctx._shop_mode=="sell" else ""]))
			list.set_item_custom_fg_color(index,info.rarity_color);list.set_item_metadata(index,row)
			add_cell(ctx,"ProductGrid",{"kind":row.kind,"count":row.get("count",1)},index,func():list.select(index);list.item_selected.emit(index))
		ctx._dialog.set_meta("rows",rows)
		if selected>=0:list.select(selected)
	for cell in ctx._dialog.get_node("ProductGrid/Grid").get_children():
		cell.get_node("Icon").selected=cell.get_index()==selected;cell.get_node("Icon").queue_redraw()
	if selected<0:clear_selection(ctx)
	else:ctx._dialog.set_meta("selection",rows[selected])
	var quantity:SpinBox=ctx._dialog.get_node("ShopQuantity")
	var confirm:Button=ctx._dialog.get_node("ShopConfirm")
	var status:Label=ctx._dialog.get_node("ShopStatus")
	Texts.bind(status,"⟦item_shop.017⟧","text")
	if selected<0:
		confirm.disabled=true
		ctx._dialog.set_meta("maximum",0);quantity.editable=false
		Texts.bind(ctx._shop_details, "⟦item_shop.019⟧" if ctx._shop_mode=="sell" else "⟦item_shop.020⟧", "text")
		return
	selection=rows[selected]
	var info:=Items.definition(selection.kind)
	var cash:int=p.get("credits",0)
	var free:bool=ctx._state.get("infinite_credits",false)
	var held:=0
	for item in bag:
		if item.get("kind")==selection.kind:held+=int(item.count)
	var price:int=info.value if ctx._shop_mode=="sell" else info.buy_price
	var maximum:int=selection.count if ctx._shop_mode=="sell" else mini(capacity(bag,selection.kind),int(info.stack) if free else int(cash/price))
	ctx._dialog.set_meta("maximum",maximum)
	quantity.max_value=maxi(1,maximum);quantity.editable=maximum>0
	var count:=int(quantity.value)
	var total:=price*count
	var after:int=cash+total if ctx._shop_mode=="sell" else cash if free else cash-total
	var reason:=""
	if ctx._shop_mode=="buy":
		if capacity(bag,selection.kind)==0:reason="⟦facility_system.003⟧"
		if not free and cash<price:
			if not reason.is_empty():reason+=" · "
			reason+="⟦item_shop.021⟧"
	if ctx._shop_mode=="sell" and after>999999:reason="⟦item_trade.005⟧"
	Texts.bind(status,reason if not reason.is_empty() else "⟦item_shop.017⟧","text")
	confirm.disabled=maximum==0 or not reason.is_empty()
	Texts.bind(confirm, Texts.format(("⟦item_shop.022⟧" if ctx._shop_mode=="sell" else "⟦item_shop.023⟧"), count), "text")
	Texts.bind(ctx._shop_details, Texts.format("⟦item_shop.024⟧", [info.name,info.rarity_name,info.type_name,info.description,held,info.weight,"⟦item_shop.025⟧" if ctx._shop_mode=="sell" else "⟦item_shop.012⟧",price,total,cash,after,reason]), "text")

static func create_grid(ctx,name:String,position:Vector2) -> void:
	var scroll:=ScrollContainer.new();scroll.name=name;scroll.position=position;scroll.size=Vector2(440,430);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;ctx._dialog.add_child(scroll)
	var grid:=GridContainer.new();grid.name="Grid";grid.columns=4;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);scroll.add_child(grid)

static func clear_grid(ctx,name:String) -> void:
	for child in ctx._dialog.get_node(name+"/Grid").get_children():
		child.get_parent().remove_child(child);child.queue_free()

static func add_cell(ctx,grid_name:String,item:Dictionary,index:int,callback:Callable) -> void:
	var button:=Button.new();button.custom_minimum_size=Vector2(96,112);button.clip_contents=true
	ctx._dialog.get_node(grid_name+"/Grid").add_child(button)
	var icon=ctx.Slot.new();icon.name="Icon";icon.position=Vector2(6,4);icon.size=Vector2(84,80);button.add_child(icon);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	icon.set_item(item,{} if item.is_empty() else Items.definition(item.kind))
	var caption=Texts.format("⟦shop.bag_empty⟧",index+1) if item.is_empty() else Items.definition(item.kind).name
	ctx._label(button,caption,Rect2(3,85,90,24),13,ctx.INK,HORIZONTAL_ALIGNMENT_CENTER)
	Texts.bind(button,caption,"tooltip_text")
	if callback.is_valid():button.pressed.connect(callback)
	else:button.mouse_default_cursor_shape=Control.CURSOR_ARROW
