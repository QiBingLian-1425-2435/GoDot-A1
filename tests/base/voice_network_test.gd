extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT=29957
var session: Node
var role:="host"
var run_id:=""
var checks:=0
var failures:=0
var children: Array[int]=[]
var heard: Array=[]
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()>1:role=args[0];run_id=args[1]
	else:run_id=str(Time.get_ticks_usec())
	Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",role," ",label)
	if not ok:failures+=1
func wait_for(test: Callable, seconds:=10.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await process_frame
	return test.call()
func path(who: String) -> String:return "user://voice_"+run_id+"_"+who+".json"
func write_report(who: String):
	var f=FileAccess.open(path(who),FileAccess.WRITE)
	f.store_string(JSON.stringify({"id":session.local_id,"heard":heard,"failures":failures}));f.close()
func read_report(who: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path(who)))
func finish():
	if role!="host":write_report(role+"_done")
	for pid in children:
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	session.offline();session.queue_free();await process_frame
	print("VOICE_NETWORK ",role," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func phase(value: int):
	session.model.state.voice_test_phase=value;session._broadcast_snapshot(true)
func send_burst(marker: int, base: int):
	for i in range(6):
		session.send_voice(PackedByteArray([marker]),base+i)
		await create_timer(0.035).timeout
func run():
	session=Session.new();root.add_child(session);session.set_physics_process(false)
	session.voice_received.connect(func(speaker,bytes):heard.append([speaker,int(bytes[0]) if not bytes.is_empty() else 0]))
	if role!="host":
		check(session.join("127.0.0.1",PORT)==OK,"real ENet connects")
		check(await wait_for(func():return session.local_id>1 and session.model.state.players.has(session.local_id)),"admitted with session token")
		write_report(role+"_ready")
		check(await wait_for(func():return int(session.model.state.get("voice_test_phase",0))==1),"phase1 arrived")
		await send_burst(2 if role=="near" else 3,100)
		await create_timer(0.4).timeout
		if role=="near":check(heard.any(func(entry):return entry[1]==1),"near client hears host")
		else:check(heard.is_empty(),"far client receives no voice at all")
		write_report(role+"_one")
		check(await wait_for(func():return int(session.model.state.get("voice_test_phase",0))==2),"phase2 arrived")
		heard.clear();await send_burst(2 if role=="near" else 3,200)
		await create_timer(0.4).timeout
		check(heard.any(func(entry):return entry[1]==(3 if role=="near" else 2)),"nearby clients hear each other through host")
		check(not heard.any(func(entry):return entry[0]==session.local_id),"no own echo")
		write_report(role+"_two")
		check(await wait_for(func():return int(session.model.state.get("voice_test_phase",0))==3),"phase3 arrived")
		session._voice_up.rpc_id(1,PackedByteArray([9]),300,session._session_token-1,int(session.model.state.world_revision))
		session._voice_up.rpc_id(1,PackedByteArray([9]),301,session._session_token,int(session.model.state.world_revision)-1)
		if role=="near":
			for i in range(3):session.send_voice(PackedByteArray(),310+i);await create_timer(.035).timeout
		await create_timer(.3).timeout
		if role=="far":check(heard.any(func(entry):return entry[1]==0),"stop packet routed to listener")
		write_report(role+"_three")
		check(await wait_for(func():return int(session.model.state.get("voice_test_phase",0))==4),"private possession phase arrived")
		heard.clear();await send_burst(4 if role=="near" else 5,400)
		await create_timer(.4).timeout
		check(heard.any(func(entry):return entry[1]==6),"both clients hear living host in their allowed channel")
		if role=="near":check(not heard.any(func(entry):return entry[1]==5),"attached ghost cannot hear third living teammate over real RPC")
		else:check(not heard.any(func(entry):return entry[1]==4),"third living teammate cannot hear ghost over real RPC")
		write_report(role+"_four")
		check(await wait_for(func():return int(session.model.state.get("voice_test_phase",0))==5),"detach phase arrived")
		heard.clear();await send_burst(8 if role=="near" else 9,500)
		await create_timer(.4).timeout
		if role=="near":check(heard.is_empty(),"detached ghost receives no living voice")
		else:check(heard.any(func(entry):return entry[1]==7) and not heard.any(func(entry):return entry[1]==8),"living voice continues while detached ghost stays silent")
		await finish();return
	check(session.host(PORT)==OK,"host starts")
	for who in ["near","far"]:
		var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/voice_network_test.gd","--",who,run_id])
		children.append(pid);check(pid>0,"independent "+who+" process launched")
	if not await wait_for(func():return FileAccess.file_exists(path("near_ready")) and FileAccess.file_exists(path("far_ready"))):check(false,"clients ready");await finish();return
	var near_id:=int(read_report("near_ready").id);var far_id:=int(read_report("far_ready").id)
	session.model.state.players[1].pos=Vector2.ZERO
	session.model.state.players[near_id].pos=Vector2(2,0)
	session.model.state.players[far_id].pos=Vector2(30,0)
	phase(1);await send_burst(1,100)
	check(await wait_for(func():return FileAccess.file_exists(path("near_one")) and FileAccess.file_exists(path("far_one"))),"phase1 client reports")
	check(heard.any(func(entry):return entry[0]==near_id) and not heard.any(func(entry):return entry[0]==far_id),"host hears near only")
	check(int(read_report("near_one").failures)==0 and int(read_report("far_one").failures)==0,"near receives / far excluded over real RPC")
	heard.clear();session.model.state.players[far_id].pos=Vector2(4,0)
	phase(2);await send_burst(1,200)
	check(await wait_for(func():return FileAccess.file_exists(path("near_two")) and FileAccess.file_exists(path("far_two"))),"phase2 client reports")
	check(heard.any(func(entry):return entry[0]==far_id),"walking into range enables host audio")
	check(int(read_report("near_two").failures)==0 and int(read_report("far_two").failures)==0,"client-to-client relay verified")
	phase(3)
	check(await wait_for(func():return FileAccess.file_exists(path("near_three")) and FileAccess.file_exists(path("far_three"))),"clients complete stale-packet phase")
	check(not heard.any(func(entry):return entry[1]==9),"stale token and world packets rejected over RPC")
	var ghost: Dictionary=session.model.state.players[near_id]
	ghost.pos=Vector2(1,0);ghost.hp=0;session.model.tick(.01)
	check(session.model.command(near_id,"possess",{"target":1}),"nearby ghost attaches to real host")
	heard.clear();phase(4);await send_burst(6,400)
	check(await wait_for(func():return FileAccess.file_exists(path("near_four")) and FileAccess.file_exists(path("far_four"))),"clients complete private-channel phase")
	check(heard.any(func(entry):return entry[1]==4),"possessed host hears ghost over transport")
	check(session.model.command(1,"release_soul"),"host detaches ghost")
	heard.clear();phase(5);await send_burst(7,500)
	check(await wait_for(func():return FileAccess.file_exists(path("near_done")) and FileAccess.file_exists(path("far_done"))),"clients finish detach phase")
	check(not heard.any(func(entry):return entry[1]==8),"host cannot hear detached ghost over transport")
	check(int(read_report("near_done").failures)==0 and int(read_report("far_done").failures)==0,"stop/no-echo client assertions pass")
	await finish()
