extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT:=29972
var session
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
func folder()->String:return "user://camp_network_"+run_id
func path(name:String)->String:return folder()+"/"+name+".json"
func report(name:String):
	var f=FileAccess.open(path(name),FileAccess.WRITE);f.store_string(JSON.stringify({"id":session.local_id,"failures":failures}));f.close()
func read_report(name:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path(name)))
func phase(value:int):session.model.state.camp_phase=value;session._broadcast_snapshot(true)
func player()->Dictionary:return session.model.state.players[session.local_id]
func assets()->Array:return [player().credits,player().bag.duplicate(true)]
func finish():
	if role!="host":report(role+"_done")
	for pid in children:
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	session.offline();session.queue_free();await process_frame
	print("CAMP_NETWORK ",role," checks=",checks," failures=",failures);quit(1 if failures else 0)
func run():
	session=Session.new();root.add_child(session)
	if role!="host":
		check(session.join("127.0.0.1",PORT)==OK,"real client connects")
		if not await wait_for(func():return session.local_id>1 and session.model.state.players.has(session.local_id)):
			check(false,"admitted");await finish();return
		if role=="c":
			check(await wait_for(func():return session.model.state.camp=={"medical":1,"training":1,"logistics":1}),"late join receives upgraded camp snapshot")
			check(player().max_hp==105 and player().max_stamina==105 and player().max_weight==45,"late join receives actual attributes")
			await finish();return
		report(role+"_ready")
		check(await wait_for(func():return session.model.state.get("camp_phase",0)==1),"phase1")
		session.send("camp_upgrade",{"facility":"medical","expected_level":0,"credits":0,"owner":1,"level":3})
		session._intent.rpc_id(1,"camp_upgrade",{"facility":"medical","expected_level":0,"world_revision":int(session.model.state.world_revision)},session._session_token,session._intent_seq)
		check(await wait_for(func():return int(session.model.state.camp.medical)==1),"shared medical upgrade confirmed")
		await create_timer(.3).timeout
		check(session.model.state.camp.medical==1 and player().max_hp==105,"race and replay cannot skip levels")
		report(role+"_one")
		check(await wait_for(func():return session.model.state.get("camp_phase",0)==2),"phase2")
		session.send("camp_upgrade",{"facility":"training" if role=="a" else "logistics","expected_level":0})
		check(await wait_for(func():return int(session.model.state.camp.training)==1 and int(session.model.state.camp.logistics)==1),"independent facilities both upgrade")
		session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP})
		check(await wait_for(func():return float(session.local_movement._state.get("max_stamina",0))==105),"client prediction receives upgraded stamina")
		check(player().max_weight==45 and player().max_hp==105,"client receives actual team attributes")
		report(role+"_two")
		check(await wait_for(func():return session.model.state.get("camp_phase",0)==3),"phase3")
		var before:Array=assets()
		session.send("camp_upgrade",{"facility":"medical","expected_level":0})
		session.send("camp_upgrade",{"facility":"medical","expected_level":1.5})
		session.send("camp_upgrade",{"facility":"forged","expected_level":0})
		session._intent_seq+=1
		session._intent.rpc_id(1,"camp_upgrade",{"facility":"medical","expected_level":1,"world_revision":int(session.model.state.world_revision)-1},session._session_token,session._intent_seq)
		await create_timer(.4).timeout
		check(assets()==before and session.model.state.camp.medical==1,"stale, malformed and old-map upgrades preserve assets")
		report(role+"_three")
		check(await wait_for(func():return session.model.state.get("camp_phase",0)==4),"phase4")
		before=assets();session.send("camp_upgrade",{"facility":"medical","expected_level":1})
		await create_timer(.3).timeout
		check(assets()==before and session.model.state.camp.medical==1,"distant upgrade refused")
		report(role+"_four")
		check(await wait_for(func():return session.model.state.get("camp_phase",0)==5),"phase5")
		before=assets();session.send("camp_upgrade",{"facility":"medical","expected_level":1})
		await create_timer(.3).timeout
		check(assets()==before and session.model.state.camp.medical==1,"failed save does not publish or charge")
		await finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	check(session.host(PORT)==OK,"host starts")
	check(session.configure_room(path("room"),"owner",func(id):return "guest_"+str(id))==OK,"isolated room configured")
	session.model.stations=[{"kind":"camp_management","pos":Vector2.ZERO}]
	for who in ["a","b"]:
		children.append(OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/camp_upgrade_network_test.gd","--",who,run_id]))
	if not await wait_for(func():return FileAccess.file_exists(path("a_ready")) and FileAccess.file_exists(path("b_ready"))):check(false,"clients ready");await finish();return
	var a:=int(read_report("a_ready").id);var b:=int(read_report("b_ready").id)
	for id in [a,b]:
		var p:Dictionary=session.model.state.players[id];p.pos=Vector2.ZERO;p.credits=50000;p.bag=session.model._empty_slots(24)
		for spec in [["scrap",20],["tape",10],["battery",5],["circuit_board",5],["optical_parts",1]]:session.model._insert(p.bag,session.model._item(spec[0],spec[1]))
	phase(1)
	check(await wait_for(func():return FileAccess.file_exists(path("a_one")) and FileAccess.file_exists(path("b_one"))),"race reports")
	var pa:Dictionary=session.model.state.players[a];var pb:Dictionary=session.model.state.players[b]
	check(session.model.state.camp.medical==1 and pa.credits+pb.credits==99200,"one upgrade charges one payer")
	check(session.model._count(pa.bag,"scrap")+session.model._count(pb.bag,"scrap")==36 and session.model._count(pa.bag,"tape")+session.model._count(pb.bag,"tape")==18,"race consumes exact materials once")
	check(session.model.state.players[1].max_hp==105,"host receives guest-funded upgrade")
	phase(2)
	check(await wait_for(func():return FileAccess.file_exists(path("a_two")) and FileAccess.file_exists(path("b_two"))),"independent reports")
	check(pa.credits+pb.credits==97400 and session.model.state.players[1].max_stamina==105 and session.model.state.players[1].max_weight==45,"independent facilities charge exact costs and buff host")
	children.append(OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/camp_upgrade_network_test.gd","--","c",run_id]))
	check(await wait_for(func():return FileAccess.file_exists(path("c_done"))),"third client joins upgraded camp")
	check(read_report("c_done").failures==0,"late transport client assertions pass")
	var restored=Session.new()
	check(restored.configure_room(path("room"),"owner",func(id):return "guest_"+str(id))==OK and restored.model.state.camp==session.model.state.camp,"reopened room retains all facilities")
	for id in [a,b]:
		restored.model.add_player(id,"returning")
		check(restored.room_store.admit(restored.model,id,"guest_"+str(id))==OK,"rejoin restores stable identity")
		var loaded:Dictionary=restored.model.state.players[id]
		check(loaded.credits==session.model.state.players[id].credits and restored.model._count(loaded.bag,"scrap")==session.model._count(session.model.state.players[id].bag,"scrap") and loaded.max_stamina==105,"returning member retains assets and benefits")
	restored.model.add_player(999,"new member")
	check(restored.model.state.players[999].max_hp==105 and restored.model.state.players[999].max_weight==45,"new late member receives shared camp")
	restored.free()
	phase(3)
	check(await wait_for(func():return FileAccess.file_exists(path("a_three")) and FileAccess.file_exists(path("b_three"))),"rejection reports")
	for p in [pa,pb]:p.pos=Vector2(10,0)
	phase(4)
	check(await wait_for(func():return FileAccess.file_exists(path("a_four")) and FileAccess.file_exists(path("b_four"))),"distance reports")
	for p in [pa,pb]:p.pos=Vector2.ZERO
	var original_path:String=session.room_store.path
	session.room_store.path="";session.upgrade_checkpoint=func(_trial):return ERR_CANT_CREATE
	phase(5)
	check(await wait_for(func():return FileAccess.file_exists(path("a_done")) and FileAccess.file_exists(path("b_done"))),"client completion reports")
	session.room_store.path=original_path
	check(read_report("a_done").failures==0 and read_report("b_done").failures==0,"all remote assertions pass")
	await finish()
