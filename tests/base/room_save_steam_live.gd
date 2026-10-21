extends SceneTree
const Main=preload("res://app/main.gd")
var game
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func wait_for(test: Callable) -> bool:
	var until:=Time.get_ticks_msec()+30000
	while not test.call() and Time.get_ticks_msec()<until:await process_frame
	return test.call()
func run():
	if not "--steam-live-test" in OS.get_cmdline_user_args():quit(2);return
	game=Main.new();game.smoke=true;game.room_save_root="user://room_save_native_"+str(Time.get_ticks_usec());game.legacy_profile_path=""
	root.add_child(game);game.set_process(false);game.set_physics_process(false)
	game.smoke=false
	var service=game.steam_service
	if not service.initialize():check(false,service.status);await finish();return
	check(service.host_room(0)==OK,"native private Steam lobby requested")
	if not await wait_for(func():return game.in_game):check(false,service.status);await finish();return
	game.session.set_physics_process(false)
	var path: String=game.session.room_store.path
	check(path.get_file()=="steam_"+str(service.steam_id)+".json" and game.session.room_store.owner=="steam_"+str(service.steam_id),"native host account determines the durable room namespace")
	game._on_action("use",{"index":3});game._on_action("transfer",{"from":"stash","index":5,"to":"bag"})
	game._return_menu()
	check(service.lobby_id==0 and FileAccess.file_exists(path),"leaving native room flushes and closes it")
	check(service.host_room(0)==OK,"native host creates another private lobby")
	if not await wait_for(func():return game.in_game):check(false,service.status);await finish();return
	game.session.set_physics_process(false)
	var p: Dictionary=game.session.model.state.players[1]
	check(game.session.room_store.path==path and p.bag[3].count==1 and p.stash[5].is_empty(),"rebuilt native lobby retains consumed food and changed warehouse")
	await finish()
func finish():
	game._return_menu();game.free();await process_frame
	print("ROOM_SAVE_STEAM_LIVE ",checks," checks; ",failures," failures; one account, private lobbies, no invitations")
	quit(1 if failures else 0)
