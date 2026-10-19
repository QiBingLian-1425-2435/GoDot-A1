extends SceneTree
## A real ENet host and separately launched Godot client; no production profile access.
const Session = preload("res://app/network/session.gd")
const ACTIONS := ["drink","eat","heal","pickup","pickup","equip","interact"]
var session
var client := false
var port := 29687
var child_pid := -1
var peer_id := 0
var elapsed := 0.0
var phase_time := 0.0
var phase := 0
var checks := 0
var failures := 0
var action_index := 0
var action_sent := false
var drop_uid := ""
var saw_velocity := false
var saw_crouch := false
var saw_timeout := false
var saw_progress := false
var seen_actions: Dictionary = {}
var last_seq := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--client": client = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	call_deferred("start")

func start() -> void:
	session = Session.new(); root.add_child(session)
	session.model.stations = [{"kind":"medical","pos":Vector2(1,4)}]
	if client:
		check(session.join("127.0.0.1",port) == OK,"client joins actual ENet transport")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path()))
		check(session.host(port) == OK,"host starts actual ENet transport")
		child_pid = OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/duckov_animation_network_test.gd","--","--client","--port=%d" % port])
		check(child_pid > 0,"start independent client process")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ANIMATION NETWORK FAIL: " + description)

func _process(delta: float) -> bool:
	if session == null: return false
	elapsed += delta; phase_time += delta
	if elapsed > 14.0:
		check(false,"bounded network test completion")
		if client: write_result()
		finish()
		return false
	if client: run_client()
	else: run_host()
	return false

func run_client() -> void:
	if phase == 0:
		if session.local_id <= 1 or not session.model.state.players.has(session.local_id): return
		phase = 1; phase_time = 0
	var p: Dictionary = session.model.state.players.get(session.local_id,{})
	if p.is_empty(): return
	if p.get("velocity",Vector2.ZERO).length() > 3.0: saw_velocity = true
	if phase == 1:
		session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.RIGHT})
		if phase_time > 0.45:
			check(saw_velocity,"client snapshots contain authoritative movement velocity")
			phase = 2; phase_time = 0
	elif phase == 2:
		session.send("move",{"direction":Vector2.ZERO,"crouch":true})
		if phase_time > 0.35:
			check(p.crouch and p.velocity == Vector2.ZERO,"stationary crouch and zero velocity synchronize")
			phase = 3; phase_time = 0
	elif phase == 3 and phase_time > 0.65:
		check(not p.crouch and p.velocity == Vector2.ZERO,"timed-out movement pose synchronizes")
		phase = 4; phase_time = 0
	elif phase == 4:
		if not action_sent:
			send_action(p)
			action_sent = true; phase_time = 0
		elif phase_time > 0.24 and int(p.get("anim_seq",0)) >= action_index + 1:
			check(p.anim_seq == action_index + 1 and p.anim_action == ACTIONS[action_index],"confirmed action snapshot: " + ACTIONS[action_index])
			check(p.anim_time > 0 and p.anim_time < p.anim_duration,"host event elapsed advances for " + ACTIONS[action_index])
			if action_index == 0:
				session.send("use",{"index":0}) # Ammo cannot be used: must not replay the drink.
				phase = 5; phase_time = 0
			else: advance_action()
	elif phase == 5 and phase_time > 0.25:
		check(p.anim_seq == 1 and p.anim_action == "drink" and p.anim_time > 0.24,"rejected RPC does not restart or replace action")
		advance_action()
	elif phase == 6 and phase_time > 1.0:
		check(p.anim_seq == 7 and p.anim_action == "interact" and is_equal_approx(p.anim_time,p.anim_duration),"expired network event retains last sequence and type")
		session.offline()
		var local: Dictionary = session.model.state.players[1]
		check(local.velocity == Vector2.ZERO and local.anim_seq == 0 and local.anim_action == "","client disconnect restores neutral local animation state")
		write_result()
		quit(0 if failures == 0 else 1)

func send_action(p: Dictionary) -> void:
	match action_index:
		0: session.send("use",{"index":2})
		1: session.send("use",{"index":3})
		2: session.send("use",{"index":1})
		3:
			drop_uid = p.bag[0].uid
			session.send("drop",{"index":0})
		4: session.send("pickup",{"uid":drop_uid})
		5: session.send("equip",{"index":6})
		6: session.send("rest")

func advance_action() -> void:
	action_index += 1; action_sent = false; phase_time = 0
	phase = 6 if action_index >= ACTIONS.size() else 4

func run_host() -> void:
	if peer_id == 0 and session.model.state.players.size() == 2:
		for id in session.model.state.players:
			if id != 1: peer_id = id
		session.model.state.players[peer_id].hp = 30.0
	if peer_id > 0 and session.model.state.players.has(peer_id):
		var p: Dictionary = session.model.state.players[peer_id]
		if p.velocity.length() > 3.0: saw_velocity = true
		if p.crouch and p.velocity == Vector2.ZERO: saw_crouch = true
		if saw_crouch and not p.crouch and p.velocity == Vector2.ZERO: saw_timeout = true
		if p.anim_seq > 0:
			seen_actions[p.anim_action] = true
			if p.anim_time > 0 and p.anim_time < p.anim_duration: saw_progress = true
			if p.anim_seq > last_seq: last_seq = p.anim_seq
	elif peer_id > 0 and not session.model.state.players.has(peer_id) and not OS.is_process_running(child_pid):
		check(saw_velocity,"host computed actual remote movement velocity")
		check(saw_crouch,"host retained remote stationary crouch")
		check(saw_timeout,"host timed out stale crouch and movement")
		for action in ["drink","eat","heal","pickup","equip","interact"]:
			check(seen_actions.has(action),"host recorded successful action " + action)
		check(saw_progress and last_seq == 7,"host action timer progresses with exactly seven successful events")
		check(not session.model._inputs.has(peer_id),"disconnected player's animation input removed")
		var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path())) if FileAccess.file_exists(result_path()) else null
		check(result is Dictionary and int(result.get("failures",-1)) == 0,"all independent client assertions passed")
		if result is Dictionary: print("DUCKOV_ANIMATION_NETWORK_CLIENT ",result)
		finish()

func result_path() -> String: return "user://duckov_animation_network_%d.json" % port

func write_result() -> void:
	var file := FileAccess.open(result_path(),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures})); file.close()

func finish() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	if not client: DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path()))
	session.offline()
	print("DUCKOV_ANIMATION_NETWORK_HOST ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
