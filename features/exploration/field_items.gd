extends RefCounted
## Host-only tool/loot rules. Geometry arrives through explicit world callbacks.
const Items=preload("res://features/inventory/item_catalog.gd")
const DURATIONS={"glowstick":60.0,"smoke_grenade":8.0,"beacon":60.0}
const COMMON=["water","canned_food","biscuits","bandage","scrap","tape"]
const GREEN=["juice","medkit","battery","glowstick"]
const BLUE=["energy_bar","medical_box","lockpick","smoke_grenade","circuit_board"]
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
	for station in ctx.stations:
		if station.get("kind")=="loot" and station.get("uid")==uid:return open_container(ctx,p,station)
	return false
static func open_container(ctx,p:Dictionary,station:Dictionary) -> bool:
	if station.is_empty() or station.get("world")!=ctx.state.world or not ctx.world_ready:return false
	if ctx.state.containers.has(station.uid):return ctx._reject("这个容器已经搜索过")
	if Vector2(p.pos).distance_to(station.pos)>2.4 or absf(float(p.get("height",0))-float(station.height))>2:return ctx._reject("靠近同一楼层的容器才能搜索")
	if not ctx.loot_reachable.is_valid() or not ctx.loot_reachable.call(station.uid,Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)):return ctx._reject("容器被墙体或烟雾遮挡")
	if station.get("locked",false):
		if ctx._count(p.bag,"lockpick")<1:return ctx._reject("需要简易开锁器，商人或工作台可获得")
		ctx._consume(p.bag,"lockpick",1)
	ctx.state.containers[station.uid]=true
	for i in range(2):
		var roll:=randf();var pool:Array=COMMON
		if station.get("locked",false) and roll<.01:pool=["encrypted_core"]
		elif station.get("locked",false) and roll<.05:pool=["gold_statue"]
		elif roll<.12:pool=["pocket_watch","optical_parts","beacon"]
		elif roll<.32:pool=BLUE
		elif roll<.62:pool=GREEN
		var kind:String=pool.pick_random();var item:Dictionary=ctx._item(kind,mini(2,int(Items.definition(kind).stack)))
		item.pos=Vector2(p.pos)+Vector2(p.aim)*.35;item.height=float(p.get("height",0))
		ctx.state.drops[item.uid]=item
	ctx._update_weight(p);ctx._animate(p,"interact",.8);ctx.last_notice="搜索完成，物品已放在脚边，按E拾取";return true
static func blocks_sight(effects: Array, from: Vector3, to: Vector3) -> bool:
	var segment:=to-from;var length2:=segment.length_squared()
	for effect in effects:
		if effect.kind!="smoke_grenade" or float(effect.ttl)<=0:continue
		var center:Vector3=effect.pos+Vector3.UP
		var t:float=clampf((center-from).dot(segment)/maxf(length2,.00001),0,1)
		if (from+segment*t).distance_squared_to(center)<9:return true
	return false
