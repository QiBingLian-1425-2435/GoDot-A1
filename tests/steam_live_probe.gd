extends SceneTree
## Real Steam SDK + lobby + native host socket, using the currently logged-in account.
## This is NOT a second-account/remote-client test.
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	game = load("res://app/main.tscn").instantiate()
	root.add_child(game)
	var session = game.session
	var error: int = session.host_steam()
	if error != OK:
		print("STEAM_LIVE_UNAVAILABLE ", session.connection_status)
		game.queue_free()
		await process_frame
		quit(2)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while session.mode != "host" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(session.mode == "host", "real Steam lobby creation reaches native host transport")
	if session.mode == "host":
		check(session.transport == "steam" and session._peer.is_class("SteamMultiplayerPeer"), "current Session runs the actual native Steam peer")
		check(session._peer.get_unique_id() == 1, "native Steam host is authority peer 1")
		var lobby = session.steam
		check(lobby.lobby_id != 0 and lobby.owner_id == int(lobby.api.getSteamID()), "real lobby owner matches the logged-in account")
		check(lobby.api.getLobbyData(lobby.lobby_id, "game") == lobby.GAME_ID and lobby.api.getLobbyData(lobby.lobby_id, "build") == lobby.build_id, "real lobby publishes the A1 game and exact build metadata")
		check(lobby.member_allowed(int(lobby.api.getSteamID())), "actual lobby membership recognizes the account")
		lobby.set_phase("raid")
		check(lobby.api.getLobbyData(lobby.lobby_id, "phase") == "raid", "real lobby metadata follows in-progress phase")
		lobby.set_phase("lobby")
		check(lobby.api.getLobbyData(lobby.lobby_id, "phase") == "lobby", "real lobby can return to waiting phase")
		session.offline()
		check(session.mode == "offline" and lobby.lobby_id == 0 and session._peer == null, "leaving closes the real Steam peer and lobby")
	game.queue_free()
	await process_frame
	print("STEAM_LIVE_PROBE ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
