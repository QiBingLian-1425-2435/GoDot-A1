extends SceneTree
## Real Main keyboard routing and physical scene across an impaired ENet transport.
## The Python runner only forwards original UDP datagrams; files configure fixtures.
const Main = preload("res://app/main.gd")
var game
var host := false
var measure_only := false
var port := 0
var output := ""
var profile := ""
var failures: Array[String] = []
var measured_failures: Array[String] = []
var checks := 0
var metrics: Dictionary = {}
var samples: Array = []
var active_case := "joining"
var done := false
var start_usec := 0
var control_serial := 0
var last_control := 0
var remote_seen := false
var previous_shown := Vector2.ZERO
var previous_remote := Vector2.ZERO
var control_clock := 0.0
var rendered_shots:Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		if arg == "--measure-only": measure_only = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--results="): output = arg.trim_prefix("--results=")
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
	Engine.max_fps = 60
	start_usec = Time.get_ticks_usec()
	call_deferred("run")

func check(value: bool, message: String, responsiveness := false) -> void:
	checks += 1
	if value: return
	if responsiveness and measure_only:
		measured_failures.append(message)
		print("BASELINE MEASURE: ", message)
	else:
		failures.append(message)
		push_error("LATENCY FAIL: " + message)

func write_json(name: String, value: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func read_json(name: String) -> Variant:
	var path := output.path_join(name)
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func now() -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000000.0

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_keys() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]: key(code, false)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func shown(id: int = -1) -> Vector2:
	if id < 0: id = game.session.local_id
	if not game.actors.has(id): return Vector2.INF
	var at: Vector3 = game.actors[id].position
	return Vector2(at.x, at.z)

func local_velocity() -> Vector2:
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	var prediction = game.session.get("local_movement")
	return prediction.sample_player(p).velocity if prediction != null else p.velocity

func protected_state() -> Dictionary:
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	var result: Dictionary = {}
	for field in ["bag", "stash", "equipment", "ammo", "credits", "hp"]:
		result[field] = p[field].duplicate(true) if p[field] is Dictionary or p[field] is Array else p[field]
	return result

func command(payload: Dictionary) -> void:
	control_serial += 1
	payload.serial = control_serial
	write_json("control.json", payload)
	var deadline := now() + 3.0
	while now() < deadline:
		var ack: Variant = read_json("control_ack.json")
		if ack is Dictionary and int(ack.get("serial", -1)) == control_serial: return
		await wait(.02)
	check(false, "host fixture command acknowledged")

func place(at: Vector2) -> void:
	release_keys()
	await command({"position": [at.x, at.y]})
	await wait(1.0)
	check(shown().distance_to(at) < .1, "authoritative fixture placement arrives through real RPC")

func run() -> void:
	game = Main.new()
	game.name = "Main"
	game.smoke = true
	game.elapsed = -1000.0
	root.add_child(game)
	# Unlike the old movement test, Main input and Session physics remain enabled.
	if host:
		check(game.session.host(port) == OK, "host creates real ENet transport")
		game._enter_base()
		write_json("host_ready.json", {"port": port})
		return
	game.session.set_physics_process(true)
	check(game.session.join("127.0.0.1", port) == OK, "client connects through UDP proxy")
	game.joining = true
	var deadline := now() + 15.0
	while not game.in_game and now() < deadline: await wait(.02)
	check(game.in_game, "client receives actual host snapshot and enters Main")
	if not game.in_game:
		finish()
		return
	await wait(.8)
	await command({"hunger":25.0})
	await place(Vector2(0, 3))
	var inventory_before := protected_state()
	await measure_start_stop()
	await measure_reverse()
	await measure_block("inventory")
	await measure_block("pause")
	await measure_block("overlay")
	await measure_wall()
	await measure_correction()
	await measure_remote()
	check(protected_state() == inventory_before, "movement and prediction never mutate authoritative inventory, equipment, ammo, credits or hp")
	await measure_shots()
	active_case = "leave"
	release_keys()
	game._return_menu()
	check(not game.in_game and game.session.mode == "offline", "menu exit clears live connection")
	check(game.session.motion_buffer._samples.is_empty(), "menu exit clears interpolation history")
	await wait(1.0)
	finish()

