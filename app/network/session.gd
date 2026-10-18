extends Node
## Keep this node at the identical /root/.../Session path on every peer.

signal state_changed()
signal notice(text: String)

const Model = preload("res://features/match/match_model.gd")
const DEFAULT_PORT := 24567
const NAMES := ["阿烬", "薇拉", "诺恩", "罗温", "艾琳"]

var model = Model.new()
var local_id: int = 1
var mode: String = "offline"
var connection_status: String = "离线试玩 · 同行伙伴待命"
var _peer: MultiplayerPeer
var steam
var preferred_transport := "steam"
var transport := "offline"
var _connect_deadline := 0
var _snapshot_clock := 0.0
var _last_event_id := 0
var _last_phase := "lobby"
var _rate_limits: Dictionary = {}
var _snapshot_serial := 0
var _received_snapshot_serial := -1

func _init() -> void:
	name = "Session"
	model.add_player(1, NAMES[0])

func _ready() -> void:
	name = "Session"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	steam = preload("res://app/network/steam_lobby.gd").new()
	steam.name = "SteamLobby"
	add_child(steam)
	steam.peer_ready.connect(_on_steam_peer)
	steam.failed.connect(_on_steam_failure)
	steam.changed.connect(func(): state_changed.emit())
	steam.join_requested.connect(_on_steam_invite)
	if DisplayServer.get_name() != "headless":
		steam.prepare_if_running.call_deferred()

func host_steam() -> Error:
	if steam.is_busy():
		return ERR_BUSY
	offline()
	preferred_transport = "steam"
	var error: Error = steam.create_room()
	connection_status = steam.status
	_emit_state()
	return error

func join_steam(code: String) -> Error:
	code = code.strip_edges()
	if not code.is_valid_int() or code.length() > 20 or int(code) <= 0:
		connection_status = "请输入有效的 Steam 房间号，或接受好友邀请"
		notice.emit(connection_status)
		return ERR_INVALID_PARAMETER
	if steam.is_busy():
		return ERR_BUSY
	offline()
	preferred_transport = "steam"
	var error: Error = steam.join_room(int(code))
	connection_status = steam.status
	_emit_state()
	return error

func network_status() -> Dictionary:
	return {"transport": preferred_transport, "active": transport,
		"lobby_id": str(steam.lobby_id) if steam != null and steam.lobby_id != 0 else "",
		"busy": steam != null and steam.is_busy(),
		"steam_status": steam.status if steam != null else "",
		"app_id": steam.app_id if steam != null else 480}

func _on_steam_peer(peer: MultiplayerPeer, hosting: bool) -> void:
	_peer = peer
	transport = "steam"
	preferred_transport = "steam"
	mode = "host" if hosting else "client"
	local_id = 1 if hosting else 0
	connection_status = steam.status
	if hosting:
		model.state.players[1].name = str(steam.api.getPersonaName()).left(20)
	else:
		model.state.players.clear()
		_received_snapshot_serial = -1
		_connect_deadline = Time.get_ticks_msec() + 25000
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	_emit_state()

func _on_steam_failure(message: String) -> void:
	offline()
	connection_status = message
	notice.emit(message)
	_emit_state()

func _on_steam_invite(lobby: int) -> void:
	if model.state.phase != "lobby" or mode != "offline" or steam.is_busy():
		notice.emit("请先离开当前房间，再接受 Steam 邀请")
		return
	join_steam(str(lobby))

func host(port: int = DEFAULT_PORT) -> Error:
	offline()
	if port < 1024 or port > 65535:
		connection_status = "端口需要在 1024–65535 之间"
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.call("create_server", port, 4)
	if error != OK:
		connection_status = "建房失败：端口可能被占用（%s）" % error_string(error)
		notice.emit(connection_status)
		return error
	multiplayer.multiplayer_peer = _peer
	# All gameplay is host-authoritative; no peer-to-peer relaying is needed.
	# Disabling relay also avoids transport sends to other peers exiting together.
	multiplayer.server_relay = false
	mode = "host"
	transport = "enet"
	local_id = 1
	connection_status = "房间已开放 · UDP %d · 2–5 人" % port
	_emit_state()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	offline()
	address = address.strip_edges().left(253)
	if address.is_empty() or port < 1024 or port > 65535:
		connection_status = "请输入房主的局域网 IP 与有效端口"
		return ERR_INVALID_PARAMETER
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.call("create_client", address, port)
	if error != OK:
		connection_status = "连接失败：%s" % error_string(error)
		notice.emit(connection_status)
		return error
	model.state.players.clear()
	_last_event_id = 0
	_received_snapshot_serial = -1
	multiplayer.multiplayer_peer = _peer
	mode = "client"
	transport = "enet"
	_connect_deadline = Time.get_ticks_msec() + 25000
	local_id = 0
	connection_status = "正在连接 %s:%d…" % [address, port]
	_emit_state()
	return OK

