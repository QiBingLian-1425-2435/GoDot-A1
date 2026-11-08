extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	for kind in ["rifle","pistol","sniper"]:
		var m=Model.new();m.add_player(1,"run");m.obstacles.clear();m.state.infinite_stamina=true
		var p:Dictionary=m.state.players[1];p.pos=Vector2.ZERO;p.equipment.weapon=m._item(kind,1);p.ammo=int(m.Items.definition(kind).magazine)
		var before:int=p.ammo
		m.command(1,"move",{"direction":Vector2.UP,"sprint":true});m.tick(.02)
		check(p.sprint and not m.command(1,"fire"),kind+" host rejects shooting during sprint")
		check(p.ammo==before and p.shots==0 and m.state.shots.is_empty() and p.fire_timer==0,kind+" blocked trigger creates no ammo, shot or cooldown changes")
		m.command(1,"move",{"direction":Vector2.ZERO,"sprint":false});m.tick(.02)
		check(not p.sprint and m.command(1,"fire") and p.ammo==before-1,kind+" shooting resumes after sprint ends")
		p.fire_timer=0;m.command(1,"move",{"direction":Vector2.ZERO,"sprint":true});m.tick(.02)
		check(not p.sprint and m.command(1,"fire"),kind+" stationary sprint key does not block shooting")
		p.fire_timer=0;p.ammo=0;m.command(1,"move",{"direction":Vector2.UP,"sprint":true});m.tick(.02)
		check(not m.command(1,"fire") and not p.reloading,kind+" empty sprint trigger cannot start automatic reload")
		check(m.command(1,"reload") and p.reloading,kind+" manual reload remains available")
	print("SPRINT_FIRE failures=",failures);quit(0 if failures==0 else 1)
