extends RefCounted
const Items=preload("res://features/inventory/item_catalog.gd")
const RECIPES := {"medkit":{"scrap":4},"glowstick":{"battery":1,"tape":1},"lockpick":{"scrap":10,"tape":3},"smoke_grenade":{"scrap":4,"tape":3,"battery":1},"beacon":{"circuit_board":2,"battery":2,"tape":2},"medical_box":{"scrap":5,"tape":4,"battery":1}}
static func available(kind: String) -> bool:
	return Items.DEFS.has(kind) and Items.definition(kind).item_type!="valuable"
static func trade(ctx, p: Dictionary, action: String, payload: Dictionary) -> bool:
	if ctx.state.world!="bunker" or not ctx._near(p,"trader"):return ctx._reject("请靠近基地商人")
	if action=="sell":
		var index:int=ctx._index(payload.get("index"),p.bag.size())
		if index<0 or p.bag[index].is_empty():return false
		var item:Dictionary=p.bag[index];var info:=Items.definition(item.kind)
		if payload.get("uid","")!=item.uid:return ctx._reject("物品已移动，请重新选择")
		if not info.sellable:return ctx._reject("训练弹不可出售")
		var amount:int=int(info.value)*int(item.count)
		if p.credits+amount>999999:return ctx._reject("资金已达上限")
		p.credits+=amount;p.bag[index]={};p.magazines.erase(item.uid);ctx._update_weight(p)
		ctx.last_notice="已出售 %s ×%d，获得%d基地币"%[info.name,item.count,amount];return true
	var kind:=str(payload.get("kind",""));var count:Variant=payload.get("count",1)
	if not available(kind) or not count is int or count<1 or count>int(Items.definition(kind).stack):return false
	var price:int=int(Items.definition(kind).buy_price)*count
	if p.credits<price:return ctx._reject("资金不足，需要%d基地币"%price)
	var bag:Array=p.bag.duplicate(true)
	if not ctx._insert(bag,ctx._item(kind,count)):return ctx._reject("背包空间不足")
	p.bag=bag;p.credits-=price;ctx._update_weight(p);ctx.last_notice="购买完成："+str(Items.definition(kind).name);return true
static func craft(ctx, p: Dictionary, kind: String) -> bool:
	if ctx.state.world!="bunker" or not ctx._near(p,"workbench"):return ctx._reject("请靠近基地工作台")
	if not RECIPES.has(kind):return false
	var bag:Array=p.bag.duplicate(true)
	for material in RECIPES[kind]:
		if ctx._count(bag,material)<int(RECIPES[kind][material]):return ctx._reject("缺少材料："+str(Items.definition(material).name))
	for material in RECIPES[kind]:ctx._consume(bag,material,int(RECIPES[kind][material]))
	if not ctx._insert(bag,ctx._item(kind,1)):return ctx._reject("背包空间不足")
	p.bag=bag;ctx._update_weight(p);ctx._animate(p,"interact",.8)
	ctx.last_notice="制作完成："+str(Items.definition(kind).name);return true
