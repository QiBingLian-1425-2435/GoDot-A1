extends RefCounted
## Migrated reference behavior; called only through the owning composition/model.

static func _physics_process(ctx, delta:float)->void:
	if ctx.session==null:return
	ctx.fire_clock-=delta
	if not ctx.in_game:return
	var blocked:bool=ctx.world_loading or ctx.ui.is_blocking() or ctx.station_dialog.visible or (is_instance_valid(ctx.steam_service) and ctx.steam_service.overlay_active)
	var focused =DisplayServer.window_is_focused() or ctx.smoke or not ctx.capture_path.is_empty()
	if blocked or not focused:ctx.trigger_held=false
	var axis =Vector2.ZERO
	if not blocked and focused:
		axis=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
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
	ctx.session.send("move",{"direction":direction,"aim":aim,"sprint":Input.is_physical_key_pressed(KEY_SHIFT) and not blocked and focused,"crouch":ctx.crouched and not blocked and focused,"ads":Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not blocked and focused})
	if not blocked and focused and ctx.trigger_held and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and ctx.fire_clock<=0:
		ctx.session.send("fire")
		ctx.fire_clock=0.13
	ctx.crosshair.active=not blocked
	ctx.crosshair.aiming=Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN if not blocked else Input.MOUSE_MODE_VISIBLE
	ctx.sound.step(delta,direction.length()>0.1,Input.is_physical_key_pressed(KEY_SHIFT))

static func _input(ctx, event:InputEvent)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		ctx.trigger_held=false

static func _unhandled_input(ctx, event:InputEvent)->void:
	if not ctx.in_game:return
	if is_instance_valid(ctx.steam_service) and ctx.steam_service.overlay_active:return
	if event is InputEventMouseButton and event.pressed and not ctx.ui.is_blocking():
		if event.button_index==MOUSE_BUTTON_LEFT:ctx.trigger_held=true
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: ctx.camera_zoom=maxf(14,ctx.camera_zoom-1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: ctx.camera_zoom=minf(31,ctx.camera_zoom+1)
	if not event is InputEventKey or not event.pressed or event.echo:return
	match event.physical_keycode:
		KEY_TAB,KEY_I:
			ctx.ui.toggle_inventory()
			ctx.get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if ctx.station_dialog.visible: ctx.station_dialog.hide()
			elif ctx.ui.is_blocking():ctx.ui.close_inventory()
			else:ctx.ui.toggle_pause()
		KEY_C:
			if not ctx.ui.is_blocking():ctx.crouched=not ctx.crouched
		KEY_R:
			if not ctx.ui.is_blocking():ctx.session.send("reload")
		KEY_SPACE:
			if not ctx.world_loading and not ctx.ui.is_blocking() and not ctx.station_dialog.visible:
				ctx.session.request_roll()
				ctx.get_viewport().set_input_as_handled()
		KEY_E:
			if not ctx.ui.is_blocking():ctx._interact()
		KEY_1:
			if not ctx.ui.is_blocking():ctx._select_weapon("rifle")
		KEY_2:
			if not ctx.ui.is_blocking():ctx._select_weapon("pistol")
		KEY_4:ctx._quick_use("medkit")
		KEY_5:ctx._quick_use("water")
		KEY_F5:ctx._save(true)
		KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

static func _quick_use(ctx, kind:String)->void:
	if ctx.ui.is_blocking():return
	var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var bag:Array=p.get("bag",[])
	for i in bag.size():
		if bag[i].get("kind","")==kind:
			ctx.session.send("use",{"index":i})
			return
	ctx.ui.toast("背包中没有这件补给")

static func _select_weapon(ctx, kind:String)->void:
	var p:Dictionary=ctx.session.model.state.players.get(ctx.session.local_id,{})
	var equipment:Dictionary=p.get("equipment",{})
	if equipment.get("weapon",{}).get("kind","")==kind:return
	var bag:Array=p.get("bag",[])
	for i in bag.size():
		if bag[i].get("kind","")==kind:
			ctx.session.send("equip",{"index":i})
			return
	ctx.ui.toast("背包中没有这把武器")
