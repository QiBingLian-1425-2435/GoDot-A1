extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _reload(ctx, p: Dictionary) -> bool:
	var weapon: Dictionary = p.equipment.weapon
	if weapon.is_empty() or p.reloading: return false
	if p.ammo >= int(ctx.Items.definition(weapon.kind).get("magazine",30)): return ctx._reject("弹匣已满")
	if ctx._count(p.bag,"ammo") <= 0: return ctx._reject("背包里没有弹药")
	p.reloading = true; p.reload_timer = 1.6; p.reload_progress = 0.0
	return true

static func _fire(ctx, p: Dictionary) -> bool:
	var weapon: Dictionary = p.equipment.weapon
	if weapon.is_empty() or p.reloading or p.fire_timer > 0: return false
	if p.ammo <= 0: return ctx._reject("弹匣已空，按R装填")
	p.ammo -= 1; p.magazines[weapon.uid] = p.ammo; p.shots += 1; p.fire_timer = 0.16
	var origin: Vector2 = p.pos
	var direction: Vector2 = p.aim
	var distance = 22.0
	for rect in ctx.obstacles:
		var hit = ctx._ray_rect(origin,direction,rect)
		if hit >= 0: distance = minf(distance,hit)
	var chosen: Dictionary = {}
	for target in ctx.state.targets:
		if int(target.get("hp",0)) <= 0: continue
		var offset: Vector2 = target.pos - origin
		var along = offset.dot(direction)
		if along > 0 and along < distance and absf(offset.cross(direction)) <= 0.55:
			distance = along; chosen = target
	if not chosen.is_empty():
		chosen.hp = maxi(0,int(chosen.hp) - int(ctx.Items.definition(weapon.kind).get("damage",20)))
		chosen.hits = int(chosen.get("hits",0)) + 1
	ctx.state.shots.append({"from":origin,"to":origin + direction * distance,"player_id":p.id,"ttl":0.16})
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
