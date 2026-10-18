extends SceneTree

const Session = preload("res://app/network/session.gd")
const Model = preload("res://features/match/match_model.gd")
var session: Node
var game
var role := "host"
var elapsed := 0.0
var raid_elapsed := 0.0
var staged := false
var client_sent := false
var movement_checked := false
var host_extracted_checked := false
var results_elapsed := 0.0
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "client":
			role = "client"
	call_deferred("_setup")

func _setup() -> void:
	game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	session = game.session
	if role == "host":
		assert(session.host(24569) == OK)
		print("NETWORK_READY 24569")
	else:
		assert(session.join("127.0.0.1", 24569) == OK)

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(role + " FAIL: " + message)
	else:
		print(role + " PASS: " + message)

func _process(delta: float) -> bool:
	if session == null:
		return false
	elapsed += delta
	if elapsed > 20.0:
		push_error(role + " NETWORK TIMEOUT")
		quit(1)
		return false
	var s: Dictionary = session.model.state
	if role == "host" and s.phase == "lobby" and s.players.size() == 2 and not staged:
		staged = true
		session.send("start")
		session.model._monster_pause = 9999.0
		for p in s.players.values():
			p.pos = Vector2(-8, 3.8)
		session.send("pickup")
		print("host: raid started with actual remote peer")
	if s.phase == "raid":
		raid_elapsed += delta
		if role == "client":
			if not client_sent:
				client_sent = true
				session.send("pickup")
				print("client: pickup command sent via reliable RPC")
			if raid_elapsed < 1.0:
				session.send("move", {"direction": Vector2.RIGHT})
			else:
				session.send("move", {"direction": Vector2.ZERO})
			if s.players.has(1) and s.players[1].status == "extracted" and not host_extracted_checked:
				host_extracted_checked = true
				verify(s.players[session.local_id].status == "alive", "client continues after host character extraction")
		else:
			var peer: Dictionary = {}
			for p in s.players.values():
				if p.id != 1:
					peer = p
			if raid_elapsed > 1.6 and not movement_checked:
				movement_checked = true
				verify(peer.pos.x > -7.0, "remote movement reaches authoritative host")
				verify(peer.bag.is_empty() and s.players[1].bag.size() == 1, "contested pickup remains unique across RPC")
				s.players[1].pos = Model.EXTRACT_POSITION
			if s.players[1].status == "extracted" and not host_extracted_checked:
				host_extracted_checked = true
				verify(peer.status == "alive" and s.phase == "raid", "host serves an active raid after own extraction")
				peer.pos = Model.EXTRACT_POSITION
	if s.phase == "results":
		results_elapsed += delta
		if results_elapsed > (0.6 if role == "host" else 0.15):
			verify(s.total_banked == 45 and s.players[1].result_value == 45, "final replicated reward is exactly 45")
			verify(host_extracted_checked, "individual extraction observed before team results")
			print("NETWORK %s COMPLETE" % role.to_upper())
			quit(1 if failed else 0)
	return false
