extends Node3D

const BaseView = preload("res://worlds/bunker/base_view.gd")
const InputController = preload("res://features/player/base_input.gd")
const WorldFlow = preload("res://features/exploration/world_flow.gd")
const Vision = preload("res://features/visibility/exploration_vision.gd")

const Actor = preload("res://features/player/base_actor.gd")
const PROFILE := "user://a1_bunker_profile_v1.json"
var profile_path:=PROFILE
var client_visit:=false
var room_save_root:="user://rooms"
var legacy_profile_path:=PROFILE
var world:Node3D
var world_id := "bunker"
var world_loading := false
var session:Node
var ui:CanvasLayer
var camera:Camera3D
var menu_stage:Node3D
var sound:Node
var crosshair:Control
var actors:Dictionary={}
var drops:Dictionary={}
var target_labels:Array[Label3D]=[]
var in_game:=false
var joining:=false
var input_clock:=0.0
var save_clock:=0.0
var fire_clock:=0.0
var elapsed:=0.0
var camera_focus:=Vector3(0,0,3)
var camera_zoom:=20.0
var crouched:=false
var nearest:Dictionary={}
var last_shots:Dictionary={}
var station_dialog:AcceptDialog
var capture_path:=""
var capture_mode:="menu"
var capture_after:=3.0
var captured:=false
var smoke:=false
var had_remote:=false
var last_mode:="offline"
var trigger_held:=false
var tracer_mesh:ImmediateMesh
var tracer_node:MeshInstance3D
var voice:Node
var steam_service:Node
var player_physics: Node3D
var vision = Vision.new()
var field_item_view:Node3D

func _ready()->void:
	field_item_view=preload("res://features/exploration/field_item_view.gd").new()
	add_child(field_item_view)
	_setup_environment()
	world=load("res://worlds/bunker/bunker.gd").new()
	world.name="Bunker"
	add_child(world)
	session=load("res://app/network/session.gd").new()
	session.name="Session"
	add_child(session)
	session.set_physics_process(false)
	session.model.obstacles.assign(world.obstacles())
	session.model.stations=world.interactions()
	player_physics = preload("res://features/player/player_physics.gd").new()
	add_child(player_physics)
	player_physics.configure(session.model)
	session.local_movement.solver = player_physics.predict
	session.local_movement.spatial_solver = player_physics.predict_spatial
	session.notice.connect(_on_notice)
	ui=load("res://ui/base_hud.gd").new()
	add_child(ui)
	ui.action_requested.connect(_on_action)
	WorldFlow.configure(self)
	session.state_changed.connect(_sync_world)
	sound=load("res://features/audio/base_sound.gd").new()
	add_child(sound)
	var overlay:=CanvasLayer.new()
	overlay.layer=4
	add_child(overlay)
	crosshair=load("res://ui/widgets/crosshair.gd").new()
	overlay.add_child(crosshair)
	menu_stage=load("res://ui/menu/menu_stage.gd").new()
	add_child(menu_stage)
	menu_stage.camera.current=true
	world.visible=false
	ui.show_menu()
	station_dialog=AcceptDialog.new()
	station_dialog.title="基地设施"
	station_dialog.min_size=Vector2i(520,230)
	station_dialog.ok_button_text="返回基地"
	station_dialog.exclusive=true
	add_child(station_dialog)
	tracer_mesh=ImmediateMesh.new()
	tracer_node=MeshInstance3D.new()
	tracer_node.mesh=tracer_mesh
	var tracer_mat:=ShaderMaterial.new()
	tracer_mat.shader=preload("res://features/visibility/vision_tracer.gdshader")
	tracer_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer_node.material_override=tracer_mat
	add_child(tracer_node)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--view="): capture_mode=arg.trim_prefix("--view=")
		if arg.begins_with("--capture-after="): capture_after=float(arg.trim_prefix("--capture-after="))
		if arg=="--smoke": smoke=true
		if arg=="--solo": capture_mode="base"
	if capture_mode in ["base","inventory","range"]:
		_start_solo()
		if capture_mode=="inventory": ui.toggle_inventory(true)
		if capture_mode=="range":
			session.model.state.players[1].pos=Vector2(9,4.2)
			session.model.state.players[1].aim=Vector2.DOWN
	elif capture_mode=="menu_open":ui._reveal_menu()
	steam_service=load("res://app/network/steam_service.gd").new()
	steam_service.name="SteamService"
	add_child(steam_service)
	voice=preload("res://features/voice/proximity_voice.gd").new()
	add_child(voice)
	voice.configure(session,steam_service)
	steam_service.transport_ready.connect(_on_steam_transport)
	steam_service.join_requested.connect(_on_steam_join_requested)
	steam_service.failed.connect(_on_steam_failure)
	if not smoke and DisplayServer.get_name()!="headless" and not "--no-steam" in OS.get_cmdline_user_args():
		steam_service.initialize()
		var args:Array=Array(OS.get_cmdline_args())+Array(OS.get_cmdline_user_args())
		for i in range(args.size()-1):
			if args[i]=="+connect_lobby":_on_steam_join_requested(str(args[i+1]))
	if capture_mode=="steam":
		ui._reveal_menu()
		ui._open_steam()
	_refresh_ui()

