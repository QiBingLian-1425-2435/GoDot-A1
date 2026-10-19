extends SceneTree
const Buffer = preload("res://features/player/motion_buffer.gd")
const Session = preload("res://app/network/session.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MOVEMENT FAIL: " + message)

func pose(x: float) -> Dictionary:
	return {"pos":Vector2(x,0),"velocity":Vector2(3.7,0),"aim":Vector2.UP}

func run() -> void:
	test_continuity(false)
	test_continuity(true)
	test_lifecycle()
	test_stream_order()
	print("MOVEMENT_SMOOTHING ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)

func test_continuity(jitter: bool) -> void:
	var buffer = Buffer.new()
	var packets: Array = []
	for i in range(81):
		if jitter and i % 11 == 5: continue
		var delay: float = [0.0,0.025,0.008,0.04][i%4] if jitter else 0.0
		packets.append({"arrival":i*.05+delay,"stamp":i*.05})
	var current := pose(0)
	var previous := 0.0
	var raw_previous := 0.0
	var moving_frames := 0
	var raw_moving_frames := 0
	var max_step := 0.0
	var backwards := 0
	for frame in range(240):
		var now := frame / 60.0
		while not packets.is_empty() and float(packets.front().arrival) <= now:
			var packet: Dictionary = packets.pop_front()
			current = pose(packet.stamp * 3.7)
			buffer.push({1:current},packet.stamp)
		buffer.advance(1.0/60.0)
		var original := current.duplicate(true)
		var shown: Dictionary = buffer.sample_player(1,current)
		if current != original: failures += 1; push_error("MOVEMENT FAIL: render modified authority")
		if frame > 30:
			var step := float(shown.pos.x) - previous
			if step > .001: moving_frames += 1
			if step < -.0001: backwards += 1
			max_step = maxf(max_step,absf(step))
			if current.pos.x > raw_previous+.001: raw_moving_frames += 1
		previous = shown.pos.x
		raw_previous = current.pos.x
	check(moving_frames >= 200,"continuous render movement between packets (jitter=%s, %d/209)" % [jitter,moving_frames])
	check(raw_moving_frames < 90,"raw network positions reproduce the old stepped movement")
	check(max_step < .08 and backwards == 0,"bounded forward render steps under jitter/loss")
	check(current.pos.x - previous < .8,"interpolation delay remains bounded")
	print("MOTION_METRICS jitter=",jitter," rendered=",moving_frames," raw=",raw_moving_frames," max_step=",max_step)
	# No extrapolation: a lost stream holds the latest confirmed point, even if velocity is nonzero.
	for i in range(60): buffer.advance(1.0/60.0)
	check(buffer.sample_player(1,current).pos == current.pos,"outage never extrapolates through a wall")
	current.velocity = Vector2.ZERO
	buffer.push({1:current},4.1)
	for i in range(30): buffer.advance(1.0/60.0)
	check(buffer.sample_player(1,current).velocity == Vector2.ZERO,"stopping settles at the confirmed position and pose")

func test_lifecycle() -> void:
	var buffer = Buffer.new()
	buffer.push({1:pose(1)},1.0)
	check(buffer.sample_player(1,pose(1)).pos == Vector2(1,0),"spawn snaps to the first known position")
	buffer.push({1:pose(20)},1.05)
	check(buffer.sample_player(1,pose(20)).pos == Vector2(20,0),"teleport does not sweep across the map")
	buffer.clear()
	buffer.push({1:pose(-5)},.1)
	check(buffer.sample_player(1,pose(-5)).pos == Vector2(-5,0),"new session does not reuse previous samples")
	buffer.retain([])
	check(buffer.sample_player(1,pose(7)).pos == Vector2(7,0),"removed peer history is discarded")
	buffer.clear()
	buffer.push({1:pose(1)},10000.0)
	buffer.push({1:pose(1.185)},10000.05)
	check(buffer._samples.size() == 2,"long sessions retain distinct 50ms snapshots")

func test_stream_order() -> void:
	var host = Session.new()
	for id in range(2,6): host.model.add_player(id,"fixture")
	var full: Dictionary = host.model.state.duplicate(true)
	var rows: Array = host._motion_rows()
	for row in rows: row[6] = "interact" # Longest current action name: measure active animation too.
	var full_bytes := var_to_bytes([full,10,1,0.0]).size()
	var motion_bytes := var_to_bytes([rows,10,1,0.0]).size()
	check(motion_bytes < 1200 and motion_bytes * 10 < full_bytes,"five-player movement stays small and excludes inventory")
	print("MOTION_BYTES players=5 full=",full_bytes," motion=",motion_bytes)
	var client = Session.new()
	root.add_child(client)
	client.set_physics_process(false)
	client.mode = "client"
	client._apply_motion(rows,10,9,.05)
	check(client._session_token == 0,"motion cannot establish a session before reliable admission")
	client._apply_snapshot(full.duplicate(true),10,10,.1)
	rows[0][1] = Vector2(2,4)
	client._apply_motion(rows,10,12,.2)
	var old_full := full.duplicate(true)
	old_full.players[1].credits = 42
	client._apply_snapshot(old_full,10,11,.15)
	check(client.model.state.players[1].credits == 42 and client.model.state.players[1].pos == Vector2(2,4),"late reliable state updates inventory without rewinding movement")
	rows[0][1] = Vector2(-9,4)
	client._apply_motion(rows,10,11,.15)
	check(client.model.state.players[1].pos == Vector2(2,4),"out-of-order movement is rejected")
	client._apply_snapshot(full.duplicate(true),10,13,.25)
	client._apply_motion(rows,10,12,.2)
	check(client.model.state.players[1].pos == full.players[1].pos,"newer full snapshot supersedes older movement")
	var removed := full.duplicate(true)
	removed.players.erase(5)
	client._apply_snapshot(removed,10,14,.3)
	client._apply_motion(rows,10,15,.35)
	check(not client.model.state.players.has(5),"movement cannot resurrect a disconnected peer")
	client.offline()
	check(client._received_motion_serial == -1 and client._session_token == 0 and client.motion_buffer._samples.is_empty(),"offline clears stream ordering and display history")
	client.mode = "client"
	client._apply_snapshot(full.duplicate(true),20,1,.1)
	client._apply_motion(rows,10,999,.5)
	check(client.model.state.players[1].pos == full.players[1].pos,"old session token cannot modify a new room")
	client._apply_motion(rows,20,3,.2)
	var joined := full.duplicate(true)
	joined.players[6] = joined.players[5].duplicate(true)
	client._apply_snapshot(joined,20,2,.15)
	check(client.model.state.players.has(6),"late reliable admission can add a peer after newer motion")
	client.free()
	host.free()
