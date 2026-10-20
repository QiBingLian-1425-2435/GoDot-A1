extends SceneTree
## Two real Main/Session processes, source map collision and client travel intents.
const Main = preload("res://app/main.gd")
const PORT := 29931
var game
var client := false
var child_pid := -1
var phase := 0
var elapsed := 0.0
var phase_time := 0.0
var failures: Array[String] = []
var checks := 0
var remote_id := 0
var start_pos := Vector2.ZERO
var shot_requested := false
var door_requested := false
var door_verified := false
var saw_rejection := false
var finished := false
var diagnostic_second := -1
var vision_test:=false
var vision_checked:=false
var vision_turned:=false
var vision_start: Dictionary={}
func _initialize() -> void:
	client="--client" in OS.get_cmdline_user_args()
	vision_test="--vision" in OS.get_cmdline_user_args()
	Engine.max_fps=60
	call_deferred("start")
func check(ok: bool, message: String) -> void:
	checks+=1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures.append(message)
func start() -> void:
	game=Main.new();game.name="Main";game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.set_physics_process(false)
	game.session.notice.connect(func(message: String):
		print("GROUND_ZERO_NET_NOTICE ",message)
		if message.contains("靠近地图入口"):saw_rejection=true)
	if client:
		check(game.session.join("127.0.0.1",PORT)==OK,"client starts an independent ENet connection")
		game.session.set_physics_process(true);game.joining=true
	else:
		DirAccess.remove_absolute(result_path())
		check(game.session.host(PORT)==OK,"host starts the real main scene")
		game._enter_base()
		var args: PackedStringArray=["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/ground_zero_network_client.log"),"--script","res://tests/base/ground_zero_network_test.gd","--","--client"]
		if vision_test:args.append("--vision")
		child_pid=OS.create_process(OS.get_executable_path(),args)
		check(child_pid>0,"a separate client process is running")
func _process(delta: float) -> bool:
	if game==null or finished:return false
	elapsed+=delta;phase_time+=delta
	var second := int(elapsed)/2
	if second!=diagnostic_second:
		diagnostic_second=second
		print("GROUND_ZERO_NET_STATE ","client" if client else "host"," phase=",phase," in_game=",game.in_game," mode=",game.session.mode," world=",game.world_id," stage=",game.session.model.state.get("qa_stage",-1)," players=",game.session.model.state.players.size())
	if elapsed>45:
		check(false,"bounded network completion phase="+str(phase));finish();return false
	if client: client_step()
	else: host_step()
	return false
func host_step() -> void:
	var model=game.session.model
	if child_pid>0 and not OS.is_process_running(child_pid):
		var result: Variant=JSON.parse_string(FileAccess.get_file_as_string(result_path())) if FileAccess.file_exists(result_path()) else null
		check(result is Dictionary and result.failures.is_empty(),"client map assertions: "+str(result))
		check(phase>=5 and model.state.world=="bunker","client intents completed the full round trip")
		finish();return
	if model.state.players.size()<2:return
	for id in model.state.players:
		if id!=1:remote_id=int(id)
	var p: Dictionary=model.state.players[remote_id]
	if phase==0 and elapsed>2:
		p.pos=Vector2(0,-8.2);p.height=0
		model.reset_transients(remote_id)
		model.state.qa_stage=1;game.session._broadcast_snapshot(true)
		phase=1
	elif phase==1 and model.state.world=="surface" and not game.world_loading:
		check(game.world_id=="surface","client E intent mounted the same source map on the host")
		if vision_test:
			vision_start={"pos":p.pos,"height":p.height}
			var host: Dictionary=model.state.players[1]
			var forward:=Vector2.UP
			for i in range(24):
				var direction:=Vector2.from_angle(TAU*float(i)/24)
				game.vision.aim=direction
				if game.vision.can_see(Vector3(host.pos.x+direction.x*4.8,float(host.height)+1,host.pos.y+direction.y*4.8)):
					forward=direction;break
			host.aim=forward;p.aim=forward;p.pos=host.pos+forward*4.8;p.height=host.height
			model.reset_transients(remote_id);model.state.qa_front=forward;model.state.qa_stage=8;phase=8
		else:
			start_pos=p.pos;model.state.qa_stage=2;phase=2
		game.session._broadcast_snapshot(true);phase_time=0
	elif phase==8 and p.shots>0 and phase_time>.5:
		check(game.actors[remote_id].visible,"host vision still sees the client in its own forward cone")
		check(Vector2(p.aim).dot(-Vector2(model.state.qa_front))>.9,"the remote player's independent turn reaches authority")
		p.pos=vision_start.pos;p.height=vision_start.height;p.shots=0;model.state.shots.clear();model.reset_transients(remote_id)
		start_pos=p.pos;model.state.qa_stage=2;game.session._broadcast_snapshot(true);phase=2;phase_time=0
	elif phase==2 and p.shots>0 and phase_time>1.6:
		check(start_pos.distance_to(p.pos)>.5 and start_pos.distance_to(p.pos)<5,"client movement is confirmed through source collision on the host")
		check(float(p.height)<-.5,"the host confirms the negative source terrain elevation")
		for station in model.stations:
			if station.get("kind")=="door":
				p.pos=station.pos;p.height=station.height;model.reset_transients(remote_id)
				model.state.qa_door=station.uid;break
		model.state.qa_stage=6;game.session._broadcast_snapshot(true);phase=6
	elif phase==6 and bool(model.state.doors.get(model.state.qa_door,false)):
		var part: Dictionary=game.world._door_nodes[model.state.qa_door][0]
		check(part.node.transform.is_equal_approx(part.open),"a client door intent applies the source open pose on the host")
		var route: Dictionary={}
		for station in model.stations:
			if station.get("destination")=="cave":route=station
		p.pos=route.pos;p.height=route.height;model.reset_transients(remote_id)
		model.state.qa_stage=3;game.session._broadcast_snapshot(true);phase=3
	elif phase==3 and model.state.world=="cave":
		model.state.qa_stage=4;game.session._broadcast_snapshot(true);phase=4
	elif phase==4 and model.state.world=="surface":
		check(true,"the client can walk to the original cave exit and return")
		check(bool(model.state.doors.get(model.state.qa_door,false)),"the host preserves shared door state across the cave round trip")
		var entry:=Vector2(455.72,-103.62)
		p.pos=entry;p.height=-1.13;model.reset_transients(remote_id)
		model.state.qa_stage=5;game.session._broadcast_snapshot(true);phase=5
