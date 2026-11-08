extends RefCounted
## Host-only swing timing and front-arc hits. Animation never decides damage.
const Sweep=preload("res://features/combat/melee_sweep.gd")
const Items=preload("res://features/inventory/item_catalog.gd")

static func is_melee(kind:String)->bool:
	return bool(Items.definition(kind).get("melee",false))

static func cancel(p:Dictionary)->void:
	p.erase("melee_attack");p.erase("melee_buffer")

static func aiming(ctx,p:Dictionary)->bool:
	var input:Dictionary=ctx._inputs.get(p.id,{})
	return bool(input.get("ads",false)) and ctx._clock-float(input.get("stamp",-100))<=ctx.INPUT_TIMEOUT

static func request(ctx,p:Dictionary)->bool:
	var weapon:Dictionary=p.equipment.weapon
	if weapon.is_empty() or not is_melee(weapon.kind) or not p.get("pending_use",{}).is_empty() or not aiming(ctx,p):return false
	if float(p.fire_timer)>0 or not p.get("melee_attack",{}).is_empty():return false
	var duration:float=Items.definition(weapon.kind).fire_interval
	p.melee_chain=int(p.get("melee_chain",0))+1
	p.melee_attack={"uid":weapon.uid,"kind":weapon.kind,"elapsed":0.0,"hits":{},"world":ctx.state.world,"revision":ctx.state.world_revision}
	p.fire_timer=duration
	ctx._animate(p,"melee_swing",duration)
	return true

static func tick(ctx,p:Dictionary,dt:float)->void:
	var attack:Dictionary=p.get("melee_attack",{})
	if not ctx.Souls.alive(p) or p.get("roll",{}).get("active",false) or not ctx.world_ready:
		cancel(p);return
	if not attack.is_empty():
		if p.equipment.weapon.get("uid","")!=attack.uid or ctx.state.world!=attack.world or ctx.state.world_revision!=attack.revision or not p.get("pending_use",{}).is_empty() or p.get("anim_action","")!="melee_swing":
			cancel(p);return
		var duration:float=Items.definition(attack.kind).fire_interval
		var previous:float=float(attack.elapsed)/duration
		attack.elapsed+=dt
		var phase:float=float(attack.elapsed)/duration
		if phase>=Sweep.START and previous<=Sweep.END:
			_strike(ctx,p,attack,minf(phase,Sweep.END))
		if phase>=1.0:p.erase("melee_attack")

static func _reachable(ctx,p:Dictionary,target:Dictionary,kind:String,phase:float)->bool:
	var offset:Vector2=target.pos-p.pos
	var distance:float=offset.length()
	var local_offset:Vector2=offset.rotated(-atan2(p.aim.x,-p.aim.y))
	if not Sweep.contains(local_offset,kind,phase):return false
	if absf(float(target.get("height",0))-float(p.get("height",0)))>.8:return false
	var direction:=offset/distance
	for rect in ctx.obstacles:
		var hit:float=ctx._ray_rect(p.pos,direction,rect)
		if hit>=0 and hit<distance-.15:return false
	if ctx.shot_query.is_valid():
		var start:=Vector3(p.pos.x,float(p.get("height",0))+Sweep.height(p.get("crouch",false)),p.pos.y)
		var end:=Vector3(target.pos.x,float(target.get("height",0))+Sweep.height(p.get("crouch",false)),target.pos.y)
		var wall:Dictionary=ctx.shot_query.call(start,end)
		if not wall.is_empty() and start.distance_to(wall.position)<start.distance_to(end)-.15:return false
	return true

static func _strike(ctx,p:Dictionary,attack:Dictionary,phase:float)->void:
	var kind:String=attack.kind
	var info:Dictionary=Items.definition(kind)
	var candidates:Array=ctx.state.targets.duplicate()
	candidates.append_array(ctx.state.get("enemies",{}).values())
	for target in candidates:
		var key:String=("enemy:" if ctx.state.get("enemies",{}).get(target.get("id",-1),{})==target else "target:")+str(target.get("id",-1))
		if attack.hits.has(key) or int(target.get("hp",0))<=0 or not _reachable(ctx,p,target,kind,phase):continue
		attack.hits[key]=true
		if not target.get("invulnerable",false):target.hp=maxi(0,int(target.hp)-int(info.damage))
		target.hits=int(target.get("hits",0))+1
		if ctx.state.get("enemies",{}).get(target.get("id",-1),{})==target:ctx.Enemies.hit(target,p.aim)
	if ctx.state.world=="bunker":return
	for member in ctx.state.players.values():
		var key:String="player:"+str(member.id)
		if attack.hits.has(key) or member.id==p.id or not ctx.Souls.mobile(member) or not _reachable(ctx,p,member,kind,phase):continue
		attack.hits[key]=true
		if ctx.Souls.zombie(member):ctx.Souls.die(ctx,member)
		else:
			member.hp=maxf(0,float(member.hp)-float(info.damage))
			ctx.Souls.reconcile(ctx,member);ctx.Movement.hit(member,p.aim)
