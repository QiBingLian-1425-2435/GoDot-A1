extends RefCounted
const Items=preload("res://features/inventory/item_catalog.gd")
const Trade=preload("res://features/inventory/item_trade.gd")
static func open(ctx,mode:String) -> void:
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
static func refresh(ctx) -> void:
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
