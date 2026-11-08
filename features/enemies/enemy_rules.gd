extends RefCounted
## Shared enemy/health state is advanced only by the authoritative BaseModel.
const SIGHT_RANGE := 12.0
const SPEED := 4.6
const REACH := 1.35
const DAMAGE := 18.0
const WINDUP := .45
const RECOVERY := .85
const HIT_SPEED := 5.5
const HIT_DECELERATION := 22.0
const HIT_DURATION := .25

static func hit(enemy:Dictionary,direction:Vector2,melee:bool=false) -> void:
	enemy.hurt_sound_seq=(int(enemy.get("hurt_sound_seq",0))+1)%65536
	enemy.hurt_sound_melee=melee
	if enemy.hp<=0 or enemy.get("kind","")=="sick_ghost":return
	enemy.knockback=direction.normalized()*HIT_SPEED if melee or enemy.get("kind","")!="zombie" else Vector2.ZERO
	enemy.mode="stagger";enemy.timer=HIT_DURATION

static func _push(ctx,enemy:Dictionary,delta:float) -> void:
	var velocity:Vector2=enemy.get("knockback",Vector2.ZERO)
	var duration:float=minf(delta,velocity.length()/HIT_DECELERATION)
	var next:Vector2=velocity.move_toward(Vector2.ZERO,HIT_DECELERATION*duration)
	var offset:Vector2=(velocity+next)*.5*duration
	enemy.knockback=next
	if not ctx.enemy_push.is_valid():return
	var before:=at(enemy)
	var moved:Vector3=ctx.enemy_push.call(int(enemy.id),before,offset)
	enemy.pos=Vector2(moved.x,moved.z);enemy.height=moved.y
	enemy.velocity=(Vector2(enemy.pos)-Vector2(before.x,before.z))/maxf(delta,.001)

static func create(id: int, at: Vector3, facing: Vector2) -> Dictionary:
	return {"id":id,"pos":Vector2(at.x,at.z),"height":at.y,"home":at,"aim":facing.normalized(),"velocity":Vector2.ZERO,"hp":100,"max_hp":100,"mode":"idle","target":0,"last_seen":at,"memory":0.0,"timer":0.0,"attack_seq":0}

static func create_sick(id:int, position:Vector3, facing:Vector2)->Dictionary:
	var enemy:=create(id,position,facing)
	enemy.kind="sick_ghost"
	enemy.invulnerable=true
	return enemy

static func create_zombie(id:int,position:Vector3,facing:Vector2)->Dictionary:
	var enemy:=create(id,position,facing)
	enemy.kind="zombie"
	return enemy

static func at(p: Dictionary) -> Vector3:
	return Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)

static func visible(ctx, enemy: Dictionary, player: Dictionary) -> bool:
	if not ctx.Souls.alive(player):return false
	var offset: Vector2=player.pos-enemy.pos
	if offset.length()>SIGHT_RANGE or absf(at(player).y-at(enemy).y)>2.0:return false
	# Nearby movement can be noticed; farther targets must be in front (140 degrees).
	if offset.length()>2 and Vector2(enemy.aim).dot(offset.normalized())<cos(deg_to_rad(70)):return false
	return clear_sight(ctx,at(enemy),at(player))

static func clear_sight(ctx, from: Vector3, to: Vector3) -> bool:
	if ctx.FieldItems.blocks_sight(ctx.state.get("field_effects",[]),from+Vector3.UP,to+Vector3.UP):return false
	return ctx.enemy_sight.is_valid() and ctx.enemy_sight.call(from+Vector3(0,.85,0),to+Vector3(0,.85,0))

static func tick(ctx, delta: float) -> void:
	if not ctx.world_ready or ctx.state.get("world","bunker")=="bunker":return
	for enemy in ctx.state.get("enemies",{}).values():
		var sick:bool=enemy.get("kind","")=="sick_ghost"
		enemy.velocity=Vector2.ZERO
		if enemy.hp<=0:enemy.mode="dead";enemy.target=0;enemy.knockback=Vector2.ZERO;continue
		if enemy.mode=="stagger":
			_push(ctx,enemy,delta)
			enemy.timer=maxf(0,float(enemy.timer)-delta)
			if enemy.timer<=0:enemy.mode="idle";enemy.knockback=Vector2.ZERO
			continue
		enemy.timer=maxf(0,float(enemy.timer)-delta)
		if enemy.mode=="windup":
			if enemy.timer<=0:
				if sick:
					for victim in ctx.enemy_targets():
						if ctx.Souls.alive(victim) and at(enemy).distance_to(at(victim))<=3.0 and clear_sight(ctx,at(enemy),at(victim)):
							ctx.enemy_damage(int(victim.id),20.0)
				else:
					var victim:Dictionary=ctx.state.players.get(enemy.target,{})
					if ctx.Souls.alive(victim) and at(enemy).distance_to(at(victim))<=REACH+.2 and clear_sight(ctx,at(enemy),at(victim)):
						ctx.enemy_damage(int(victim.id),DAMAGE)
				enemy.attack_seq+=1;enemy.mode="recover";enemy.timer=2.2 if sick else RECOVERY
			continue
		if enemy.mode=="recover" and enemy.timer>0:continue
		var chosen:Dictionary={};var nearest:=SIGHT_RANGE+1
		for player in ctx.enemy_targets():
			if at(player).distance_to(enemy.home)>28:continue
			var distance:float=Vector2(player.pos).distance_to(enemy.pos)
			if distance<nearest and visible(ctx,enemy,player):chosen=player;nearest=distance
		if not chosen.is_empty():
			enemy.target=chosen.id;enemy.last_seen=at(chosen);enemy.memory=2.0
			if at(chosen).distance_to(at(enemy))<=(2.8 if sick else REACH):
				enemy.mode="windup";enemy.timer=.8 if sick else WINDUP
				enemy.aim=Vector2(chosen.pos-enemy.pos).normalized()
				continue
		else:enemy.memory=maxf(0,float(enemy.memory)-delta)
		var destination:Vector3=enemy.last_seen if enemy.memory>0 else enemy.home
		var direction:=Vector2(destination.x,destination.z)-Vector2(enemy.pos)
		if direction.length()<.2:
			enemy.mode="idle";enemy.target=0;continue
		enemy.mode="chase" if enemy.memory>0 else "return"
		enemy.aim=direction.normalized()
		if not ctx.enemy_move.is_valid():continue
		var before:=at(enemy)
		var moved:Vector3=ctx.enemy_move.call(int(enemy.id),before,direction.limit_length((2.0 if sick or enemy.get("kind","")=="zombie" else SPEED)*delta))
		enemy.pos=Vector2(moved.x,moved.z);enemy.height=moved.y
		enemy.velocity=(Vector2(enemy.pos)-Vector2(before.x,before.z))/delta
