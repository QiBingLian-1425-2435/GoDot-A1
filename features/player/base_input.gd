extends RefCounted
const Keys = preload("res://features/player/key_bindings.gd")
## Migrated reference behavior; called only through the owning composition/model.

static func _physics_process(ctx, delta:float)->void:
	if ctx.session==null:return
	ctx.fire_clock-=delta
	if not ctx.in_game:return
	var blocked:bool=ctx.world_loading or ctx.ui.is_blocking() or (is_instance_valid(ctx.global_map) and ctx.global_map.is_open()) or ctx.station_dialog.visible or (is_instance_valid(ctx.steam_service) and ctx.steam_service.overlay_active)
	var focused =DisplayServer.window_is_focused() or ctx.smoke or not ctx.capture_path.is_empty()
	if not ctx.session.model.Souls.mobile(ctx.session.model.state.players.get(ctx.session.local_id,{})): blocked=true
	if blocked or not focused:ctx.trigger_held=false
	var axis =Vector2.ZERO
	if not blocked and focused:
		axis=Vector2(float(Keys.held("move_right"))-float(Keys.held("move_left")),float(Keys.held("move_down"))-float(Keys.held("move_up")))
	var right =Vector2(ctx.camera.global_basis.x.x,ctx.camera.global_basis.x.z).normalized()
	var down =Vector2(ctx.camera.global_basis.z.x,ctx.camera.global_basis.z.z).normalized()
	var direction:Vector2=(right*axis.x+down*axis.y).limit_length(1)
	var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var aim:Vector2=p.get("aim",Vector2.UP)
	if not blocked and focused:
		var plane =Plane(Vector3.UP,float(p.get("height",0))+.75)
		var mouse =ctx.get_viewport().get_mouse_position()
		var point:Variant=plane.intersects_ray(ctx.camera.project_ray_origin(mouse),ctx.camera.project_ray_normal(mouse))
		if point is Vector3:
			aim=(Vector2(point.x,point.z)-Vector2(p.get("pos",Vector2.ZERO))).normalized()
	ctx.session.send("move",{"direction":direction,"aim":aim,"sprint":Keys.held("sprint") and not blocked and focused,"crouch":ctx.crouched and not blocked and focused,"ads":Keys.held("aim") and not blocked and focused})
	if ctx.session.model.Souls.alive(p) and not blocked and focused and ctx.trigger_held and Keys.held("fire") and ctx.fire_clock<=0:
		ctx.session.send("fire")
		ctx.fire_clock=0.13
	ctx.crosshair.active=not blocked
	ctx.crosshair.aiming=Keys.held("aim")
	var soul_controls: bool = is_instance_valid(ctx.ui._soul_panel) and ctx.ui._soul_panel.visible
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN if not blocked and not soul_controls else Input.MOUSE_MODE_VISIBLE
	var audible_motion := p
	if ctx.session.mode == "client" and ctx.session.local_movement != null:
		audible_motion = ctx.session.local_movement.sample_player(p)
	var footstep := _footstep_state(audible_motion)
	ctx.sound.step(delta,footstep.moving,footstep.sprint)

static func _footstep_state(motion: Dictionary) -> Dictionary:
	# Input expresses intent; collision-resolved velocity says whether the feet
	# actually travelled. Holding a key into a wall or corner must stay silent.
	var velocity: Vector2 = motion.get("velocity",Vector2.ZERO)
	return {"moving":velocity.length()>.1,"sprint":bool(motion.get("sprint",false)) and velocity.length()>.1}

static func _input(ctx, event:InputEvent)->void:
	if (event is InputEventMouseButton or event is InputEventKey) and Keys.matches("fire",event) and not event.pressed:
		ctx.trigger_held=false

static func _unhandled_input(ctx, event:InputEvent)->void:
	if not ctx.in_game:return
	if is_instance_valid(ctx.steam_service) and ctx.steam_service.overlay_active:return
	if event is InputEventMouseButton and event.pressed and not ctx.ui.is_blocking():
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: ctx.camera_zoom=maxf(14,ctx.camera_zoom-1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: ctx.camera_zoom=minf(31,ctx.camera_zoom+1)
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed:return
	if event is InputEventKey and event.echo:return
	var action := ""
	if event is InputEventKey and Keys.event_code(event) == KEY_ESCAPE:
		action = "pause"
	else:
		for candidate in Keys.DEFAULTS:
			if Keys.matches(candidate,event):
				action = candidate
				break
	if ctx.session.model.Souls.zombie(ctx.session.model.state.players.get(ctx.session.local_id,{})) and action not in ["pause","fullscreen"]: return
	match action:
		"fire":
			if not ctx.ui.is_blocking():ctx.trigger_held=true
		"rescue":
			if not ctx.ui.is_blocking() and ctx.nearest.get("kind","")=="corpse":
				ctx.session.send("rescue",{"target":ctx.nearest.target,"uid":ctx.nearest.uid})
		"map":
			ctx.toggle_global_map()
			ctx.get_viewport().set_input_as_handled()
		"inventory":
			ctx.ui.toggle_inventory()
			ctx.get_viewport().set_input_as_handled()
		"pause":
			if is_instance_valid(ctx.global_map) and ctx.global_map.is_open():ctx.global_map.set_open(false)
			elif ctx.station_dialog.visible: ctx.station_dialog.hide()
			elif ctx.ui.is_blocking():ctx.ui.close_inventory()
			else:ctx.ui.toggle_pause()
		"crouch":
			if not ctx.ui.is_blocking():ctx.crouched=not ctx.crouched
		"reload":
			if not ctx.ui.is_blocking():ctx.session.send("reload")
		"roll":
			if not ctx.world_loading and not ctx.ui.is_blocking() and not ctx.station_dialog.visible:
				ctx.session.request_roll()
				ctx.get_viewport().set_input_as_handled()
		"interact":
			if not ctx.ui.is_blocking():ctx._interact()
		"rifle":
			if not ctx.ui.is_blocking():ctx._select_weapon("rifle")
		"pistol":
			if not ctx.ui.is_blocking():ctx._select_weapon("pistol")
		"medkit":ctx._quick_use("medkit")
		"water":ctx._quick_use("water")
		"save":ctx._save(true)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

static func _quick_use(ctx, kind:String)->void:
	if ctx.ui.is_blocking():return
	var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var bag:Array=p.get("bag",[])
	for i in bag.size():
		if bag[i].get("kind","")==kind:
			ctx.session.send("use",{"index":i})
			return
	ctx.ui.toast("⟦base_input.001⟧")

static func _select_weapon(ctx, kind:String)->void:
	var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var equipment:Dictionary=p.get("equipment",{})
	if equipment.get("weapon",{}).get("kind","")==kind:return
	var bag:Array=p.get("bag",[])
	for i in bag.size():
		if bag[i].get("kind","")==kind:
			ctx.session.send("equip",{"index":i})
			return
	ctx.ui.toast("⟦base_input.002⟧")
