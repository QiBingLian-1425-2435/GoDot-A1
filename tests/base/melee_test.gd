extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Melee=preload("res://features/combat/melee_system.gd")
const Quick=preload("res://features/player/quick_slots.gd")
const Sweep=preload("res://features/combat/melee_sweep.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func fixture(kind:String):
	var m=Model.new();m.add_player(1,"melee");m.obstacles.clear()
	var p:Dictionary=m.state.players[1];p.pos=Vector2.ZERO;p.aim=Vector2.UP
	p.equipment.weapon=m._item(kind,1);p.ammo=0;p.reloading=false
	m.command(1,"move",{"ads":true})
	m.state.targets=[{"id":1,"pos":Vector2(0,-1),"hp":500,"hits":0},{"id":2,"pos":Vector2(0,1),"hp":500,"hits":0},{"id":3,"pos":Vector2(0,-4),"hp":500,"hits":0}]
	return m
func advance(m,seconds:float):
	for i in ceili(seconds/.01):
		m.command(1,"move",{"ads":true});m.tick(.01)
func run():
	for kind in ["fire_axe","crowbar","baseball_bat","baton","machete","katana"]:
		var m=fixture(kind);var p:Dictionary=m.state.players[1];var info:Dictionary=m.Items.definition(kind)
		check(Melee.is_melee(kind) and Quick.allowed(kind) and m.Trade.available(kind),kind+" shop and quick slot")
		check(not m.command(1,"reload") and not p.reloading,kind+" cannot reload")
		var reserve:int=m._count(p.bag,"ammo")
		m.command(1,"move",{"ads":false})
		check(not m.command(1,"fire") and p.get("melee_chain",0)==0,kind+" attack without aim rejected by host")
		m.command(1,"move",{"ads":true})
		check(m.command(1,"fire") and p.anim_action=="melee_swing",kind+" single click starts one slash")
		m.tick(.05);check(m.state.targets[0].hp==500,kind+" windup has no premature damage")
		for i in 20:m.command(1,"fire")
		advance(m,float(info.fire_interval)*.5)
		check(m.state.targets[0].hp==500-int(info.damage) and m.state.targets[0].hits==1,kind+" hits front target once")
		check(m.state.targets[1].hp==500 and m.state.targets[2].hp==500,kind+" rear and distant targets excluded")
		check(p.ammo==0 and m._count(p.bag,"ammo")==reserve and p.shots==0 and m.state.shots.is_empty(),kind+" no ammo, bullets or muzzle events")
		advance(m,float(p.fire_timer)-.10)
		check(not m.command(1,"fire"),kind+" recovery click does not buffer another attack")
		advance(m,.15)
		check(int(p.melee_chain)==1 and m.state.targets[0].hits==1,kind+" one click never chains another attack")
		check(m.command(1,"fire") and p.anim_action=="melee_swing",kind+" new click starts same slash again")
		advance(m,float(info.fire_interval))
		check(m.state.targets[0].hits==2,kind+" return swing hits once")
		var capture:Dictionary=m.Profile.capture(m,1)
		check(m.Profile.valid(m,capture) and m.Profile.apply(m,capture,1)==OK and m.state.players[1].equipment.weapon.kind==kind,kind+" profile roundtrip")
	var m=fixture("fire_axe");var p:Dictionary=m.state.players[1]
	m.command(1,"fire");advance(m,.6);m.command(1,"fire")
	m.command(1,"move",{"ads":false})
	for i in 40:m.tick(.01)
	check(p.get("melee_chain",0)==1 and not p.has("melee_buffer"),"releasing aim discards queued follow-up")
	check(not m.command(1,"fire"),"stale aim input cannot authorize attack")
	m=fixture("katana");p=m.state.players[1]
	var reach:float=Sweep.reach("katana")
	m.state.targets=[{"id":1,"pos":Vector2(0,-reach-.02),"hp":500,"hits":0},{"id":2,"pos":Vector2(sin(deg_to_rad(72)), -cos(deg_to_rad(72))),"hp":500,"hits":0},{"id":3,"pos":Vector2(0,-reach+.02),"hp":500,"hits":0}]
	m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hits==0 and m.state.targets[1].hits==0 and m.state.targets[2].hits==1,"damage matches effect radius and side boundary")
	m=fixture("katana");p=m.state.players[1];m.state.targets=[]
	for degrees in [-72,-69,69,72]:m.state.targets.append({"id":degrees,"pos":Vector2(sin(deg_to_rad(degrees)),-cos(deg_to_rad(degrees))),"hp":500,"hits":0})
	m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hits==0 and m.state.targets[1].hits==1 and m.state.targets[2].hits==1 and m.state.targets[3].hits==0,"both visible arc side boundaries match hit rejection")
	m=fixture("katana");p=m.state.players[1];p.aim=Vector2.RIGHT;m.state.targets[0].pos=Vector2(1,0)
	m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hits==1,"effect footprint rotates with player aim")
	m=fixture("fire_axe");p=m.state.players[1];m.state.targets[0].pos=Vector2(0,1)
	m.command(1,"fire");advance(m,float(m.Items.definition("fire_axe").fire_interval)*.65)
	m.state.targets[0].pos=Vector2(0,-1);advance(m,.4)
	check(m.state.targets[0].hits==0,"fading recovery afterimage does not deal damage")
	m=fixture("fire_axe");p=m.state.players[1]
	m.obstacles.assign([Rect2(-.3,-.6,.6,.1)]);m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hp==500,"solid obstacle blocks melee")
	m.obstacles.clear();m.shot_query=func(_a,_b):return {"position":Vector3(0,.9,-.5)}
	m.command(1,"fire");advance(m,.8);check(m.state.targets[0].hp==500,"3D collision query blocks melee")
	m.shot_query=Callable();m.state.targets[0].height=2.0;m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hp==500,"another floor cannot be hit")
	m.state.targets[0].height=0;m.state.targets[0].invulnerable=true;m.command(1,"fire");advance(m,.8)
	check(m.state.targets[0].hp==500 and m.state.targets[0].hits==1,"invulnerable monster still survives melee")
	m=fixture("katana");p=m.state.players[1];m.command(1,"fire");p.equipment.weapon=m._item("pistol",1);advance(m,.8)
	check(m.state.targets[0].hits==0,"switching weapons cancels pending hit")
	m=fixture("katana");p=m.state.players[1];m.command(1,"fire");m.state.world_revision+=1;advance(m,.8)
	check(m.state.targets[0].hits==0,"map change cancels pending hit")
	m=fixture("katana");p=m.state.players[1];m.command(1,"fire");p.hp=0;advance(m,.8)
	check(m.state.targets[0].hits==0,"death cancels pending hit")
	m=fixture("katana");p=m.state.players[1];m.command(1,"fire");p.anim_action="drink";advance(m,.8)
	check(m.state.targets[0].hits==0,"another action cancels pending hit")
	m=fixture("katana");p=m.state.players[1];m.command(1,"fire");m.world_ready=false;advance(m,.8)
	check(m.state.targets[0].hits==0,"unready world cancels pending hit")
	m=fixture("katana");p=m.state.players[1];m.add_player(2,"friend");var friend:Dictionary=m.state.players[2];friend.pos=Vector2(0,-1)
	m.command(1,"fire");advance(m,.7);check(friend.hp==100,"base protects teammates")
	m.state.world="city";p.fire_timer=0;m.command(1,"fire");advance(m,.7);check(friend.hp<100,"exploration follows existing friendly fire rules")
	print("MELEE_RULES failures=",failures);quit(0 if failures==0 else 1)
