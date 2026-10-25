extends SceneTree
const Session = preload("res://app/network/session.gd")
var session
var child := -1
var client := false
var run_id := ""
var failures := 0
var checks := 0
func _initialize():
	var args := OS.get_cmdline_user_args()
	client=args.size()>0;run_id=args[0] if client else str(Time.get_ticks_usec())
	Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func wait_for(test: Callable) -> bool:
	var end := Time.get_ticks_msec()+12000
	while not test.call() and Time.get_ticks_msec()<end: await process_frame
	return test.call()
func stage(value: String):
	session.model.state.zombie_stage=value;session._broadcast_snapshot(true)
func run():
	session=Session.new();root.add_child(session)
	var result_path := "user://zombie_network_"+run_id+".json"
	if client:
		check(session.join("127.0.0.1",29875)==OK,"join independent ENet host")
		if not await wait_for(func():return session.local_id>1 and session.model.state.get("zombie_stage","")=="ready"):
			check(false,"receive ready fixture");quit(1);return
		var id: int=session.local_id
		session.send("use",{"index":0})
		check(await wait_for(func():return session.model.state.players[id].get("life","")=="zombie"),"client SAN depletion replicates zombie")
		check(session.model.state.players[id].san==0 and session.model.state.players[id].hp==0,"zero SAN and HP replicate")
		check(not session.VoiceRules.can_speak(session.model.state.players,id),"client zombie cannot speak")
		session.send_voice(PackedByteArray([4,5,6]),1)
		session.send("possess",{"target":1});session.send("rest");session.send("pickup",{"uid":"fake"})
		session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
		check(await wait_for(func():return session.model.state.players[id].pos.x>.15),"client zombie movement reaches authority")
		session.send("move",{"direction":Vector2.ZERO})
		check(await wait_for(func():return session.model.state.get("zombie_stage","")=="revived"),"host item revival replicates")
		check(session.model.state.players[id].life=="alive" and session.model.state.players[id].san==30,"client revival restores SAN and life")
		check(await wait_for(func():return session.model.state.get("zombie_stage","")=="contact"),"client receives second zombie state")
		check(session.model.state.players[1].life=="soul","client sees automatic teammate kill")
		session.send("suicide")
		check(await wait_for(func():return session.model.state.players[id].life=="soul"),"client suicide crosses sanitized RPC")
		check(session.model.state.corpses.has(session.model.state.players[id].corpse_uid),"suicide corpse snapshot replicated")
		var f := FileAccess.open(result_path,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		check(session.host(29875)==OK,"host starts")
		child=OS.create_process(OS.get_executable_path(),["--headless","--log-file",ProjectSettings.globalize_path("res://artifacts/base_tests/zombie_client.log"),"--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/zombie_network_test.gd","--",run_id])
		check(child>0,"launch independent zombie client")
		if not await wait_for(func():return session.model.state.players.size()==2):
			check(false,"client connected");quit(1);return
		var id: int=session.model.state.players.keys()[1]
		var p: Dictionary=session.model.state.players[id];var host: Dictionary=session.model.state.players[1]
		var heard: Array=[];session.voice_received.connect(func(speaker,bytes):heard.append([speaker,bytes]))
		p.pos=Vector2.ZERO;p.bag[0]=session.model._item("san_capsule",1);host.pos=Vector2(8,0)
		stage("ready")
		check(await wait_for(func():return p.get("life","")=="zombie" and p.pos.x>.15),"authority accepts remote zombie and motion")
		check(p.possessing==0 and p.hp==0 and not session.model.enemy_damage(id,10),"forged operations and enemy damage cannot revive zombie")
		check(heard.is_empty(),"zombie voice bytes never reach host")
		host.pos=p.pos+Vector2(1.8,0);host.bag[20]=session.model._item("revival_serum",1)
		check(session.model.command(1,"use",{"index":20}),"host uses revival item on client")
		stage("revived")
		var end := Time.get_ticks_msec()+700
		while Time.get_ticks_msec()<end: await process_frame
		session.model.change_san(id,-100);host.pos=p.pos+Vector2(.5,0);session.model.tick(.01)
		check(host.life=="soul" and p.life=="zombie","authority contact kills host")
		stage("contact")
		check(await wait_for(func():return FileAccess.file_exists(result_path)),"client completes suicide and snapshot checks")
		if FileAccess.file_exists(result_path):check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"independent client assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("ZOMBIE_NETWORK checks=",checks," failures=",failures);quit(1 if failures else 0)
