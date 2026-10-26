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
		game.set_process(false)
		await RenderingServer.frame_post_draw
		var shown: Image = game.get_viewport().get_texture().get_image()
		shown.save_png("res://artifacts/tracer_short_streak.png")
		game.tracer_node.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden: Image = game.get_viewport().get_texture().get_image()
		var changed := 0
		var center: Vector2 = game.camera.unproject_position((first[0]+first[2])*.5)
		for y in range(maxi(0,int(center.y)-80),mini(shown.get_height(),int(center.y)+80)):
			for x in range(maxi(0,int(center.x)-80),mini(shown.get_width(),int(center.x)+80)):
				var a: Color = shown.get_pixel(x,y)
				var b: Color = hidden.get_pixel(x,y)
				if a.r-b.r > .15 and a.g-b.g > .1: changed += 1
		print("TRACER_VISIBLE_PIXELS ",changed)
		check(changed > 8,"tracer actually contributes bright pixels to the rendered frame")
		game.tracer_node.visible = true
		game.set_process(true)
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
	# Reliable state on another channel overtakes a near-expired fire snapshot.
	var late:Dictionary=state.duplicate(true)
	late.shots[0].sequence=200;late.shots[0].ttl=.001
	var newer:Dictionary=late.duplicate(true);newer.shots=[]
	game.session._session_token=55
	game.session._apply_snapshot(newer,55,21,1.1)
	game.session._apply_snapshot(late,56,20,1.0)
	check(game.session.visual_shots().is_empty(),"wrong-room shots never enter presentation")
	var old_world:Dictionary=late.duplicate(true);old_world.world_revision=-1
	game.session._apply_snapshot(old_world,55,20,1.0)
	check(game.session.visual_shots().is_empty(),"old-world shots never enter presentation")
	game.session._apply_snapshot(late,55,20,1.0)
	game._update_tracers()
	check(vertices(game).size()==6,"late confirmed shot renders even after newer state overtook its snapshot")
	check(game.session.model.state.shots.is_empty(),"late shot does not rewind authoritative state")
	game.session._apply_snapshot(late,55,20,1.0)
	check(game.session._shot_visuals.size()==1,"repeated snapshots cannot restart a tracer")
	game.session._shot_visuals[0].received-=300000
	game._update_tracers()
	check(vertices(game).is_empty(),"received tracer expires by local time even without new snapshots")
	game.session._apply_snapshot(late,55,20,1.0)
	check(game.session.visual_shots().is_empty(),"expired shot cannot be replayed by delayed duplicate")
	var next_shot:Dictionary=late.shots[0].duplicate(true);next_shot.sequence=202
	game.session._capture_shot_visuals([next_shot])
	next_shot.sequence=201;game.session._capture_shot_visuals([next_shot])
	check(game.session.visual_shots().size()==2,"out-of-order unseen shots are retained rather than discarded by a highest-sequence check")
	game.session.reset_world_motion()
	check(game.session._shot_visuals.is_empty() and game.session._shot_seen.is_empty(),"world transition clears visual events and identities")
	game.session.model.state=state
	shot=state.shots[0]
	game.session.mode = "offline"
	shot.to = shot.from
	game._update_tracers()
	check(vertices(game).is_empty(),"zero distance produces no invalid geometry")
	await create_timer(.5).timeout
	check(feedback.impacts.is_empty(),"impact sparks, dust and point lights are reclaimed")
	check(feedback.kick == 0.0,"camera recoil settles back to zero")
	var before_hp: int = game.session.model.state.targets[0].hp
	feedback.observe({"from":Vector2(8,8),"to":Vector2(8,8.8),"player_id":1,"sequence":300,"weapon":"rifle","impact":"target","target_id":0},0.0)
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
