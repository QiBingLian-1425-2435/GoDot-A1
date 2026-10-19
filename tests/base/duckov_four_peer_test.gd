extends SceneTree
## One real host plus three real ENet clients, then replace a disconnected client.
## Starts only test-owned subprocesses and never reads or writes a gameplay profile.
const Session = preload("res://app/network/session.gd")
var session
var client_slot := 0
var port := 29676
var phase := 0
var phase_time := 0.0
var elapsed := 0.0
var failures := 0
var checks := 0
var child_pids: Array[int] = []
var initial_positions: Dictionary = {}
var expected_drop_uids: Dictionary = {}
var client_peer_ids: Dictionary = {}
var initial_pos := Vector2.ZERO
var own_drop_uid := ""
var removed_peer := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--client-slot="): client_slot = int(arg.trim_prefix("--client-slot="))
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	call_deferred("start")

func start() -> void:
	session = Session.new()
	root.add_child(session)
	if client_slot > 0:
		check(session.join("127.0.0.1",port) == OK,"client creation")
	else:
		for slot in range(1,5): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path(slot)))
		check(session.host(port) == OK,"host creation")
		for slot in range(1,4): launch_client(slot)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FOUR PEER FAIL: " + description)

func launch_client(slot: int) -> void:
	var pid := OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/duckov_four_peer_test.gd","--","--client-slot=%d" % slot,"--port=%d" % port])
	child_pids.append(pid)
	check(pid > 0,"start client process " + str(slot))

func _process(delta: float) -> bool:
	if session == null: return false
	elapsed += delta; phase_time += delta
	if elapsed > 18.0:
		check(false,"bounded completion")
		if client_slot > 0: write_result()
		finish()
		return false
	if client_slot > 0: run_client()
	else: run_host()
	return false

func run_client() -> void:
	if phase >= 3 and session.mode == "offline":
		quit(0 if failures == 0 else 1)
		return
	if phase == 0:
		if session.mode != "client" or session.model.state.players.size() != 4 or not session.model.state.players.has(session.local_id): return
		check(session.model.state.players.size() == 4,"client receives four-player authoritative snapshot")
		initial_pos = session.model.state.players[session.local_id].pos
		own_drop_uid = session.model.state.players[session.local_id].bag[2].uid
		phase = 1; phase_time = 0
	elif phase == 1:
		var direction := Vector2.DOWN if client_slot % 2 == 1 else Vector2.UP
		session.send("move",{"direction":direction,"aim":Vector2.LEFT})
		if phase_time > 0.4:
			session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.LEFT})
			session.send("drop",{"index":2})
			phase = 2; phase_time = 0
	elif phase == 2:
		var desired_drops := 4 if client_slot == 4 else 3
		if session.model.state.drops.size() != desired_drops: return
		var p: Dictionary = session.model.state.players[session.local_id]
		check(p.pos.distance_to(initial_pos) > 0.7,"client movement survives host authority")
		check(p.bag[2].is_empty() and session.model.state.drops.has(own_drop_uid),"client inventory and own drop agree")
		check(unique_ownership(),"client snapshot has unique ownership across all four inventories and drops")
		check(session.model.state.players.size() == 4,"all four players remain in final client snapshot")
		write_result()
		phase = 3; phase_time = 0

func run_host() -> void:
	var players: Dictionary = session.model.state.players
	for id in players:
		if id == 1 or initial_positions.has(id): continue
		initial_positions[id] = players[id].pos
		expected_drop_uids[id] = players[id].bag[2].get("uid","")
	if phase == 0:
		if players.size() != 4 or session.model.state.drops.size() != 3: return
		for slot in range(1,4):
			if not FileAccess.file_exists(result_path(slot)): return
		check(players.size() == 4,"host sees itself and three actual ENet peers")
		check(session.multiplayer.get_peers().size() == 3,"transport has three connected peers")
		for slot in range(1,4):
			var result: Dictionary = read_result(slot)
			check(int(result.get("failures",-1)) == 0 and int(result.get("checks",0)) >= 6,"client " + str(slot) + " confirms four-player snapshot and actions")
			var id := int(result.get("peer_id",0))
			client_peer_ids[slot] = id
			check(players.has(id) and players[id].pos.distance_to(initial_positions.get(id,Vector2.INF)) > 0.7,"host saw client " + str(slot) + " movement")
			check(session.model.state.drops.has(expected_drop_uids.get(id,"")),"host saw unique drop from client " + str(slot))
		check(unique_ownership(),"host four-player item ownership unique")
		removed_peer = int(client_peer_ids[3])
		session._peer.disconnect_peer(removed_peer)
		phase = 1; phase_time = 0
	elif phase == 1:
		if players.size() != 3 or players.has(removed_peer): return
		check(not session._last_movement.has(removed_peer),"disconnect cleans removed peer state")
		check(session.model.state.drops.size() == 3,"disconnected player's world drop remains available")
		launch_client(4)
		phase = 2; phase_time = 0
	elif phase == 2:
		if players.size() != 4 or session.model.state.drops.size() != 4 or not FileAccess.file_exists(result_path(4)): return
		var result: Dictionary = read_result(4)
		var replacement_id := int(result.get("peer_id",0))
		check(int(result.get("failures",-1)) == 0,"replacement client sees complete four-player state")
		check(replacement_id != removed_peer and players.has(replacement_id),"new player joins freed fourth slot")
		check(unique_ownership() and session.model.state.drops.size() == 4,"replacement does not duplicate prior players' dropped items")
		check(players[replacement_id].pos.distance_to(initial_positions.get(replacement_id,Vector2.INF)) > 0.7,"replacement player moves authoritatively")
		session.offline()
		phase = 3; phase_time = 0
	elif phase == 3:
		var running := false
		for pid in child_pids:
			if pid > 0 and OS.is_process_running(pid): running = true
		if not running or phase_time > 2.0: finish()

func unique_ownership() -> bool:
	var seen := {}
	for p in session.model.state.players.values():
		for container in [p.bag,p.stash,p.equipment.values()]:
			for item in container:
				if item.is_empty(): continue
				if seen.has(item.uid): return false
				seen[item.uid] = true
	for uid in session.model.state.drops:
		if seen.has(uid): return false
		seen[uid] = true
	return true

func result_path(slot: int) -> String:
	return "user://duckov_four_peer_%d_%d.json" % [port,slot]

func write_result() -> void:
	var file := FileAccess.open(result_path(client_slot),FileAccess.WRITE)
	file.store_string(JSON.stringify({"slot":client_slot,"peer_id":session.local_id,"checks":checks,"failures":failures})); file.close()

func read_result(slot: int) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path(slot)))
	return value if value is Dictionary else {}

func finish() -> void:
	for pid in child_pids:
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	if client_slot == 0:
		for slot in range(1,5):
			if FileAccess.file_exists(result_path(slot)):
				print("DUCKOV_FOUR_PEER_CLIENT ",read_result(slot))
				DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path(slot)))
	print("DUCKOV_FOUR_PEER_HOST ",checks," checks, ",failures," failures")
	session.offline()
	quit(0 if failures == 0 else 1)
