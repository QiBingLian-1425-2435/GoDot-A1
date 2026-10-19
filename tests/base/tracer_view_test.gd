extends SceneTree
const Main = preload("res://app/main.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func vertices(game) -> PackedVector3Array:
	if game.tracer_mesh.get_surface_count() == 0: return PackedVector3Array()
	return game.tracer_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
func run() -> void:
	var game = Main.new()
	game.smoke = true; game.elapsed = -100; game.capture_mode = "base"
	root.add_child(game)
	game.set_physics_process(false); game.session.set_physics_process(false)
	var p: Dictionary = game.session.model.state.players[1]
	p.pos = Vector2(9,4.2); p.aim = Vector2.DOWN
	check(game.session.model.command(1,"fire"),"actual authority produces shot")
	var state: Dictionary = game.session.model.state.duplicate(true)
	game._update_tracers()
	var first := vertices(game)
	check(first.size() == 2 and first[0].distance_to(first[1]) <= 1.801,"shot draws a short streak instead of a full static ray")
	check(game.session.model.state == state,"view never mutates hit or inventory state")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		game._update_actors(0.016)
		for i in range(20): game._update_camera(0.1)
		await RenderingServer.frame_post_draw
		game.get_viewport().get_texture().get_image().save_png("res://artifacts/tracer_short_streak.png")
	var shot: Dictionary = game.session.model.state.shots[0]
	shot.ttl = 0.15
	p.pos.x += 2.0
	game._update_tracers()
	var moved := vertices(game)
	check(moved.size() == 2 and moved[0].z > first[0].z + 1.0,"streak advances along original trajectory while shooter moves")
	check(is_equal_approx(moved[0].x,first[0].x),"moving shooter cannot drag the confirmed ray sideways")
	check(moved[1].z <= float(shot.to.y) + 0.001,"streak cannot extend beyond wall or target hit")
	shot.ttl = 0.01
	game._update_tracers()
	check(vertices(game).is_empty(),"visual expires even while old shot is still retained by authority")
	# A received snapshot is not ticked locally; snapshot age must still retire its streak.
	shot.from = Vector2.ZERO; shot.to = Vector2(0,22); shot.ttl = 0.16
	game.session.mode = "client"
	game.session._snapshot_received_usec = Time.get_ticks_usec() - 300000
	game._update_tracers()
	check(vertices(game).is_empty(),"old client snapshot cannot leave a stationary tracer")
	game.session.mode = "offline"
	shot.to = shot.from
	game._update_tracers()
	check(vertices(game).is_empty(),"zero distance produces no invalid geometry")
	game.queue_free(); await process_frame
	print("TRACER_VIEW_TEST failures=",failures)
	quit(0 if failures == 0 else 1)
