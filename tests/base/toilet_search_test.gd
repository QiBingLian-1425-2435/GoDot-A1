extends SceneTree
const Main = preload("res://app/main.gd")
var game
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func settle():
	game._update_actors(1); game._update_camera(1); game._update_drops()
	game.vision.update(game, .06); game._update_interaction(); game._refresh_ui()
func capture(name: String):
	if DisplayServer.get_name() == "headless": return
	for i in range(4): await process_frame; settle()
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("A1_TEST_ARTIFACTS")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(folder)
	check(game.get_viewport().get_texture().get_image().save_png(folder + "/toilet_" + name + ".png") == OK, "capture " + name)
func run():
	game = Main.new(); game.smoke = true; game.elapsed = -10000
	root.add_child(game); game.sound.muted = true
	game.set_process(false); game.set_physics_process(false); game.session.set_physics_process(false)
	game._start_solo()
	var model = game.session.model
	var p: Dictionary = model.state.players[1]
	p.pos = Vector2(0, -8.2); game.session.send("travel", {"route":"bunker_to_surface"})
	while game.world_loading: await process_frame
	await physics_frame; await physics_frame
	var toilets: Array = []
	for station in model.stations:
		if station.get("container_name") == "厕所": toilets.append(station)
	check(toilets.size() == 9, "all nine source toilets are searchable")
	for station in toilets:
		game.ui._close_dialog()
		var reached := false
		for radius in [.6, 1.2, 1.8]:
			for angle in range(24):
				var offset: Vector2 = Vector2.from_angle(TAU * angle / 24.0) * radius
				var safe: Dictionary = game.player_physics.safe_standing_position(Vector3(station.pos.x + offset.x, station.height, station.pos.y + offset.y))
				if safe.is_empty(): continue
				var at: Vector3 = safe.position
				p.pos = Vector2(at.x, at.z); p.height = at.y; p.aim = (station.pos - p.pos).normalized()
				settle()
				if game.nearest.get("uid") == station.uid and model.Loot.reachable(model, p, station): reached = true; break
			if reached: break
		check(reached, "real physics and E prompt reach toilet " + station.uid)
		if not reached: continue
		check(not station.locked and game.nearest.title == "搜索厕所", "toilet uses its own prompt without a lockpick")
		if station == toilets[0]: await capture("world")
		p.bag = model._empty_slots(24)
		game._interact(); settle()
		check(game.ui._dialog_kind == "搜索厕所" and p.loot_uid == station.uid, "E opens toilet search panel")
		var box: Dictionary = model.state.containers.get(station.uid, {})
		if box.is_empty(): check(false, "toilet contains food"); continue
		var food_only: bool = box.items.size() >= 2
		for item in box.items:
			if not item.kind in model.Loot.FOOD: food_only = false
		check(food_only, "toilet produces edible food only")
		var original: Array = box.items.duplicate(true)
		for i in range(150): model.tick(.01)
		settle()
		check(box.revealed == 1, "toilet uses sequential discovery")
		if station == toilets[0]: await capture("panel")
		game.ui._loot_selected = 0; game.ui.ContainerPanel.take(game.ui, false); settle()
		check(box.items[0].is_empty() and model._count(p.bag, original[0].kind) == original[0].count, "revealed food enters inventory exactly once")
		game.ui._close_dialog()
		var remaining: Array = box.items.duplicate(true)
		game.session.send("search", {"uid":station.uid}); settle()
		check(box.items == remaining and p.loot_uid == station.uid, "reopening toilet preserves remaining food")
	game.ui._close_dialog(); game.queue_free()
	await process_frame; await process_frame
	print("TOILET_SEARCH checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
