extends SceneTree
const Main=preload("res://app/main.gd")
const PORT=29962
var game
var client:=false
var child_pid:=-1
var stage:=0
var elapsed:=0.0
var failures:=0
var finished:=false
func _initialize():
	client="--client" in OS.get_cmdline_user_args()
	call_deferred("start")
func check(ok: bool, message: String):
	print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func start():
	game=Main.new();game.name="Main";game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.set_physics_process(false);game.sound.muted=true
	if client:
		check(game.session.join("127.0.0.1",PORT)==OK,"independent client connects")
		game.joining=true
	else:
		DirAccess.remove_absolute("user://city_network_result.json")
		check(game.session.host(PORT)==OK,"host starts")
		game._enter_base()
		child_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/city_network_client.log"),"--script","res://tests/base/city_doors_network_test.gd","--","--client"])
func _process(delta: float) -> bool:
	if game==null or finished:return false
	elapsed+=delta
	if elapsed>40:
		check(false,"network timeout stage "+str(stage));finish();return false
	var model=game.session.model
	if not client:
		if child_pid>0 and not OS.is_process_running(child_pid):
			check(FileAccess.get_file_as_string("user://city_network_result.json")=="0","client confirmed synchronized door and collision")
			check(stage==3,"host received client open and close intents")
			finish();return false
		if model.state.players.size()<2:return false
		if stage==0 and elapsed>3:
			for route in model.stations:
				if route.get("destination","")!="city":continue
				for p in model.state.players.values():p.pos=route.pos;p.height=0
				check(model.command(1,"travel",{"route":route.uid}),"host travels party to city")
				game._sync_world();stage=1;break
		elif stage==1 and game.world_id=="city" and not game.world_loading:
			var room: Dictionary=game.world.layout.buildings[0]
			for id in model.state.players:
				var p: Dictionary=model.state.players[id]
				p.pos=Vector2(room.door[0],room.door[2])+Vector2(room.normal[0],room.normal[1])*1.2
				p.height=.04;model.reset_transients(id)
			model.state.qa_door=room.id;model.state.qa_stage=1
			game.session._broadcast_snapshot(true);stage=2
		elif stage==2 and model.state.doors.get(model.state.qa_door,false):
			check(game.world._door_open[model.state.qa_door],"host applies client open request")
			model.state.qa_stage=2;game.session._broadcast_snapshot(true);stage=3
		elif stage==3 and not model.state.doors.get(model.state.qa_door,true):
			model.state.qa_stage=3;game.session._broadcast_snapshot(true)
	else:
		if not game.in_game or game.world_loading or game.world_id!="city":return false
		var phase: int=int(model.state.get("qa_stage",0))
		var uid: String=str(model.state.get("qa_door",""))
		if phase==1 and stage==0:
			game._update_interaction()
			check(game.nearest.get("uid")==uid,"client real E candidate")
			game._interact();stage=1
		elif phase==2 and stage==1:
			check(model.state.doors.get(uid,false) and game.world._door_open.get(uid,false),"client receives confirmed open state")
			check(is_equal_approx(game.world._door_nodes[uid].body.rotation.y,-PI/2),"client physical leaf rotates open")
			game._update_interaction();game._interact();stage=2
		elif phase==3 and stage==2:
			check(not model.state.doors[uid] and not game.world._door_open[uid],"client receives confirmed close state")
			finish()
	return false
func finish():
	if finished:return
	finished=true
	if client:
		var file=FileAccess.open("user://city_network_result.json",FileAccess.WRITE)
		file.store_string(str(failures));file.close()
	elif child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
	print("CITY_NETWORK ","client" if client else "host"," failures=",failures)
	game.queue_free();await process_frame
	quit(1 if failures else 0)
