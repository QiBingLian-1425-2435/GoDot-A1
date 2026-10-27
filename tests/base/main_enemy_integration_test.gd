extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var m=Model.new();m.add_player(1,"host");m.add_player(2,"guest");m.state.world="surface"
	var p:Dictionary=m.state.players[1];var q:Dictionary=m.state.players[2]
	m.state.camp.logistics=3;p.hunger=25;m.Camp.refresh_all(m)
	check(is_equal_approx(p.max_weight,35.25),"camp logistics bonus participates in satiety capacity")
	m.enemy_sight=func(_a,_b):return true
	var e:Dictionary=m.Enemies.create(1,Vector3.ZERO,Vector2.UP)
	q.pos=Vector2(0,-1);q.san=0;m.Souls.reconcile(m,q)
	check(q.life=="zombie" and not m.Enemies.visible(m,e,q) and not m.enemy_damage(2,10),"monsters do not select or damage SAN zombies")
	m.Souls.revive(m,q);q.hp=1;m.enemy_damage(2,18)
	var uid:String=q.corpse_uid
	var original:Array=m.state.containers[uid].items.duplicate(true)
	check(q.life=="soul" and original.size()>0,"monster lethal damage preserves equipment in soul corpse")
	for i in range(60):m.tick(.1)
	check(q.life=="soul" and q.hp==0,"waiting does not apply retired automatic revive")
	m.state.containers.test_box={"items":[],"revealed":0,"progress":0.0,"searcher":0}
	m.state.enemies[1]=e;e.hp=0;m.state.enemies_seeded=true
	m.WorldTravel.enter_world(m,"bunker",Vector3.ZERO)
	m.WorldTravel.enter_world(m,"surface",Vector3.ZERO)
	check(m.state.corpses.has(uid) and m.state.containers[uid].items==original,"re-entering map retains corpse items without duplication")
	check(m.state.containers.has("test_box") and m.state.enemies.is_empty() and not m.state.enemies_seeded,"searched containers persist while monsters refresh independently")
	print("MAIN_INTEGRATION failures=",failures);quit(1 if failures else 0)
