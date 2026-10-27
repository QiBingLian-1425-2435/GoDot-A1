extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT=29981
var session
var client:=false
var child:=-1
var failures:=0
func _initialize():
	client="--client" in OS.get_cmdline_user_args();call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ","guest " if client else "host ",label)
	if not ok:failures+=1
func wait_for(test:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+10000
	while not test.call() and Time.get_ticks_msec()<deadline:await process_frame
	return test.call()
func player()->Dictionary:return session.model.state.players.get(session.local_id,{})
func run():
	session=Session.new();root.add_child(session)
	if client:
		check(session.join("127.0.0.1",PORT)==OK,"connect")
		check(await wait_for(func():return session.model.state.get("infinite_credits",false) and player().get("credits",-1)==0),"host toggle reaches guest")
		session.send("set_infinite_credits",{"enabled":false})
		session.send("buy",{"kind":"scrap","count":1})
		check(await wait_for(func():return session.model._count(player().get("bag",[]),"scrap")==1),"guest purchase succeeds at zero balance")
		check(session.model.state.get("infinite_credits",false) and player().get("credits",-1)==0,"forged guest toggle rejected and balance preserved")
		var f=FileAccess.open("user://infinite_credits_network_result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		DirAccess.remove_absolute("user://infinite_credits_network_result.json")
		check(session.host(PORT)==OK,"listen")
		session.send("set_infinite_credits",{"enabled":true})
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/infinite_credits_network_test.gd","--","--client"])
		check(await wait_for(func():return session.model.state.players.size()==2),"guest admitted")
		session.model.stations=[{"kind":"trader","pos":Vector2.ZERO}]
		for id in session.model.state.players:
			var p:Dictionary=session.model.state.players[id];p.pos=Vector2.ZERO;p.credits=0;p.bag=session.model._empty_slots(24)
		session._broadcast_snapshot(true)
		var done:=await wait_for(func():return FileAccess.file_exists("user://infinite_credits_network_result.json"))
		check(done,"guest report")
		if done:check(int(JSON.parse_string(FileAccess.get_file_as_string("user://infinite_credits_network_result.json")).failures)==0,"guest assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("INFINITE_CREDITS_NETWORK failures=",failures);quit(1 if failures else 0)
