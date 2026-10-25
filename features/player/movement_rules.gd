extends RefCounted
const ROLL_DURATION := .65
const ROLL_DISTANCE := 3.0
const ROLL_COST := 20.0
const ROLL_COOLDOWN := 1.0

static func empty_roll() -> Dictionary:
	return {"active":false,"time":0.0,"direction":Vector2.UP,"cooldown":0.0,"seen":0}

static func roll_curve(t: float) -> float:
	return t*t*(3.0-2.0*t)
## Shared movement math only. The supplied solver owns collision; no inventory/actions here.
static func step(p: Dictionary, input: Dictionary, delta: float, solver: Callable) -> void:
	var direction: Vector2 = input.get("direction",Vector2.ZERO)
	if not p.has("roll"): p.roll = empty_roll()
	var roll: Dictionary = p.roll
	roll.cooldown = maxf(0, float(roll.cooldown)-delta)
	var requested := int(input.get("roll_seq",0))
	if requested > int(roll.seen):
		roll.seen = requested
		if not roll.active and roll.cooldown <= 0 and p.stamina >= ROLL_COST and not p.get("reloading",false) and p.get("pending_use",{}).is_empty() and str(p.get("loot_uid","")).is_empty() and float(p.get("hp",100)) > 0:
			roll.active = true; roll.time = 0.0; roll.cooldown = ROLL_COOLDOWN
			var roll_direction:Vector2=input.get("roll_direction",direction)
			roll.direction = roll_direction.normalized() if not roll_direction.is_zero_approx() else Vector2(input.get("aim",p.get("aim",Vector2.UP))).normalized()
			if Vector2(roll.direction).is_zero_approx(): roll.direction = Vector2.UP
			p.stamina -= ROLL_COST
	if roll.active:
		var previous: Vector2 = p.pos
		var old_time: float = roll.time
		roll.time = minf(ROLL_DURATION, old_time+delta)
		var distance := ROLL_DISTANCE*(roll_curve(roll.time/ROLL_DURATION)-roll_curve(old_time/ROLL_DURATION))
		var solved: Variant = solver.call(previous,Vector2(roll.direction)*distance)
		if solved is Vector3: p.pos = Vector2(solved.x,solved.z); p.height = solved.y
		else: p.pos = solved
		p.velocity = (Vector2(p.pos)-previous)/delta
		p.aim = roll.direction; p.sprint = false; p.crouch = false; p.ads = false
		if roll.time >= ROLL_DURATION: roll.active = false
		return
	p.crouch = bool(input.get("crouch",false))
	p.ads = bool(input.get("ads",false))
	var sprint_requested := bool(input.get("sprint",false))
	var exhausted_this_step := false
	if not sprint_requested: p.sprint_exhausted = false
	# A normal run can end the previous frame between 0 and the 1-point sprint
	# threshold. Treat that state as exhaustion too; otherwise held Shift keeps
	# spending each tiny recovery pulse and the stamina bar appears frozen.
	if sprint_requested and not bool(p.get("sprint_exhausted",false)) and not direction.is_zero_approx() and p.stamina <= 1.0:
		p.stamina = 0.0
		p.sprint_exhausted = true
		exhausted_this_step = true
	if sprint_requested and not bool(p.get("sprint_exhausted",false)) and not p.crouch and not p.ads and p.stamina > 1.0 and not direction.is_zero_approx():
		var sprint_cost := delta*19.0
		if p.stamina <= sprint_cost:
			p.stamina = 0.0
			p.sprint_exhausted = true
			exhausted_this_step = true
		p.sprint = not bool(p.get("sprint_exhausted",false))
	else:
		p.sprint = false
	var speed := 3.7
	if p.sprint: speed *= 1.65; p.stamina -= delta*19.0
	elif not exhausted_this_step: p.stamina = minf(100,p.stamina+delta*12)
	if p.crouch: speed *= .48
	if p.ads: speed *= .62
	if p.weight > p.max_weight: speed *= clampf(p.max_weight/p.weight,.3,1.0)
	var previous: Vector2 = p.pos
	var solved: Variant = solver.call(previous,direction*speed*delta)
	if solved is Vector3:
		p.pos = Vector2(solved.x,solved.z)
		p.height = solved.y
	else: p.pos = solved
	p.velocity = (Vector2(p.pos)-previous)/delta
	var aim: Vector2 = input.get("aim",p.get("aim",Vector2.UP))
	if aim.length_squared() > .001: p.aim = aim.normalized()

