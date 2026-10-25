extends RefCounted
const Texts = preload("res://features/localization/game_text.gd")
## Host-owned container contents, sequential discovery and atomic inventory transfer.
const Items = preload("res://features/inventory/item_catalog.gd")
const COMMON = ["water", "canned_food", "biscuits", "bandage", "scrap", "tape"]
const GREEN = ["juice", "medkit", "battery", "glowstick"]
const BLUE = ["energy_bar", "medical_box", "lockpick", "smoke_grenade", "circuit_board"]
const FOOD = ["canned_food", "biscuits", "energy_bar"]
const SEARCH_SECONDS := 1.4

static func station(ctx, uid: String) -> Dictionary:
	if ctx.state.get("corpses",{}).has(uid): return ctx.state.corpses[uid]
	for target in ctx.stations:
		if target.get("kind") == "loot" and target.get("uid") == uid:
			return target
	return {}

static func reachable(ctx, p: Dictionary, target: Dictionary) -> bool:
	if not ctx.Souls.alive(p): return false
	if target.get("kind","") == "corpse": return ctx.Souls.reachable(ctx,p,target)
	if target.is_empty() or not ctx.world_ready or target.get("world") != ctx.state.world:
		return false
	if Vector2(p.pos).distance_to(target.pos) > 2.4 or absf(float(p.get("height", 0)) - float(target.height)) > 2:
		return false
	return ctx.loot_reachable.is_valid() and ctx.loot_reachable.call(target.uid, Vector3(p.pos.x, float(p.get("height", 0)), p.pos.y))

static func open(ctx, p: Dictionary, target: Dictionary) -> bool:
	if not reachable(ctx, p, target):
		return ctx._reject("⟦container_loot.001⟧")
	var uid: String = target.uid
	if not ctx.state.containers.has(uid):
		if target.get("locked", false):
			if ctx._count(p.bag, "lockpick") < 1:
				return ctx._reject("⟦container_loot.002⟧")
			ctx._consume(p.bag, "lockpick", 1)
		var items: Array = []
		for i in range(randi_range(2, 5)):
			var kind := str(FOOD.pick_random()) if target.get("loot_pool", "") == "food" else roll(bool(target.get("locked", false)))
			items.append(ctx._item(kind, randi_range(1, mini(3, int(Items.definition(kind).stack)))))
		ctx.state.containers[uid] = {"items": items, "revealed": 0, "progress": 0.0, "searcher": 0, "title":str(target.get("container_name", "⟦container_loot.003⟧"))}
	# Old in-room boolean entries are already exhausted, never reroll them.
	if not ctx.state.containers[uid] is Dictionary:
		ctx.state.containers[uid] = {"items": [], "revealed": 0, "progress": 0.0, "searcher": 0}
	close(ctx, p)
	p.loot_uid = uid
	var box: Dictionary = ctx.state.containers[uid]
	if int(box.searcher) == 0 and int(box.revealed) < box.items.size():
		box.searcher = p.id
	ctx._update_weight(p)
	ctx._animate(p, "interact", .8)
	ctx.last_notice = Texts.format("⟦container_loot.004⟧", str(target.get("container_name", "⟦container_loot.003⟧")))
	return true

static func close(ctx, p: Dictionary, uid: String = "") -> bool:
	var active := str(p.get("loot_uid", ""))
	if not uid.is_empty() and uid != active:
		return false
	var box: Variant = ctx.state.containers.get(active, {})
	if box is Dictionary and int(box.get("searcher", 0)) == int(p.id):
		box.searcher = 0
	p.loot_uid = ""
	return not active.is_empty()

static func tick(ctx, delta: float) -> void:
	for p in ctx.state.players.values():
		var uid := str(p.get("loot_uid", ""))
		if not uid.is_empty() and not reachable(ctx, p, station(ctx, uid)):
			close(ctx, p)
	for uid in ctx.state.containers:
		var box: Variant = ctx.state.containers[uid]
		if not box is Dictionary or int(box.revealed) >= box.items.size():
			continue
		var owner: Dictionary = ctx.state.players.get(int(box.searcher), {})
		if owner.is_empty() or owner.get("loot_uid", "") != uid:
			box.searcher = 0
			for p in ctx.state.players.values():
				if p.get("loot_uid", "") == uid:
					box.searcher = p.id
					break
		if int(box.searcher) == 0:
			continue
		box.progress += delta
		while float(box.progress) >= SEARCH_SECONDS and int(box.revealed) < box.items.size():
			box.progress -= SEARCH_SECONDS
			box.revealed += 1
		if int(box.revealed) == box.items.size():
			box.progress = 0.0
			box.searcher = 0

static func take(ctx, p: Dictionary, payload: Dictionary) -> bool:
	var uid := str(payload.get("uid", ""))
	if uid.is_empty() or p.get("loot_uid", "") != uid or not reachable(ctx, p, station(ctx, uid)):
		return ctx._reject("⟦container_loot.005⟧")
	var box: Dictionary = ctx.state.containers.get(uid, {})
	if box.is_empty():
		return false
	var index: Variant = payload.get("index")
	if not index is int or index < -1 or index >= int(box.revealed):
		return ctx._reject("⟦container_loot.006⟧")
	if index >= 0 and (box.items[index].is_empty() or box.items[index].uid != payload.get("item_uid", "")):
		return ctx._reject("⟦container_loot.007⟧")
	var taken := 0
	for i in range(int(box.revealed)):
		if (index >= 0 and i != index) or box.items[i].is_empty():
			continue
		var copy: Array = p.bag.duplicate(true)
		if not ctx._insert(copy, box.items[i].duplicate(true)):
			continue
		p.bag = copy
		var item: Dictionary = box.items[i]
		if Items.definition(item.kind).category == "weapon": p.magazines[item.uid] = int(item.get("magazine",0))
		box.items[i] = {}
		taken += 1
	if taken == 0:
		return ctx._reject("⟦container_loot.008⟧")
	ctx._update_weight(p)
	ctx.last_notice = Texts.format("⟦container_loot.009⟧", taken)
	return true

static func roll(locked: bool) -> String:
	var chance := randf()
	var pool: Array = COMMON
	if locked and chance < .01: pool = ["encrypted_core"]
	elif locked and chance < .05: pool = ["gold_statue"]
	elif chance < .12: pool = ["pocket_watch", "optical_parts", "beacon"]
	elif chance < .32: pool = BLUE
	elif chance < .62: pool = GREEN
	return str(pool.pick_random())

static func public_state(state: Dictionary) -> Dictionary:
	# Unknown slots reveal neither item kind nor UID to network clients.
	var result := state.duplicate()
	result.containers = state.containers.duplicate(true)
	for box in result.containers.values():
		if not box is Dictionary: continue
		for i in range(int(box.revealed), box.items.size()):
			box.items[i] = {}
	return result
