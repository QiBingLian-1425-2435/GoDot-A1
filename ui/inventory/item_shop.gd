extends RefCounted
const Items=preload("res://features/inventory/item_catalog.gd")
const Trade=preload("res://features/inventory/item_trade.gd")
static func open_craft(ctx,mode:String) -> void:
	ctx._dialog_panel("工作台制作" if mode=="craft" else "基地商人",Vector2(1000,710))
	ctx._shop_mode=mode;ctx._shop_kind=""
	var list:=ItemList.new();list.name="ShopItems";list.position=Vector2(30,100);list.size=Vector2(440,475);list.add_theme_font_size_override("font_size",20)
	ctx._dialog.add_child(list)
	for kind in Trade.RECIPES if mode=="craft" else Items.DEFS:
		if mode!="craft" and not Trade.available(kind):continue
		var info:=Items.definition(kind);var index:=list.add_item("[%s] %s"%[info.rarity_name,info.name])
		list.set_item_custom_fg_color(index,info.rarity_color);list.set_item_metadata(index,kind)
	ctx._shop_details=ctx._label(ctx._dialog,"选择物品",Rect2(500,100,465,350),19,ctx.INK);ctx._shop_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	list.item_selected.connect(func(index:int):ctx._shop_kind=str(list.get_item_metadata(index));refresh(ctx))
	ctx._button(ctx._dialog,"制作1件" if mode=="craft" else "购买1件",Rect2(510,458,420,50),func():
		if ctx._shop_kind.is_empty():return
		ctx.action_requested.emit("craft_item" if mode=="craft" else "buy",{"kind":ctx._shop_kind,"count":1}),ctx.GREEN,21)
	if mode!="craft":
		ctx._button(ctx._dialog,"购买一组",Rect2(510,520,420,46),func():
			if ctx._shop_kind.is_empty():return
			ctx.action_requested.emit("buy",{"kind":ctx._shop_kind,"count":int(Items.definition(ctx._shop_kind).stack)}),ctx.TEAL,19)
	ctx._label(ctx._dialog,"回收：将物品放在背包中，靠近商人后右键 → 出售整组。训练弹不可卖。" if mode!="craft" else "配方只消耗随身背包材料；材料不足或没有空间时不扣除材料。",Rect2(30,588,935,38),16,ctx.MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._button(ctx._dialog,"关闭",Rect2(350,643,300,45),ctx._close_dialog,ctx.TEAL,20)
	if list.item_count>0:list.select(0);ctx._shop_kind=str(list.get_item_metadata(0));refresh(ctx)
static func refresh_craft(ctx) -> void:
	if not is_instance_valid(ctx._shop_details) or ctx._shop_kind.is_empty():return
	var kind:String=ctx._shop_kind;var info:=Items.definition(kind);var p:Dictionary=ctx._player()
	var text:="%s · %s\n%s\n%s\n\n资金：%d"%[info.name,info.rarity_name,info.type_name,info.description,int(p.get("credits",0))]
	if ctx._shop_mode=="craft":
		text+="\n\n所需材料（持有 / 需要）："
		for material in Trade.RECIPES.get(kind,{}):
			var held:=0
			for item in p.get("bag",[]):
				if item.get("kind")==material:held+=int(item.count)
			text+="\n%s  %d / %d"%[Items.definition(material).name,held,int(Trade.RECIPES[kind][material])]
	else:text+="\n\n购入单价：%d\n一组 %d 件：%d\n回收单价：%s"%[info.buy_price,info.stack,int(info.buy_price)*int(info.stack),str(info.value) if info.sellable else "不可出售"]
	ctx._shop_details.text=text

# Shop controls only preview confirmed inventory and submit intents.
static func open(ctx,mode:String) -> void:
	if mode=="craft":open_craft(ctx,mode);return
	ctx._dialog_panel("基地商人",Vector2(1000,710))
	ctx._shop_mode="buy";ctx._shop_kind=""
	ctx._dialog.set_meta("revision",int(ctx._state.get("world_revision",0)))
	ctx._dialog.set_meta("selection",{})
	ctx._dialog.set_meta("rows",[])
	var tabs:=OptionButton.new();tabs.name="ShopMode";tabs.position=Vector2(30,88);tabs.size=Vector2(200,44)
	tabs.add_item("购买");tabs.add_item("出售材料");ctx._dialog.add_child(tabs)
	var filter:=OptionButton.new();filter.name="ShopFilter";filter.position=Vector2(250,88);filter.size=Vector2(220,44)
	filter.add_item("全部");filter.add_item("制作材料");ctx._dialog.add_child(filter)
	var list:=ItemList.new();list.name="ShopItems";list.position=Vector2(30,145);list.size=Vector2(440,430);list.add_theme_font_size_override("font_size",20);ctx._dialog.add_child(list)
	ctx._shop_details=ctx._label(ctx._dialog,"选择物品",Rect2(500,145,465,295),19,ctx.INK);ctx._shop_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	ctx._label(ctx._dialog,"数量",Rect2(500,450,65,40),19,ctx.INK)
	var quantity:=SpinBox.new();quantity.name="ShopQuantity";quantity.position=Vector2(565,450);quantity.size=Vector2(140,44);quantity.min_value=1;quantity.max_value=1;quantity.step=1;quantity.value=1;ctx._dialog.add_child(quantity)
	ctx._button(ctx._dialog,"1",Rect2(720,450,75,44),func():quantity.value=1,ctx.TEAL,19)
	ctx._button(ctx._dialog,"最大",Rect2(810,450,120,44),func():quantity.value=maxi(1,int(ctx._dialog.get_meta("maximum",0))),ctx.TEAL,19)
	var confirm=ctx._button(ctx._dialog,"购买1件",Rect2(510,515,420,50),func():submit(ctx),ctx.GREEN,21);confirm.name="ShopConfirm"
	ctx._label(ctx._dialog,"仅交易随身背包；购买单笔最多一组，出售只扣选中的物品组。",Rect2(30,590,935,38),16,ctx.MUTED)
	ctx._button(ctx._dialog,"关闭",Rect2(350,643,300,45),ctx._close_dialog,ctx.TEAL,20)
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
		list.clear()
		for row in rows:
			var info:=Items.definition(row.kind)
			var index:=list.add_item("[%s] %s%s"%[info.rarity_name,info.name," ×%d（格%d）"%[row.count,row.index+1] if ctx._shop_mode=="sell" else ""])
			list.set_item_custom_fg_color(index,info.rarity_color);list.set_item_metadata(index,row)
		ctx._dialog.set_meta("rows",rows)
		if selected>=0:list.select(selected)
	if selected<0:clear_selection(ctx)
	else:ctx._dialog.set_meta("selection",rows[selected])
	var quantity:SpinBox=ctx._dialog.get_node("ShopQuantity")
	var confirm:Button=ctx._dialog.get_node("ShopConfirm")
	confirm.disabled=true
	if selected<0:
		ctx._dialog.set_meta("maximum",0);quantity.editable=false
		ctx._shop_details.text="选择材料出售" if ctx._shop_mode=="sell" else "选择购买的物品"
		return
	selection=rows[selected]
	var info:=Items.definition(selection.kind)
	var cash:int=p.get("credits",0)
	var held:=0
	for item in bag:
		if item.get("kind")==selection.kind:held+=int(item.count)
	var price:int=info.value if ctx._shop_mode=="sell" else info.buy_price
	var maximum:int=selection.count if ctx._shop_mode=="sell" else mini(capacity(bag,selection.kind),int(cash/price))
	ctx._dialog.set_meta("maximum",maximum)
	quantity.max_value=maxi(1,maximum);quantity.editable=maximum>0
	var count:=int(quantity.value)
	var total:=price*count
	var after:int=cash+total if ctx._shop_mode=="sell" else cash-total
	var reason:=""
	if ctx._shop_mode=="buy" and maximum==0:reason="资金不足" if cash<price else "背包空间不足"
	if ctx._shop_mode=="sell" and after>999999:reason="资金已达上限"
	confirm.disabled=maximum==0 or not reason.is_empty()
	confirm.text=("出售%d件" if ctx._shop_mode=="sell" else "购买%d件")%count
	ctx._shop_details.text="%s · %s\n%s\n%s\n\n背包持有：%d\n单件重量：%.2f kg\n%s单价：%d\n交易总额：%d\n当前余额：%d → 交易后：%d\n%s"%[info.name,info.rarity_name,info.type_name,info.description,held,info.weight,"出售" if ctx._shop_mode=="sell" else "购买",price,total,cash,after,reason]
