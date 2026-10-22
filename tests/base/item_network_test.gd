extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT=29963
var session:Node
var role:="host"
var run_id:=""
var checks:=0
var failures:=0
var children:Array[int]=[]
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()>1:role=args[0];run_id=args[1]
	else:run_id=str(Time.get_ticks_usec())
	Engine.max_fps=60;call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",role," ",label)
	if not ok:failures+=1
func wait_for(test:Callable,seconds:=10.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await process_frame
	return test.call()
func path(name:String)->String:return "user://items_"+run_id+"_"+name+".json"
func report(name:String):
	var f=FileAccess.open(path(name),FileAccess.WRITE);f.store_string(JSON.stringify({"id":session.local_id,"failures":failures}));f.close()
func read_report(name:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path(name)))
func phase(value:int):session.model.state.item_phase=value;session._broadcast_snapshot(true)
func player()->Dictionary:return session.model.state.players[session.local_id]
func finish():
	if role!="host":report(role+"_done")
	for pid in children:
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	session.offline();session.queue_free();await process_frame
	print("ITEM_NETWORK ",role," checks=",checks," failures=",failures);quit(1 if failures else 0)
func run():
	session=Session.new();root.add_child(session)
	if role!="host":
		check(session.join("127.0.0.1",PORT)==OK,"real transport connects")
		check(await wait_for(func():return session.local_id>1 and session.model.state.players.has(session.local_id)),"admitted")
		report(role+"_ready")
		check(await wait_for(func():return session.model.state.get("item_phase",0)==1),"phase1")
		if role=="a":
			session.send("buy",{"kind":"water","count":1,"price":0,"credits":999999})
			check(await wait_for(func():return player().credits==9910 and session.model._count(player().bag,"water")==1),"remote purchase has authoritative price and item")
		else:
			session.send("sell",{"index":3,"uid":player().bag[3].uid,"value":999999})
			check(await wait_for(func():return player().credits==16800 and player().bag[3].is_empty()),"remote sale credits only catalog value")
			report(role+"_one")
		report(role+"_one")
		check(await wait_for(func():return session.model.state.get("item_phase",0)==2),"phase2")
		if role=="a":session.send("use",{"index":0,"position":Vector3(999,99,999),"owner":1})
		check(await wait_for(func():return session.model.state.field_effects.size()==1),"both clients receive the confirmed smoke effect")
		var effect:Dictionary=session.model.state.field_effects[0]
		check(effect.pos.distance_to(Vector3(0,0,-.9))<.01 and int(effect.owner)!=1,"client cannot forge effect location or owner")
		report(role+"_two")
		check(await wait_for(func():return session.model.state.get("item_phase",0)==3),"phase3")
		check(session.model.state.field_effects.is_empty(),"host expiry clears smoke on clients")
		# An old-map packet is delivered on the real action channel and must do nothing.
		session._intent_seq+=1
		session._intent.rpc_id(1,"use",{"index":0,"world_revision":int(session.model.state.world_revision)-1},session._session_token,session._intent_seq)
		session.send("search",{"uid":"loot_one"})
		check(await wait_for(func():return session.model.state.containers.has("loot_one")),"shared locked container opens")
		check(session.model.state.drops.size()==2,"one loot result replicated to each client")
		report(role+"_three")
		check(await wait_for(func():return session.model.state.get("item_phase",0)==4),"phase4")
		var cash:int=player().credits
		session.send("buy",{"kind":"juice","count":1})
		await create_timer(.4).timeout
		check(player().credits==cash,"out-of-range remote buy cannot spend or grant")
		await finish();return
	check(session.host(PORT)==OK,"host starts")
	for who in ["a","b"]:
		var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/item_network_test.gd","--",who,run_id]);children.append(pid)
		check(pid>0,"independent "+who+" client")
	if not await wait_for(func():return FileAccess.file_exists(path("a_ready")) and FileAccess.file_exists(path("b_ready"))):check(false,"clients ready");await finish();return
	var a:=int(read_report("a_ready").id);var b:=int(read_report("b_ready").id)
	session.model.stations=[{"kind":"trader","pos":Vector2.ZERO}]
	for id in [a,b]:
		var p:Dictionary=session.model.state.players[id];p.pos=Vector2.ZERO;p.aim=Vector2.UP;p.credits=10000;p.bag=session.model._empty_slots(24)
		for spec in [["smoke_grenade",1],["lockpick",2],["juice",1],["gold_statue",1]]:session.model._insert(p.bag,session.model._item(spec[0],spec[1]))
	phase(1)
	check(await wait_for(func():return FileAccess.file_exists(path("a_one")) and FileAccess.file_exists(path("b_one"))),"trade reports")
	check(session.model.state.players[a].credits==9910 and session.model.state.players[b].credits==16800,"host confirms buy/sell economic values")
	phase(2)
	check(await wait_for(func():return FileAccess.file_exists(path("a_two")) and FileAccess.file_exists(path("b_two"))),"both clients observe smoke")
	check(session.model.state.field_effects.size()==1 and session.model._count(session.model.state.players[a].bag,"smoke_grenade")==0,"one remote tool consumed exactly once")
	for i in range(81):session.model.tick(.1)
	session.model.state.world="surface";session.model.state.world_revision+=1
	session.model.stations=[{"kind":"loot","uid":"loot_one","world":"surface","pos":Vector2(.5,0),"height":0.0,"locked":true}]
	session.model.loot_reachable=func(_uid,_from):return true
	phase(3)
	check(await wait_for(func():return FileAccess.file_exists(path("a_three")) and FileAccess.file_exists(path("b_three"))),"competing search reports")
	var picks:int=session.model._count(session.model.state.players[a].bag,"lockpick")+session.model._count(session.model.state.players[b].bag,"lockpick")
	check(picks==3 and session.model.state.drops.size()==2,"racing requests yield one opening and one lockpick consumption")
	check(session.model.state.field_effects.is_empty(),"stale world use packet cannot recreate smoke")
	session.model.state.world="bunker";session.model.state.world_revision+=1;session.model.stations=[{"kind":"trader","pos":Vector2.ZERO}]
	for id in [a,b]:session.model.state.players[id].pos=Vector2(10,0)
	phase(4)
	check(await wait_for(func():return FileAccess.file_exists(path("a_done")) and FileAccess.file_exists(path("b_done"))),"client completion reports")
	check(int(read_report("a_done").failures)==0 and int(read_report("b_done").failures)==0,"all remote assertions pass")
	await finish()
