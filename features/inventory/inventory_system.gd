extends RefCounted
## Authority-only subsystem. ctx is the match; no scene/UI dependencies.
const Rules = preload("res://features/inventory/inventory_rules.gd")



func _pickup(ctx, p: Dictionary, quiet: bool = false) -> bool:
	var nearest = -1
	var distance = 1.6
	for index in ctx.state.loot.size():
		if quiet and not Rules.can_add(p.bag, ctx.state.loot[index], float(p.capacity)):
			continue
		var d: float = p.pos.distance_to(ctx.state.loot[index].pos)
		if d < distance and ctx._line_clear(p.pos, ctx.state.loot[index].pos):
			nearest = index
			distance = d
	if nearest >= 0:
		var item: Dictionary = ctx.state.loot[nearest]
		if not Rules.can_add(p.bag, item, float(p.capacity)):
			if not quiet:
				ctx._event("负重不足：先丢下物品再拾取 %s" % item.name, p.id)
			return false
		ctx.state.loot.remove_at(nearest)
		item.erase("pos")
		p.bag.append(item)
		ctx._event("%s 拾取了 %s" % [p.name, item.name])
		return true
	for corpse in ctx.state.corpses:
		if p.pos.distance_to(corpse.pos) < 1.6 and ctx._line_clear(p.pos, corpse.pos):
			return _loot_corpse(ctx, p, corpse, quiet)
	if not quiet:
		ctx._event("靠近发光遗物后按 E 拾取", p.id)
	return false

func _drop(ctx, p: Dictionary, item_id: int) -> void:
	for index in p.bag.size():
		if int(p.bag[index].id) == item_id:
			var item: Dictionary = p.bag[index]
			p.bag.remove_at(index)
			item.pos = p.pos
			ctx.state.loot.append(item)
			ctx._event("%s 放下了 %s，队友可拾取" % [p.name, item.name])
			return

func _loot_corpse(ctx, p: Dictionary, corpse: Dictionary, quiet: bool = false) -> bool:
	if corpse.items.is_empty():
		return false
	for index in corpse.items.size():
		var item: Dictionary = corpse.items[index]
		if Rules.can_add(p.bag, item, float(p.capacity)):
			corpse.items.remove_at(index)
			p.bag.append(item)
			ctx._event("%s 接过遗留的 %s" % [p.name, item.name])
			return true
	if not quiet:
		ctx._event("背包已满，无法接手遗留物品", p.id)
	return false
