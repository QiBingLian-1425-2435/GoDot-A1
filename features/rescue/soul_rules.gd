extends RefCounted
## Only BaseModel invokes these transitions on the authority.
const RESCUE_SECONDS := 3.0
const ZOMBIE_KILL_RANGE := 0.9

static func zombie(p: Dictionary) -> bool:
	return p.get("life", "alive") == "zombie"

static func mobile(p: Dictionary) -> bool:
	return alive(p) or zombie(p)

static func zombify(ctx, p: Dictionary) -> void:
	if not alive(p): return
	ctx.reset_transients(int(p.id))
	p.life = "zombie"; p.hp = 0.0; p.san = 0.0; p.possessing = 0; p.rescue = {}
	p.relocation_seq = int(p.get("relocation_seq",0))+1

static func reconcile(ctx, p: Dictionary) -> void:
	if p.get("life", "alive") != "alive": return
	if float(p.hp)<=0: die(ctx,p)
	elif float(p.get("san",100))<=0: zombify(ctx,p)

static func use_revival(ctx, p: Dictionary, index: int) -> bool:
	var chosen: Dictionary = {}
	var distance := 2.4
	for target in ctx.state.players.values():
		if alive(target) or target.id==p.id: continue
		var body: Dictionary = {"pos":target.pos,"height":target.get("height",0),"world":ctx.state.world} if zombie(target) else ctx.state.corpses.get(target.get("corpse_uid",""),{})
		if not reachable(ctx,p,body): continue
		var d: float = Vector2(p.pos).distance_to(body.pos)
		if d<=distance: chosen=target; distance=d
	if chosen.is_empty(): return ctx._reject("⟦soul_rules.001⟧")
	p.bag[index].count-=1
	if p.bag[index].count<=0: p.bag[index]={}
	revive(ctx,chosen)
	ctx._update_weight(p); ctx._animate(p,"heal",1.5)
	return true

static func alive(p: Dictionary) -> bool:
	return not p.is_empty() and float(p.get("hp",100)) > 0 and p.get("life","alive") == "alive"

static func observer_id(players: Dictionary, id: int) -> int:
	var p: Dictionary = players.get(id,{})
	var target := int(p.get("possessing",0))
	return target if p.get("life", "alive")=="soul" and alive(players.get(target,{})) else id

static func die(ctx, p: Dictionary) -> void:
	if p.get("life","alive") == "soul": return
	ctx.reset_transients(int(p.id))
	p.life = "soul"; p.hp = 0.0; p.possessing = 0; p.rescue = {}
	p.relocation_seq = int(p.get("relocation_seq",0))+1
	var uid := "corpse_%d" % ctx._next_uid
	ctx._next_uid += 1
	p.corpse_uid = uid
	var items: Array = []
	for item in p.bag + p.equipment.values():
		if item.is_empty(): continue
		var copy: Dictionary = item.duplicate(true)
		if ctx.Items.definition(copy.kind).category == "weapon":
			copy.magazine = int(p.magazines.get(copy.uid,0))
			p.magazines.erase(copy.uid)
		items.append(copy)
	ctx.state.corpses[uid] = {"uid":uid,"kind":"corpse","owner":p.id,"pos":p.pos,"height":p.get("height",0),"world":ctx.state.world,"container_name":str(p.name)+"⟦soul_rules.002⟧"}
	ctx.state.containers[uid] = {"items":items,"revealed":0,"progress":0.0,"searcher":0,"title":str(p.name)+"⟦soul_rules.002⟧"}
	p.bag = ctx._empty_slots(24)
	for slot in ctx.EQUIPMENT: p.equipment[slot] = {}
	p.ammo = 0
	ctx._update_weight(p)

static func reachable(ctx, p: Dictionary, body: Dictionary) -> bool:
	if not alive(p) or body.is_empty() or not ctx.world_ready or body.world != ctx.state.world: return false
	if Vector2(p.pos).distance_to(body.pos)>2.4 or absf(float(p.get("height",0))-float(body.height))>1.8: return false
	var a := Vector3(p.pos.x,float(p.get("height",0))+.7,p.pos.y)
	var b := Vector3(body.pos.x,float(body.height)+.7,body.pos.y)
	if ctx.rescue_reachable.is_valid(): return ctx.rescue_reachable.call(a,b)
	# Pure rule fixtures retain the same rectangle obstruction boundary.
	for rect in ctx.obstacles:
		var offset := Vector2(body.pos)-Vector2(p.pos)
		if offset.length()<.001: break
		var hit: float = ctx._ray_rect(p.pos,offset.normalized(),rect)
		if hit>=0 and hit<offset.length(): return false
	return true

