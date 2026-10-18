extends SceneTree
## Controller test double only. Does not prove Steam connectivity or account access.
const Lobby = preload("res://app/network/steam_lobby.gd")
var failures := 0
var checks := 0
var peers_created := 0
var received_hosts: Array[bool] = []

class FakeSteam extends RefCounted:
	signal lobby_created(result, id)
	signal lobby_joined(id, permissions, locked, response)
	signal lobby_data_update(success, id, member)
	signal lobby_chat_update(id, changed_id, by, state)
	signal join_requested(id, friend_id)
	signal lobby_kicked(id, admin, disconnected)
	var running := true
	var online := true
	var user := 111
	var owner := 111
	var data: Dictionary = {}
	var left: Array[int] = []
	var members: Array[int] = [111, 222]
	var joinable := true
	var limit := 0
	var lobby_type := -1
	var initialized := 0
	var init_status := 0
	func isSteamRunning(): return running
	func loggedOn(): return online
	func steamInitEx(_id, _embedded):
		initialized += 1
		return {"status": init_status, "verbal": "fixture"}
	func getSteamID(): return user
	func getPersonaName(): return "Fixture"
	func initRelayNetworkAccess(): pass
	func run_callbacks(): pass
	func createLobby(kind, count):
		lobby_type = kind
		limit = count
	func joinLobby(_id): pass
	func leaveLobby(id): left.append(id)
	func getLobbyOwner(_id): return owner
	func getLobbyData(_id, key): return data.get(key, "")
	func setLobbyData(_id, key, value):
		data[key] = value
		return true
	func setLobbyMemberLimit(_id, count): limit = count
	func setLobbyJoinable(_id, value): joinable = value
	func getNumLobbyMembers(_id): return members.size()
	func getLobbyMemberByIndex(_id, index): return members[index]
	func requestLobbyData(_id): return true
	func getLaunchCommandLine(): return ""
	func activateGameOverlayInviteDialog(_id): pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func fixture():
	var lobby = Lobby.new()
	lobby.api = FakeSteam.new()
	lobby.peer_factory = func(_hosting, _owner):
		peers_created += 1
		return {"peer": OfflineMultiplayerPeer.new(), "error": OK}
	lobby.peer_ready.connect(func(_peer, hosting): received_hosts.append(hosting))
	root.add_child(lobby)
	return lobby

func prepare_join(lobby) -> void:
	lobby.api.owner = 222
	lobby.api.data = {"game": Lobby.GAME_ID, "protocol": Lobby.PROTOCOL,
		"build": lobby.build_id, "owner": "222", "phase": "lobby"}

func run() -> void:
	var lobby = fixture()
	lobby.api.running = false
	check(lobby.create_room() == ERR_UNAVAILABLE and not lobby.is_busy(), "missing Steam client never fakes a successful lobby")
	lobby.api.running = true
	lobby.api.init_status = 2
	check(lobby.initialize() == ERR_CANT_CONNECT and not lobby.initialized, "SDK init failure remains retryable and reports failure")
	lobby.api.init_status = 0
	check(lobby.create_room() == OK and lobby.is_busy(), "host waits for asynchronous lobby creation")
	check(lobby.create_room() == ERR_BUSY, "duplicate host requests are rejected")
	lobby.api.lobby_created.emit(1, 99)
	check(lobby.lobby_id == 99 and received_hosts.back(), "successful lobby hands a host peer to Session")
	check(lobby.api.limit == 5 and lobby.api.lobby_type == 1, "lobby is friends-only and includes at most five members")
	check(lobby.api.data.game == Lobby.GAME_ID and lobby.api.data.build == lobby.build_id, "host publishes game and build filters")
	check(lobby.member_allowed(222) and not lobby.member_allowed(333), "transport admission requires a real lobby membership")
	lobby.api.lobby_created.emit(1, 99)
	check(lobby.api.left.is_empty(), "duplicate create callback cannot leave the active room")
	lobby.set_phase("raid")
	check(not lobby.api.joinable and lobby.api.data.phase == "raid", "starting closes lobby admission")
	lobby.set_phase("lobby")
	check(lobby.api.joinable, "returning to lobby reopens admission")
	lobby.close()
	check(lobby.lobby_id == 0 and lobby.api.left.has(99), "leaving clears local lobby and calls Steam leave")
	lobby.create_room()
	lobby.close()
	check(not lobby.is_busy(), "cancelled create releases UI without waiting for the SDK callback")
	check(lobby.create_room() == ERR_BUSY, "a second native create waits for the unidentifiable old callback")
	prepare_join(lobby)
	check(lobby.join_room(201) == OK, "cancelled create allows joining another room before callback drainage")
	lobby.api.lobby_joined.emit(201, 0, false, 1)
	check(lobby.lobby_id == 201, "join callback is handled while a cancelled create is draining")
	lobby.api.lobby_created.emit(1, 100)
	check(lobby.lobby_id == 201 and lobby.api.left.has(100) and not lobby.is_busy(), "cancelled create drains without replacing or closing the joined room")
	lobby.close()
	lobby.create_room()
	lobby._deadline = Time.get_ticks_msec() - 1
	lobby._process(0.0)
	check(not lobby.is_busy(), "create timeout releases the UI even when the native callback never arrives")
	lobby.api.lobby_created.emit(1, 101)
	check(lobby.lobby_id == 0 and lobby.api.left.has(101), "timed-out create leaves its late lobby without adopting it")
	check(lobby.join_room(0) == ERR_INVALID_PARAMETER, "invalid lobby code is rejected before an SDK call")
	prepare_join(lobby)
	lobby.join_room(200)
	lobby.api.lobby_joined.emit(200, 0, false, 1)
	check(lobby.owner_id == 222 and not received_hosts.back(), "client connects to the validated original Steam owner")
	lobby.api.lobby_chat_update.emit(200, 222, 222, 2)
	check(lobby.lobby_id == 0, "original owner leaving ends the room instead of migrating authority")
	for pair in [["build", "old"], ["protocol", "other"], ["game", "spacewar_other_game"], ["phase", "raid"], ["owner", "999"]]:
		prepare_join(lobby)
		lobby.api.data[pair[0]] = pair[1]
		var before := peers_created
		lobby.join_room(300)
		lobby.api.lobby_joined.emit(300, 0, false, 1)
		check(peers_created == before and lobby.lobby_id == 0, "reject incompatible lobby before making a peer: " + pair[0])
	lobby.join_room(400)
	lobby.close()
	lobby.api.lobby_joined.emit(400, 0, false, 1)
	check(lobby.lobby_id == 0 and lobby.api.left.has(400), "cancelled join cannot be resurrected by a late callback")
	prepare_join(lobby)
	lobby.join_room(500)
	lobby.api.lobby_joined.emit(500, 0, false, 4)
	check(lobby.lobby_id == 0 and not lobby.is_busy(), "Steam full/rejected join clears pending state")
	lobby.join_room(600)
	lobby._deadline = Time.get_ticks_msec() - 1
	lobby._process(0.0)
	check(lobby.lobby_id == 0 and not lobby.is_busy(), "join timeout closes pending requests")
	lobby.queue_free()
	await process_frame
	print("STEAM_LOBBY_TEST ", checks, " checks; ", failures, " failures (controller doubles only)")
	quit(1 if failures else 0)