func offline() -> void:
	if is_inside_tree():
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _peer != null:
		_peer.close()
		_peer = null
	if steam != null:
		steam.close()
	transport = "offline"
	_connect_deadline = 0
	mode = "offline"
	local_id = 1
	connection_status = "离线试玩 · 同行伙伴待命"
	model.state.players.clear()
	model.state.events.clear()
	model.state.total_banked = 0
	model.state.round = 0
	model.reset_lobby()
	model.add_player(1, NAMES[0])
	_rate_limits.clear()
	_snapshot_clock = 0.0
	_snapshot_serial = 0
	_received_snapshot_serial = -1
	_last_event_id = 0
	_last_phase = "lobby"
	_emit_state()

func start_solo() -> void:
	if mode != "offline" or (steam != null and (steam.is_busy() or steam.lobby_id != 0)):
		offline()
	if model.state.phase == "results":
		model.reset_lobby()
	if model.state.phase != "lobby":
		return
	if not model.state.players.has(2):
		model.add_player(2, "薇拉", true)
	model.start_round()
	_emit_state()

func send(action: String, payload: Dictionary = {}) -> void:
	if mode == "client":
		if local_id == 0 or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		if action == "move":
			var direction: Variant = payload.get("direction", Vector2.ZERO)
			if direction is Vector2 and direction.is_finite():
				_movement.rpc_id(1, direction.limit_length(1.0), bool(payload.get("interact", false)), int(model.state.round))
		else:
			_intent.rpc_id(1, action, _clean_payload(action, payload), int(model.state.round))
	else:
		model.command(local_id, action, _clean_payload(action, payload))
		if action != "move":
			_emit_state()

func _physics_process(delta: float) -> void:
	if mode == "client":
		if _connect_deadline != 0 and Time.get_ticks_msec() > _connect_deadline:
			_on_steam_failure("连接房主游戏传输超时，请检查 Steam/网络及测试包版本" if transport == "steam" else "连接超时，请检查 IP、UDP 24567 和房主在线")
		return
	if transport == "steam":
		steam.set_phase(str(model.state.phase))
	model.tick(delta)
	_snapshot_clock += delta
	var phase_changed: bool = _last_phase != str(model.state.phase)
	if _snapshot_clock >= 0.0833 or phase_changed:
		_snapshot_clock = 0.0
		_last_phase = str(model.state.phase)
		_emit_state()
		if mode == "host" and _peer != null and multiplayer.has_multiplayer_peer():
			_broadcast_snapshot(phase_changed)

func _clean_payload(action: String, payload: Dictionary) -> Dictionary:
	match action:
		"move":
			var direction: Variant = payload.get("direction", Vector2.ZERO)
			if direction is Vector2 and direction.is_finite():
				return {"direction": direction.limit_length(1.0), "interact": bool(payload.get("interact", false))}
		"drop":
			if payload.get("item_id") is int:
				return {"item_id": payload.item_id}
		"possession_request":
			if payload.get("target") is int:
				return {"target": payload.target}
	return {}