func _sync_world() -> void:
	WorldFlow.sync(self)
	if is_instance_valid(steam_service):steam_service.set_join_allowed(session.model.state.get("world","bunker")=="bunker" and session.model.world_ready)

func _setup_environment()->void:
	return BaseView._setup_environment(self)

func _start_solo()->void:
	if is_instance_valid(steam_service):steam_service.leave_room()
	session.start_solo()
	if not smoke and capture_path.is_empty():
		session.model.load_profile(profile_path,1)
	_enter_base()

func _enter_base()->void:
	client_visit=session.mode=="client"
	session.set_physics_process(true)
	in_game=true
	joining=false
	if is_instance_valid(steam_service) and session.transport=="steam":steam_service.mark_connected()
	crouched=false
	world.visible=not world_loading
	menu_stage.visible=false
	camera.current=true
	ui.show_game()
	ui.toast("欢迎回到基地  ·  TAB 背包与仓库  ·  E 互动")
	_update_actors(1.0)
	_refresh_ui()

func _on_action(action:String,payload:Dictionary)->void:
	sound.play("ui")
	match action:
		"solo": _start_solo()
		"host":
			if is_instance_valid(steam_service):steam_service.leave_room()
			var result:int=session.host(int(payload.get("port",24567)))
			if result==OK:
				var addresses:PackedStringArray=IP.get_local_addresses()
				for address in addresses:
					if address.begins_with("192.168."):
						session.connection_status="IP %s  ·  UDP %d  ·  最多5人"%[address,int(payload.get("port",24567))]
						break
				if not smoke: session.model.load_profile(profile_path,1)
				_enter_base()
		"join":
			if is_instance_valid(steam_service):steam_service.leave_room()
			session.set_physics_process(true)
			joining=session.join(str(payload.get("address","127.0.0.1")),int(payload.get("port",24567)))==OK
		"cancel_join":
			joining=false
			session.offline()
		"steam_connect":steam_service.initialize()
		"steam_refresh":steam_service.refresh_friends()
		"steam_host":
			joining=false
			session.offline()
			steam_service.host_room()
		"steam_join":
			session.offline()
			joining=steam_service.join_room(str(payload.get("lobby_id","")))==OK
		"steam_cancel":
			joining=false
			session.offline()
			steam_service.leave_room()
		"steam_invite":
			steam_service.invite_friends()
			ui.toast(steam_service.status)
		"steam_copy_lobby":
			steam_service.copy_lobby()
			ui.toast(steam_service.status)
		"menu","leave": _return_menu()
		"save": _save(true)
		"quit":
			_save(false)
			get_tree().quit()
		"settings":
			if payload.has("voice_muted"):
				voice.set_muted(bool(payload.voice_muted));ui.voice_muted=voice.muted
			if payload.has("volume"):
				AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,float(payload.volume))))
			if payload.has("fullscreen"):
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if payload.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		_:
			session.send(action,payload)
	_refresh_ui()

