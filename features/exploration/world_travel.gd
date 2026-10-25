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
	if Vector2(p.pos).distance_to(chosen.pos)>2.4: return ctx._reject("靠近地图入口后才能出发")
	if absf(float(p.get("height",0))-float(chosen.get("height",p.get("height",0))))>3: return false
	var destination: String = str(chosen.destination)
	if not destination in ["bunker","surface","cave"]: return false
	if ctx.travel_validator.is_valid() and not ctx.travel_validator.call(destination):
		return ctx._reject("零号区外置素材未还原，请先执行地图提取工具")
	if chosen.get("scope","")=="player" and destination==ctx.state.get("world",""):
		var target: Vector3 = chosen.spawn
		p.pos = Vector2(target.x,target.z);p.height=target.y
		ctx.reset_transients(id)
		ctx.last_notice = "已到达传送点"
		return true
	return enter_world(ctx,destination,chosen.spawn)

static func enter_world(ctx, destination: String, spawn: Vector3) -> bool:
	for member in ctx.state.players.values():
		ctx.Souls.reconcile(ctx,member)
		if ctx.Souls.zombie(member): return ctx._reject("队伍中有尸变者，无法切换地图或撤离；请先复活或自杀进入灵魂状态")
	for member in ctx.state.players.values(): ctx.Loot.close(ctx,member)
	var current: String = str(ctx.state.get("world","bunker"))
	ctx.world_cache[current] = {"drops":ctx.state.drops,"targets":ctx.state.targets,"doors":ctx.state.doors,"containers":ctx.state.get("containers",{}),"corpses":ctx.state.get("corpses",{})}
	var saved: Dictionary = ctx.world_cache.get(destination,{"drops":{},"targets":[],"doors":{}})
	ctx.state.drops = saved.drops
	ctx.state.targets = saved.targets
	ctx.state.doors = saved.get("doors",{})
	ctx.state.containers=saved.get("containers",{})
	ctx.state.corpses=saved.get("corpses",{})
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
	ctx.last_notice = "队伍已进入"+{"bunker":"地下基地","surface":"零号区","cave":"神秘山洞"}[destination]
	return true

static func toggle_door(ctx, id: int, payload: Dictionary) -> bool:
	var uid := str(payload.get("uid",""))
	var p: Dictionary=ctx.state.players[id]
	for station in ctx.stations:
		if station.get("kind","")!="door" or station.uid!=uid or station.world!=ctx.state.get("world",""):continue
		if Vector2(p.pos).distance_to(station.pos)>2.4 or absf(float(p.get("height",0))-float(station.height))>2:return ctx._reject("靠近门后才能操作")
		if ctx.door_reachable.is_valid() and not ctx.door_reachable.call(uid,Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)):return ctx._reject("门被墙体遮挡，请走到门口")
		var opened:=bool(ctx.state.doors.get(uid,station.get("initial_open",false)))
		if opened and ctx.door_clearance.is_valid() and not ctx.door_clearance.call(uid):return ctx._reject("有人经过门口，请稍候")
		ctx.state.doors[uid]=not opened
		return true
	return false
