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
	var m=fixture();var p:Dictionary=m.state.players[1]
	var e:=Rules.create_sick(1,Vector3.ZERO,Vector2.UP);m.state.enemies[1]=e
	p.pos=Vector2(0,-6);m.tick(.1)
	check(e.mode=="chase" and e.pos.y<0,"sick ghost approaches visible player")
	p.pos=e.pos+Vector2(0,-2);e.mode="idle";e.timer=0;m.tick(.1)
	check(e.mode=="windup" and p.hp==100,"cough telegraphs before damage")
	for i in range(9):m.tick(.1)
	check(p.hp==80 and e.attack_seq==1,"cough deals twenty damage once")
	for i in range(10):m.tick(.1)
	check(p.hp==80,"cough cooldown prevents frame damage")
	e.mode="windup";e.timer=.1;p.pos=e.pos+Vector2(0,-4);m.tick(.2)
	check(p.hp==80,"outside radius avoids cough")
	e.mode="windup";e.timer=.1;p.pos=e.pos+Vector2(0,-2);m.enemy_sight=func(_a,_b):return false;m.tick(.2)
	check(p.hp==80,"wall blocks cough")
	m.enemy_sight=func(_a,_b):return true;p.pos=e.pos+Vector2(0,2);p.aim=Vector2.UP
	for i in range(10):p.fire_timer=0;m.command(1,"fire")
	check(e.hp==100 and e.mode!="stagger","repeated bullets cannot kill or interrupt sick ghost")
	print("SICK_RULES checks=",checks," failures=",failures);quit(1 if failures else 0)
