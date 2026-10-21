extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT:=29961
var session
var client:=false
var phase:=1
var folder:=""
var elapsed:=0.0
var checks:=0
var failures:=0
var child:=-1
var prepared:=false
var sent:=false
var done:=false
var old_id:=0
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:call_deferred("run_series");return
	if args.size()>=2:phase=int(args[0]);folder=args[1]
	else:folder="user://room_save_network_"+str(Time.get_ticks_usec())
	client="--client" in args;Engine.max_fps=60;call_deferred("start")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func count(items: Array, kind: String) -> int:
	var value:=0
	for item in items:
		if item.get("kind")==kind:value+=int(item.count)
	return value
func report_path() -> String:return folder+"/client_"+str(phase)+".json"
func start():
	session=Session.new();root.add_child(session)
	if client:
		check(session.join("127.0.0.1",PORT)==OK,"independent client connects")
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		check(session.host(PORT)==OK,"fresh host process starts phase "+str(phase))
		# ENet has no Steam identity. This server-owned fixture substitutes only the authenticated account lookup.
		check(session.configure_room(folder+"/room.json","owner_a",func(_peer):return "guest_x")==OK,"host opens stable room file")
		if phase==1:session.send("transfer",{"from":"stash","index":5,"to":"bag"})
		else:check(count(session.model.state.players[1].stash,"water")==0,"host warehouse survives complete process restart")
		session.model.state.qa_ready=false
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/room_save_network_test.gd","--",str(phase),folder,"--client"])
		check(child>0,"launched a separate guest process")
func _process(delta: float) -> bool:
	elapsed+=delta
	if elapsed>25:
		check(false,"network persistence completes within bound");finish();return false
	if session==null:return false
	if client:client_step()
	else:host_step()
	return false
func host_step():
	var model=session.model
	if child>0 and not OS.is_process_running(child):
		var result: Variant=JSON.parse_string(FileAccess.get_file_as_string(report_path())) if FileAccess.file_exists(report_path()) else null
		check(result is Dictionary and result.failures==0,"remote process assertions: "+str(result))
		if phase!=2:check(not model.state.players.has(old_id),"disconnect removes only active player, retaining durable profile")
		if phase==1:
			var second=Session.new();check(second.room_store.begin(second.model,folder+"/room.json","owner_a")==OK and count(second.room_store.profiles.guest_x.bag,"canned_food")==0,"guest consumption is on disk after disconnect");second.free()
		finish();return
	if done or model.state.players.size()<2:return
	var remote:=0
	for id in model.state.players:
		if id!=1:remote=int(id)
	var player: Dictionary=model.state.players[remote]
	if not prepared:
		old_id=remote
		if phase==1:player.hunger=0
		if phase==2:player.thirst=0
		if phase>=2:check(count(player.bag,"canned_food")==0,"returning guest has no respawned food")
		if phase==3:check(count(player.bag,"water")==0,"host shutdown retained the connected guest's consumed water")
		model.state.qa_ready=true;session._broadcast_snapshot(true);prepared=true
	if (phase==1 and count(player.bag,"canned_food")==0) or (phase==2 and count(player.bag,"water")==0):
		var disk: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/room.json"))
		check(count(disk.profiles.guest_x.bag,"canned_food" if phase==1 else "water")==0,"accepted consumption RPC is immediately durable")
		if phase==1:model.state.qa_done=true;session._broadcast_snapshot(true)
		else:session.offline()
		done=true
func client_step():
	if phase==2 and sent and session.mode=="offline":
		check(count(session.model.state.players[1].bag,"canned_food")==2,"leaving another host does not overwrite local solo inventory")
		finish();return
	if session.local_id<=0 or not session.model.state.players.has(session.local_id):return
	var model=session.model;var p: Dictionary=model.state.players[session.local_id]
	if not model.state.get("qa_ready",false):return
	if not sent:
		if phase==1:
			check(count(p.bag,"canned_food")==2,"new guest initially has two food")
			session.send("use",{"index":3});session.send("use",{"index":3})
		elif phase==2:
			check(count(p.bag,"canned_food")==0,"new connection restores the previous guest profile")
			session.send("use",{"index":2});session.send("use",{"index":2})
		else:
			check(count(p.bag,"canned_food")==0 and count(p.bag,"water")==0,"third independent session restores both empty stacks")
			finish();return
		sent=true
	if phase==1 and model.state.get("qa_done",false):
		check(count(p.bag,"canned_food")==0,"host-confirmed food consumption reaches client")
		finish()
func finish():
	if not client:
		var report:=FileAccess.open(folder+"/host_"+str(phase)+".json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":checks,"failures":failures}));report.close()
	if client:
		var file:=FileAccess.open(report_path(),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"peer_id":session.local_id}));file.close()
	elif child>0 and OS.is_process_running(child):OS.kill(child)
	if session!=null:session.offline();session.free();session=null
	print("ROOM_SAVE_NETWORK ","client" if client else "host"," phase=",phase," checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func run_series():
	folder="user://room_save_network_suite_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for index in [1,2,3]:
		var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path(folder+"/host_"+str(index)+".log"),"--script","res://tests/base/room_save_network_test.gd","--",str(index),folder])
		var deadline:=Time.get_ticks_msec()+20000
		while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
		var file:=folder+"/host_"+str(index)+".json"
		var result: Variant=JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else null
		check(result is Dictionary and result.failures==0,"independent restart phase "+str(index)+": "+str(result))
		if failures>0:break
	print("ROOM_SAVE_NETWORK_SERIES ",checks," phases; ",failures," failures")
	quit(1 if failures else 0)
