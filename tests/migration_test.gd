extends SceneTree
## Exercises the migrated app composition and real physics, beyond model-only fixtures.
var failures := 0
var checks := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func advance(model, seconds: float) -> void:
	for step in ceili(seconds / 0.05):
		await physics_frame
		model.tick(0.05)

func run() -> void:
	game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.session.set_physics_process(false)
	var model = game.session.model
	game.session.start_solo()
	model._monster_pause = 9999.0
	check(model.motion_solver.is_valid(), "app wires engine physics into authority model")
	check(game.world.obstacles().size() == 11, "inn exports the reference eleven furniture regions")
	var static_count := 0
	for child in game.world.get_children():
		if child is StaticBody3D:
			static_count += 1
	check(static_count == 15, "furniture and four boundaries have actual static collision bodies")
	var rules = load("res://features/inventory/inventory_rules.gd")
	check(is_equal_approx(rules.weight([{"weight": 1.5}, {"weight": 2.5}]), 4.0), "inventory preserves fractional reference weights")
	check(rules.can_add([{"weight": 10.5}], {"weight": 1.5}) and not rules.can_add([{"weight": 11.0}], {"weight": 1.5}), "twelve kg accepts exact capacity and rejects overflow")
	for actor_name in ["hero", "companion", "monster"]:
		check(load("res://assets/characters/" + actor_name + ".png") is Texture2D, "reference texture imported: " + actor_name)
	var human: Dictionary = model.get_player(1)
	var bot: Dictionary = model.get_player(2)
	bot.bot = false
	human.pos = Vector2(-2.5, 3.0)
	for step in 30:
		model.command(1, "move", {"direction": Vector2.UP})
		await advance(model, 0.05)
	check(human.pos.y >= 2.35 and human.pos.y < 2.5, "authority movement stops at the visible table")
	check(game.player_physics.bodies[1] is CharacterBody3D, "authority uses a CharacterBody3D, separate from paper visuals")
	# Bypass navigation entirely to prove collision is performed by Godot itself.
	var pos := Vector2(-2.5, 3.0)
	for step in 30:
		await physics_frame
		pos = game.player_physics.solve(1, pos, Vector2(0.0, -0.1))
	check(pos.y >= 2.34 and pos.y < 2.5, "engine collision blocks movement even without rectangle prevalidation")
	model.command(1, "move", {"direction": Vector2.ZERO})
	bot.bot = true
	human.pos = Vector2(-8, -4)
	await advance(model, 15.0)
	check(bot.pos.distance_to(human.pos) < 3.8, "live companion follows around inn furniture with engine collision")
	human.pos = bot.pos + Vector2(0.7, 0.0)
	human.status = "downed"
	human.hp = 0.0
	human.down_left = 22.0
	await advance(model, 3.6)
	check(human.status == "alive" and human.hp == 65.0, "live companion rescues the downed player")
	human.pos = model.EXTRACT_POSITION
	await advance(model, 19.0)
	check(human.status == "extracted" and bot.status == "extracted" and model.state.phase == "results", "live physics companion follows extraction and completes the round")
	game.session.send("start")
	check(model.state.round == 2 and model.state.corpses.is_empty(), "composed app restarts a clean second round")
	game.session.offline()
	check(model.state.phase == "lobby" and model.state.players.size() == 1 and model.state.total_banked == 0, "leave clears room results and restores fresh local lobby")
	game.queue_free()
	await process_frame
	print("MIGRATION_TEST ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
