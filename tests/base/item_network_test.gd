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
			session.send("buy",{"kind":"scrap","count":3,"price":0,"credits":999999})
			var seq:int=session._intent_seq
			session._intent.rpc_id(1,"buy",{"kind":"scrap","count":3,"world_revision":int(session.model.state.world_revision)},session._session_token,seq)
			check(await wait_for(func():return player().credits==9838 and session.model._count(player().bag,"scrap")==8),"remote material purchase has authoritative price and item")
			await create_timer(.3).timeout
			check(player().credits==9838 and session.model._count(player().bag,"scrap")==8,"repeated intent sequence does not buy twice")
		else:
			session.send("sell",{"count":1,"index":3,"uid":player().bag[3].uid,"value":999999})
			check(await wait_for(func():return player().credits==16800 and player().bag[3].is_empty()),"remote sale credits only catalog value")
			var uid:String=player().bag[4].uid
			session.send("sell",{"index":4,"uid":uid,"count":2,"value":999999})
			check(await wait_for(func():return player().credits==16836 and player().bag[4].count==3),"remote partial material sale")
			check(player().bag[4].uid==uid,"remote remainder retains UID")
			session._intent.rpc_id(1,"sell",{"index":4,"uid":uid,"count":2,"world_revision":int(session.model.state.world_revision)},session._session_token,session._intent_seq)
			await create_timer(.3).timeout
			check(player().credits==16836 and player().bag[4].count==3,"repeated sale sequence does not sell twice")
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
		check(await wait_for(func():return int(session.model.state.containers["loot_one"].revealed)>=1),"host timer reveals first item")
		var box:Dictionary=session.model.state.containers["loot_one"]
		check(box.items[0].has("kind") and (int(box.revealed)>=box.items.size() or box.items[int(box.revealed)].is_empty()),"unsearched content is hidden from client snapshots")
		check(box.items[0].kind in session.model.Loot.FOOD,"remote toilet contents use the host food pool")
		var item_uid:String=box.items[0].uid
		session.send("loot_take",{"uid":"loot_one","index":0,"item_uid":item_uid,"kind":"encrypted_core","count":999})
		check(await wait_for(func():return session.model.state.containers["loot_one"].items[0].is_empty()),"competing clients observe a single item removal")
		report(role+"_three")
		check(await wait_for(func():return session.model.state.get("item_phase",0)==4),"phase4")
		var cash:int=player().credits
		var materials:int=session.model._count(player().bag,"scrap")
		session._intent_seq+=1
		session._intent.rpc_id(1,"buy",{"kind":"scrap","count":1,"world_revision":int(session.model.state.world_revision)-1},session._session_token,session._intent_seq)
		session.send("buy",{"kind":"juice","count":1})
		session.send("sell",{"index":4,"uid":player().bag[4].uid,"count":1})
		await create_timer(.4).timeout
		check(player().credits==cash and session.model._count(player().bag,"scrap")==materials,"distant sale/buy and stale map intent preserve assets")
		await finish();return
	check(session.host(PORT)==OK,"host starts")
	check(session.configure_room("user://material_trade_"+run_id+"/room.json","owner",func(id):return "guest_"+str(id))==OK,"isolated room save configured")
	for who in ["a","b"]:
		var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/item_network_test.gd","--",who,run_id]);children.append(pid)
		check(pid>0,"independent "+who+" client")
	if not await wait_for(func():return FileAccess.file_exists(path("a_ready")) and FileAccess.file_exists(path("b_ready"))):check(false,"clients ready");await finish();return
	var a:=int(read_report("a_ready").id);var b:=int(read_report("b_ready").id)
	session.model.stations=[{"kind":"trader","pos":Vector2.ZERO}]
	for id in [a,b]:
		var p:Dictionary=session.model.state.players[id];p.pos=Vector2.ZERO;p.aim=Vector2.UP;p.credits=10000;p.bag=session.model._empty_slots(24)
		for spec in [["smoke_grenade",1],["lockpick",2],["juice",1],["gold_statue",1],["scrap",5]]:session.model._insert(p.bag,session.model._item(spec[0],spec[1]))
	phase(1)
	check(await wait_for(func():return FileAccess.file_exists(path("a_one")) and FileAccess.file_exists(path("b_one"))),"trade reports")
	check(session.model.state.players[a].credits==9838 and session.model.state.players[b].credits==16836,"host confirms buy/sell economic values")
	var restored=Session.new()
	check(restored.room_store.begin(restored.model,session.room_store.path,"owner")==OK,"reopen confirmed material room save")
	for id in [a,b]:
		restored.model.add_player(id,"restored")
		check(restored.room_store.admit(restored.model,id,"guest_"+str(id))==OK,"restore guest identity")
		check(restored.model.state.players[id].credits==session.model.state.players[id].credits and restored.model._count(restored.model.state.players[id].bag,"scrap")==session.model._count(session.model.state.players[id].bag,"scrap"),"material and credits survive room reopen")
	restored.free()
	phase(2)
	check(await wait_for(func():return FileAccess.file_exists(path("a_two")) and FileAccess.file_exists(path("b_two"))),"both clients observe smoke")
	check(session.model.state.field_effects.size()==1 and session.model._count(session.model.state.players[a].bag,"smoke_grenade")==0,"one remote tool consumed exactly once")
	for i in range(81):session.model.tick(.1)
	session.model.state.world="surface";session.model.state.world_revision+=1
	session.model.stations=[{"kind":"loot","uid":"loot_one","world":"surface","pos":Vector2(.5,0),"height":0.0,"locked":true,"loot_pool":"food","container_name":"厕所"}]
	session.model.loot_reachable=func(_uid,_from):return true
	var initial_counts:Dictionary={}
	for kind in session.model.Items.DEFS:
		initial_counts[kind]=session.model._count(session.model.state.players[a].bag,kind)+session.model._count(session.model.state.players[b].bag,kind)
	phase(3)
	check(await wait_for(func():return session.model.state.containers.has("loot_one")),"first remote search creates container")
	var first_item:Dictionary=session.model.state.containers["loot_one"].items[0].duplicate(true)
	check(await wait_for(func():return FileAccess.file_exists(path("a_three")) and FileAccess.file_exists(path("b_three"))),"competing search reports")
	var picks:int=session.model._count(session.model.state.players[a].bag,"lockpick")+session.model._count(session.model.state.players[b].bag,"lockpick")
	check(picks==3 and session.model.state.drops.is_empty(),"racing searches spend one lockpick and create no duplicate drops")
	var box:Dictionary=session.model.state.containers["loot_one"]
	var after_count:int=session.model._count(session.model.state.players[a].bag,first_item.kind)+session.model._count(session.model.state.players[b].bag,first_item.kind)
	check(box.items[0].is_empty() and after_count-int(initial_counts[first_item.kind])==int(first_item.count),"racing remote take grants original stack exactly once")
	check(session.model.state.field_effects.is_empty(),"stale world use packet cannot recreate smoke")
	session.model.state.world="bunker";session.model.state.world_revision+=1;session.model.stations=[{"kind":"trader","pos":Vector2.ZERO}]
	for id in [a,b]:session.model.state.players[id].pos=Vector2(10,0)
	phase(4)
	check(await wait_for(func():return FileAccess.file_exists(path("a_done")) and FileAccess.file_exists(path("b_done"))),"client completion reports")
	check(int(read_report("a_done").failures)==0 and int(read_report("b_done").failures)==0,"all remote assertions pass")
	await finish()