static func command(ctx, p: Dictionary, action: String, payload: Dictionary) -> bool:
	if zombie(p):
		if action != "suicide": return false
		die(ctx,p)
		return true
	match action:
		"soul_wait":
			if alive(p): return false
			p.possessing = 0
			return true
		"possess":
			var target: Variant = payload.get("target")
			if alive(p) or not target is int or target == p.id or not alive(ctx.state.players.get(target,{})): return false
			p.possessing = target
			return true
		"release_soul":
			if not alive(p): return false
			for ghost in ctx.state.players.values():
				if int(ghost.get("possessing",0)) == int(p.id): ghost.possessing = 0
			return true
		"rescue":
			var target: Variant = payload.get("target")
			if not target is int or not ctx.state.players.has(target): return false
			var ghost: Dictionary = ctx.state.players[target]
			var body: Dictionary = ctx.state.corpses.get(ghost.get("corpse_uid",""),{})
			if payload.has("uid") and payload.uid!=body.get("uid",""): return false
			if ghost.get("life","alive")!="soul" or not reachable(ctx,p,body): return ctx._reject("⟦soul_rules.003⟧")
			if not p.get("rescue",{}).is_empty(): return false
			ctx.Loot.close(ctx,p)
			p.pending_use = {}
			p.rescue = {"target":target,"uid":body.uid,"remaining":RESCUE_SECONDS,"origin":p.pos}
			return true
		"rescue_cancel":
			p.rescue = {}
			return true
		"return_camp":
			for member in ctx.state.players.values():
				if zombie(member): return ctx._reject("⟦soul_rules.004⟧")
				if alive(member): return ctx._reject("⟦soul_rules.005⟧")
			return ctx.WorldTravel.enter_world(ctx,"bunker",Vector3(-1,0,4))
	return false

static func revive(ctx, p: Dictionary) -> void:
	p.life = "alive"; p.hp = minf(30,float(p.get("max_hp",100))); p.possessing = 0; p.rescue = {}
	p.san = 30.0
	p.relocation_seq = int(p.get("relocation_seq",0))+1
	ctx.reset_transients(int(p.id))

static func tick(ctx, delta: float) -> void:
	for p in ctx.state.players.values():
		reconcile(ctx,p)
	# Gather victims before mutation, so conversion order cannot affect attacks.
	var victims: Dictionary = {}
	if ctx.world_ready:
		for attacker in ctx.state.players.values():
			if not zombie(attacker): continue
			for target in ctx.state.players.values():
				if not alive(target) or Vector2(attacker.pos).distance_to(target.pos)>ZOMBIE_KILL_RANGE: continue
				var body := {"pos":attacker.pos,"height":attacker.get("height",0),"world":ctx.state.world}
				if reachable(ctx,target,body): victims[target.id]=target
	for target in victims.values(): die(ctx,target)
	for p in ctx.state.players.values():
		if not alive(p):
			if not alive(ctx.state.players.get(int(p.get("possessing",0)),{})): p.possessing = 0
			continue
		var rescue: Dictionary = p.get("rescue",{})
		if rescue.is_empty(): continue
		var ghost: Dictionary = ctx.state.players.get(int(rescue.target),{})
		var body: Dictionary = ctx.state.corpses.get(str(rescue.uid),{})
		if ghost.is_empty() or ghost.get("life","alive")!="soul" or ghost.get("corpse_uid","")!=rescue.uid or not reachable(ctx,p,body) or Vector2(p.pos).distance_to(rescue.origin)>.15:
			p.rescue = {}; continue
		rescue.remaining -= delta
		if float(rescue.remaining)<=0:
			ghost.pos = body.pos; ghost.height = body.height
			revive(ctx,ghost)
			p.rescue = {}
