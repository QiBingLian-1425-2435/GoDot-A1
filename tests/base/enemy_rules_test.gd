extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Rules=preload("res://features/enemies/enemy_rules.gd")
const Session=preload("res://app/network/session.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func fixture():
	var m=Model.new();m.add_player(1,"owner");m.state.world="surface"
	m.state.players[1].pos=Vector2(0,-7);m.state.players[1].enemy_return=Vector3(8,0,8)
	m.enemy_sight=func(_a,_b):return true
	m.enemy_move=func(_id,at,offset):return at+Vector3(offset.x,0,offset.y)
	m.state.enemies[1]=Rules.create(1,Vector3.ZERO,Vector2.UP)
	return m
func run():
	var m=fixture();var p:Dictionary=m.state.players[1];var e:Dictionary=m.state.enemies[1]
	m.tick(.1)
	check(e.mode=="chase" and e.pos.y<-.4,"visible player triggers chase toward player")
	m.enemy_sight=func(_a,_b):return false
	for i in range(25):m.tick(.1)
	check(e.memory==0 and e.mode in ["return","idle"] and p.hp==100,"lost sight expires pursuit and wall prevents damage")
	m=fixture();p=m.state.players[1];e=m.state.enemies[1];p.pos=Vector2(0,7)
	m.tick(.1);check(e.mode=="idle","far player behind enemy is not seen")
	p.pos=Vector2(0,-1);m.tick(.1)
	check(e.mode=="windup" and p.hp==100,"melee has a visible windup before damage")
	for i in range(3):m.tick(.1)
	check(p.hp==100,"no early damage during windup")
	p.pos=Vector2(0,-4)
	for i in range(3):m.tick(.1)
	check(p.hp==100 and e.attack_seq==1,"moving out of reach dodges committed attack")
	e.mode="idle";e.timer=0;p.pos=Vector2(0,-1)
	m.tick(.1);m.enemy_sight=func(_a,_b):return false
	for i in range(6):m.tick(.1)
	check(p.hp==100,"closing line of sight during windup blocks damage")
	m.enemy_sight=func(_a,_b):return true
	e.mode="idle";e.timer=0
	for i in range(7):m.tick(.1)
	check(p.hp==82,"one melee strike applies host damage once")
	for i in range(5):m.tick(.1)
	check(p.hp==82,"recovery interval prevents damage every tick")
	e.mode="idle";e.timer=0;p.hp=10
	for i in range(7):m.tick(.1)
	check(p.hp==0 and p.knockout_remaining>0,"lethal hit starts temporary knockout")
	var down_at:Vector2=p.pos
	check(not m.command(1,"fire") and not m.command(1,"move",{"direction":Vector2.RIGHT}),"knocked out player cannot attack or move")
	m.tick(.1);check(p.pos==down_at,"old movement does not move knocked out body")
	for i in range(55):m.tick(.1)
	check(p.hp==50 and p.pos==Vector2(8,8) and p.enemy_immunity>0,"knockout returns to region entrance with recovery grace")
	m=fixture();p=m.state.players[1];e=m.state.enemies[1]
	p.pos=Vector2(0,3);p.aim=Vector2.UP
	for i in range(3):p.fire_timer=0;m.command(1,"fire")
	check(e.hp==0 and p.ammo==17,"existing rifle fire kills hostile using real ammunition")
	m.tick(.1);check(e.mode=="dead" and e.velocity==Vector2.ZERO,"dead enemy cannot chase or attack")
	m=fixture();p=m.state.players[1];e=m.state.enemies[1];p.pos=Vector2(0,3);p.aim=Vector2.UP
	m.shot_query=func(_a,_b):return {"position":Vector3(0,.9,2)}
	m.command(1,"fire");check(e.hp==100,"world collision blocks bullets before monster")
	m.shot_query=Callable();e.height=3;p.fire_timer=0;m.command(1,"fire")
	check(e.hp==100,"shots cannot hit a monster on another floor")
	m=fixture();p=m.state.players[1];e=m.state.enemies[1]
	m.state.field_effects=[{"kind":"smoke_grenade","pos":Vector3(0,0,-3),"ttl":5.0}]
	m.tick(.1);check(e.mode=="idle","smoke blocks acquisition")
	m.state.field_effects=[];m.world_ready=false;m.tick(.1)
	check(e.mode=="idle","enemy simulation pauses during map loading")
	m.world_ready=true;m.state.world="bunker";m.tick(.1)
	check(e.mode=="idle","base remains safe")
	var s=Session.new();s.mode="client";s._session_token=9;s.model=fixture();s.model.state.world_revision=2
	s._apply_enemies([[1,Vector2(2,3),.1,Vector2.UP,66,"chase",0,2,Vector2.UP]],9,10,2)
	check(s.model.state.enemies[1].hp==66,"confirmed compact enemy motion applies")
	s._apply_enemies([[1,Vector2.ZERO,0,Vector2.ZERO,100,"idle",0,0,Vector2.UP]],9,9,2)
	check(s.model.state.enemies[1].hp==66,"out of order enemy motion cannot resurrect enemy")
	var old:Dictionary=s.model.state.duplicate(true);old.enemies[1].hp=100
	s._apply_snapshot(old,9,8,0)
	check(s.model.state.enemies[1].hp==66,"delayed reliable snapshot preserves newer enemy state")
	s._apply_enemies([[1,Vector2.ZERO,0,Vector2.ZERO,100,"idle",0,0,Vector2.UP]],9,11,1)
	check(s.model.state.enemies[1].hp==66,"old map enemy packets rejected")
	for id in range(2,5):s.model.state.enemies[id]=Rules.create(id,Vector3(id,0,0),Vector2.UP)
	check(var_to_bytes([s._enemy_rows(),9,10,2]).size()<1200,"four-hostile motion packet fits transport budget")
	for id in range(5,17):s.model.state.enemies[id]=Rules.create(id,Vector3(id,0,0),Vector2.UP)
	var batches:Array=s._enemy_batches()
	check(batches.size()==4,"sixteen hostiles split into four packets")
	var budget_ok:=true
	for batch in batches:budget_ok=budget_ok and var_to_bytes([batch,9,12,2]).size()<1200
	check(budget_ok,"every hostile packet stays below transport budget")
	batches[0][0][4]=32;batches[3][3][4]=42
	s._apply_enemies(batches[3],9,12,2);s._apply_enemies(batches[0],9,12,2)
	check(s.model.state.enemies[1].hp==32 and s.model.state.enemies[16].hp==42,"same sequence batches apply independently in reverse arrival order")
	s._apply_enemies([[1,Vector2.ZERO,0,Vector2.ZERO,100,"idle",0,0,Vector2.UP]],9,11,2)
	check(s.model.state.enemies[1].hp==32,"older per-enemy update cannot resurrect a damaged enemy")
	s.free()
	print("ENEMY_RULES checks=",checks," failures=",failures);quit(1 if failures else 0)