func measure_start_stop() -> void:
	active_case = "start"
	var origin := shown()
	var pressed := now()
	key(KEY_W, true)
	while shown().distance_to(origin) < .01 and now() - pressed < 1.5: await process_frame
	metrics.start_ms = (now() - pressed) * 1000.0
	check(metrics.start_ms <= 50.0, "physical key starts local actor within 50 ms (%.1f)" % metrics.start_ms, true)
	await wait(.65)
	active_case = "stop"
	var released := now()
	var release_pos := shown()
	key(KEY_W, false)
	var last_motion := released
	var stopped_at := -1.0
	var resumed := false
	var idle_at := -1.0
	var previous := shown()
	var max_drift := 0.0
	while now() - released < 1.4:
		await process_frame
		var current := shown()
		if current.distance_to(previous) > .002: last_motion = now()
		if local_velocity().length() <= .01:
			if stopped_at < 0: stopped_at = now()
		elif stopped_at >= 0: resumed = true
		max_drift = maxf(max_drift, current.distance_to(release_pos))
		if idle_at < 0 and game.actors[game.session.local_id].animation_state == "idle": idle_at = now()
		previous = current
	metrics.stop_ms = (stopped_at - released) * 1000.0 if stopped_at >= 0 else 1400.0
	metrics.last_display_motion_ms = (last_motion - released) * 1000.0
	metrics.idle_ms = (idle_at - released) * 1000.0 if idle_at >= 0 else 1400.0
	metrics.stop_drift_m = max_drift
	check(metrics.stop_ms <= 50.0, "physical key release stops local actor within 50 ms (%.1f)" % metrics.stop_ms, true)
	check(not resumed, "late ACK never resumes input-driven movement after release", true)
	check(metrics.idle_ms <= 100.0, "release stops locomotion animation within 100 ms (%.1f)" % metrics.idle_ms, true)
	check(max_drift < .2, "old packets do not replay held movement after release (drift %.3f m)" % max_drift, true)
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	check(shown().distance_to(p.pos) < .12 and Vector2(p.velocity).length() < .01, "stopped display converges to the real host state")

func measure_reverse() -> void:
	await place(Vector2(0, 3))
	active_case = "reverse"
	key(KEY_W, true)
	await wait(.8)
	var previous := shown()
	var down := Vector2(game.camera.global_basis.z.x, game.camera.global_basis.z.z).normalized()
	var switched := now()
	key(KEY_W, false)
	key(KEY_S, true)
	while now() - switched < 1.3:
		await process_frame
		var current := shown()
		if (current - previous).dot(down) > .002: break
		previous = current
	metrics.reverse_ms = (now() - switched) * 1000.0
	check(metrics.reverse_ms <= 50.0, "reverse key changes local travel within 50 ms (%.1f)" % metrics.reverse_ms, true)
	key(KEY_S, false)
	await wait(1.0)

func measure_block(kind: String) -> void:
	await place(Vector2(0, 3))
	active_case = kind
	key(KEY_W, true)
	await wait(.8)
	var blocked_at := now()
	var last_motion := blocked_at
	var previous := shown()
	var blocked_pos := previous
	var stopped_at := -1.0
	var resumed := false
	var max_drift := 0.0
	if kind == "inventory":
		key(KEY_TAB, true)
		key(KEY_TAB, false)
	elif kind == "pause":
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
	else:
		game.steam_service.overlay_active = true
	var previous_confirmed := Vector2.INF
	var previous_error := INF
	var diverged := false
	for _frame in range(75):
		await process_frame
		if shown().distance_to(previous) > .002: last_motion = now()
		max_drift = maxf(max_drift,shown().distance_to(blocked_pos))
		if local_velocity().length() <= .01:
			if stopped_at < 0: stopped_at = now()
		elif stopped_at >= 0: resumed = true
		var authority: Dictionary = game.session.model.state.players[game.session.local_id]
		var error := shown().distance_to(authority.pos)
		if Vector2(authority.velocity).is_zero_approx() and local_velocity().is_zero_approx() and Vector2(authority.pos).is_equal_approx(previous_confirmed):
			if error > previous_error+.003: diverged = true
		previous_confirmed = authority.pos
		previous_error = error
		previous = shown()
	metrics[kind + "_stop_ms"] = (stopped_at - blocked_at) * 1000.0 if stopped_at >= 0 else 1250.0
	metrics[kind + "_last_display_motion_ms"] = (last_motion - blocked_at) * 1000.0
	metrics[kind + "_drift_m"] = max_drift
	check(metrics[kind + "_stop_ms"] <= 50.0, kind + " blocks held movement within 50 ms (%.1f)" % metrics[kind + "_stop_ms"], true)
	check(not resumed, kind + " never resumes input movement during late authority correction", true)
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	var prediction = game.session.get("local_movement")
	var predicted_pos: Vector2 = prediction._state.pos if prediction != null else p.pos
	check(not diverged and predicted_pos.distance_to(p.pos) < .015 and shown().distance_to(p.pos) <= .121 and Vector2(p.velocity).is_zero_approx(), kind + " correction converges to the stopped host without reversing away")
	check(game.ui.is_blocking() if kind != "overlay" else game.steam_service.overlay_active, kind + " is actually active")
	key(KEY_W, false)
	if kind == "inventory":
		key(KEY_TAB, true)
		key(KEY_TAB, false)
	elif kind == "pause":
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
	else:
		game.steam_service.overlay_active = false
	await wait(.8)

