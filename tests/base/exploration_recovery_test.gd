extends SceneTree
const Texts = preload("res://features/localization/game_text.gd")
const Main=preload("res://app/main.gd")
const Service=preload("res://app/network/steam_service.gd")
const FakeSteam=preload("res://tests/base/fake_steam.gd")
const FakePeer=preload("res://tests/base/fake_peer.gd")
const ROOM=109775243000000001
var checks:=0
var failures:=0
var game
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func labels(node: Node) -> Array[String]:
	var result: Array[String]=[]
	if node is Button:result.append(node.text)
	for child in node.get_children():result.append_array(labels(child))
	return result
func run():
	game=Main.new();game.smoke=true;game.elapsed=-10000;game.capture_mode="base"
	root.add_child(game);game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
	await physics_frame;await physics_frame
	var model=game.session.model
	var player: Dictionary=model.state.players[1]
	check(not "IP 直连" in labels(game.ui._menu_buttons),"main menu has no IP direct entry")
	game.ui._open_steam()
	check(not "IP 直连" in labels(game.ui._dialog),"Steam panel has no alternate IP direct entry")
	game.ui._close_dialog();game.ui.toggle_pause()
	var recovery: Button
	for child in game.ui._pause_panel.get_children():
		if child is Button and child.text=="脱离卡死":recovery=child
	check(recovery!=null,"Esc menu exposes recovery in the real game")
	var bag: Array=player.bag.duplicate(true)
	var before: Vector2=player.pos
	recovery.pressed.emit()
	check(before.distance_to(player.pos)>.6 and player.bag==bag,"real recovery button moves only the player and preserves inventory")
	check(not model.command(1,"unstuck") and Texts.resolve(model.last_notice).contains("冷却"),"repeated recovery is rate limited by host rules")
	check(game.session._clean_payload("unstuck",{"position":Vector3(999,999,999),"player_id":2}).is_empty(),"client cannot nominate recovery coordinates or another player")
	model.world_ready=false
	check(not model.command(1,"unstuck") and Texts.resolve(model.last_notice).contains("加载"),"recovery is refused while world geometry is unavailable")
	model.world_ready=true
	game.ui.toggle_pause();player.pos=Vector2(0,-8.2)
	game.session.send("travel",{"route":"bunker_to_surface"})
	while game.world_loading:await process_frame
	await physics_frame;await physics_frame
	check(not game.session.can_accept_join(),"surface rejects new session admissions")
	model._clock+=11
	player.pos=Vector2(210.491, -289.591);player.height=24.751
	before=player.pos
	check(model.command(1,"unstuck") and before.distance_to(player.pos)>.6,"recovery escapes a reproduced original box-and-rock trap")
	var safe: Dictionary=game.player_physics.safe_standing_position(Vector3(player.pos.x,player.height,player.pos.y))
	check(not safe.is_empty() and player.bag==bag,"destination has support, capsule clearance and unchanged inventory")
	var actual: Vector2=player.pos
	var can_leave:=false
	for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		var start:=Vector3(actual.x,player.height,actual.y)
		for i in range(20):start=game.player_physics.prediction_body.move_spatial(start,direction*.06)
		if Vector2(start.x,start.z).distance_to(actual)>.7:can_leave=true
	check(can_leave,"recovered duck can walk away using the real capsule")
	if DisplayServer.get_name()!="headless":
		game._update_actors(1);game._update_camera(1);game.vision.update(game,.1);game._refresh_ui();game.ui.toggle_pause()
		await process_frame;await RenderingServer.frame_post_draw
		var folder:=OS.get_environment("A1_TEST_ARTIFACTS")
		if folder.is_empty():folder="res://artifacts"
		DirAccess.make_dir_recursive_absolute(folder)
		check(root.get_texture().get_image().save_png(folder.path_join("recovery_menu.png"))==OK,"visible recovery menu evidence saved")
	game._return_menu()
	check(game.session.can_accept_join(),"returning to base restores the session admission gate")
	check(model.command(1,"unstuck"),"a new offline session does not inherit the previous recovery cooldown")
	var api=FakeSteam.new();var svc=Service.new();svc.steam=api;svc.peer_factory=func():return FakePeer.new()
	root.add_child(svc);svc.set_process(false);svc.host_room();api.emit_created(ROOM)
	api.rooms[ROOM].members.append(api.FRIEND_ID)
	svc.set_join_allowed(false)
	check(api.joinable[ROOM]==false and api.rooms[ROOM].data.join_state=="exploration","Steam lobby becomes non-joinable with explicit exploration metadata")
	check(svc.accept_peer(12),"locking keeps existing lobby members authorized")
	svc.invite_friends()
	check(api.invites.is_empty() and Texts.resolve(svc.status).contains("回到基地"),"in-game invites are disabled during exploration")
	svc.set_join_allowed(true)
	check(api.joinable[ROOM] and api.rooms[ROOM].data.join_state=="base","returning opens the existing Steam lobby again")
	svc.leave_room();api.populate(ROOM,Service.GAME_KEY,Service.PROTOCOL);api.rooms[ROOM].data.join_state="exploration"
	svc.join_room(str(ROOM));api.lobby_data_update.emit(1,ROOM,ROOM)
	check(api.joined.is_empty() and Texts.resolve(svc.status).contains("正在探索"),"old invite or pasted code is rejected with a readable lock reason")
	api.rooms[ROOM].data.join_state="base";svc.join_room(str(ROOM));api.lobby_data_update.emit(1,ROOM,ROOM)
	api.rooms[ROOM].data.join_state="exploration";api.emit_joined(ROOM)
	check(svc.lobby_id==0 and Texts.resolve(svc.status).contains("已出发"),"a join racing with departure is rechecked before P2P transport")
	var receiver=load("res://app/network/session.gd").new()
	receiver.mode="client";receiver._session_token=42;receiver._received_motion_serial=10
	receiver.model.state=model.state.duplicate(true)
	receiver.model.state.players[1].relocation_seq=3
	var delayed: Dictionary=receiver.model.state.duplicate(true)
	delayed.players[1].relocation_seq=2
	receiver._apply_snapshot(delayed,42,9,1.0)
	check(receiver.model.state.players[1].relocation_seq==3,"delayed reliable state cannot rewind recovery epoch after newer motion")
	receiver.free()
	svc.free();game.queue_free();await process_frame
	print("EXPLORATION_RECOVERY ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
