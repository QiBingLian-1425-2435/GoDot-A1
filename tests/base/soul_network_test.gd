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
	client = args.size()>0
	run_id = args[0] if client else str(Time.get_ticks_usec())
	Engine.max_fps=60;call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func wait_for(test: Callable) -> bool:
	var end := Time.get_ticks_msec()+15000
	while not test.call() and Time.get_ticks_msec()<end: await process_frame
	return test.call()
func stage(value: String):
	session.model.state.soul_stage=value;session._broadcast_snapshot(true)
func run():
	session=Session.new();root.add_child(session)
	var result_path := "user://soul_network_"+run_id+".json"
	if client:
		check(session.join("127.0.0.1",29874)==OK,"join real ENet host")
		if not await wait_for(func():return session.local_id>1 and session.model.state.get("soul_stage","")=="ready"):
			check(false,"receive fixture");quit(1);return
		var id: int = session.local_id
		session.send("use",{"index":0})
		check(await wait_for(func():return session.model.state.players[id].get("life","")=="soul"),"remote lethal item confirms soul state")
		var uid: String = session.model.state.players[id].corpse_uid
		check(session.model.state.corpses.has(uid) and session.model.state.players[id].equipment.weapon.is_empty(),"remote snapshot carries corpse and emptied equipment")
		session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.UP})
		session.local_movement.advance(.1,session.model.state.players[id])
		check(session.local_movement.sample_player(session.model.state.players[id]).pos==Vector2.ZERO,"client prediction stays frozen while dead")
		session.send("possess",{"target":1})
		check(await wait_for(func():return session.model.state.players[id].get("possessing",0)==1),"remote possession confirmed")
		check(session.VoiceRules.gain(session.model.state.players,id,1)==1,"voice follows far-away possessed host")
		session.send_voice(PackedByteArray([4,5,6]),1)
		check(await wait_for(func():return session.model.state.get("soul_stage","")=="rescuing"),"host receives possessed voice and begins rescue")
		check(await wait_for(func():return session.model.state.players[id].get("life","")=="alive"),"host rescue reaches independent client")
		check(session.model.state.players[id].hp==30 and session.model.state.players[id].possessing==0,"revive health and detach replicated")
		check(await wait_for(func():return session.model.state.get("soul_stage","")=="host_dead"),"client observes host death")
		session.send("rescue",{"target":1})
		check(await wait_for(func():return session.model.state.players[1].get("life","")=="alive"),"client rescues host through RPC")
		var f := FileAccess.open(result_path,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		check(session.host(29874)==OK,"real host starts")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/soul_network_test.gd","--",run_id])
		check(child>0,"launch independent client process")
		if not await wait_for(func():return session.model.state.players.size()==2):
			check(false,"client connects");quit(1);return
		var id: int = session.model.state.players.keys()[1]
		var p: Dictionary = session.model.state.players[id]
		p.pos=Vector2.ZERO;p.bag=session.model._empty_slots(24);p.bag[0]=session.model._item("poison_capsule",1)
		var host: Dictionary = session.model.state.players[1];host.pos=Vector2(50,0)
		var heard: Array = [];session.voice_received.connect(func(speaker,bytes):heard.append([speaker,bytes]))
		stage("ready")
		check(await wait_for(func():return not heard.is_empty()),"possessed soul voice relays over real transport")
		check(p.get("possessing",0)==1 and p.pos==Vector2.ZERO,"attachment never teleports or controls dead body")
		host.pos=Vector2(.5,0)
		var uid: String = p.get("corpse_uid","")
		check(session.model.command(1,"search",{"uid":uid}),"host searches remote corpse")
		check(await wait_for(func():return session.model.state.containers[uid].revealed==2),"corpse search progresses in live tick")
		var box: Dictionary = session.model.state.containers[uid]
		var gun: Dictionary = box.items[0]
		check(session.model.command(1,"loot_take",{"uid":uid,"index":0,"item_uid":gun.uid}),"host takes remote equipped weapon")
		check(not session.model.command(1,"loot_take",{"uid":uid,"index":0,"item_uid":gun.uid}),"duplicate remote item take rejected")
		check(session.model.command(1,"rescue",{"target":id}),"host begins timed rescue")
		stage("rescuing")
		check(await wait_for(func():return p.get("life","")=="alive"),"host completes rescue")
		# Keep the revived state visible before the reciprocal rescue phase.
		stage("revived")
		var until := Time.get_ticks_msec()+800
		while Time.get_ticks_msec()<until: await process_frame
		host.hp=0;session.model.tick(.01);stage("host_dead")
		check(await wait_for(func():return FileAccess.file_exists(result_path)),"client completes reciprocal rescue")
		if FileAccess.file_exists(result_path):check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"all independent client assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("SOUL_NETWORK checks=",checks," failures=",failures);quit(1 if failures else 0)