func client_step() -> void:
	if not game.in_game or game.world_loading or not game.session.model.state.players.has(game.session.local_id):return
	var model=game.session.model
	var p: Dictionary=model.state.players[game.session.local_id]
	var stage:=int(model.state.get("qa_stage",0))
	if stage==0 and phase==0:
		game.session.send("travel",{"route":"bunker_to_surface"});phase=1
	if stage==1 and phase<2 and game.world_id=="bunker" and Vector2(p.pos).distance_to(Vector2(0,-8.2))<.2:
		check(saw_rejection,"a remote client cannot travel from outside the entrance")
		game._update_interaction();game._interact();phase=2
	elif stage==8 and not vision_checked:
		game._update_actors(.016);game.vision.update(game,.06)
		if not vision_turned:
			check(game.vision.enabled and game.actors[game.session.local_id].visible and not game.actors[1].visible,"the remote client hides the host behind its own observer")
			game.session.send("move",{"direction":Vector2.ZERO,"aim":-Vector2(model.state.qa_front)})
			vision_turned=true
		elif game.actors[1].visible:
			check(true,"turning the client's local aim reveals the host without sharing the host's cone")
			game.session.send("fire");vision_checked=true
	elif stage==2 and game.world_id=="surface":
		if phase==2:
			check(game.player_physics.spatial_enabled and game.world.data.renderers.size()>48000,"the client loads source geometry and the same spatial solver")
			phase=3;phase_time=0
		game.session.send("move",{"direction":Vector2.UP if phase_time<1 else Vector2.ZERO,"aim":Vector2.DOWN})
		if phase_time>1.2 and not shot_requested:
			game.session.send("fire");shot_requested=true
			var shown: Vector3=game.actors[game.session.local_id].position
			check(absf(shown.y-float(p.height))<.2,"client prediction and the visible duck preserve the confirmed floor elevation")
	elif stage==6 and not door_requested:
		game.session.send("move",{"direction":Vector2.ZERO})
		game.session.send("door",{"uid":model.state.qa_door});door_requested=true
	elif stage==3 and game.world_id=="surface" and phase<4:
		if not door_verified:
			var part: Dictionary=game.world._door_nodes[model.state.qa_door][0]
			check(bool(model.state.doors.get(model.state.qa_door,false)) and part.node.transform.is_equal_approx(part.open),"the confirmed door state and source pose reach the remote client")
			door_verified=true
		var route: Dictionary={}
		for station in model.stations:
			if station.get("destination")=="cave":route=station
		if Vector2(p.pos).distance_to(route.pos)<.2:
			game.session.send("move",{"direction":Vector2.ZERO})
			game.session.send("travel",{"route":route.uid});phase=4
	elif stage==4 and game.world_id=="cave":
		var route: Dictionary=model.stations[0]
		var offset: Vector2=route.pos-Vector2(p.pos)
		if offset.length()>2.1:game.session.send("move",{"direction":offset.normalized(),"aim":offset.normalized()})
		elif phase<5:
			check(game.world.zone=="cave" and absf(float(p.height))<1,"the client sees the source cave at its own floor elevation")
			game.session.send("move",{"direction":Vector2.ZERO})
			game.session.send("travel",{"route":route.uid});phase=5
	elif stage==5 and game.world_id=="surface" and phase<6:
		if Vector2(p.pos).distance_to(Vector2(455.72,-103.62))<.2:
			game.session.send("move",{"direction":Vector2.ZERO})
			game.session.send("travel",{"route":"surface_to_bunker"});phase=6
	elif phase==6 and game.world_id=="bunker":
		check(game.world.obstacles().size()==43 and game.ui._stash_access,"returning restores local base UI and physics")
		game._return_menu();finish()
func result_path() -> String:return "user://ground_zero_network_%d.json"%PORT
func finish() -> void:
	if finished:return
	finished=true
	if client:
		var file:=FileAccess.open(result_path(),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	else:
		if child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
	print("GROUND_ZERO_NETWORK ","client" if client else "host"," ",checks," checks; ",failures.size()," failures")
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
