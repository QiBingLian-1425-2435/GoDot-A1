extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _near(ctx, p: Dictionary, kind: String) -> bool:
	for station in ctx.stations:
		if str(station.get("kind",station.get("id",""))) == kind and station.get("pos") is Vector2 and p.pos.distance_to(station.pos) <= 2.5:
			return true
	return false

static func _craft(ctx, p: Dictionary) -> bool:
	if not ctx._near(p,"workbench"): return ctx._reject("请靠近工作台")
	if ctx._count(p.bag,"scrap") < 4: return ctx._reject("需要背包中4个金属零件")
	var bag: Array = p.bag.duplicate(true)
	ctx._consume(bag,"scrap",4)
	if not ctx._insert(bag,ctx._item("medkit",1)): return ctx._reject("背包空间不足")
	p.bag = bag; ctx._update_weight(p)
	ctx.last_notice = "制作完成：急救包 ×1"
	ctx._animate(p,"interact",0.8)
	return true

static func _buy_ammo(ctx, p: Dictionary) -> bool:
	if not ctx._near(p,"trader"): return ctx._reject("请靠近商人")
	if p.credits < 60: return ctx._reject("需要60基地币")
	if not ctx._insert(p.bag,ctx._item("ammo",30)): return ctx._reject("背包空间不足")
	p.credits -= 60; ctx._update_weight(p)
	ctx.last_notice = "购入训练弹 ×30，花费60基地币"
	ctx._animate(p,"interact",0.8)
	return true