func _allowed_sender(sender: int, action: String, round_number: int) -> bool:
	if mode != "host" or sender <= 1 or not model.state.players.has(sender):
		return false
	if round_number != int(model.state.round):
		return false
	if not action in ["move", "pickup", "drop", "interact", "possession_request", "possession_accept", "possession_decline", "detach"]:
		return false
	var second := int(Time.get_ticks_msec() / 1000)
	var counter: Dictionary = _rate_limits.get(sender, {"second": second, "count": 0})
	if counter.second != second:
		counter = {"second": second, "count": 0}
	counter.count += 1
	_rate_limits[sender] = counter
	return counter.count <= 100

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _movement(direction: Vector2, interact: bool, round_number: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _allowed_sender(sender, "move", round_number) or not direction.is_finite():
		return
	model.command(sender, "move", {"direction": direction.limit_length(1.0), "interact": interact})

@rpc("any_peer", "call_remote", "reliable", 0)
func _intent(action: String, payload: Dictionary, round_number: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _allowed_sender(sender, action, round_number):
		return
	model.command(sender, action, _clean_payload(action, payload))
	_emit_state()

@rpc("authority", "call_remote", "reliable", 2)
func _snapshot(snapshot: Dictionary) -> void:
	_receive_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable", 0)
func _snapshot_reliable(snapshot: Dictionary) -> void:
	_receive_snapshot(snapshot)

func _receive_snapshot(snapshot: Dictionary) -> void:
	if mode != "client" or multiplayer.get_remote_sender_id() != 1:
		return
	var serial := int(snapshot.get("snapshot_seq", 0))
	if serial <= _received_snapshot_serial:
		return
	_received_snapshot_serial = serial
	model.state = snapshot
	_emit_state()

func _stamp_snapshot() -> void:
	_snapshot_serial += 1
	model.state.snapshot_seq = _snapshot_serial

func _broadcast_snapshot(reliable_control: bool = false) -> void:
	if mode != "host" or _peer == null:
		return
	_stamp_snapshot()
	for peer_id in multiplayer.get_peers():
		var transport_peer = _peer.call("get_peer", peer_id)
		var connected_state := ENetPacketPeer.STATE_CONNECTED if transport == "enet" else ClassDB.class_get_integer_constant("SteamPacketPeer", "STATE_CONNECTED")
		if transport_peer == null or transport_peer.get_state() != connected_state:
			continue
		if reliable_control:
			_snapshot_reliable.rpc_id(peer_id, model.state)
		else:
			_snapshot.rpc_id(peer_id, model.state)

@rpc("authority", "call_remote", "reliable", 0)
func _refused(message: String) -> void:
	if mode == "client" and multiplayer.get_remote_sender_id() == 1:
		connection_status = message
		notice.emit(message)

func _on_peer_connected(peer_id: int) -> void:
	if mode != "host":
		return
	if transport == "steam" and not steam.member_allowed(int(_peer.call("get_steam_id_for_peer_id", peer_id))):
		_peer.disconnect_peer(peer_id)
		return
	if model.state.phase != "lobby" or model.state.players.size() >= 5:
		_refused.rpc_id(peer_id, "本局已经开始或房间已满，请等待房主下一局")
		await get_tree().create_timer(0.15).timeout
		if mode == "host" and _peer != null:
			_peer.disconnect_peer(peer_id)
		return
	var display_name: String = NAMES[mini(model.state.players.size(), 4)]
	if transport == "steam":
		display_name = str(steam.api.getFriendPersonaName(int(_peer.call("get_steam_id_for_peer_id", peer_id)))).left(20)
	model.add_player(peer_id, display_name)
	_broadcast_snapshot(true)
	_emit_state()

func _on_peer_disconnected(peer_id: int) -> void:
	if mode == "host":
		model.remove_player(peer_id)
		_rate_limits.erase(peer_id)
		_emit_state()
		# Publish next physics tick, after all pending disconnects have been polled.
		_snapshot_clock = 0.1

func _on_connected() -> void:
	if mode != "client":
		return
	local_id = multiplayer.get_unique_id()
	_connect_deadline = 0
	connection_status = "Steam 传输已连接 · 等待房主开始" if transport == "steam" else "已加入房间 · 等待房主开始"
	if transport == "steam":
		print("STEAM_TRANSPORT_CONNECTED peer_id=", local_id)
	_emit_state()

func _on_connection_failed() -> void:
	if mode != "client":
		return
	var was_steam := transport == "steam"
	offline()
	connection_status = "Steam 传输连接失败，请检查房主在线、账号及相同测试包" if was_steam else "无法连接房间，请检查 IP、相同版本及 UDP 24567 防火墙"
	notice.emit(connection_status)
	_emit_state()

func _on_server_disconnected() -> void:
	if mode != "client":
		return
	var was_rejected := connection_status.contains("已经开始")
	offline()
	connection_status = "本局已经开始或房间已满，请等待下一局" if was_rejected else "房主已关闭房间，当前联机已结束"
	notice.emit(connection_status)
	_emit_state()

func _emit_state() -> void:
	for event in model.state.events:
		if int(event.id) > _last_event_id:
			_last_event_id = int(event.id)
			if int(event.get("player_id", 0)) == 0 or int(event.player_id) == local_id:
				notice.emit(str(event.text))
	state_changed.emit()
