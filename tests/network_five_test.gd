extends SceneTree
## Launch one process with -- host, followed by four processes with -- client.
## Real ENet transport; accelerated test setup, ordinary four-second extraction.

const Session = preload("res://app/network/session.gd")
const Model = preload("res://features/match/match_model.gd")
const EXPECTED_VALUE := 755
var session: Node
var game
var role := "host"
var elapsed := 0.0
var lobby_elapsed := 0.0
var round_elapsed := 0.0
var results_elapsed := 0.0
var observed_round := 0
var pickup_sent_round := 0
var extracted_host_round := 0
var verified_rounds: Dictionary = {}
var failures := 0

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
	var error: Error = session.host(24570) if role == "host" else session.join("127.0.0.1", 24570)
	verify(error == OK, "transport created")
	if role == "host" and error == OK:
		print("NETWORK_READY 24570")

func verify(condition: bool, message: String) -> void:
	if condition:
		print("%s %d PASS: %s" % [role, session.local_id if session != null else 0, message])
	else:
		failures += 1
		push_error("%s FAIL: %s" % [role, message])

func _start_round() -> void:
	session.send("start")
	var s: Dictionary = session.model.state
	verify(s.players.size() == 5, "five players retained in new round %d" % s.round)
	verify(s.corpses.is_empty() and s.loot.size() == 12, "round %d has fresh containers and twelve loot instances" % s.round)
	session.model._monster_pause = 9999.0
	var ids: Array = s.players.keys()
	ids.sort()
	for slot in ids.size():
		var player: Dictionary = s.players[ids[slot]]
		verify(player.bag.is_empty() and player.result_value == 0 and player.status == "alive", "round %d resets player %d transient state" % [s.round, player.id])
		player.pos = s.loot[slot].pos
	session.send("pickup")

func _process(delta: float) -> bool:
	if session == null:
		return false
	elapsed += delta
	if elapsed > 35.0:
		push_error("%s five-process test timed out" % role)
		quit(1)
		return false
	var s: Dictionary = session.model.state
	if role == "host" and s.phase == "lobby" and s.players.size() == 5:
		lobby_elapsed += delta
		if lobby_elapsed > 0.4:
			verify(session.multiplayer.get_peers().size() == 4, "server admits exactly four remote clients plus the host")
			_start_round()
	if s.phase == "raid":
		if observed_round != int(s.round):
			observed_round = int(s.round)
			round_elapsed = 0.0
			results_elapsed = 0.0
			verify(s.players.size() == 5, "all five players visible in raid snapshot %d" % observed_round)
			if role == "client":
				verify(session.local_id > 1 and s.players.has(session.local_id), "snapshot includes this real peer identity")
		round_elapsed += delta
		if role == "client":
			if pickup_sent_round != int(s.round):
				pickup_sent_round = int(s.round)
				session.send("pickup")
			if s.players[1].status == "extracted" and s.players[session.local_id].status == "alive":
				extracted_host_round = int(s.round)
		else:
			if round_elapsed > 0.7 and s.players[1].pos != Model.EXTRACT_POSITION:
				var count := 0
				var ids: Dictionary = {}
				for player in s.players.values():
					count += player.bag.size()
					for item in player.bag:
						ids[item.id] = true
				verify(count == 5 and ids.size() == 5, "five independent RPC pickups own five unique items in round %d" % s.round)
				s.players[1].pos = Model.EXTRACT_POSITION
			if round_elapsed > 1.4:
				for player in s.players.values():
					if player.id != 1:
						player.pos = Model.EXTRACT_POSITION
	if s.phase == "results":
		results_elapsed += delta
		if not verified_rounds.has(s.round):
			verified_rounds[s.round] = true
			verify(s.round_value == EXPECTED_VALUE and s.total_banked == EXPECTED_VALUE * int(s.round), "round %d and cumulative rewards match on this peer" % s.round)
			var extracted := 0
			for player in s.players.values():
				if player.status == "extracted" and player.bag.size() == 1:
					extracted += 1
			verify(extracted == 5, "all five immutable extraction results arrive together")
			if role == "client":
				verify(extracted_host_round == int(s.round), "client continued while host was already extracted")
		if int(s.round) < 3:
			if role == "host" and results_elapsed > 0.5:
				_start_round()
		elif results_elapsed > (1.0 if role == "host" else 0.2):
			verify(verified_rounds.size() == 3, "three consecutive real-network rounds completed")
			print("FIVE PROCESS %s %d COMPLETE: %d failures" % [role.to_upper(), session.local_id, failures])
			quit(1 if failures > 0 else 0)
	return false
