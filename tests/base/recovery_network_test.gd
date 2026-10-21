extends SceneTree
const Main=preload("res://app/main.gd")
const PORT=29941
var game
var checks:=0
var failures:=0
var children: Array[int]=[]
var role:="host"
var run_id:=""
func _initialize():
	var args:=OS.get_cmdline_user_args()
	if args.size()>1:role=args[0];run_id=args[1]
	else:run_id=str(Time.get_ticks_usec())
	Engine.max_fps=60
	call_deferred("run")
func check(ok: bool, message: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func wait_for(test: Callable, seconds: float=15) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await process_frame
	return test.call()
func report_path(who: String) -> String:return "res://artifacts/recovery_"+run_id+"_"+who+".json"
func launch(who: String):
	var pid:=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/recovery_network_test.gd","--",who,run_id])
	children.append(pid);check(pid>0,"launched independent "+who+" process")
func finish():
	if role!="host":
		var file=FileAccess.open(report_path(role),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	for pid in children:
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	game.queue_free();await process_frame
	print("RECOVERY_NETWORK ",role," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func read_report(who: String) -> bool:
	if not FileAccess.file_exists(report_path(who)):return false
	return int(JSON.parse_string(FileAccess.get_file_as_string(report_path(who))).failures)==0
func run():
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game=Main.new();game.name="Main";game.smoke=true;game.elapsed=-10000
	root.add_child(game);game.set_physics_process(false)
	if role!="host":
		check(game.session.join("127.0.0.1",PORT)==OK,"client connects through real ENet")
		game.session.set_physics_process(true);game.joining=true
		if role=="denied":
			check(await wait_for(func():return game.session.mode!="client"),"exploration host rejects the late connection")
			await finish();return
		check(await wait_for(func():return game.in_game and game.session.local_id>1 and game.session.model.state.players.has(game.session.local_id)),"client is admitted in base")
		if role=="reopened":await finish();return
		check(await wait_for(func():return game.session.model.state.get("recovery_test_stage",0)==1 and not game.world_loading,25),"existing client stays connected through exploration loading")
		var player: Dictionary=game.session.model.state.players[game.session.local_id]
		var bag: Array=player.bag.duplicate(true)
		game.session.send("unstuck",{"position":Vector3(999,999,999),"player_id":1})
		check(await wait_for(func():return int(game.session.model.state.players[game.session.local_id].get("relocation_seq",0))>0),"remote recovery request is confirmed by host")
		player=game.session.model.state.players[game.session.local_id]
		check(player.bag==bag,"remote recovery preserves authoritative inventory")
		await process_frame
		var display: Dictionary=game.session.local_movement.sample_player(player)
		check(Vector2(display.pos).distance_to(player.pos)<.15,"client prediction snaps to the confirmed recovery position")
		# Report before disconnecting; host also verifies the original party remains connected.
		var file=FileAccess.open(report_path("client"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
		await wait_for(func():return game.session.model.state.get("recovery_test_stage",0)==2,20)
		await finish();return
	check(game.session.host(PORT)==OK,"real host starts")
	game._enter_base();launch("client")
	if not await wait_for(func():return game.session.model.state.players.size()==2):check(false,"initial client arrived");await finish();return
	var model=game.session.model
	var remote:int=0
	for id in model.state.players:
		if id!=1:remote=id
	model.state.players[1].pos=Vector2(0,-8.2)
	game.session.send("travel",{"route":"bunker_to_surface"})
	check(await wait_for(func():return not game.world_loading,25),"host completes surface loading")
	launch("denied")
	check(await wait_for(func():return FileAccess.file_exists(report_path("denied"))) and read_report("denied"),"new process cannot join during exploration")
	check(model.state.players.size()==2 and model.state.players.has(remote),"locking does not disconnect existing teammate")
	model.state.players[remote].pos=Vector2(210.491,-289.591);model.state.players[remote].height=24.751
	model.reset_transients(remote);model.state.recovery_test_stage=1;game.session._broadcast_snapshot(true)
	check(await wait_for(func():return FileAccess.file_exists(report_path("client"))) and read_report("client"),"client verifies recovery and prediction over real RPC")
	check(model.state.players[1].get("relocation_seq",0)==0,"forged target id cannot relocate the host")
	var route: Dictionary={}
	for entry in model.stations:
		if entry.get("uid")=="surface_to_bunker":route=entry
	model.state.players[1].pos=route.pos;model.state.players[1].height=route.height
	game.session.send("travel",{"route":"surface_to_bunker"})
	check(game.session.can_accept_join(),"base return reopens authoritative admission")
	launch("reopened")
	check(await wait_for(func():return FileAccess.file_exists(report_path("reopened"))) and read_report("reopened"),"fresh process can join the same room after base return")
	model.state.recovery_test_stage=2;game.session._broadcast_snapshot(true)
	await finish()
