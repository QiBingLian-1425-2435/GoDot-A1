extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Migrated reference behavior; called only through the owning composition/model.

static func _near(ctx, p: Dictionary, kind: String) -> bool:
	for station in ctx.stations:
		if str(station.get("kind",station.get("id",""))) == kind and station.get("pos") is Vector2 and p.pos.distance_to(station.pos) <= 2.5:
			return true
	return false

static func _craft(ctx, p: Dictionary) -> bool:
	if not ctx._near(p,"workbench"): return ctx._reject("⟦facility_system.001⟧")
	if ctx._count(p.bag,"scrap") < 4: return ctx._reject("⟦facility_system.002⟧")
	var bag: Array = p.bag.duplicate(true)
	ctx._consume(bag,"scrap",4)
	if not ctx._insert(bag,ctx._item("medkit",1)): return ctx._reject("⟦facility_system.003⟧")
	p.bag = bag; ctx._update_weight(p)
	ctx.last_notice = "⟦facility_system.004⟧"
	ctx._animate(p,"interact",0.8)
	return true

static func resupply_ammo(ctx, p: Dictionary) -> bool:
	if not ctx._near(p,"ammo_supply"): return ctx._reject("⟦facility_system.005⟧")
	var needed: int = maxi(0,120 - ctx._count(p.bag,"ammo"))
	if needed == 0: return ctx._reject("⟦facility_system.006⟧")
	var bag: Array = p.bag.duplicate(true)
	var remaining := needed
	while remaining > 0:
		var amount := mini(remaining,int(ctx.Items.definition("ammo").stack))
		if not ctx._insert(bag,ctx._item("ammo",amount)):
			return ctx._reject("⟦facility_system.007⟧")
		remaining -= amount
	p.bag = bag
	ctx._update_weight(p)
	ctx.last_notice = Texts.format("⟦facility_system.008⟧", needed)
	ctx._animate(p,"interact",0.8)
	return true

static func _buy_ammo(ctx, p: Dictionary) -> bool:
	if not ctx._near(p,"trader"): return ctx._reject("⟦facility_system.009⟧")
	if not ctx.state.get("infinite_credits",false) and p.credits < 60: return ctx._reject("⟦facility_system.010⟧")
	if not ctx._insert(p.bag,ctx._item("ammo",30)): return ctx._reject("⟦facility_system.003⟧")
	if not ctx.state.get("infinite_credits",false):p.credits -= 60
	ctx._update_weight(p)
	ctx.last_notice = "⟦facility_system.011⟧"
	ctx._animate(p,"interact",0.8)
	return true
