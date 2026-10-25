extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var child := -1
var checks := 0
var failures := 0
func _initialize(): Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures+=1
func wait_for(test: Callable) -> bool:
	var end:=Time.get_ticks_msec()+12000
	while not test.call() and Time.get_ticks_msec()<end: await process_frame
	return test.call()
func run():
	session=Session.new();root.add_child(session)
	var args:=OS.get_cmdline_user_args()
	var client:=args.size()>0
	var run_id:=args[0] if client else str(Time.get_ticks_usec())
	var result_path:="user://extraction_network_"+run_id+".json"
	if client:
		check(session.join("127.0.0.1",29876)==OK,"client joins independent host")
		if not await wait_for(func():return session.local_id>1 and session.model.state.get("extraction_ready",false)):
			check(false,"receive fixture");quit(1);return
		var notices: Array=[];session.notice.connect(func(msg):notices.append(msg))
		session.send("travel",{"route":"extract"})
		check(await wait_for(func():return not notices.is_empty()),"host sends extraction rejection to client")
		check(session.model.state.world=="surface","remote request cannot drag distant living host into camp")
		session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.RIGHT})
		session.send("fire")
		check(await wait_for(func():return session.model.state.players[1].life=="soul"),"remote gunfire kills host and replicates soul")
		check(session.model.state.corpses.has(session.model.state.players[1].corpse_uid),"client receives host corpse")
		session.send("travel",{"route":"extract"})
		check(await wait_for(func():return session.model.state.world=="bunker"),"remote extraction succeeds after teammate death")
		var f:=FileAccess.open(result_path,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		check(session.host(29876)==OK,"host starts")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/base_tests/party_extraction_client.log"),"--script","res://tests/base/party_extraction_network_test.gd","--",run_id])
		check(child>0,"launch independent client")
		if not await wait_for(func():return session.model.state.players.size()==2):
			check(false,"client connected");if child>0:OS.kill(child)
			quit(1);return
		var m=session.model
		m.state.world="surface";m.state.phase="exploration";m.state.targets=[]
		m.state.players[1].pos=Vector2(4,0);m.state.players[1].hp=1
		for id in m.state.players:
			if id!=1:m.state.players[id].pos=Vector2.ZERO
		m.stations=[{"kind":"travel","uid":"extract","world":"surface","destination":"bunker","pos":Vector2.ZERO,"height":0,"spawn":Vector3.ZERO}]
		m.state.extraction_ready=true;session._broadcast_snapshot(true)
		check(await wait_for(func():return FileAccess.file_exists(result_path)),"remote flow finishes")
		check(m.state.world=="bunker" and m.world_cache.surface.corpses.size()==1,"authority preserves corpse and completes party return")
		if FileAccess.file_exists(result_path):check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"client assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("PARTY_EXTRACTION_NETWORK checks=",checks," failures=",failures);quit(1 if failures else 0)
