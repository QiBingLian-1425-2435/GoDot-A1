extends RefCounted
# The legacy roll field is retained for saved input bindings and packet layout.
# Protocol v19 interprets it as a physical jump, never a dodge roll.
const JUMP_SPEED := 5.0
const JUMP_GRAVITY := 18.0
const JUMP_COST := 15.0
const JUMP_COOLDOWN := .7
const HIT_SPEED := 5.5
const HIT_DECELERATION := 22.0

static func hit(p:Dictionary,direction:Vector2) -> void:
	if float(p.get("hp",0))<=0:return
	p.knockback=direction.normalized()*HIT_SPEED
	p.hit_seq=(int(p.get("hit_seq",0))+1)%65536

static func _recoil(p:Dictionary,delta:float)->Vector2:
	var speed:Vector2=p.get("knockback",Vector2.ZERO)
	var duration:float=minf(delta,speed.length()/HIT_DECELERATION)
	var next:Vector2=speed.move_toward(Vector2.ZERO,HIT_DECELERATION*duration)
	p.knockback=next
	return (speed+next)*.5*duration

static func empty_roll() -> Dictionary:
	return {"active":false,"time":0.0,"direction":Vector2.ZERO,"cooldown":0.0,"seen":0}

## Shared movement math only. The supplied solver owns collision; no inventory/actions here.
static func step(p: Dictionary, input: Dictionary, delta: float, solver: Callable) -> void:
	if p.get("life","")=="soul":
		if int(p.get("possessing",0))>0:
			p.velocity=Vector2.ZERO;p.sprint=false;p.crouch=false;p.ads=false;p.roll=empty_roll()
			return
		var direction: Vector2 = Vector2(input.get("direction",Vector2.ZERO)).limit_length(1)
		var speed: int = int(p.get("soul_speed",2))
		if speed not in [2,4,6,8]:speed=2
		var previous: Vector2 = p.pos
		var next: Vector2 = previous+direction*3.7*speed*delta
		var bounds: Rect2 = p.get("soul_bounds",Rect2(-10000,-10000,20000,20000))
		next=next.clamp(bounds.position,bounds.end)
		var solved: Variant = solver.call(previous,next-previous)
		if solved is Vector3:p.pos=Vector2(solved.x,solved.z);p.height=solved.y
		else:p.pos=solved
		p.velocity=(Vector2(p.pos)-previous)/maxf(delta,.000001)
		p.sprint=false;p.crouch=false;p.ads=false;p.roll=empty_roll()
		return
	if float(p.get("hp",100))<=0 and p.get("life","alive")!="zombie":
		p.velocity = Vector2.ZERO; p.sprint = false; p.crouch = false; p.ads = false
		p.roll = empty_roll()
		p.knockback=Vector2.ZERO
		return
	var direction: Vector2 = input.get("direction",Vector2.ZERO)
	var recoiling:bool=not Vector2(p.get("knockback",Vector2.ZERO)).is_zero_approx()
	var recoil:Vector2=_recoil(p,delta)
	if recoiling:direction=Vector2.ZERO
	if not p.has("roll"): p.roll = empty_roll()
	var roll: Dictionary = p.roll
	roll.cooldown = maxf(0, float(roll.cooldown)-delta)
	var requested := int(input.get("roll_seq",0))
	if requested > int(roll.seen):
		roll.seen = requested
		if not recoiling and not roll.active and roll.cooldown <= 0 and (p.stamina >= JUMP_COST or p.get("infinite_stamina",false)) and not p.get("reloading",false) and p.get("pending_use",{}).is_empty() and str(p.get("loot_uid","")).is_empty() and float(p.get("hp",100)) > 0:
			roll.active = true; roll.time = 0.0; roll.cooldown = JUMP_COOLDOWN
			roll.direction=direction
			if not p.get("infinite_stamina",false): p.stamina -= JUMP_COST
	if roll.active:
		var previous:Vector2=p.pos
		var old_height:=float(p.get("height",0))
		var old_time:=float(roll.time)
		roll.time=minf(30.0,old_time+delta)
		var vertical:float=JUMP_SPEED*delta-JUMP_GRAVITY*(old_time*delta+.5*delta*delta)
		roll.vertical_delta=vertical
		roll.direction=direction
		var speed:=3.7
		if p.weight>p.max_weight:speed*=clampf(p.max_weight/p.weight,.3,1.0)
		var solved:Variant=solver.call(previous,direction*speed*delta+recoil)
		if solved is Vector3:
			p.pos=Vector2(solved.x,solved.z);p.height=solved.y
		else:
			p.pos=solved;p.height=maxf(0.0,old_height+vertical)
		if vertical<0 and float(p.height)>old_height+vertical+.001:
			roll.active=false
		elif vertical>0 and float(p.height)<old_height+vertical-.001:
			# A ceiling cancels upward velocity immediately.
			roll.time=maxf(roll.time,JUMP_SPEED/JUMP_GRAVITY)
		p.velocity=(Vector2(p.pos)-previous)/delta
		p.aim=input.get("aim",p.aim);p.sprint=false;p.crouch=false;p.ads=false
		return
	p.crouch = bool(input.get("crouch",false))
	p.ads = bool(input.get("ads",false))
	var sprint_requested := bool(input.get("sprint",false))
	var exhausted_this_step := false
	if p.get("infinite_stamina",false): p.stamina = float(p.get("max_stamina",100))
	if not sprint_requested: p.sprint_exhausted = false
	# A normal run can end the previous frame between 0 and the 1-point sprint
	# threshold. Treat that state as exhaustion too; otherwise held Shift keeps
	# spending each tiny recovery pulse and the stamina bar appears frozen.
	if not p.get("infinite_stamina",false) and sprint_requested and not bool(p.get("sprint_exhausted",false)) and not direction.is_zero_approx() and p.stamina <= 1.0:
		p.stamina = 0.0
		p.sprint_exhausted = true
		exhausted_this_step = true
	if sprint_requested and not bool(p.get("sprint_exhausted",false)) and not p.crouch and not p.ads and (p.stamina > 1.0 or p.get("infinite_stamina",false)) and not direction.is_zero_approx():
		var sprint_cost := delta*19.0
		if not p.get("infinite_stamina",false) and p.stamina <= sprint_cost:
			p.stamina = 0.0
			p.sprint_exhausted = true
			exhausted_this_step = true
		p.sprint = not bool(p.get("sprint_exhausted",false))
	else:
		p.sprint = false
	var speed := 3.7
	if p.sprint:
		speed *= 1.65
		if p.get("infinite_stamina",false): p.stamina = float(p.get("max_stamina",100))
		else: p.stamina -= delta*19.0
	elif not exhausted_this_step: p.stamina = minf(float(p.get("max_stamina",100)),p.stamina+delta*12)
	if p.crouch: speed *= .48
	if p.ads: speed *= .62
	if p.weight > p.max_weight: speed *= clampf(p.max_weight/p.weight,.3,1.0)
	var previous: Vector2 = p.pos
	var solved: Variant = solver.call(previous,direction*speed*delta+recoil)
	if solved is Vector3:
		p.pos = Vector2(solved.x,solved.z)
		p.height = solved.y
	else: p.pos = solved
	p.velocity = (Vector2(p.pos)-previous)/delta
	var aim: Vector2 = input.get("aim",p.get("aim",Vector2.UP))
	if aim.length_squared() > .001: p.aim = aim.normalized()

