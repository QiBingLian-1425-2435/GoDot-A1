extends SceneTree
## Real integrated scene, UI signals and injected keyboard events. Never reads/writes a real profile.
const Main = preload("res://app/main.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("INTEGRATION FAIL: " + description)

func frames(count: int = 3) -> void:
	for i in range(count): await physics_frame
	await process_frame

func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key_event(code,true)
	await frames(2)
	key_event(code,false)
	await frames(2)

func run() -> void:
	game = Main.new()
	game.name = "DuckovIntegration"
	game.smoke = true
	game.elapsed = -100.0
	game.capture_mode = "base"
	root.add_child(game)
	await frames()
	check(game.smoke and game.in_game,"real main starts solo in profile-isolated smoke mode")
	check(game.session.model.state.players.size() == 1,"real Session supplies local authoritative player")
	check(game.world.visible and not game.menu_stage.visible and game.camera.current,"world and gameplay camera active")
	check(game.actors.has(1) and game.actors[1].visible,"real actor created from player state")
	check(game.ui._hud.visible and not game.ui._menu.visible,"real HUD connected and visible")
	check(game.session.model.obstacles.size() == game.world.obstacles().size() and game.world.obstacles().size() > 30,"world collision obstacles wired to model")
	check(game.session.model.stations.size() == game.world.interactions().size(),"station authority uses actual world coordinates")
	var reachable := reachable_stations()
	for station in game.world.interactions():
		check(bool(reachable.get(station.id,false)),"radius-aware path to " + str(station.id))
	# Use the actual world range origin and model target positions; walls must not silently block practice.
	var range_pos := Vector2.ZERO
	for station in game.world.interactions():
		if station.kind == "range": range_pos = station.pos
	var p: Dictionary = game.session.model.state.players[1]
	var original_bag: Array = p.bag.duplicate(true)
	p.pos = Vector2(7.2,2.7)
	game._update_interaction()
	check(game.nearest.get("kind","") == "ammo_supply","actual ammo box is selected for interaction")
	game._interact()
	check(game.session.model._count(p.bag,"ammo") == 120,"world interaction grants authoritative reserve")
	p.bag = original_bag
	game.session.model._update_weight(p)
	check(game.session.model._free(range_pos),"range firing origin is collision-free")
	p.pos = range_pos
	for target in game.session.model.state.targets:
		p.aim = (Vector2(target.pos) - range_pos).normalized()
		p.fire_timer = 0.0
		var hp_before := int(target.hp)
		game.session.send("fire")
		check(int(target.hp) < hp_before and int(target.hits) == 1,"range shot reaches actual target " + str(target.id))
	await frames()
	check(game.target_labels.size() == 3 and game.target_labels[0].text.contains("命中 1"),"target damage reaches visible world labels")
	check(game.actors[1].position.distance_to(Vector3(range_pos.x,0,range_pos.y)) < 0.01,"actor position follows authoritative movement")
	check(int(game.ui._ammo_label.text) == int(p.ammo),"HUD ammunition reads authoritative value")
	# A shot through the real northern range divider must stop at the wall.
	p.pos = Vector2(10,-3)
	p.aim = (Vector2(game.session.model.state.targets[1].pos) - Vector2(p.pos)).normalized()
	p.fire_timer = 0.0
	var blocked_target_hp := int(game.session.model.state.targets[1].hp)
	game.session.send("fire")
	check(int(game.session.model.state.targets[1].hp) == blocked_target_hp,"real world divider blocks bullets to range")
	check(game.session.model.state.shots.back().to.y < 0,"blocked tracer terminates at divider")
	p.pos = range_pos
	# TAB travels through Input and _unhandled_input rather than calling the menu method directly.
	await tap(KEY_TAB)
	check(game.ui.inventory_is_open() and game.ui.is_blocking(),"TAB opens and blocks through actual input routing")
	check(game.ui._bag_slots.size() == 24 and game.ui._stash_slots.size() == 48,"inventory widgets have correct dimensions")
	await process_frame
	check(game.ui._portrait.actor.human_visual.gender == p.get("appearance",{}).get("gender","male"),"inventory preview uses current human model")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/inventory_human_preview.png")

	var before_bandage_uid:String=p.bag[1].uid
	game.ui._slot_action("context",{"from":"bag","index":1,"item":p.bag[1],"position":Vector2(600,300)})
	check(game.ui._popup.get_item_index(5)>=0,"stack context menu offers split")
	game.ui._context_selected(5)
	game.ui._popup.hide()
	await frames()
	p=game.session.model.state.players[1]
	check(p.bag[1].uid==before_bandage_uid and p.bag[1].count==2 and p.bag[7].get("kind","")=="bandage" and p.bag[7].count==1,"split context action reaches authority and preserves stack totals")
	check(game.ui._bag_slots[7].item.get("kind","")=="bandage","split new slot appears in inventory UI")
	var water_uid: String = p.bag[2].uid
	var ctrl_click := InputEventMouseButton.new()
	ctrl_click.button_index = MOUSE_BUTTON_LEFT; ctrl_click.pressed = true; ctrl_click.ctrl_pressed = true
	game.ui._bag_slots[2]._gui_input(ctrl_click)
	await frames()
	p = game.session.model.state.players[1]
	check(p.bag[2].is_empty(),"Ctrl slot event travels UI to main to Session to model")
	check(game.ui._bag_slots[2].item.is_empty(),"authoritative transfer refreshes visible slot")
	var stash_water := -1
	for i in range(p.stash.size()):
		if p.stash[i].get("uid","") == water_uid: stash_water = i
	check(stash_water >= 0,"Ctrl transfer preserves item UID in storage")
	if stash_water >= 0:
		game.ui._bag_slots[12]._drop_data(Vector2.ZERO,{"duckov_item":true,"from":"stash","index":stash_water})
		await frames()
		p = game.session.model.state.players[1]
		check(p.bag[12].get("uid","") == water_uid and game.ui._bag_slots[12].item.get("uid","") == water_uid,"drag slot event updates model and visible destination")
	var pos_before: Vector2 = p.pos
	key_event(KEY_D,true)
	await frames(15)
	key_event(KEY_D,false)
	check(p.pos.distance_to(pos_before) < 0.01,"inventory blocks held movement key")
	await tap(KEY_R)
	check(not p.reloading,"inventory blocks reload shortcut")
	await tap(KEY_TAB)
	check(not game.ui.inventory_is_open() and not game.ui.is_blocking(),"TAB closes inventory")
	await tap(KEY_R)
	check(p.reloading and game.ui._reload_label.text.contains("装填中"),"R starts authoritative reload and HUD feedback")
	await frames(110)
	check(p.ammo == 30 and not p.reloading,"reload finishes through actual Session physics")
	p.pos = Vector2(0,3)
	await frames()
	pos_before = p.pos
	key_event(KEY_D,true)
	await frames(20)
	key_event(KEY_D,false)
	await frames(4)
	check(p.pos.distance_to(pos_before) > 0.4,"WASD injected physical key moves through real main input")
	await tap(KEY_ESCAPE)
	check(game.ui.is_blocking() and game.ui._pause_panel.visible,"Escape opens base menu")
	pos_before = p.pos
	key_event(KEY_W,true)
	await frames(15)
	key_event(KEY_W,false)
	check(p.pos.distance_to(pos_before) < 0.01,"base menu blocks movement")
	await tap(KEY_ESCAPE)
	check(not game.ui.is_blocking(),"Escape closes base menu")
	# Interaction dispatch uses the same range station ID as host validation.
	p.pos = range_pos
	await frames()
	check(game.nearest.get("kind","") == "range","actual world range prompt becomes nearest interaction")
	await tap(KEY_E)
	check(game.session.model.state.targets[0].hp == 100 and game.session.model.state.targets[0].hits == 0,"E on range prompt resets authoritative targets")
	# Real UI action signals exercise inventory lifetime across the front end.
	var saved_bag: Array = p.bag.duplicate(true)
	game.ui.action_requested.emit("menu",{})
	await frames()
	check(not game.in_game and game.menu_stage.visible and not game.world.visible,"menu action returns to start screen")
	check(game.ui._menu.visible and not game.ui._hud.visible and not game.actors[1].visible,"menu hides live HUD and actor")
	game.ui.action_requested.emit("solo",{})
	await frames()
	check(game.in_game and game.actors.size() == 1 and game.actors[1].visible,"solo action re-enters without duplicate actors")
	check(game.session.model.state.players[1].bag == saved_bag,"offline inventory retained across menu round trip")
	check(game.ui._hud.visible and not game.ui.is_blocking(),"re-entry restores interactive HUD")
	print("DUCKOV_INTEGRATION_TEST ",checks," checks, ",failures," failures; obstacles=",game.world.obstacles().size())
	game.set_process(false)
	game.set_physics_process(false)
	for player in game.sound.sounds.values(): player.stop()
	await create_timer(.2).timeout
	game.queue_free()
	await create_timer(.2).timeout
	quit(0 if failures == 0 else 1)

func reachable_stations() -> Dictionary:
	var model = game.session.model
	var spawn: Vector2 = model.state.players[1].pos
	var goals := {}
	for station in game.world.interactions(): goals[station.id] = false
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO:true}
	var head := 0
	var step := 0.35
	var directions := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var pos := spawn + Vector2(cell) * step
		for station in game.world.interactions():
			if pos.distance_to(station.pos) < 2.35: goals[station.id] = true
		if not goals.values().has(false): break
		for direction in directions:
			var neighbor: Vector2i = cell + direction
			if visited.has(neighbor): continue
			visited[neighbor] = true
			var destination := spawn + Vector2(neighbor) * step
			# Both end and midpoint use the same player-radius collision rule as live movement.
			if model._free(destination) and model._free((destination + pos) * 0.5): queue.append(neighbor)
	return goals