func _return_menu()->void:
	if is_instance_valid(voice):voice.stop();voice.clear_playback()
	_save(false)
	joining=false
	in_game=false
	session.offline()
	field_item_view.update(self)
	if is_instance_valid(steam_service):steam_service.leave_room()
	session.set_physics_process(false)
	world.visible=false
	for actor in actors.values(): actor.visible=false
	for drop in drops.values(): drop.visible=false
	for label in target_labels: label.visible=false
	tracer_mesh.clear_surfaces()
	menu_stage.visible=true
	menu_stage.camera.current=true
	ui.show_menu()
	crosshair.active=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _save(show_notice:bool)->void:
	if not in_game or session.mode=="client" or client_visit or smoke or not capture_path.is_empty():
		if show_notice: ui.toast("物品由房主自动保存，重进同一房主的房间可恢复")
		return
	var result:int=session.save_room() if not session.room_store.path.is_empty() else session.model.save_profile(profile_path,session.local_id)
	if show_notice: ui.toast("背包、装备与仓库已保存" if result==OK else "保存失败："+error_string(result))

func _notification(what:int)->void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_CLOSE_REQUEST] and is_instance_valid(voice):voice.stop()
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(session): _save(false)

func _physics_process(delta:float)->void:
	return InputController._physics_process(self, delta)

func _input(event:InputEvent)->void:
	if event is InputEventKey and event.physical_keycode==KEY_Q and not event.pressed and is_instance_valid(voice):voice.stop()
	return InputController._input(self, event)

func _unhandled_input(event:InputEvent)->void:
	return InputController._unhandled_input(self, event)

func _quick_use(kind:String)->void:
	return InputController._quick_use(self, kind)

func _select_weapon(kind:String)->void:
	return InputController._select_weapon(self, kind)

func _process(delta:float)->void:
	elapsed+=delta
	if session==null:return
	if is_instance_valid(voice):
		var allowed: bool=in_game and not world_loading and not ui.is_blocking() and not station_dialog.visible and not steam_service.overlay_active and DisplayServer.window_is_focused()
		voice.update(Input.is_physical_key_pressed(KEY_Q),allowed,delta)
		ui.set_voice_status(voice.status+voice.speaking_names())
	if joining and session.local_id>0 and session.model.state.players.has(session.local_id) and session.mode=="client":_enter_base()
	if session.mode=="client":had_remote=true
	if had_remote and last_mode=="client" and session.mode=="offline":
		had_remote=false
		var disconnect_message:String=session.connection_status
		_return_menu()
		ui.toast(disconnect_message)
	last_mode=session.mode
	if in_game:
		_update_actors(delta)
		_update_camera(delta)
		_update_drops()
		vision.update(self,delta)
		field_item_view.update(self)
		_update_tracers()
		_update_interaction()
		save_clock+=delta
		if save_clock>30:
			save_clock=0
			_save(false)
	_refresh_ui()
	if not captured and not capture_path.is_empty() and elapsed>capture_after:
		captured=true
		_capture.call_deferred()
	if smoke and elapsed>5:
		print("DUCKOV MAIN SMOKE PASS players=",session.model.state.players.size()," obstacles=",world.obstacles().size())
		get_tree().quit()

func _capture()->void:
	await BaseView._capture(self)

func _update_camera(delta:float)->void:
	return BaseView._update_camera(self, delta)

func _update_actors(delta:float)->void:
	return BaseView._update_actors(self, delta)

func _update_drops()->void:
	return BaseView._update_drops(self)

func _update_tracers()->void:
	return BaseView._update_tracers(self)

