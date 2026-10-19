extends SceneTree
const Main = preload("res://app/main.gd")
const Model = preload("res://features/base/base_model.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func run() -> void:
	var model = Model.new()
	for id in range(1, 7): model.add_player(id, "test_%d" % id)
	check(model.state.players.size() == 5 and not model.state.players.has(6), "five-player model limit rejects the sixth player")
	var game = Main.new()
	game.smoke = true
	game.elapsed = -100
	game.capture_mode = "base"
	root.add_child(game)
	await physics_frame
	await physics_frame
	check(game.session.model.motion_solver.is_valid(), "live base installs the engine collision adapter")
	var bodies := 0
	for child in game.world.get_children():
		if child is StaticBody3D: bodies += 1
	check(bodies == game.world.obstacles().size() and bodies == 43, "reference obstacles and four perimeter walls have real StaticBody3D colliders")
	var stop: Vector2 = game.player_physics.solve(1, Vector2(0, -9.5), Vector2(0, -3))
	check(stop.y > -10.6 and stop.y < -9.5, "CharacterBody3D is stopped by the actual northern wall")
	check(Main.PROFILE == "user://a1_bunker_profile_v1.json", "new base uses its own profile and does not read the reference save")
	check(game.session.name == "Session", "all transports keep the identical Session node path")
	game.queue_free()
	await process_frame
	print("BUNKER_MIGRATION_CONTRACT ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
