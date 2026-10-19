extends SceneTree
## Run without arguments. Starts a real second Godot process over localhost ENet.
const Session = preload("res://app/network/session.gd")
var session
var client := false
var port := 29673
var elapsed := 0.0
var phase_time := 0.0
var phase := 0
var peer_id := 0
var child_pid := -1
var failures := 0
var checks := 0
var initial_pos := Vector2.ZERO
var seen_motion := false
var seen_transfer := false
var seen_drop := false
var picked_drop := false
var seen_disconnect := false
var tracked_uid := ""
var original_ammo_uid := ""
var pickup_uid := ""
var item_totals: Dictionary = {}
var scenario := "normal"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--client": client = true
		if arg == "--failure": client = true; scenario = "failure"
		if arg == "--host-loss": scenario = "host_loss"
		if arg == "--host-loss-client": client = true; scenario = "host_loss"
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	call_deferred("start")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NETWORK FAIL: " + description)

func start() -> void:
	session = Session.new()
	root.add_child(session)
	if client:
		if scenario != "normal": session.model.state.players[1].credits = 321
		check(session.join("127.0.0.1",port) == OK,"client creation")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path()))
		check(session.host(port) == OK,"host creation")
		var args := ["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/duckov_network_test.gd","--","--client","--port=%d" % port]
		if scenario == "host_loss": args.append("--host-loss-client")
		child_pid = OS.create_process(OS.get_executable_path(),args)
		check(child_pid > 0,"launch real second process")

func _process(delta: float) -> bool:
	if session == null: return false
	elapsed += delta; phase_time += delta
	if elapsed > 14:
		check(false,"test completed before timeout")
		finish()
		return false
	if scenario != "normal":
		run_failure_scenario()
		return false
	if client: run_client()
	else: run_host()
	return false

func run_client() -> void:
	if phase == 0:
		if session.local_id == 0 or not session.model.state.players.has(session.local_id): return
		phase = 1; phase_time = 0
		initial_pos = session.model.state.players[session.local_id].pos
		original_ammo_uid = session.model.state.players[session.local_id].bag[0].uid
	if phase == 1:
		session.send("move",{"direction":Vector2.LEFT,"aim":Vector2.DOWN})
		if phase_time > 0.45:
			session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.DOWN})
			session.send("transfer",{"from":"bag","index":0,"to":"stash","target":10})
			phase = 2; phase_time = 0
	elif phase == 2 and phase_time > 0.4:
		var p: Dictionary = session.model.state.players[session.local_id]
		check(p.pos.distance_to(initial_pos) > 0.8,"client receives authoritative movement")
		check(p.bag[0].is_empty() and p.stash[10].get("uid","") == original_ammo_uid,"client sees authoritative inventory transfer")
		tracked_uid = p.bag[2].uid
		session.send("split",{"container":"bag","index":1,"count":1})
		session.send("drop",{"index":2})
		phase = 3; phase_time = 0
	elif phase == 3 and phase_time > 0.5:
		var split_p: Dictionary = session.model.state.players[session.local_id]
		check(split_p.bag[1].get("count",0) == 2 and split_p.bag[0].get("kind","") == "bandage" and split_p.bag[0].get("count",0) == 1,"client split RPC returns separate conserved stacks")
		# Host has claimed this item. Replays cannot create another owner.
		session.send("pickup",{"uid":tracked_uid})
		session.send("pickup",{"uid":tracked_uid})
		# Test stale movement and stale token without injecting final positions.
		session._movement.rpc_id(1,{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT},session._session_token,1)
		session._movement.rpc_id(1,{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT},session._session_token + 1,99999)
		phase = 4; phase_time = 0
	elif phase == 4 and phase_time > 0.6:
		check(not session.model.state.drops.has(tracked_uid),"claimed drop stays absent after duplicate pickup")
		check(unique(session.model),"client snapshot has unique item ownership")
		session.offline()
		print("DUCKOV_NETWORK_CLIENT ",checks," checks, ",failures," failures")
		var file := FileAccess.open(result_path(),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures})); file.close()
		quit(0 if failures == 0 else 1)

