extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1;print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func setup():
 var m=Model.new();m.add_player(1,"first");m.add_player(2,"second");m.state.world="city";m.bounds=Rect2(-100,-100,200,200);m.obstacles.clear();m.state.targets=[]
 m.state.players[1].pos=Vector2(0,20);m.state.players[1].aim=Vector2.UP;m.state.players[2].pos=Vector2(8,-5)
 m.enemy_sight=func(_a,_b):return false
 m.enemy_move=func(_id,at,offset):return at+Vector3(offset.x,0,offset.y)
 m.enemy_push=m.enemy_move
 m.state.enemies[1]=m.Enemies.create_zombie(1,Vector3.ZERO,Vector2.UP)
 return m
func run():
 var m=setup();var p:Dictionary=m.state.players[1];var e:Dictionary=m.state.enemies[1]
 m.tick(.1);check(e.mode=="idle","unseen player behind remains undetected before attack")
 check(m.command(1,"fire") and e.aggro_target==1 and e.target==1 and e.aim.y>.99,"actual gun hit immediately selects unseen attacker")
 check(is_equal_approx(e.aggro_until-m._clock,5.0),"hit starts five second window")
 for i in 4:m.tick(.1)
 check(e.mode=="chase" and e.pos.y>0,"chase starts after original hit pause")
 p.pos=Vector2(-20,20);m.tick(.1)
 check(e.aim.x<0 and e.last_seen.x==-20,"tracks current position rather than fixed hit location")
 p.pos=Vector2(-60,20);m.tick(.1)
 check(e.mode=="chase" and e.aim.x<0,"forced pursuit ignores normal sight range and home leash")
 var until:float=e.aggro_until
 while m._clock<until-.11:m.tick(.1)
 check(e.get("aggro_target",0)==1,"tracking remains active just before expiry")
 m.tick(.1);m.tick(.1)
 check(e.aggro_target==0 and e.memory==0 and e.mode=="return","five second expiry returns to ordinary unseen behavior without extra memory")
 m=setup();e=m.state.enemies[1]
 m.Enemies.provoke(m,e,1)
 for i in 35:m.tick(.1)
 m.Enemies.provoke(m,e,2)
 check(e.aggro_target==2 and is_equal_approx(e.aggro_until-m._clock,5),"latest attacker switches target and refreshes window")
 m.state.players[2].hp=0;m.tick(.1)
 check(e.aggro_target==0,"dead attacker clears tracking")
 m.Enemies.provoke(m,e,1);m.state.players.erase(1);m.tick(.1)
 check(e.aggro_target==0,"disconnected attacker clears tracking")
 m=setup();e=m.state.enemies[1];p=m.state.players[1];p.pos=Vector2(0,1);p.aim=Vector2.UP;p.equipment.weapon=m._item("baton",1);p.ammo=0
 m.command(1,"move",{"ads":true,"aim":Vector2.UP});m.tick(.01);m.command(1,"fire")
 for i in 26:m.command(1,"move",{"ads":true,"aim":Vector2.UP});m.tick(.01)
 check(e.hp==76 and e.aggro_target==1 and e.mode=="stagger","actual melee retains pause and adds attacker tracking")
 m=setup();e=m.state.enemies[1]
 m.Throwables.damage(m,{"pos":Vector3.ZERO,"owner":2},10)
 check(e.hp==90 and e.aggro_target==2,"throwable hit tracks actual owner")
 m=setup();e=m.state.enemies[1];m.Enemies.provoke(m,e,1)
 m.state.field_effects=[{"kind":"smoke_grenade","pos":Vector3(0,0,3),"ttl":15.0}]
 m.tick(.1);check(e.mode=="chase","smoke does not interrupt active hit tracking")
 m.state.players[1].pos=Vector2(0,.8);m.tick(.1)
 check(e.mode=="chase" and m.state.players[1].hp==100,"tracking cannot attack through blocked sight at close range")
 var before:Vector2=e.pos;m.enemy_move=func(_id,at,_offset):return at
 m.tick(.1);check(e.pos==before,"forced pursuit still respects physical movement adapter")
 m=setup();m.state.enemies[1]=m.Enemies.create_sick(1,Vector3.ZERO,Vector2.UP);e=m.state.enemies[1]
 m.Enemies.provoke(m,e,1);m.tick(.1)
 check(e.aggro_target==1 and e.mode=="chase" and e.invulnerable,"invulnerable sick ghost also reacts to attacker")
 e.hp=0;m.Enemies.provoke(m,e,2)
 check(e.aggro_target==1,"dead enemy cannot receive new pursuit")
 print("HIT_TRACKING ",checks," checks failures=",failures);quit(1 if failures else 0)
