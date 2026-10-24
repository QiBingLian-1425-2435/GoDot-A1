extends RefCounted
## Shared enemy/health state is advanced only by the authoritative BaseModel.
const SIGHT_RANGE := 12.0
const SPEED := 4.6
const REACH := 1.35
const DAMAGE := 18.0
const WINDUP := .45
const RECOVERY := .85
const RESPAWN_TIME := 5.0

static func create(id: int, at: Vector3, facing: Vector2) -> Dictionary:
	return {"id":id,"pos":Vector2(at.x,at.z),"height":at.y,"home":at,"aim":facing.normalized(),"velocity":Vector2.ZERO,"hp":100,"max_hp":100,"mode":"idle","target":0,"last_seen":at,"memory":0.0,"timer":0.0,"attack_seq":0}

static func at(p: Dictionary) -> Vector3:
	return Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)

static func visible(ctx, enemy: Dictionary, player: Dictionary) -> bool:
	if float(player.get("hp",0))<=0 or float(player.get("enemy_immunity",0))>0:return false
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
	for p in ctx.state.players.values():
		p.enemy_immunity=maxf(0,float(p.get("enemy_immunity",0))-delta)
		if float(p.hp)>0:continue
		p.knockout_remaining=maxf(0,float(p.get("knockout_remaining",RESPAWN_TIME))-delta)
		if p.knockout_remaining<=0:
			var spawn:Vector3=p.get("enemy_return",at(p))
			p.pos=Vector2(spawn.x,spawn.z);p.height=spawn.y;p.hp=50.0
			p.relocation_seq=int(p.get("relocation_seq",0))+1
			ctx.reset_transients(int(p.id));p.enemy_immunity=3.0
	for enemy in ctx.state.get("enemies",{}).values():
		enemy.velocity=Vector2.ZERO
		if enemy.hp<=0:enemy.mode="dead";enemy.target=0;continue
		enemy.timer=maxf(0,float(enemy.timer)-delta)
		if enemy.mode=="windup":
			if enemy.timer<=0:
				var victim:Dictionary=ctx.state.players.get(enemy.target,{})
				if not victim.is_empty() and victim.hp>0 and float(victim.get("enemy_immunity",0))<=0 and at(enemy).distance_to(at(victim))<=REACH+.2 and clear_sight(ctx,at(enemy),at(victim)):
					victim.hp=maxf(0,float(victim.hp)-DAMAGE)
					if victim.hp<=0:
						ctx.Loot.close(ctx,victim)
						victim.knockout_remaining=RESPAWN_TIME;victim.roll=ctx.Movement.empty_roll()
						victim.reloading=false;victim.reload_timer=0;victim.reload_progress=0;victim.pending_use={}
						victim.velocity=Vector2.ZERO
				enemy.attack_seq+=1;enemy.mode="recover";enemy.timer=RECOVERY
			continue
		if enemy.mode=="recover" and enemy.timer>0:continue
		var chosen:Dictionary={};var nearest:=SIGHT_RANGE+1
		for player in ctx.state.players.values():
			if at(player).distance_to(enemy.home)>28:continue
			var distance:float=Vector2(player.pos).distance_to(enemy.pos)
			if distance<nearest and visible(ctx,enemy,player):chosen=player;nearest=distance
		if not chosen.is_empty():
			enemy.target=chosen.id;enemy.last_seen=at(chosen);enemy.memory=2.0
			if at(chosen).distance_to(at(enemy))<=REACH:
				enemy.mode="windup";enemy.timer=WINDUP
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
		var moved:Vector3=ctx.enemy_move.call(int(enemy.id),before,direction.limit_length(SPEED*delta))
		enemy.pos=Vector2(moved.x,moved.z);enemy.height=moved.y
		enemy.velocity=(Vector2(enemy.pos)-Vector2(before.x,before.z))/delta
