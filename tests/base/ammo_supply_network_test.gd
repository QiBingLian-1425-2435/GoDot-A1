extends SceneTree
const Session = preload("res://app/network/session.gd")
var session
var client := false
var elapsed := 0.0
var joined_at := -1.0
var child_pid := -1
var phase := 0
var remote_id := 0
var failures := 0
var port := 29794
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	client = "--ammo-client" in OS.get_cmdline_user_args()
	call_deferred("start")
func start() -> void:
	session = Session.new(); root.add_child(session)
	if client:
		check(session.join("127.0.0.1",port) == OK,"client starts")
	else:
		check(session.host(port) == OK,"host starts")
		session.model.stations = [{"kind":"ammo_supply","pos":Vector2(7.2,2.7)}]
		child_pid = OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/base/ammo_supply_network_test.gd","--","--ammo-client"])
		check(child_pid > 0,"real client starts")
func _process(delta: float) -> bool:
	if session == null: return false
	elapsed += delta
	if elapsed > 12:
		check(false,"network resupply timed out"); finish(); return false
	if client:
		if session.local_id <= 1 or not session.model.state.players.has(session.local_id): return false
		var p: Dictionary = session.model.state.players[session.local_id]
		if phase == 0:
			session.send("resupply_ammo"); phase = 1
		elif phase == 1 and p.pos.distance_to(Vector2(7.2,2.7)) < 0.1:
			session.send("resupply_ammo"); phase = 2
		elif phase == 2 and session.model._count(p.bag,"ammo") == 120:
			session.send("resupply_ammo"); session.send("reload"); phase = 3
	else:
		for id in session.model.state.players:
			if id != 1 and remote_id == 0: remote_id = id; joined_at = elapsed
		if remote_id == 0: return false
		var p: Dictionary = session.model.state.players[remote_id]
		if phase == 0 and elapsed - joined_at > 1.0:
			check(session.model._count(p.bag,"ammo") == 60,"distant RPC cannot grant ammo")
			p.pos = Vector2(7.2,2.7); phase = 1
		elif phase == 1 and p.ammo == 30:
			check(session.model._count(p.bag,"ammo") == 110,"remote refill and reload confirmed by host without repeat overflow")
			check(p.credits == 500,"remote refill is free")
			check(session.model._count(session.model.state.players[1].bag,"ammo") == 60,"host inventory untouched")
			finish()
	return false
func finish() -> void:
	if child_pid > 0 and OS.is_process_running(child_pid): OS.kill(child_pid)
	session.offline()
	print("AMMO_SUPPLY_NETWORK failures=",failures)
	quit(0 if failures == 0 else 1)
