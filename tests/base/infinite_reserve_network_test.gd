extends SceneTree
const Session = preload("res://app/network/session.gd")
var session
var client := false
var elapsed := 0.0
var child_pid := -1
var phase := 0
var remote_id := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	client = "--reserve-client" in OS.get_cmdline_user_args()
	call_deferred("start")
func start() -> void:
	session = Session.new(); root.add_child(session)
	if client:
		check(session.join("127.0.0.1",29795) == OK,"join starts")
	else:
		check(session.host(29795) == OK,"host starts")
		session.send("set_infinite_reserve",{"enabled":true})
		child_pid = OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/infinite_reserve_network_test.gd","--","--reserve-client"])
		check(child_pid > 0,"client process starts")
func _process(delta: float) -> bool:
	if session == null: return false
	elapsed += delta
	if elapsed > 12:
		check(false,"network timeout"); finish(); return false
	if client:
		if session.local_id <= 1 or not session.model.state.players.has(session.local_id): return false
		var p: Dictionary = session.model.state.players[session.local_id]
		if phase == 0 and session.model._count(p.bag,"ammo") == 0:
			check(session.model.state.get("infinite_reserve",false),"late join receives host setting")
			session.send("set_infinite_reserve",{"enabled":false})
			session.send("reload")
			phase = 1
		elif phase == 1 and p.ammo == 30:
			session.send("fire"); phase = 2
	else:
		for id in session.model.state.players:
			if id != 1 and remote_id == 0:
				remote_id = id
				session.model._consume(session.model.state.players[id].bag,"ammo",60)
		if remote_id == 0: return false
		var p: Dictionary = session.model.state.players[remote_id]
		if p.shots > 0:
			check(session.model.state.infinite_reserve,"client RPC cannot disable setting")
			check(p.ammo == 29 and session.model._count(p.bag,"ammo") == 0,"remote empty reserve reload and finite magazine confirmed by host")
			finish()
	return false
func finish() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	session.offline()
	print("INFINITE_RESERVE_NETWORK failures=",failures)
	quit(0 if failures == 0 else 1)
