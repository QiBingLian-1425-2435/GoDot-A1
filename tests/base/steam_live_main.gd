extends SceneTree
const Main=preload("res://app/main.gd")
var game
var timer:=0.0
var phase:=0
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("start")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("STEAM MAIN FAIL: "+label)
	else:print("STEAM MAIN PASS: "+label)
func start()->void:
	if not "--steam-live-test" in OS.get_cmdline_user_args():quit(2);return
	game=Main.new()
	game.smoke=true
	game.elapsed=-100
	root.add_child(game)
	check(game.steam_service.initialize(),"real main Steam service initializes")
	if not game.steam_service.initialized:finish();return
	check(game.steam_service.host_room(0)==OK,"real main requests private lobby")
	phase=1
func _process(delta:float)->bool:
	timer+=delta
	if phase==1 and game.in_game:
		check(game.session.transport=="steam" and game.session.mode=="host","Steam callback mounts actual Session transport")
		check(game.session._peer.get_class()=="SteamMultiplayerPeer","native Steam peer backs MultiplayerAPI")
		check(game.ui._hud.visible and game.actors.has(1),"Steam host enters actual base with player and HUD")
		game.ui.toggle_pause()
		game._refresh_ui()
		check(not game.ui._steam_copy_button.disabled and game.ui._steam_room_label.text.contains(str(game.steam_service.lobby_id)),"room code and invite controls are connected")
		game.ui._steam_copy_button.pressed.emit()
		check(DisplayServer.clipboard_get()==str(game.steam_service.lobby_id),"actual copy button copies the native lobby ID")
		check(game.steam_service.steam.getLobbyMemberLimit(game.steam_service.lobby_id)==5,"native Steam lobby retains five members")
		check(game.steam_service.steam.getLobbyData(game.steam_service.lobby_id,"build")==game.steam_service.build_id,"native lobby publishes the exact migrated build")
		game.ui.action_requested.emit("menu",{})
		phase=2
	elif phase==2:
		check(not game.in_game and game.session.transport=="offline" and game.steam_service.lobby_id==0,"menu closes session and leaves real private lobby")
		phase=3
		finish()
	elif timer>30 and phase<3:
		phase=3
		check(false,"real main Steam host timeout")
		finish()
	return false
func finish()->void:
	print("STEAM_LIVE_MAIN ",checks," checks, ",failures," failures; no client, no invitation sent")
	if is_instance_valid(game):game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit(0 if failures==0 else 1)
