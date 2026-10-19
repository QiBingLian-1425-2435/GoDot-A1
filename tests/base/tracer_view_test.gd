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
	check(first.size() == 6 and first[0].distance_to(first[2]) <= 3.802,"shot draws a wide short streak instead of a full static ray")
	check(game.session.model.state == state,"view never mutates hit or inventory state")
	var feedback = game.get_node("ShotFeedback")
	var count: int = feedback.impacts.size()
	game._update_tracers()
	check(feedback.impacts.size() == count and count == 1,"confirmed wall hit creates one effect; snapshot repeats do not replay it")
	var width: float = first[0].distance_to(first[1])
	game.session.model.state.shots[0].weapon = "pistol"
	game._update_tracers()
	var pistol := vertices(game)
	check(pistol[0].distance_to(pistol[1]) < width and pistol[0].distance_to(pistol[2]) < first[0].distance_to(first[2]),"pistol streak is narrower and shorter than rifle")
	game.session.model.state.shots[0].weapon = "rifle"
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
	check(moved.size() == 6 and moved[0].z > first[0].z + 1.0,"streak advances along original trajectory while shooter moves")
	check(is_equal_approx(moved[0].x,first[0].x),"moving shooter cannot drag the confirmed ray sideways")
	check(moved[2].z <= float(shot.to.y) + 0.1,"streak cannot extend beyond wall or target hit")
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
	await create_timer(.5).timeout
	check(feedback.impacts.is_empty(),"impact sparks, dust and point lights are reclaimed")
	check(feedback.kick == 0.0,"camera recoil settles back to zero")
	var before_hp: int = game.session.model.state.targets[0].hp
	feedback.observe({"from":Vector2(8,8),"to":Vector2(8,8.8),"player_id":1,"sequence":100,"weapon":"rifle","impact":"target","target_id":0},0.0)
	await create_timer(.03).timeout
	check(absf(game.world.target_nodes[0].rotation.z) > .001,"confirmed target feedback visibly rocks its board")
	check(game.session.model.state.targets[0].hp == before_hp,"target feedback never changes damage")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		game.get_viewport().get_texture().get_image().save_png("res://artifacts/weapon_impact.png")
	game.in_game = false
	await process_frame
	await process_frame
	check(feedback.impacts.is_empty() and feedback.seen.is_empty(),"leaving base clears effects and event identities")
	game.queue_free(); await process_frame
	print("TRACER_VIEW_TEST failures=",failures)
	quit(0 if failures == 0 else 1)
