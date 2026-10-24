extends RefCounted
## Party travel is a host-confirmed rule. Map nodes supply routes, never authority.
static func travel(ctx, id: int, payload: Dictionary) -> bool:
	var p: Dictionary = ctx.state.players[id]
	var chosen: Dictionary = {}
	for station in ctx.stations:
		if station.get("kind","")=="travel" and station.get("uid","")==payload.get("route",""):
			chosen = station
			break
	if chosen.is_empty() or chosen.get("world","")!=ctx.state.get("world","bunker"): return false
	if Vector2(p.pos).distance_to(chosen.pos)>2.4001: return ctx._reject("⟦world_travel.001⟧")
	if absf(float(p.get("height",0))-float(chosen.get("height",p.get("height",0))))>3: return false
	var destination: String = str(chosen.destination)
	if not destination in ["bunker","surface","cave"]: return false
	if ctx.travel_validator.is_valid() and not ctx.travel_validator.call(destination):
		return ctx._reject("⟦world_travel.002⟧")
	if chosen.get("scope","")=="player" and destination==ctx.state.get("world",""):
		var target: Vector3 = chosen.spawn
		p.pos = Vector2(target.x,target.z);p.height=target.y
		ctx.reset_transients(id)
		ctx.last_notice = "⟦world_travel.003⟧"
		return true
	if destination=="bunker" and ctx.state.get("world","")!="bunker":
		for member in ctx.state.players.values():
			ctx.Souls.reconcile(ctx,member)
			if ctx.Souls.alive(member) and (Vector2(member.pos).distance_to(chosen.pos)>2.4001 or absf(float(member.get("height",0))-float(chosen.get("height",0)))>3):
				return ctx._reject("⟦world_travel.010⟧")
	return enter_world(ctx,destination,chosen.spawn)

static func enter_world(ctx, destination: String, spawn: Vector3) -> bool:
	for member in ctx.state.players.values():
		ctx.Souls.reconcile(ctx,member)
		if ctx.Souls.zombie(member): return ctx._reject("⟦world_travel.004⟧")
	for member in ctx.state.players.values(): ctx.Loot.close(ctx,member)
	var current: String = str(ctx.state.get("world","bunker"))
	ctx.world_cache[current] = {"drops":ctx.state.drops,"targets":ctx.state.targets,"doors":ctx.state.doors,"containers":ctx.state.get("containers",{,"enemies":ctx.state.get("enemies",{}),"enemies_seeded":ctx.state.get("enemies_seeded",false)}),"corpses":ctx.state.get("corpses",{,"enemies":ctx.state.get("enemies",{}),"enemies_seeded":ctx.state.get("enemies_seeded",false)}),"enemies":ctx.state.get("enemies",{}),"enemies_seeded":ctx.state.get("enemies_seeded",false)}
	var saved: Dictionary = ctx.world_cache.get(destination,{"drops":{},"targets":[],"doors":{}})
	ctx.state.drops = saved.drops
	ctx.state.targets = saved.targets
	ctx.state.doors = saved.get("doors",{})
	ctx.state.containers=saved.get("containers",{})
	ctx.state.corpses=saved.get("corpses",{})
	ctx.state.enemies=saved.get("enemies",{})
	ctx.state.enemies_seeded=saved.get("enemies_seeded",false)
	ctx.state.field_effects=[]
	ctx.state.shots.clear()
	ctx.state.world = destination
	ctx.state.map_revision = "" if destination=="bunker" else ctx.map_revision
	ctx.state.phase = "base" if destination=="bunker" else "exploration"
	ctx.state.world_revision = int(ctx.state.get("world_revision",0))+1
	var index := 0
	for player_id in ctx.state.players:
		var player: Dictionary = ctx.state.players[player_id]
		player.pos = Vector2(spawn.x,spawn.z)+Vector2(index%3*.8,index/3*.8)
		player.height = spawn.y
		player.possessing = 0; player.rescue = {}
		if destination=="bunker" and not ctx.Souls.alive(player): ctx.Souls.revive(ctx,player)
		elif not ctx.Souls.alive(player):
			var body: Dictionary = ctx.state.corpses.get(player.get("corpse_uid",""),{})
			if not body.is_empty(): player.pos=body.pos; player.height=body.height
		ctx.reset_transients(player_id)
		index += 1
	ctx.last_notice = "⟦world_travel.005⟧"+{"bunker":"⟦world_travel.006⟧","surface":"⟦world_flow.002⟧","cave":"⟦world_flow.003⟧"}[destination]
	return true

static func toggle_door(ctx, id: int, payload: Dictionary) -> bool:
	var uid := str(payload.get("uid",""))
	var p: Dictionary=ctx.state.players[id]
	for station in ctx.stations:
		if station.get("kind","")!="door" or station.uid!=uid or station.world!=ctx.state.get("world",""):continue
		if Vector2(p.pos).distance_to(station.pos)>2.4 or absf(float(p.get("height",0))-float(station.height))>2:return ctx._reject("⟦world_travel.007⟧")
		if ctx.door_reachable.is_valid() and not ctx.door_reachable.call(uid,Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)):return ctx._reject("⟦world_travel.008⟧")
		var opened:=bool(ctx.state.doors.get(uid,station.get("initial_open",false)))
		if opened and ctx.door_clearance.is_valid() and not ctx.door_clearance.call(uid):return ctx._reject("⟦world_travel.009⟧")
		ctx.state.doors[uid]=not opened
		return true
	return false
