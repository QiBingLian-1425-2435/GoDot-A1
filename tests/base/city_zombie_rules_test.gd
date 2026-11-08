extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1;print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func setup():
 var m=Model.new();m.add_player(1,"test");m.state.world="city";m.bounds=Rect2(-100,-100,200,200);m.obstacles.clear()
 m.enemy_sight=func(_a,_b):return true
 m.enemy_move=func(_id,at,offset):return at+Vector3(offset.x,0,offset.y)
 m.enemy_push=m.enemy_move
 var p:Dictionary=m.state.players[1];p.pos=Vector2(0,-5)
 m.state.enemies[1]=m.Enemies.create_zombie(1,Vector3.ZERO,Vector2.UP)
 return m
func run():
 var m=setup();var p:Dictionary=m.state.players[1];var e:Dictionary=m.state.enemies[1]
 m.tick(.1);check(e.mode=="chase" and is_equal_approx(e.velocity.length(),2) and e.aim.dot((p.pos-e.pos).normalized())>.99,"zombie sees player and chases facing forward")
 m.enemy_sight=func(_a,_b):return false
 e.memory=0;e.pos=Vector2.ZERO;e.home=Vector3.ZERO;m.tick(.1)
 check(e.mode=="idle","wall blocks acquisition")
 m=setup();p=m.state.players[1];e=m.state.enemies[1];p.pos=Vector2(0,-1)
 m.tick(.1);check(e.mode=="windup" and p.hp==100,"near zombie winds up")
 for i in 5:m.tick(.1)
 check(p.hp==82 and e.attack_seq==1,"swing deals one authoritative hit")
 for i in 5:m.tick(.1)
 check(p.hp==82,"attack recovery prevents continuous damage")
 m=setup();p=m.state.players[1];e=m.state.enemies[1];p.pos=Vector2(0,-1);p.aim=Vector2.DOWN
 var at:Vector2=e.pos
 check(m.command(1,"fire") and e.hp==66 and e.mode=="stagger" and e.knockback==Vector2.ZERO,"gun damages and staggers zombie without knockback")
 for i in 2:m.tick(.1)
 check(e.pos==at and p.hp==100,"gun pause prevents movement and attack")
 m.tick(.1);m.tick(.1);check(e.mode!="stagger","zombie resumes after hit pause")
 m=setup();p=m.state.players[1];e=m.state.enemies[1];p.pos=Vector2(0,-1);p.aim=Vector2.DOWN
 p.equipment.weapon=m._item("baton",1);p.ammo=0
 m.command(1,"move",{"aim":Vector2.DOWN,"ads":true});m.tick(.01)
 check(m.command(1,"fire"),"aimed melee swing begins")
 for i in 24:
  m.command(1,"move",{"aim":Vector2.DOWN,"ads":true});m.tick(.01)
 check(e.hp==76 and e.mode=="stagger" and e.knockback.y>0,"melee damages, pauses and pushes away")
 var before:Vector2=e.pos;m.tick(.05)
 check(e.pos.y>before.y,"melee knockback moves through physical adapter")
 m.state.field_effects=[{"kind":"smoke_grenade","pos":Vector3(0,0,-.5),"ttl":15}]
 check(not m.Enemies.visible(m,e,p),"smoke hides player from zombie")
 m.state.enemies={};m.state.enemies_seeded=false
 for i in 10:m.state.enemies[i+1]=m.Enemies.create_zombie(i+1,Vector3(i*8,0,20),Vector2.UP)
 check(preload("res://features/exploration/world_travel.gd").enter_world(m,"bunker",Vector3.ZERO),"travel leaves city")
 check(m.state.enemies.is_empty() and not m.state.enemies_seeded,"leaving clears all enemies and seeding flag")
 print("CITY_ZOMBIE_RULES ",checks," checks failures=",failures);quit(1 if failures else 0)
