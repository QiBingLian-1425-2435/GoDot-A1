extends SceneTree
const Session=preload("res://app/network/session.gd")
const PORT=29979
var session
var client:=false
var child:=-1
var failures:=0
func _initialize():
	client="--client" in OS.get_cmdline_user_args()
	Engine.max_fps=60
	call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ","client " if client else "host ",label)
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
		var ready:=await wait_for(func():return player().get("hunger",100)==0 and player().get("max_weight",44)==22)
		check(ready,"host hunger and reduced capacity reach guest")
		if ready:
			session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
			check(await wait_for(func():return player().get("input_max_weight",0)==22),"prediction anchor carries reduced capacity")
			session.send("use",{"index":0,"hunger":100,"max_weight":999})
			check(await wait_for(func():return player().get("max_weight",0)==44 and player().get("hunger",0)>50),"remote food restores host-confirmed capacity")
			check(player().hunger<56 and session.model._count(player().bag,"energy_bar")==0,"forged hunger ignored and food consumed once")
		var f=FileAccess.open("user://satiety_network_result.json",FileAccess.WRITE)
		f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		DirAccess.remove_absolute("user://satiety_network_result.json")
		check(session.host(PORT)==OK,"listen")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/satiety_network_test.gd","--","--client"])
		var joined:=await wait_for(func():return session.model.state.players.size()==2)
		check(joined,"guest admitted")
		if joined:
			session.model.state.world="ground_zero"
			for id in session.model.state.players:
				if id==1:continue
				var p:Dictionary=session.model.state.players[id]
				p.hunger=0;p.bag=session.model._empty_slots(24);p.bag[0]=session.model._item("energy_bar",1)
				session.model._update_weight(p)
			session._broadcast_snapshot(true)
		var done:=await wait_for(func():return FileAccess.file_exists("user://satiety_network_result.json"))
		check(done,"remote report received")
		if done:check(int(JSON.parse_string(FileAccess.get_file_as_string("user://satiety_network_result.json")).failures)==0,"all remote assertions pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("SATIETY_NETWORK failures=",failures);quit(1 if failures else 0)
