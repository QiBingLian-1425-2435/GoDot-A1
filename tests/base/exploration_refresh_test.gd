extends SceneTree
const Model=preload("res://features/base/base_model.gd")
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func stations(m):
	var world:String=m.state.world
	m.stations=[{"kind":"loot","uid":"box","world":world,"pos":Vector2.ZERO,"height":0.0,"locked":true}, {"kind":"loot","uid":"toilet","world":world,"pos":Vector2.ZERO,"height":0.0,"locked":false,"loot_pool":"food"}]
func travel(m,destination:String):
	m.stations.append({"kind":"travel","uid":"go","world":m.state.world,"destination":destination,"pos":Vector2.ZERO,"spawn":Vector3.ZERO})
	return m.command(1,"travel",{"route":"go"})
func run():
	var m=Model.new();m.add_player(1,"host");m.add_player(2,"guest")
	m.state.world="surface"
	m.loot_reachable=func(_uid,_from):return true
	var p:Dictionary=m.state.players[1];p.pos=Vector2.ZERO;p.bag=m._empty_slots(24);p.bag[0]=m._item("lockpick",3)
	m.state.players[2].pos=Vector2.ZERO
	stations(m)
	check(m.command(1,"search",{"uid":"box"}),"first visit opens locked box")
	var old_uid:String=m.state.containers.box.items[0].uid
	m.state.containers.box.revealed=m.state.containers.box.items.size()
	check(m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":old_uid}),"first visit grants item")
	check(m.command(2,"search",{"uid":"toilet"}),"guest can search toilet")
	var old_food:String=m.state.containers.toilet.items[0].uid
	m.state.enemies={1:m.Enemies.create(1,Vector3.ZERO,Vector2.UP)};m.state.enemies[1].hp=0;m.state.enemies_seeded=true
	var revision:int=m.state.world_revision
	m.stations.append({"kind":"travel","uid":"local","scope":"player","world":"surface","destination":"surface","pos":Vector2.ZERO,"spawn":Vector3.ZERO})
	check(m.command(1,"travel",{"route":"local"}) and m.state.containers.has("box") and m.state.enemies[1].hp==0 and m.state.world_revision==revision,"same-map teleport does not refresh encounters")
	var bag:Array=p.bag.duplicate(true)
	m.state.drops.saved_drop={"uid":"saved_drop","kind":"scrap","count":1,"pos":Vector2.ZERO}
	check(travel(m,"bunker"),"party returns to base")
	check(p.loot_uid.is_empty() and m.state.players[2].loot_uid.is_empty(),"travel clears every player's search ownership")
	check(m.state.enemies.is_empty() and m.state.containers.is_empty(),"base has no carried enemy/container state")
	stations(m)
	# Enemy caches refresh; searched container inventories survive re-entry.
	m.world_cache.surface.enemies={1:{"hp":0}};m.world_cache.surface.enemies_seeded=true
	check(travel(m,"surface"),"party re-enters surface")
	check(m.state.enemies.is_empty() and not m.state.enemies_seeded and m.state.containers.has("box"),"new entry resets enemies while retaining searched containers")
	check(p.bag==bag and m.state.drops.has("saved_drop"),"acquired inventory and player ground drops are preserved")
	check(m.state.world_revision==revision+2,"new visit advances network map revision")
	stations(m)
	var picks_before:int=m._count(p.bag,"lockpick")
	check(not m.command(1,"search",{"uid":"box"}) and m.command(1,"loot_view",{"uid":"box"}) and m._count(p.bag,"lockpick")==picks_before,"new visit views original box without spending another lockpick")
	check(m.state.containers.box.items[0].is_empty() and m.state.containers.box.revealed==m.state.containers.box.items.size(),"taken loot and completed discovery never refresh")
	m.state.containers.box.revealed=m.state.containers.box.items.size()
	check(not m.command(1,"loot_take",{"uid":"box","index":0,"item_uid":old_uid}),"already-taken stack cannot be claimed on another visit")
	check(not m.command(1,"search",{"uid":"toilet"}) and m.command(1,"loot_view",{"uid":"toilet"}) and m.state.containers.toilet.items[0].uid==old_food,"toilet food retains original identity")
	stations(m);check(travel(m,"cave") and m.state.containers.is_empty(),"entering cave also starts with fresh containers")
	stations(m);m.command(1,"search",{"uid":"toilet"})
	stations(m);travel(m,"surface");stations(m);travel(m,"cave")
	check(m.state.containers.has("toilet") and not m.state.enemies_seeded,"returning to cave preserves search while refreshing enemies")
	print("EXPLORATION_REFRESH checks=",checks," failures=",failures);quit(1 if failures else 0)