func measure_wall() -> void:
	await place(Vector2(0, -9.5))
	active_case = "wall"
	key(KEY_W, true)
	var minimum := shown().y
	var until := now() + 1.3
	while now() < until:
		await process_frame
		minimum = minf(minimum, shown().y)
	key(KEY_W, false)
	await wait(1.0)
	metrics.wall_min_y = minimum
	check(minimum > -10.6 and minimum < -10.2, "client displayed body is stopped by actual northern wall")
	var p: Dictionary = game.session.model.state.players[game.session.local_id]
	check(p.pos.y > -10.6 and shown().distance_to(p.pos) < .15, "host CharacterBody3D and local display agree at real wall")

func measure_correction() -> void:
	await place(Vector2(0, 3))
	active_case = "correction"
	await command({"position": [.55, 3.0]})
	await wait(1.2)
	check(shown().distance_to(Vector2(.55, 3)) < .1, "authoritative small position correction converges")
	await command({"position": [0.0, -9.5]})
	await wait(1.2)
	check(shown().distance_to(Vector2(0, -9.5)) < .1, "authoritative teleport replaces stale local trajectory")

func measure_remote() -> void:
	active_case = "remote"
	await command({"host_position": [0.0, 3.0], "host_walk": true})
	await wait(.8)
	var frames := 0
	var moved := 0
	var backwards := 0
	var biggest := 0.0
	var previous := shown(1)
	var down := Vector2(game.camera.global_basis.z.x, game.camera.global_basis.z.z).normalized()
	var until := now() + .8
	while now() < until:
		await process_frame
		var at := shown(1)
		var delta := at - previous
		frames += 1
		if delta.length() > .001: moved += 1
		if delta.dot(down) > .002: backwards += 1
		biggest = maxf(biggest, delta.length())
		previous = at
	metrics.remote_frames = frames
	metrics.remote_moving_frames = moved
	metrics.remote_max_step_m = biggest
	check(frames > 20 and moved > frames * (.6 if profile == "jitter" else .8), "remote interpolation still advances on most render frames")
	check(backwards == 0 and biggest < .23, "remote interpolation avoids rewinds and whole-packet jumps")
	await command({"host_walk": false})
	await wait(.8)

func measure_shots() -> void:
	active_case="shots"
	release_keys()
	rendered_shots.clear()
	for i in range(3):
		await command({"fire":true})
		await wait(.3)
		game.session.send("fire")
		await wait(.8)
	await wait(1.0)
	metrics.rendered_shots=rendered_shots.size()
	check(rendered_shots.size()==6,"all host and client confirmed shots produce visible tracer geometry through impaired RPC")

func _process(delta: float) -> bool:
	if game == null or done: return false
	if now() > 90:
		check(false, "bounded completion")
		finish()
		return false
	if host:
		remote_seen = remote_seen or game.session.model.state.players.size() > 1
		control_clock += delta
		if control_clock > .02:
			control_clock = 0
			var control: Variant = read_json("control.json")
			if control is Dictionary and int(control.get("serial", 0)) > last_control:
				last_control = int(control.serial)
				if control.has("position"):
					for id in game.session.model.state.players:
						if id != 1:
							game.session.model.state.players[id].pos = Vector2(control.position[0], control.position[1])
							game.session.model.reset_transients(id)
				if control.has("host_position"):
					game.session.model.state.players[1].pos = Vector2(control.host_position[0], control.host_position[1])
				if control.has("hunger"):
					for p in game.session.model.state.players.values():p.hunger=float(control.hunger)
				if control.has("fire"):game.session.send("fire")
				if control.has("host_walk"): key(KEY_W, control.host_walk)
				game.session._broadcast_snapshot(true)
				write_json("control_ack.json", {"serial": last_control})
		if FileAccess.file_exists(output.path_join("client_result.json")):
			check(remote_seen, "host observed a real remote ENet player")
			check(game.session.model.state.players.size() == 1, "client exit removes remote authority player")
			finish()
		return false
	if game.in_game and game.actors.has(game.session.local_id):
		var p: Dictionary = game.session.model.state.players[game.session.local_id]
		if game.tracer_mesh.get_surface_count()>0:
			for shot in game.session.visual_shots():rendered_shots["%s:%s"%[shot.player_id,shot.sequence]]=true
		var at := shown()
		var predicted_velocity := local_velocity()
		samples.append({"time": now(), "case": active_case, "shown": [at.x, at.y],
			"confirmed": [p.pos.x, p.pos.y], "velocity": [p.velocity.x, p.velocity.y],
			"local_velocity": [predicted_velocity.x,predicted_velocity.y],
			"animation": game.actors[game.session.local_id].animation_state,
			"physics_frame": Engine.get_physics_frames()})
	return false

func finish() -> void:
	if done: return
	done = true
	release_keys()
	var result := {"checks": checks, "failures": failures, "measured_failures": measured_failures, "metrics": metrics, "profile": profile,
		"not_tested": ["actual window focus loss (smoke bypasses DisplayServer focus)", "Steam two-account cross-network transport"]}
	write_json("host_result.json" if host else "client_result.json", result)
	if not host: write_json("frames.json", samples)
	print("LATENCY_RESULT ", JSON.stringify(result))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
