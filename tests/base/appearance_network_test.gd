extends SceneTree
const Session=preload("res://app/network/session.gd")
const Rules=preload("res://features/player/appearance_rules.gd")
var session
var child:=-1
var client:=false
var run_id:=""
var failures:=0
func _initialize():
	var args:=OS.get_cmdline_user_args();client=not args.is_empty()
	run_id=args[0] if client else str(Time.get_ticks_usec())
	Engine.max_fps=60;call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func wait_for(test:Callable)->bool:
	var end:=Time.get_ticks_msec()+10000
	while not test.call() and Time.get_ticks_msec()<end:await process_frame
	return test.call()
func run():
	session=Session.new();root.add_child(session)
	var result_path:="user://appearance_network_"+run_id+".json"
	if client:
		check(session.join("127.0.0.1",29989)==OK,"real ENet client connects")
		check(await wait_for(func():return session.local_id>1 and session.model.state.players.has(session.local_id)),"client receives initial appearance")
		var id:int=session.local_id
		var wanted:=Rules.defaults("female");wanted.hair="#cc8844";wanted.skin="#885533";wanted.shirt="#227799";wanted.pants="#334466"
		session.send("appearance",wanted)
		check(await wait_for(func():return session.model.state.players[id].appearance==wanted),"host confirms gender and all four colors to client")
		check(session.model.state.players[1].appearance==Rules.defaults(),"client cannot recolor host")
		var bad:Dictionary=wanted.duplicate();bad.skin="#zzzzzz"
		session.send("appearance",bad)
		await create_timer(.3).timeout
		check(session.model.state.players[id].appearance==wanted,"invalid network appearance is rejected")
		var f:=FileAccess.open(result_path,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		check(session.host(29989)==OK,"real appearance host starts")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/appearance_network_test.gd","--",run_id])
		check(await wait_for(func():return FileAccess.file_exists(result_path)),"client finishes appearance verification")
		if FileAccess.file_exists(result_path):
			check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"all client appearance checks pass")
			DirAccess.remove_absolute(result_path)
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("APPEARANCE_NETWORK failures=",failures);quit(1 if failures else 0)