func _update_interaction()->void:
	nearest={}
	if world_loading:
		ui.set_interaction("")
		return
	var p:Dictionary=session.model.state.players.get(session.local_id,{})
	var pos:Vector2=p.get("pos",Vector2.ZERO)
	var distance:=2.4
	for uid in session.model.state.drops:
		var drop:Dictionary=session.model.state.drops[uid]
		if not vision.can_see(Vector3(drop.pos.x,float(drop.get("height",0))+.2,drop.pos.y)):continue
		var d:=pos.distance_to(drop.pos)
		if d<minf(distance,2.0):
			distance=d
			nearest={"kind":"pickup","uid":uid,"title":"拾取地上物品"}
	for station in session.model.stations:
		if station.get("kind")=="loot" and session.model.state.containers.has(station.uid):continue
		var d:=pos.distance_to(station.pos)
		if d>=distance:continue
		if station.get("kind")=="door":
			if absf(float(p.get("height",0))-float(station.height))>2:continue
			if not world.can_reach_door(station.uid,Vector3(pos.x,float(p.get("height",0)),pos.y)):continue
		elif station.get("kind")=="loot":
			if absf(float(p.get("height",0))-float(station.height))>2:continue
			var target:Dictionary=world.loot_target(station.uid)
			var seen:=false
			for point in target.get("points",[]):
				if vision.can_see(point,target.exclude):seen=true;break
			if not seen:continue
		else:
			if not vision.can_see(Vector3(station.pos.x,float(station.get("height",0))+.8,station.pos.y)):continue
		distance=d
		nearest=station.duplicate()
		if station.get("kind")=="loot":nearest.title="开启上锁容器（消耗开锁器）" if station.get("locked",false) else "搜索物资"
		if station.get("kind")=="door":
			nearest.title="关门" if session.model.state.doors.get(station.uid,station.get("initial_open",false)) else "开门"
	ui.set_interaction("" if nearest.is_empty() else "E   "+str(nearest.title))

func _interact()->void:
	if world_loading:return
	if nearest.is_empty():return
	match str(nearest.kind):
		"loot":session.send("search",{"uid":nearest.uid})
		"door":session.send("door",{"uid":nearest.uid})
		"travel":session.send("travel",{"route":nearest.uid})
		"pickup":session.send("pickup",{"uid":nearest.uid})
		"stash":ui.toggle_inventory(true)
		"medical":session.send("rest")
		"workbench":ui.open_item_shop("craft")
		"trader","merchant":ui.open_item_shop("buy")
		"range":session.send("reset_targets")
		"ammo_supply":session.send("resupply_ammo")
	_refresh_ui()

func _on_notice(message:String)->void:
	if is_instance_valid(ui):ui.toast(message)

func _refresh_ui()->void:
	if is_instance_valid(ui):ui.update_state(session.model.state,session.local_id,session.mode,session.connection_status)
	if is_instance_valid(ui) and is_instance_valid(steam_service):ui.update_steam(steam_service.info(session.transport))

func _on_steam_transport(peer:MultiplayerPeer,as_host:bool)->void:
	var owner_key:="steam_"+str(steam_service.steam_id)
	var room_path:=room_save_root.path_join(owner_key+".json") if as_host and not smoke and capture_path.is_empty() else ""
	var result:int=session.use_steam_peer(peer,as_host,steam_service.accept_peer,steam_service.peer_name,steam_service.peer_identity,room_path,owner_key,legacy_profile_path)
	if result!=OK:
		steam_service._fail("Steam 会话或房间存档建立失败，原存档未覆盖："+error_string(result))
		return
	session.set_physics_process(true)
	if as_host:
		session.model.state.players[1].name=steam_service.persona.left(24)
		_enter_base()
	else:
		joining=true

func _on_steam_join_requested(code:String)->void:
	if is_instance_valid(steam_service) and str(steam_service.lobby_id)==code:return
	_return_menu()
	ui._reveal_menu()
	ui._open_steam()
	_on_action("steam_join",{"lobby_id":code})

func _on_steam_failure(message:String)->void:
	if session.transport=="steam":_return_menu()
	joining=false
	if is_instance_valid(ui):ui.toast(message)
