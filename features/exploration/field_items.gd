extends RefCounted
## Host-only tool/loot rules. Geometry arrives through explicit world callbacks.
const Items=preload("res://features/inventory/item_catalog.gd")
const DURATIONS={"glowstick":60.0,"smoke_grenade":8.0,"beacon":60.0}
static func use(ctx, p: Dictionary, kind: String) -> bool:
	if not ctx.world_ready:return ctx._reject("地图加载中，暂时不能使用道具")
	if kind=="lockpick":
		var chosen:Dictionary={};var distance:=2.4
		for station in ctx.stations:
			if station.get("kind")!="loot" or not station.get("locked",false) or ctx.state.containers.has(station.uid):continue
			if absf(float(p.get("height",0))-float(station.height))>2:continue
			if not ctx.loot_reachable.is_valid() or not ctx.loot_reachable.call(station.uid,Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)):continue
			var d:float=Vector2(p.pos).distance_to(station.pos)
			if d<distance:chosen=station;distance=d
		return open_container(ctx,p,chosen) if not chosen.is_empty() else ctx._reject("附近没有同层可触及、尚未开启的上锁容器")
	if not DURATIONS.has(kind):return false
	if ctx.state.field_effects.size()>=32:return ctx._reject("场景道具数量已达上限")
	var count:=0;var smoke_count:=0
	for effect in ctx.state.field_effects:
		if effect.kind==kind and int(effect.owner)==int(p.id):count+=1
		if effect.kind=="smoke_grenade":smoke_count+=1
	if count>=2 or (kind=="smoke_grenade" and smoke_count>=8):return ctx._reject("同类道具同时最多2个，烟雾全队最多8个")
	var from:=Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)
	var target:=from+Vector3(p.aim.x,0,p.aim.y)*.9
	if not ctx._free(Vector2(target.x,target.z)):return ctx._reject("前方没有放置空间")
	if ctx.field_placement.is_valid():
		var placement:Dictionary=ctx.field_placement.call(from,target)
		if placement.is_empty():return ctx._reject("前方有遮挡或没有安全地面")
		target=placement.position
	if ctx._consume(p.bag,kind,1)!=1:return false
	var uid:="effect_%d"%ctx._next_uid;ctx._next_uid+=1
	ctx.state.field_effects.append({"uid":uid,"kind":kind,"owner":p.id,"owner_name":str(p.name),"pos":target,"ttl":DURATIONS[kind],"world":ctx.state.world})
	ctx._update_weight(p);ctx._animate(p,"interact",.6);ctx.last_notice="已放置"+str(Items.definition(kind).name);return true
static func search(ctx,p:Dictionary,uid:String) -> bool:
	return ctx.Loot.open(ctx,p,ctx.Loot.station(ctx,uid))
static func open_container(ctx,p:Dictionary,station:Dictionary) -> bool:
	return ctx.Loot.open(ctx,p,station)
static func blocks_sight(effects: Array, from: Vector3, to: Vector3) -> bool:
	var segment:=to-from;var length2:=segment.length_squared()
	for effect in effects:
		if effect.kind!="smoke_grenade" or float(effect.ttl)<=0:continue
		var center:Vector3=effect.pos+Vector3.UP
		var t:float=clampf((center-from).dot(segment)/maxf(length2,.00001),0,1)
		if (from+segment*t).distance_squared_to(center)<9:return true
	return false