func run_host() -> void:
	var players: Dictionary = session.model.state.players
	if peer_id == 0 and players.size() == 2:
		for id in players:
			if id != 1: peer_id = id
		initial_pos = players[peer_id].pos
		original_ammo_uid = players[peer_id].bag[0].uid
		item_totals = totals(session.model)
		check(peer_id > 1,"host identifies actual remote sender")
	if peer_id > 0 and players.has(peer_id):
		var p: Dictionary = players[peer_id]
		if p.pos.distance_to(initial_pos) > 0.8: seen_motion = true
		if p.bag[0].is_empty() and p.stash[10].get("uid","") == original_ammo_uid: seen_transfer = true
		if not session.model.state.drops.is_empty():
			seen_drop = true
			pickup_uid = str(session.model.state.drops.keys()[0])
			session.send("pickup",{"uid":pickup_uid})
			picked_drop = not session.model.state.drops.has(pickup_uid)
		# Wait for the actual stop packet, not a deadline relative to process launch.
		# A slower client may still be sending valid movement at host elapsed=1.8.
		var stopped: bool = session.model._inputs.get(peer_id, {}).get("direction", Vector2.INF) == Vector2.ZERO
		if elapsed > 1.8 and phase == 0 and stopped and seen_transfer and picked_drop:
			check(totals(session.model) == item_totals,"real RPC transfer/drop/pickup conserve all item counts")
			check(unique(session.model),"host ownership unique after contested pickup")
			initial_pos = p.pos
			phase = 1; phase_time = 0
		elif phase == 1 and phase_time > 0.35:
			check(p.pos.distance_to(initial_pos) < 0.05,"stale sequence and wrong session token cannot restart movement")
			phase = 2
	elif peer_id > 0 and not players.has(peer_id):
		seen_disconnect = true
		if not OS.is_process_running(child_pid):
			var client_result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path())) if FileAccess.file_exists(result_path()) else null
			check(client_result is Dictionary and int(client_result.get("failures",-1)) == 0,"client process assertions passed")
			if client_result is Dictionary: print("DUCKOV_NETWORK_CLIENT_RESULT ", client_result)
			check(seen_motion,"host applied remote movement")
			check(seen_transfer,"host applied remote storage transfer")
			check(seen_drop and picked_drop,"host picks up remote dropped item")
			check(seen_disconnect and players.size() == 1,"disconnect cleans authoritative player")
			check(not session._last_movement.has(peer_id) and not session._rate_limits.has(peer_id),"disconnect clears request state")
			finish()

func unique(model) -> bool:
	var seen := {}
	for p in model.state.players.values():
		for container in [p.bag,p.stash,p.equipment.values()]:
			for item in container:
				if item.is_empty(): continue
				if seen.has(item.uid): return false
				seen[item.uid] = true
	for item in model.state.drops.values():
		if seen.has(item.uid): return false
		seen[item.uid] = true
	return true

func totals(model) -> Dictionary:
	var result := {}
	for p in model.state.players.values():
		for container in [p.bag,p.stash,p.equipment.values()]:
			for item in container:
				if not item.is_empty(): result[item.kind] = int(result.get(item.kind,0)) + int(item.count)
	for item in model.state.drops.values(): result[item.kind] = int(result.get(item.kind,0)) + int(item.count)
	return result

func finish() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	print("DUCKOV_NETWORK_HOST ",checks," checks, ",failures," failures")
	session.offline()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path()))
	quit(0 if failures == 0 else 1)

func result_path() -> String:
	return "user://duckov_network_test_%d.json" % port

func run_failure_scenario() -> void:
	if client:
		if scenario == "host_loss" and phase == 0 and session.local_id > 1 and session.model.state.players.has(session.local_id):
			phase = 1
			check(session.model.state.players[session.local_id].credits == 500,"joined host uses separate temporary inventory")
		if session.mode == "offline" and (scenario == "failure" or phase == 1):
			check(session.local_id == 1 and session.model.state.players.size() == 1,"failed or lost connection returns to solo")
			check(session.model.state.players[1].credits == 321,"original local profile restored after network exit")
			check(session.connection_status.contains("连接失败") if scenario == "failure" else session.connection_status.contains("房主已离开"),"network failure has actionable status")
			print("DUCKOV_NETWORK_",scenario.to_upper(),"_CLIENT ",checks," checks, ",failures," failures")
			if scenario == "host_loss":
				var file := FileAccess.open(result_path(),FileAccess.WRITE)
				file.store_string(JSON.stringify({"checks":checks,"failures":failures})); file.close()
			quit(0 if failures == 0 else 1)
	else:
		if phase == 0 and session.model.state.players.size() == 2:
			phase = 1; phase_time = 0
		elif phase == 1 and phase_time > 0.35:
			session.offline(); phase = 2
		elif phase == 2 and not OS.is_process_running(child_pid):
			var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path())) if FileAccess.file_exists(result_path()) else null
			check(result is Dictionary and int(result.get("failures",-1)) == 0,"server-loss client assertions passed")
			if result is Dictionary: print("DUCKOV_NETWORK_HOST_LOSS_CLIENT_RESULT ",result)
			finish()
