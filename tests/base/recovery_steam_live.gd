extends SceneTree
const Main=preload("res://app/main.gd")
var game
var failures:=0
func _initialize():call_deferred("run")
func check(value: bool, message: String):
	print("PASS: " if value else "FAIL: ",message)
	if not value:failures+=1
func wait_for(test: Callable, seconds: float) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<end:await process_frame
	return test.call()
func run():
	if not "--steam-live-test" in OS.get_cmdline_user_args():quit(2);return
	game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game.set_physics_process(false)
	var service=game.steam_service
	if not service.initialize():check(false,service.status);await finish();return
	check(service.host_room(0)==OK,"native Steam private lobby requested")
	if not await wait_for(func():return game.in_game and game.session.transport=="steam",30):check(false,service.status);await finish();return
	var lobby:int=service.lobby_id
	check(service.steam.getLobbyData(lobby,"join_state")=="base","native lobby advertises base admission")
	game.session.model.state.players[1].pos=Vector2(0,-8.2)
	game.session.send("travel",{"route":"bunker_to_surface"})
	check(not service.join_allowed and not game.session.can_accept_join(),"actual surface transition locks Steam UI and Session admission")
	check(service.steam.getLobbyData(lobby,"join_state")=="exploration","native lobby publishes exploration lock metadata")
	if not await wait_for(func():return not game.world_loading,20):check(false,"surface loading timeout");await finish();return
	var route:Dictionary={}
	for entry in game.session.model.stations:
		if entry.get("uid")=="surface_to_bunker":route=entry
	var player:Dictionary=game.session.model.state.players[1];player.pos=route.pos;player.height=route.height
	game.session.send("travel",{"route":"surface_to_bunker"})
	check(service.lobby_id==lobby and service.join_allowed and game.session.can_accept_join(),"returning preserves the native lobby and reopens admission")
	check(service.steam.getLobbyData(lobby,"join_state")=="base","native lobby publishes reopened base metadata")
	await finish()
func finish():
	game._return_menu();check(game.steam_service.lobby_id==0,"private test lobby closes cleanly")
	game.queue_free();await process_frame
	print("RECOVERY_STEAM_LIVE failures=",failures,"; single account only, no invitations")
	quit(1 if failures else 0)
