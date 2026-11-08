extends RefCounted
## Host-only swing timing and front-arc hits. Animation never decides damage.
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
	if float(p.fire_timer)>0:
		# One buffered click near recovery; repeated requests cannot stack damage.
		if not p.get("melee_attack",{}).is_empty() and float(p.fire_timer)<=.24:
			p.melee_buffer={"uid":weapon.uid,"expires":ctx._clock+.3};return true
		return false
	var duration:float=Items.definition(weapon.kind).fire_interval
	p.melee_chain=int(p.get("melee_chain",0))+1
	p.melee_attack={"uid":weapon.uid,"kind":weapon.kind,"elapsed":0.0,"hit":false,"world":ctx.state.world,"revision":ctx.state.world_revision}
	p.fire_timer=duration
	ctx._animate(p,"melee_forward" if int(p.melee_chain)%2==1 else "melee_back",duration)
	return true

static func tick(ctx,p:Dictionary,dt:float)->void:
	var attack:Dictionary=p.get("melee_attack",{})
	if not aiming(ctx,p):p.erase("melee_buffer")
	if not ctx.Souls.alive(p) or p.get("roll",{}).get("active",false) or not ctx.world_ready:
		cancel(p);return
	if not attack.is_empty():
		if p.equipment.weapon.get("uid","")!=attack.uid or ctx.state.world!=attack.world or ctx.state.world_revision!=attack.revision or not p.get("pending_use",{}).is_empty() or p.get("anim_action","") not in ["melee_forward","melee_back"]:
			cancel(p);return
		attack.elapsed+=dt
		var duration:float=Items.definition(attack.kind).fire_interval
		if not attack.hit and float(attack.elapsed)>=duration*.42:
			attack.hit=true;_strike(ctx,p,attack.kind)
		if float(attack.elapsed)>=duration:p.erase("melee_attack")
	var queued:Dictionary=p.get("melee_buffer",{})
	if not queued.is_empty():
		if float(queued.expires)<ctx._clock or p.equipment.weapon.get("uid","")!=queued.uid:p.erase("melee_buffer")
		elif p.get("melee_attack",{}).is_empty() and float(p.fire_timer)<=0:
			p.erase("melee_buffer");request(ctx,p)

static func _reachable(ctx,p:Dictionary,target:Dictionary,reach:float)->bool:
	var offset:Vector2=target.pos-p.pos
	var distance:float=offset.length()
	if distance>reach or distance<.001 or offset.normalized().dot(p.aim)<.5:return false
	if absf(float(target.get("height",0))-float(p.get("height",0)))>.8:return false
	var direction:=offset/distance
	for rect in ctx.obstacles:
		var hit:float=ctx._ray_rect(p.pos,direction,rect)
		if hit>=0 and hit<distance-.15:return false
	if ctx.shot_query.is_valid():
		var start:=Vector3(p.pos.x,float(p.get("height",0))+.9,p.pos.y)
		var end:=Vector3(target.pos.x,float(target.get("height",0))+.9,target.pos.y)
		var wall:Dictionary=ctx.shot_query.call(start,end)
		if not wall.is_empty() and start.distance_to(wall.position)<start.distance_to(end)-.15:return false
	return true

static func _strike(ctx,p:Dictionary,kind:String)->void:
	var info:Dictionary=Items.definition(kind)
	var candidates:Array=ctx.state.targets.duplicate()
	candidates.append_array(ctx.state.get("enemies",{}).values())
	for target in candidates:
		if int(target.get("hp",0))<=0 or not _reachable(ctx,p,target,float(info.reach)):continue
		if not target.get("invulnerable",false):target.hp=maxi(0,int(target.hp)-int(info.damage))
		target.hits=int(target.get("hits",0))+1
		if ctx.state.get("enemies",{}).get(target.get("id",-1),{})==target:ctx.Enemies.hit(target,p.aim)
	if ctx.state.world=="bunker":return
	for member in ctx.state.players.values():
		if member.id==p.id or not ctx.Souls.mobile(member) or not _reachable(ctx,p,member,float(info.reach)):continue
		if ctx.Souls.zombie(member):ctx.Souls.die(ctx,member)
		else:
			member.hp=maxf(0,float(member.hp)-float(info.damage))
			ctx.Souls.reconcile(ctx,member);ctx.Movement.hit(member,p.aim)
