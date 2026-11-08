extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Rules=preload("res://features/combat/throwable_system.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error("THROWABLE FAIL: "+label)
func setup(kind:String):
	var m=Model.new();m.add_player(1,"throw");m.state.world="ground_zero";m.bounds=Rect2(-100,-100,200,200);m.obstacles.clear()
	var p:Dictionary=m.state.players[1];p.pos=Vector2.ZERO;p.bag=m._empty_slots(24);p.bag[0]=m._item(kind,3)
	m.enemy_sight=func(_a,_b):return true
	return m
func run():
	for kind in Rules.KINDS:
		var m=setup(kind);var p:Dictionary=m.state.players[1]
		check(m.command(1,"use",{"index":0}) and p.bag[0].count==3 and m.state.field_effects.is_empty(),kind+" selection holds without consumption")
		check(not m.command(1,"fire",{"target":Vector3(0,0,-6)}),"aim required")
		m.command(1,"move",{"ads":true,"aim":Vector2.UP});m.tick(.01)
		check(not m.command(1,"fire",{"target":Vector3(NAN,0,0)}),"nonfinite target rejected")
		check(not m.command(1,"reload"),"held tool cannot reload hidden gun")
		m.state.targets=[{"id":0,"pos":Vector2(0,-6),"hp":500,"hits":0},{"id":1,"pos":Vector2(0,-9.1),"hp":500,"hits":0},{"id":2,"pos":Vector2(.2,-6),"hp":500,"hits":0,"invulnerable":true}]
		check(m.command(1,"fire",{"target":Vector3(0,400,-6)}),kind+" aimed throw accepted with authoritative height")
		check(not m.command(1,"fire",{"target":Vector3(0,0,-6)}) and p.bag[0].count==2,"one click consumes exactly one")
		check(m.state.targets[0].hp==500 and m.state.field_effects[0].phase=="flight","no damage during flight")
		var effect:Dictionary=m.state.field_effects[0]
		for flight_tick in 30:
			if effect.phase!="flight":break
			m.tick(.1)
		check(Vector3(effect.pos).distance_to(Vector3(0,0,-6))<.01,"landing matches preview endpoint")
		if kind=="frag_grenade":
			check(m.state.targets[0].hp==435 and m.state.targets[1].hp==500 and m.state.targets[2].hp==500,"explosion one hit within radius and respects invulnerability")
		elif kind=="smoke_grenade":
			check(is_equal_approx(effect.ttl,15),"smoke starts with fifteen seconds at landing")
			check(not m.Enemies.visible(m,{"pos":Vector2(0,-6),"aim":Vector2.DOWN},p),"enemy inside smoke loses sight")
			for i in 149:m.tick(.1)
			check(not m.state.field_effects.is_empty(),"smoke remains before fifteen seconds")
			m.tick(.1)
			check(m.state.field_effects.is_empty() and m.Enemies.visible(m,{"pos":Vector2(0,-6),"aim":Vector2.DOWN},p),"expired smoke restores sight")
		elif kind=="molotov":
			for i in 49:m.tick(.1)
			check(not m.state.field_effects.is_empty() and m.state.targets[0].hp==392,"fire pulses while active")
			m.tick(.1)
			check(m.state.field_effects.is_empty() and m.state.targets[0].hp==380 and m.state.targets[1].hp==500 and m.state.targets[2].hp==500,"fire deals 120 total damage over five seconds then clears")
		for i in 170:m.tick(.1)
		check(m.state.field_effects.is_empty(),"all effects cleaned up")
		m.command(1,"hold_throwable",{"index":-1});check(Rules.held(p).is_empty(),"gun selection clears tool")
		check(not m.command(1,"fire",{"target":Vector3(0,0,-6)}) and p.shots==0,"late tool intent cannot fire the gun after deselection")
		var path:=Rules.arc(p,Vector3(0,0,-999))
		check(is_equal_approx(Vector2(path.back().x,path.back().z).length(),10),"range clamped to ten meters")
		m.projectile_query=func(a:Vector3,b:Vector3)->Dictionary:
			if a.z>-2 and b.z<=-2:return {"position":a.lerp(b,(-2-a.z)/(b.z-a.z)),"normal":Vector3.BACK}
			return {}
		path=Rules.arc(p,Vector3(0,0,-8),m.projectile_query)
		check(path.back().z>=-2.001,"arc clips physical wall")
		m.state.field_effects=[{"kind":"smoke_grenade","world":"other","revision":0,"ttl":15,"phase":"active","pos":Vector3.ZERO}]
		m.tick(.1);check(m.state.field_effects.is_empty(),"old map effect removed")
	print("THROWABLE_RULES ",checks," checks failures=",failures);quit(1 if failures else 0)
