extends Node3D
## Composition and input intents. Authority lives in features/match and its systems.
var session
var world
var hud
var sound
var view
var player_physics
var camera: Camera3D
var input_clock := 0.0
var help_open := false
var muted := false
var actors: Dictionary:
	get:
		return view.actors if view != null else {}

func _ready() -> void:
	world = preload("res://worlds/lantern_inn/room.tscn").instantiate()
	add_child(world)
	session = preload("res://app/network/session.gd").new()
	session.model.obstacles = world.obstacles()
	add_child(session)
	player_physics = preload("res://features/player/player_physics.gd").new()
	add_child(player_physics)
	player_physics.configure(session.model)
	hud = preload("res://ui/hud.gd").new()
	add_child(hud)
	sound = preload("res://features/audio/sound.gd").new()
	add_child(sound)
	view = preload("res://worlds/lantern_inn/raid_view.gd").new()
	view.session = session
	view.hud = hud
	view.sound = sound
	add_child(view)
	view.setup_environment()
	view.create_extraction()
	camera = view.camera
	hud.action_requested.connect(_on_action)
	session.notice.connect(_on_notice)
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo-preview" or arg == "--ui-smoke":
			session.start_solo()
		if arg.begins_with("--capture="):
			view.capture_path = arg.trim_prefix("--capture=")
		if arg == "--ui-smoke":
			view.automated = true
	update_hud()

func _physics_process(delta:float)->void:
	if session==null:
		return
	input_clock+=delta
	if input_clock>=0.05:
		input_clock=0
		var axis:=Vector2.ZERO
		if not help_open and session.model.state.phase=="raid":
			axis.x=float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))-float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
			axis.y=float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))-float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
		var right:=Vector2(camera.global_basis.x.x,camera.global_basis.x.z).normalized()
		var down:=Vector2(camera.global_basis.z.x,camera.global_basis.z.z).normalized()
		var direction:Vector2=(right*axis.x+down*axis.y).limit_length(1.0)
		session.send("move",{"direction":direction,"interact":Input.is_key_pressed(KEY_E) and not help_open})
		var player:Dictionary=session.model.state.players.get(session.local_id,{})
		if axis.length()>0.1 and player.get("status","")=="alive" and sound!=null and sound.has_method("footstep"):
			sound.footstep()

func _unhandled_key_input(event:InputEvent)->void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			if not help_open:
				session.send("pickup")
		KEY_TAB:
			hud.set_tab("team" if hud.tab=="bag" else "bag")
			get_viewport().set_input_as_handled()
		KEY_F1,KEY_ESCAPE:
			help_open=not help_open
			hud.toggle_help(help_open)
		KEY_M:
			muted=not muted
			if sound!=null:
				sound.set_muted(muted)
			hud.toast("声音已关闭" if muted else "声音已开启")

func update_hud()->void:
	if hud!=null:
		hud.update_view(session.model.state,session.local_id,session.mode,session.connection_status)

func _on_notice(message:String)->void:
	if hud!=null:
		hud.toast(message)

func _on_action(action:String,payload:Dictionary)->void:
	match action:
		"solo":
			session.start_solo()
		"host":
			var err:int=session.host()
			if err==OK:
				var ip:="127.0.0.1"
				for address in IP.get_local_addresses():
					if ":" not in address and (address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172.")):
						ip=address
						break
				session.connection_status="房间已开放 · "+ip+"\n等待同行者加入后，点击全员出发。"
		"join":
			session.join(hud.address.text)
		"leave":
			session.offline()
		"help":
			help_open=true
			hud.toggle_help(true)
		"close_help":
			help_open=false
			hud.toggle_help(false)
		"room":
			if session.model.state.phase=="lobby":
				hud.toast(session.connection_status)
			else:
				hud.set_tab("team")
				hud.toast("本局仍在继续；个人撤离后请等待全队结算。")
		"tab":
			hud.set_tab(payload.get("tab","bag"))
		_:
			session.send(action,payload)
	update_hud()
