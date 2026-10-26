extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Shared camp definitions and authoritative rules. Persistence is supplied by Session.
const DEFS := {
	"medical":{"name":"⟦camp_upgrades.001⟧","stat":"⟦camp_upgrades.002⟧","step":5,"costs":[{"credits":800,"items":{"scrap":4,"tape":2}},{"credits":2000,"items":{"battery":2,"tape":4}},{"credits":5000,"items":{"battery":4,"circuit_board":2}}]},
	"training":{"name":"⟦camp_upgrades.003⟧","stat":"⟦camp_upgrades.004⟧","step":5,"costs":[{"credits":800,"items":{"scrap":6,"tape":2}},{"credits":2000,"items":{"scrap":12,"battery":2}},{"credits":5000,"items":{"scrap":20,"circuit_board":3}}]},
	"logistics":{"name":"⟦camp_upgrades.005⟧","stat":"⟦camp_upgrades.006⟧","step":1,"costs":[{"credits":1000,"items":{"scrap":8,"tape":3}},{"credits":2500,"items":{"scrap":15,"tape":6,"battery":2}},{"credits":6000,"items":{"circuit_board":3,"optical_parts":1}}]}
}
static func initial() -> Dictionary:return {"medical":0,"training":0,"logistics":0}
static func valid(value:Variant) -> bool:
	if not value is Dictionary or value.size()!=DEFS.size():return false
	for key in DEFS:
		var level:Variant=value.get(key)
		if (not level is int and not level is float) or not is_finite(float(level)) or float(level)!=floor(float(level)) or level<0 or level>3:return false
	return true
static func normalized(value:Dictionary) -> Dictionary:
	var result:=initial()
	for key in result:result[key]=int(value[key])
	return result
static func refresh_player(ctx,p:Dictionary) -> void:
	var levels:Dictionary=ctx.state.get("camp",initial())
	p.max_hp=100.0+5*int(levels.medical)
	p.max_stamina=100.0+5*int(levels.training)
	p.camp_weight_bonus=float(levels.logistics)
	p.hp=minf(float(p.hp),p.max_hp);p.stamina=minf(float(p.stamina),p.max_stamina)
	ctx._update_weight(p)
static func refresh_all(ctx) -> void:
	for p in ctx.state.players.values():refresh_player(ctx,p)
static func reason(ctx,p:Dictionary,facility:String,expected:Variant) -> String:
	if not ctx.world_ready:return "⟦camp_upgrades.007⟧"
	if ctx.state.get("world","bunker")!="bunker" or not ctx._near(p,"camp_management"):return "⟦camp_upgrades.008⟧"
	if absf(float(p.get("height",0)))>1.8:return "⟦camp_upgrades.008⟧"
	if not DEFS.has(facility):return "⟦camp_upgrades.009⟧"
	var level:int=ctx.state.camp[facility]
	if not expected is int or expected!=level:return "⟦camp_upgrades.010⟧"
	if level>=3:return "⟦camp_upgrades.011⟧"
	var cost:Dictionary=DEFS[facility].costs[level]
	if not ctx.state.get("infinite_credits",false) and p.credits<int(cost.credits):return Texts.format("⟦camp_upgrades.012⟧", cost.credits)
	for kind in cost.items:
		if ctx._count(p.bag,kind)<int(cost.items[kind]):return Texts.format("⟦camp_upgrades.013⟧", [ctx.Items.definition(kind).name,int(cost.items[kind])-ctx._count(p.bag,kind)])
	return ""
static func upgrade(ctx,p:Dictionary,payload:Dictionary) -> bool:
	var facility:=str(payload.get("facility",""))
	var message:=reason(ctx,p,facility,payload.get("expected_level"))
	if not message.is_empty():return ctx._reject(message)
	var level:int=ctx.state.camp[facility]
	var cost:Dictionary=DEFS[facility].costs[level]
	var bag:Array=p.bag.duplicate(true)
	for kind in cost.items:ctx._consume(bag,kind,int(cost.items[kind]))
	p.bag=bag
	if not ctx.state.get("infinite_credits",false):p.credits-=int(cost.credits)
	ctx.state.camp[facility]=level+1
	refresh_all(ctx)
	ctx.last_notice=Texts.format("⟦camp_upgrades.014⟧", [DEFS[facility].name,level+1,DEFS[facility].stat,(level+1)*int(DEFS[facility].step),"⟦format.camp_panel.002⟧" if facility=="logistics" else ""])
	return true
