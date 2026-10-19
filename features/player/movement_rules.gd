extends RefCounted
## Shared movement math only. The supplied solver owns collision; no inventory/actions here.
static func step(p: Dictionary, input: Dictionary, delta: float, solver: Callable) -> void:
	var direction: Vector2 = input.get("direction",Vector2.ZERO)
	p.crouch = bool(input.get("crouch",false))
	p.ads = bool(input.get("ads",false))
	p.sprint = bool(input.get("sprint",false)) and not p.crouch and not p.ads and p.stamina > 1.0 and not direction.is_zero_approx()
	var speed := 3.7
	if p.sprint: speed *= 1.65; p.stamina = maxf(0,p.stamina-delta*19)
	else: p.stamina = minf(100,p.stamina+delta*12)
	if p.crouch: speed *= .48
	if p.ads: speed *= .62
	if p.weight > p.max_weight: speed *= clampf(p.max_weight/p.weight,.3,1.0)
	var previous: Vector2 = p.pos
	p.pos = solver.call(previous,direction*speed*delta)
	p.velocity = (Vector2(p.pos)-previous)/delta
	var aim: Vector2 = input.get("aim",p.get("aim",Vector2.UP))
	if aim.length_squared() > .001: p.aim = aim.normalized()
