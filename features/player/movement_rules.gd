extends RefCounted
# The legacy roll field is retained for saved input bindings and packet layout.
# Protocol v19 interprets it as a physical jump, never a dodge roll.
const JUMP_SPEED := 5.0
const JUMP_GRAVITY := 18.0
const JUMP_COST := 15.0
const JUMP_COOLDOWN := .7
const JUMP_CHAIN_WINDOW := .18
const JUMP_BUFFER_WINDOW := .28
const JUMP_CHAIN_MAX := 4
const JUMP_CHAIN_HEIGHT_BONUS := .045
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
	return {"active":false,"time":0.0,"direction":Vector2.ZERO,"cooldown":0.0,"seen":0,"chain":0,"chain_window":0.0,"takeoff_speed":3.7,"jump_speed":JUMP_SPEED,"chain_eligible":false,"buffered":false,"buffer_time":0.0,"buffer_reward":false}

static func _weight_factor(p:Dictionary)->float:
	return clampf(float(p.max_weight)/float(p.weight),.3,1.0) if p.weight>p.max_weight else 1.0

static func _can_sprint_jump(p:Dictionary,input:Dictionary,direction:Vector2)->bool:
	return bool(input.get("sprint",false)) and not bool(p.get("sprint_exhausted",false)) and not bool(input.get("crouch",false)) and not bool(input.get("ads",false)) and not direction.is_zero_approx() and (float(p.stamina)>JUMP_COST or p.get("infinite_stamina",false))

static func _start_jump(p:Dictionary,roll:Dictionary,input:Dictionary,direction:Vector2,continue_chain:bool,chain_delta:int=0)->void:
	var sprint_jump:=_can_sprint_jump(p,input,direction)
	if continue_chain and sprint_jump:
		if chain_delta < 0:
			roll.chain = 0
		elif chain_delta > 0:
			roll.chain = clampi(int(roll.get("chain",0))+chain_delta,0,JUMP_CHAIN_MAX)
		# chain_delta == 0 preserves the current tier for forgiving late input.
	else:
		roll.chain = 0
	roll.active=true;roll.time=0.0;roll.cooldown=JUMP_COOLDOWN
	roll.direction=direction;roll.chain_window=0.0;roll.chain_eligible=sprint_jump
	roll.buffered=false;roll.buffer_time=0.0;roll.buffer_reward=false
	var bonus_scale:=clampf(float(p.get("jump_chain_bonus",150))/100.0,1.0,2.0)
	var weight_factor:=_weight_factor(p)
	var base_speed:=3.7*(1.65 if sprint_jump else 1.0)*weight_factor
	var max_speed:=maxf(base_speed,float(p.get("jump_chain_max_speed",18))*weight_factor)
	var progress:=minf(1.0,float(roll.chain)/float(JUMP_CHAIN_MAX)*bonus_scale)
	roll.takeoff_speed=lerpf(base_speed,max_speed,progress)
	roll.jump_speed=JUMP_SPEED*(1.0+float(roll.chain)*JUMP_CHAIN_HEIGHT_BONUS*bonus_scale)
	if not p.get("infinite_stamina",false):p.stamina-=JUMP_COST

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
	roll.chain_window=maxf(0.0,float(roll.get("chain_window",0.0))-delta)
	roll.buffer_time=maxf(0.0,float(roll.get("buffer_time",0.0))-delta)
	if roll.buffer_time<=0.0:roll.buffered=false
	if not roll.active and int(roll.get("chain",0))>0 and (roll.chain_window<=0.0 or not _can_sprint_jump(p,input,direction)):
		roll.chain=0
		roll.chain_eligible=false
	var requested := int(input.get("roll_seq",0))
	if requested > int(roll.seen):
		roll.seen = requested
		var in_chain_window:=bool(roll.get("chain_eligible",false)) and float(roll.get("chain_window",0.0))>0.0
		if not recoiling and not roll.active and (roll.cooldown <= 0 or in_chain_window) and (p.stamina >= JUMP_COST or p.get("infinite_stamina",false)) and not p.get("reloading",false) and p.get("pending_use",{}).is_empty() and str(p.get("loot_uid","")).is_empty() and float(p.get("hp",100)) > 0:
			# A late grounded press keeps the current tier for forgiving continuity,
			# but only a precise pre-landing press can increase it.
			_start_jump(p,roll,input,direction,in_chain_window,0)
		elif roll.active and float(roll.get("time",0.0))>=float(roll.get("jump_speed",JUMP_SPEED))/JUMP_GRAVITY and _can_sprint_jump(p,input,direction):
			# Any late descent press can buffer continuity. Only the configurable
			# final timing window grants a tier; an earlier buffer drops one tier.
			var remaining:=maxf(0.0,float(roll.get("jump_speed",JUMP_SPEED))*2.0/JUMP_GRAVITY-float(roll.time))
			roll.buffered=true;roll.buffer_time=JUMP_BUFFER_WINDOW
			roll.buffer_reward=remaining<=float(p.get("jump_reward_window_ms",70))/1000.0
	if roll.active:
		var previous:Vector2=p.pos
		var old_height:=float(p.get("height",0))
		var old_time:=float(roll.time)
		roll.time=minf(30.0,old_time+delta)
		var jump_speed:float=float(roll.get("jump_speed",JUMP_SPEED))
		var vertical:float=jump_speed*delta-JUMP_GRAVITY*(old_time*delta+.5*delta*delta)
		roll.vertical_delta=vertical
		roll.direction=direction
		var speed:float=float(roll.get("takeoff_speed",3.7))
		var solved:Variant=solver.call(previous,direction*speed*delta+recoil)
		if solved is Vector3:
			p.pos=Vector2(solved.x,solved.z);p.height=solved.y
		else:
			p.pos=solved;p.height=maxf(0.0,old_height+vertical)
		if vertical<0 and float(p.height)>old_height+vertical+.001:
			roll.active=false
			roll.chain_window=JUMP_CHAIN_WINDOW if bool(roll.get("chain_eligible",false)) else 0.0
			if bool(roll.get("buffered",false)) and roll.buffer_time>0.0 and _can_sprint_jump(p,input,direction) and (p.stamina>=JUMP_COST or p.get("infinite_stamina",false)):
				_start_jump(p,roll,input,direction,true,1 if bool(roll.get("buffer_reward",false)) else -1)
		elif vertical>0 and float(p.height)<old_height+vertical-.001:
			# A ceiling cancels upward velocity immediately.
			roll.time=maxf(roll.time,jump_speed/JUMP_GRAVITY)
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

