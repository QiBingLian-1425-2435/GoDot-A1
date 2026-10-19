extends SceneTree
## Actual Main/Session, CharacterBody3D, actor and camera across two ENet processes.
## --visible-client runs the joining player's real window and saves a screenshot.
const Main = preload("res://app/main.gd")
var game
var client := false
var visible_client := false
var child_pid := -1
var phase := 0
var elapsed := 0.0
var phase_time := 0.0
var failures: Array[String] = []
var checks := 0
var frames := 0
var smooth_frames := 0
var raw_frames := 0
var backwards := 0
var previous := Vector2.ZERO
var previous_raw := Vector2.ZERO
var max_step := 0.0
var shot_count := 0
var finished := false
const PORT := 29819

func _initialize() -> void:
	client = "--client" in OS.get_cmdline_user_args()
	visible_client = "--visible-client" in OS.get_cmdline_user_args()
	Engine.max_fps = 60
	call_deferred("start")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error("MOVEMENT SCENE FAIL: " + message)

func start() -> void:
	game = Main.new()
	game.name = "Main"
	game.smoke = true; game.elapsed = -100.0
	root.add_child(game)
	game.set_physics_process(false) # Test sends intents; leave real Session and physics enabled.
	if client:
		game.session.set_physics_process(true)
		check(game.session.join("127.0.0.1",PORT) == OK,"client starts real transport")
		game.joining = true
	else:
		DirAccess.remove_absolute(result_path())
		check(game.session.host(PORT) == OK,"host starts real main scene")
		game._enter_base()
		var args := ["--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/movement_scene_network_test.gd","--","--client"]
		if not visible_client: args.push_front("--headless")
		child_pid = OS.create_process(OS.get_executable_path(),args)
		check(child_pid > 0,"launch independent client")

func _process(delta: float) -> bool:
	if game == null or finished: return false
	elapsed += delta
	phase_time += delta
	if elapsed > 20:
		check(false,"bounded completion")
		finish()
		return false
	if not client:
		if child_pid > 0 and not OS.is_process_running(child_pid):
			var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path())) if FileAccess.file_exists(result_path()) else null
			check(result is Dictionary and result.failures.is_empty(),"client scene assertions: " + str(result))
			check(game.session.model.state.players.size() == 1,"client exit removes remote player")
			print("MOVEMENT_SCENE_CLIENT ",result)
			finish()
		return false
	if not game.in_game or not game.actors.has(game.session.local_id): return false
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	var actor = game.actors[game.session.local_id]
	var shown := Vector2(actor.position.x,actor.position.z)
	if phase == 0:
		phase = 1; phase_time = 0
	elif phase == 1:
		game.session.send("move",{"direction":Vector2.UP,"aim":Vector2.DOWN})
		if phase_time > .4 and phase_time < 1.6:
			frames += 1
			var step := previous.y - shown.y
			if step > .001: smooth_frames += 1
			if step < -.001: backwards += 1
			max_step = maxf(max_step,absf(step))
			if p.pos.distance_to(previous_raw) > .001: raw_frames += 1
		if phase_time > 1.65:
			check(frames > 25 and smooth_frames > frames*.85,"visible actor moves on most frames between network packets")
			check(raw_frames < smooth_frames*.75,"actual raw RPC state still arrives less often than render frames")
			check(backwards == 0 and max_step < .22,"real actor does not rewind or jump whole snapshot distances")
			var focus: Vector3 = game.camera_focus
			var target: Vector3 = actor.position*.76
			target.y = 0
			game._update_camera(1.0/60.0)
			check(game.camera_focus.is_equal_approx(focus.lerp(target,.1)),"moving camera follows the displayed position")
			phase = 2; phase_time = 0
	elif phase == 2:
		game.session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.DOWN})
		if phase_time > .4:
			var prediction = game.session.local_movement
			check(Vector2(prediction._state.pos).distance_to(p.pos) < .015 and p.velocity == Vector2.ZERO and prediction._state.velocity == Vector2.ZERO,"stopped logical prediction converges to host-confirmed physical position")
			check(shown.distance_to(p.pos) <= prediction.REST_ERROR_LIMIT+.001,"stationary display holds only the bounded small correction")
			var original: Dictionary = game.session.model.state.duplicate(true)
			var focus: Vector3 = game.camera_focus
			var target: Vector3 = actor.position*.76
			target.y = 0
			game._update_camera(1.0/60.0)
			check(game.camera_focus.is_equal_approx(focus.lerp(target,.1)),"camera follows the same displayed position")
			check(game.session.model.state == original,"render/camera never write authority state")
			shot_count = p.shots
			game.session.send("fire")
			phase = 3; phase_time = 0
	elif phase == 3 and phase_time > .3:
		check(p.shots == shot_count+1,"shot counter synchronizes over real transport")
		check(game.tracer_mesh.get_surface_count() == 0,"shot tracer expires between full snapshots")
		game.session.send("reload")
		phase = 4; phase_time = 0
	elif phase == 4 and phase_time > 1.75:
		check(not p.reloading and p.ammo == 30,"reload completion promptly confirms ammo via reliable state")
		phase = 5; phase_time = 0
		if DisplayServer.get_name() != "headless":capture.call_deferred()
	elif phase == 5 and phase_time > .3:
		game._return_menu()
		check(game.session.motion_buffer._samples.is_empty(),"leaving real scene clears interpolation history")
		finish()
	previous = shown
	previous_raw = p.pos
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	game.get_viewport().get_texture().get_image().save_png("res://artifacts/movement_client.png")

func result_path() -> String: return "user://movement_scene_%d.json" % PORT

func finish() -> void:
	finished = true
	if client:
		var result := {"checks":checks,"failures":failures,"frames":frames,"smooth":smooth_frames,"raw":raw_frames,"max_step":max_step}
		var file := FileAccess.open(result_path(),FileAccess.WRITE)
		file.store_string(JSON.stringify(result)); file.close()
	else:
		if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
		DirAccess.remove_absolute(result_path())
	print("MOVEMENT_SCENE ",checks," checks, ",failures.size()," failures")
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
