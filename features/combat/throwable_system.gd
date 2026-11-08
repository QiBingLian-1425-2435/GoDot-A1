extends RefCounted
## Host-owned projectiles and areas. Preview and simulation share the same arc.
const KINDS=["frag_grenade","smoke_grenade","molotov"]
const RADIUS=3.0
const RANGE=10.0
const DURATIONS={"frag_grenade":.8,"smoke_grenade":15.0,"molotov":5.0}

static func is_throwable(kind:String)->bool:return kind in KINDS

static func held(p:Dictionary)->Dictionary:
	var selected:String=p.get("held_throwable","")
	for item in p.get("bag",[]):
		if item.get("uid","")==selected and is_throwable(item.get("kind","")):return item
	return {}

static func select(p:Dictionary,index:int)->bool:
	if index==-1:p.held_throwable="";return true
	if index<0 or index>=p.bag.size() or not is_throwable(p.bag[index].get("kind","")):return false
	p.held_throwable=p.bag[index].uid
	p.reloading=false;p.reload_progress=0.0;p.reload_timer=0.0
	return true

static func arc(p:Dictionary,requested:Vector3,query:Callable=Callable())->Array[Vector3]:
	var ground:=Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)
	var offset:=Vector2(requested.x-ground.x,requested.z-ground.z).limit_length(RANGE)
	var target:=ground+Vector3(offset.x,0,offset.y)
	if query.is_valid():
		var support:Dictionary=query.call(target+Vector3.UP*.6,target-Vector3.UP*8)
		if not support.is_empty():target=support.position+Vector3.UP*.04
	var start:=ground+Vector3.UP*(.95 if p.get("crouch",false) else 1.4)
	var points:Array[Vector3]=[start]
	for i in range(1,49):
		var t:=float(i)/48
		var point:Vector3=start.lerp(target,t)+Vector3.UP*(4*t*(1-t)*(1.2+offset.length()*.12))
		if query.is_valid():
			var hit:Dictionary=query.call(points.back(),point)
			if not hit.is_empty():points.append(hit.position+hit.get("normal",Vector3.UP)*.04);break
		points.append(point)
	return points

static func point(path:Array,t:float)->Vector3:
	var f:float=clampf(t,0,1)*(path.size()-1)
	return Vector3(path[int(f)]).lerp(path[mini(int(f)+1,path.size()-1)],f-floorf(f))

static func request(ctx,p:Dictionary,payload:Dictionary)->bool:
	var item:=held(p)
	if item.is_empty() or not ctx.world_ready or not ctx.Melee.aiming(ctx,p) or p.sprint or p.reloading or p.fire_timer>0 or not p.get("pending_use",{}).is_empty():return false
	var target:Variant=payload.get("target")
	if not target is Vector3 or not target.is_finite() or ctx.state.field_effects.size()>=32:return false
	if item.kind=="smoke_grenade":
		var count:=0
		for effect in ctx.state.field_effects:
			if effect.kind=="smoke_grenade":count+=1
		if count>=8:return false
	var path:=arc(p,target,ctx.projectile_query)
	if not ctx.bounds.has_point(Vector2(path.back().x,path.back().z)):return false
	var duration:float=.55+Vector2(p.pos).distance_to(Vector2(path.back().x,path.back().z))*.055
	var uid:String="throw_%d"%ctx._next_uid;ctx._next_uid+=1
	ctx.state.field_effects.append({"uid":uid,"kind":item.kind,"owner":p.id,"owner_name":p.name,"world":ctx.state.world,"revision":ctx.state.world_revision,"pos":path[0],"path":path,"phase":"flight","age":-.22,"duration":duration,"ttl":duration+.22,"pulse":0.0})
	item.count-=1
	if item.count<=0:
		for i in p.bag.size():
			if p.bag[i].get("uid","")==item.uid:p.bag[i]={};break
	ctx._update_weight(p);p.fire_timer=.8;ctx._animate(p,"throw",.65)
	# Keep a visual copy during the release animation, even on the last item.
	p.throw_kind=item.kind
	return true

static func tick(ctx,dt:float)->void:
	for i in range(ctx.state.field_effects.size()-1,-1,-1):
		var effect:Dictionary=ctx.state.field_effects[i]
		if not is_throwable(effect.kind):
			effect.ttl-=dt
		elif effect.get("world","")!=ctx.state.world or effect.get("revision",ctx.state.world_revision)!=ctx.state.world_revision:
			effect.ttl=0.0
		elif effect.get("phase","")=="flight":
			effect.age+=dt;effect.ttl=maxf(0,effect.duration-effect.age)
			effect.pos=point(effect.path,effect.age/effect.duration)
			if effect.age>=effect.duration-.00001:
				effect.phase="active";effect.age=0.0;effect.ttl=DURATIONS[effect.kind]
				if effect.kind=="frag_grenade":damage(ctx,effect,65.0)
		else:
			var elapsed:float=minf(dt,float(effect.ttl))
			effect.ttl-=dt;effect.age=float(effect.get("age",0))+elapsed
			if effect.kind=="molotov":
				effect.pulse=float(effect.get("pulse",0))+elapsed
				if effect.pulse>=.5-.00001:damage(ctx,effect,12.0);effect.pulse-=.5
		if effect.ttl<=.00001:ctx.state.field_effects.remove_at(i)

static func reachable(ctx,effect:Dictionary,target:Dictionary)->bool:
	var at:Vector3=effect.pos
	var end:=Vector3(target.pos.x,float(target.get("height",0))+.6,target.pos.y)
	var delta:=Vector2(end.x-at.x,end.z-at.z)
	if delta.length()>RADIUS or absf(end.y-(at.y+.6))>1.5:return false
	for rect in ctx.obstacles:
		var hit:float=ctx._ray_rect(Vector2(at.x,at.z),delta.normalized(),rect)
		if hit>=0 and hit<delta.length()-.15:return false
	if ctx.projectile_query.is_valid():
		var hit:Dictionary=ctx.projectile_query.call(at+Vector3.UP*.25,end)
		if not hit.is_empty() and Vector3(hit.position).distance_to(end)>.2:return false
	return true

static func damage(ctx,effect:Dictionary,amount:float)->void:
	var candidates:Array=ctx.state.targets.duplicate()
	candidates.append_array(ctx.state.get("enemies",{}).values())
	for target in candidates:
		if int(target.hp)<=0 or not reachable(ctx,effect,target):continue
		if not target.get("invulnerable",false):target.hp=maxi(0,int(target.hp)-int(amount))
		target.hits=int(target.get("hits",0))+1
	if ctx.state.world=="bunker":return
	for member in ctx.state.players.values():
		if not ctx.Souls.mobile(member) or not reachable(ctx,effect,member):continue
		member.hp=maxf(0,float(member.hp)-amount);ctx.mark_player_hurt(member);ctx.Souls.reconcile(ctx,member)
