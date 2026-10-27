extends SceneTree
const Model = preload("res://features/base/base_model.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1
func fixture():
	var m=Model.new();m.add_player(1,"shooter");m.add_player(2,"teammate")
	m.state.world="surface";m.state.phase="exploration";m.state.targets=[]
	m.stations=[{"kind":"travel","uid":"extract","world":"surface","destination":"bunker","pos":Vector2.ZERO,"height":0,"spawn":Vector3.ZERO}]
	m.state.players[1].pos=Vector2.ZERO;m.state.players[1].aim=Vector2.RIGHT
	m.state.players[2].pos=Vector2(4,0)
	return m
func run():
	var m=fixture();var p: Dictionary=m.state.players[2]
	check(not m.command(1,"travel",{"route":"extract"}) and m.state.world_revision==0 and m.world_cache.is_empty(),"distant living teammate blocks extraction without changing map")
	check(m.last_notice=="⟦world_travel.010⟧","rejection explains the gathering rule")
	p.pos=Vector2.ZERO;p.height=4
	check(not m.command(1,"travel",{"route":"extract"}),"another floor does not count as gathered")
	p.height=0;p.pos=Vector2(2.4,0)
	check(m.command(1,"travel",{"route":"extract"}) and m.state.world=="bunker","all living teammates at boundary can extract")
	m=fixture();p=m.state.players[2];p.hp=1
	check(m.command(1,"fire") and p.life=="soul" and p.hp==0,"exploration gunfire can kill a refusing teammate")
	var uid: String=p.corpse_uid
	check(m.state.corpses.has(uid) and not m.state.containers[uid].items.is_empty() and p.equipment.weapon.is_empty(),"friendly kill uses corpse and equipment transfer")
	check(m.command(1,"travel",{"route":"extract"}) and not m.world_cache.surface.has("corpses"),"distant soul no longer blocks extraction and old corpse is discarded")
	m=fixture();p=m.state.players[2];m.obstacles.assign([Rect2(2,-1,.3,2)])
	m.command(1,"fire");check(p.hp==100,"wall blocks friendly fire")
	m=fixture();p=m.state.players[2];p.height=2
	m.command(1,"fire");check(p.hp==100,"gunfire does not hit a teammate on another floor")
	m=fixture();p=m.state.players[2];p.pos=Vector2(4,1)
	m.command(1,"fire");check(p.hp==100,"gunfire must aim at teammate")
	m=fixture();p=m.state.players[2];m.state.targets=[{"id":0,"pos":Vector2(2,0),"hp":100}]
	m.command(1,"fire");check(p.hp==100 and m.state.targets[0].hp<100,"nearer target stops shot before teammate")
	m=fixture();p=m.state.players[2];m.add_player(3,"behind");m.state.players[3].pos=Vector2(6,0)
	m.command(1,"fire");check(p.hp<100 and m.state.players[3].hp==100 and m.state.players[1].hp==100,"only nearest teammate is hit and shooter is excluded")
	m=fixture();p=m.state.players[2];m.state.world="bunker"
	m.command(1,"fire");check(p.hp==100,"camp training remains safe")
	m=fixture();p=m.state.players[2];m.change_san(2,-100)
	check(not m.command(1,"travel",{"route":"extract"}),"zombie still blocks party extraction")
	check(m.command(1,"fire") and p.life=="soul" and m.command(1,"travel",{"route":"extract"}),"shooting zombie releases extraction block through soul death")
	m=fixture();m.remove_player(2)
	check(m.command(1,"travel",{"route":"extract"}),"disconnected member does not block extraction")
	m=fixture();m.stations[0].destination="cave"
	check(m.command(1,"travel",{"route":"extract"}),"ordinary map transfer retains existing behavior")
	print("PARTY_EXTRACTION checks=",checks," failures=",failures);quit(1 if failures else 0)
