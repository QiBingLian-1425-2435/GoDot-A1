extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _reload(ctx, p: Dictionary) -> bool:
	var weapon: Dictionary = p.equipment.weapon
	if weapon.is_empty() or p.reloading: return false
	if p.ammo >= int(ctx.Items.definition(weapon.kind).get("magazine",30)): return ctx._reject("⟦combat_system.001⟧")
	if not ctx.state.get("infinite_reserve",false) and ctx._count(p.bag,"ammo") <= 0: return ctx._reject("⟦combat_system.002⟧")
	var reload_time := float(ctx.Items.definition(weapon.kind).get("reload_time",1.6))
	p.reloading = true; p.reload_timer = reload_time; p.reload_progress = 0.0
	return true

static func _fire(ctx, p: Dictionary) -> bool:
	var weapon: Dictionary = p.equipment.weapon
	if weapon.is_empty() or p.reloading or p.fire_timer > 0: return false
	if p.ammo <= 0: return _reload(ctx, p)
	p.ammo -= 1; p.magazines[weapon.uid] = p.ammo; p.shots += 1
	p.fire_timer = float(ctx.Items.definition(weapon.kind).get("fire_interval",0.16))
	var origin: Vector2 = p.pos
	var direction: Vector2 = p.aim
	var distance = 22.0
	var impact := "none"
	var height := float(p.get("height",0))+.9
	if ctx.shot_query.is_valid():
		var start := Vector3(origin.x,height,origin.y)
		var result: Dictionary = ctx.shot_query.call(start,start+Vector3(direction.x,0,direction.y)*distance)
		if not result.is_empty():
			distance = start.distance_to(result.position)
			impact = "wall"
	for rect in ctx.obstacles:
		var hit = ctx._ray_rect(origin,direction,rect)
		if hit >= 0 and hit < distance:
			distance = hit; impact = "wall"
	var chosen: Dictionary = {}
	var candidates:Array=ctx.state.targets.duplicate()
	candidates.append_array(ctx.state.get("enemies",{}).values())
	for target in candidates:
		if int(target.get("hp",0)) <= 0: continue
		if absf(float(target.get("height",0))+.9-height)>.7:continue
		var offset: Vector2 = target.pos - origin
		var along = offset.dot(direction)
		if along > 0 and along < distance and absf(offset.cross(direction)) <= 0.55:
			distance = along; chosen = target; impact = "target"
	# Exploration friendly fire uses host positions and the same world occlusion.
	var teammate: Dictionary = {}
	if ctx.state.get("world","bunker")!="bunker":
		for member in ctx.state.players.values():
			if member.id==p.id or not ctx.Souls.mobile(member): continue
			if absf(float(member.get("height",0))+.9-height)>.8: continue
			var offset: Vector2 = Vector2(member.pos)-origin
			var along: float = offset.dot(direction)
			var side: float = absf(offset.cross(direction))
			if along<=0 or side>ctx.PLAYER_RADIUS: continue
			var hit: float = maxf(0,along-sqrt(ctx.PLAYER_RADIUS*ctx.PLAYER_RADIUS-side*side))
			if hit<distance:
				distance=hit;teammate=member;impact="player"
	if not teammate.is_empty():
		var damage := float(ctx.Items.definition(weapon.kind).get("damage",20))
		if ctx.Souls.zombie(teammate): ctx.Souls.die(ctx,teammate)
		else:
			teammate.hp=maxf(0,float(teammate.hp)-damage)
			ctx.Souls.reconcile(ctx,teammate)
	elif not chosen.is_empty():
		chosen.hp = maxi(0,int(chosen.hp) - int(ctx.Items.definition(weapon.kind).get("damage",20)))
		chosen.hits = int(chosen.get("hits",0)) + 1
		if ctx.state.get("enemies",{}).get(chosen.get("id",-1),{})==chosen:
			ctx.Enemies.hit(chosen,direction)
	ctx.state.shots.append({"from":origin,"to":origin + direction * distance,"height":height,"player_id":p.id,"sequence":p.shots,"weapon":weapon.kind,"impact":impact,"target_id":chosen.get("id",-1) if teammate.is_empty() else -1,"hit_player_id":teammate.get("id",0),"ttl":0.16})
	return true

static func _ray_rect(ctx, origin: Vector2, direction: Vector2, rect: Rect2) -> float:
	var near = 0.0
	var far = 1000.0
	for axis in range(2):
		if absf(direction[axis]) < 0.00001:
			if origin[axis] < rect.position[axis] or origin[axis] > rect.end[axis]: return -1
		else:
			var a = (rect.position[axis] - origin[axis]) / direction[axis]
			var b = (rect.end[axis] - origin[axis]) / direction[axis]
			near = maxf(near,minf(a,b)); far = minf(far,maxf(a,b))
			if near > far: return -1
	return near
