extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _item(ctx, kind: String, count: int) -> Dictionary:
	var result = {"uid":"item_%d" % ctx._next_uid, "kind":kind, "count":count}
	ctx._next_uid += 1
	return result

static func _transfer(ctx, id: int, payload: Dictionary) -> bool:
	var original: Dictionary = ctx.state.players[id]
	var p: Dictionary = original.duplicate(true)
	var from = str(payload.get("from",""))
	var to = str(payload.get("to",""))
	if not from in ["bag","stash","equipment"] or not to in ["bag","stash","equipment"]: return false
	var source: Variant = payload.get("slot",payload.get("index"))
	if from == "equipment":
		if not source is String or not source in ctx.EQUIPMENT: return false
	else:
		source = ctx._index(source,p[from].size())
		if source < 0: return false
	var item: Dictionary = p[from][source]
	if item.is_empty(): return false
	var target: Variant = payload.get("target",null)
	if to == "equipment":
		if target == null: target = str(ctx.Items.definition(item.kind).category)
		if not target is String or not target in ctx.EQUIPMENT or ctx.Items.definition(item.kind).category != target: return ctx._reject("装备槽位不匹配")
	elif target != null:
		target = ctx._index(target,p[to].size())
		if target < 0: return false
	if from == to and source == target: return false
	var old_weapon: String = str(p.equipment.weapon.get("uid",""))
	if target == null:
		p[from][source] = {}
		if not ctx._insert(p[to],item): return ctx._reject("没有足够的空位")
	else:
		var destination: Dictionary = p[to][target]
		if not destination.is_empty() and destination.kind == item.kind and int(ctx.Items.definition(item.kind).stack) > 1:
			var amount = mini(int(item.count),int(ctx.Items.definition(item.kind).stack) - int(destination.count))
			if amount <= 0: return false
			destination.count += amount; item.count -= amount
			if item.count == 0: p[from][source] = {}
		else:
			if from == "equipment" and not destination.is_empty() and ctx.Items.definition(destination.kind).category != source: return ctx._reject("无法把该物品换入装备槽")
			p[from][source] = destination
			p[to][target] = item
	ctx._sync_weapon(p,old_weapon)
	if from == "equipment" or to == "equipment": ctx._animate(p,"equip",0.5)
	ctx._update_weight(p)
	ctx.state.players[id] = p
	return true

static func _sync_weapon(ctx, p: Dictionary, old_uid: String) -> void:
	var weapon: Dictionary = p.equipment.weapon
	var uid = str(weapon.get("uid",""))
	if uid != old_uid:
		p.reloading = false; p.reload_timer = 0.0; p.reload_progress = 0.0
		p.ammo = int(p.magazines.get(uid,0)) if uid != "" else 0

static func _split(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var container_name = str(payload.get("container",""))
	if not container_name in ["bag","stash"]: return false
	var container: Array = p[container_name]
	var index = ctx._index(payload.get("index"),container.size())
	if index < 0 or container[index].is_empty(): return false
	var source: Dictionary = container[index]
	var amount: Variant = payload.get("count",int(source.count) / 2)
	if not amount is int or amount < 1 or amount >= int(source.count): return ctx._reject("拆分数量必须小于原堆叠数量")
	var destination = -1
	for i in range(container.size()):
		if container[i].is_empty(): destination = i; break
	if destination < 0: return ctx._reject("没有空位可以拆分物品")
	# Validate the whole operation before allocating or mutating either stack.
	var split_item = ctx._item(str(source.kind),int(amount))
	source.count -= int(amount)
	container[destination] = split_item
	return true

static func _use(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var index = ctx._index(payload.get("index"),p.bag.size())
	if index < 0 or p.bag[index].is_empty(): return false
	var item: Dictionary = p.bag[index]
	var stat = ""
	var amount = 0.0
	match item.kind:
		"medkit": stat = "hp"; amount = 45
		"bandage": stat = "hp"; amount = 18
		"water": stat = "thirst"; amount = 40
		"canned_food": stat = "hunger"; amount = 35
		_: return ctx._reject("此物品不能直接使用")
	if p[stat] >= 100: return ctx._reject("当前状态已满，无需消耗")
	p[stat] = minf(100,p[stat] + amount)
	item.count -= 1
	if item.count <= 0: p.bag[index] = {}
	ctx._update_weight(p)
	ctx._animate(p,"drink" if item.kind == "water" else "eat" if item.kind == "canned_food" else "heal",1.5 if stat == "hp" else 1.3)
	return true

static func _drop(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var index = ctx._index(payload.get("index"),p.bag.size())
	if index < 0 or p.bag[index].is_empty(): return false
	var item: Dictionary = p.bag[index].duplicate(true)
	if ctx.Items.definition(item.kind).category == "weapon":
		item.magazine = int(p.magazines.get(item.uid,0))
		p.magazines.erase(item.uid)
	item.pos = p.pos + p.aim * 0.55
	if not ctx._free(item.pos): item.pos = p.pos
	ctx.state.drops[item.uid] = item
	p.bag[index] = {}
	ctx._update_weight(p)
	ctx._animate(p,"pickup",0.65)
	return true

static func _pickup(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var uid: Variant = payload.get("uid","")
	if not uid is String or not ctx.state.drops.has(uid): return false
	var drop: Dictionary = ctx.state.drops[uid]
	if p.pos.distance_to(drop.pos) > 2.0: return ctx._reject("物品太远")
	var item = {"uid":drop.uid,"kind":drop.kind,"count":drop.count}
	if not ctx._insert(p.bag,item): return ctx._reject("背包已满")
	if ctx.Items.definition(item.kind).category == "weapon": p.magazines[item.uid] = int(drop.get("magazine",0))
	ctx.state.drops.erase(uid)
	ctx._update_weight(p)
	ctx._animate(p,"pickup",0.65)
	return true

static func _sort(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var container = str(payload.get("container","bag"))
	if not container in ["bag","stash"]: return false
	var merged = ctx._empty_slots(p[container].size())
	var items: Array = []
	for item in p[container]:
		if not item.is_empty(): items.append(item.duplicate(true))
	items.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.kind) < str(b.kind))
	for item in items:
		if not ctx._insert(merged,item): return false
	p[container] = merged
	return true
