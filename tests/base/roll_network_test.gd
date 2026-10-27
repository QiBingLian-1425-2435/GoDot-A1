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
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func wait_for(test:Callable)->bool:
	var end:=Time.get_ticks_msec()+10000
	while not test.call() and Time.get_ticks_msec()<end:await process_frame
	return test.call()
func run():
	session=Session.new();root.add_child(session)
	session.local_movement.solver=session.model.solve_motion.bind(0)
	var result_path:="user://jump_"+run_id+".json"
	if client:
		check(session.join("127.0.0.1",29987)==OK,"join real ENet host")
		check(await wait_for(func():return session.local_id>1 and session.model.state.get("roll_ready",false)),"receive jump fixture")
		var id:int=session.local_id
		session.request_roll();session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.UP})
		session.local_movement.advance(.01,session.model.state.players[id])
		check(session.local_movement.sample_player(session.model.state.players[id]).roll.active,"local predicted jump starts before reply")
		var saw_jump:=false
		var started:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-started<1800:
			session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP})
			var p:Dictionary=session.model.state.players[id]
			if p.roll.active:
				saw_jump=true
				check(float(p.get("height",0))>0,"authoritative airborne height reaches client")
			await process_frame
		var p:Dictionary=session.model.state.players[id]
		check(saw_jump and not p.roll.active and absf(p.get("height",0))<.03 and absf(p.pos.x)<.5,"host confirms one jump and landing")
		var display:Dictionary=session.local_movement.sample_player(p)
		check(display.pos.distance_to(p.pos)<.12 and not display.roll.active,"prediction converges after jump without restarting it")
		var f:=FileAccess.open(result_path,FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures}));f.close()
	else:
		check(session.host(29987)==OK,"host starts")
		child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/roll_network_test.gd","--",run_id])
		check(await wait_for(func():return session.model.state.players.size()==2),"independent client connects")
		for id in session.model.state.players:
			if id!=1:session.model.state.players[id].pos=Vector2.ZERO
		session.model.state.roll_ready=true;session._broadcast_snapshot(true)
		check(await wait_for(func():return FileAccess.file_exists(result_path)),"client finishes movement verification")
		if FileAccess.file_exists(result_path):check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"all remote jump checks pass")
		if child>0 and OS.is_process_running(child):OS.kill(child)
	session.offline();session.queue_free();await process_frame
	print("ROLL_NETWORK checks=",checks," failures=",failures);quit(1 if failures else 0)
