extends Node
## Steam lobby lifecycle only. Match rules and RPC identity validation stay in Session.
signal peer_ready(peer: MultiplayerPeer, hosting: bool)
signal failed(message: String)
signal changed()
signal join_requested(lobby: int)

const GAME_ID := "godot_a1_lantern_below"
const PROTOCOL := "a1_rpc_steam_v1"
const TIMEOUT_MS := 25000
var app_id := 480
var build_id := "a1_steam_dev_20261018_01"
var api: Object
var peer_factory: Callable # Optional controller-test seam; production uses the native class.
var initialized := false
var lobby_id := 0
var owner_id := 0
var hosting := false
var status := "Steam 测试模式 · App ID 480"
var _creating := false
var _cancel_create := false
var _joining := 0
var _validating := false
var _deadline := 0
var _last_phase := ""
var _signals_connected := false

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("res://app/network/steam_config.cfg") == OK:
		app_id = int(config.get_value("steam", "app_id", 480))
		build_id = str(config.get_value("steam", "build_id", build_id))

func is_busy() -> bool:
	return (_creating and not _cancel_create) or _joining != 0 or _validating

func initialize() -> Error:
	if initialized:
		if api.loggedOn():
			return OK
		status = "Steam 已离线，请恢复 Steam 登录后再试"
		changed.emit()
		return ERR_UNAVAILABLE
	if api == null and Engine.has_singleton("Steam"):
		api = Engine.get_singleton("Steam")
	if api == null or (not peer_factory.is_valid() and not ClassDB.class_exists("SteamMultiplayerPeer")):
		status = "缺少 GodotSteam 4.23.1 扩展，请使用完整测试包"
		changed.emit()
		return ERR_UNAVAILABLE
	if not api.isSteamRunning():
		status = "请先打开 Steam 并登录，再创建或加入房间"
		changed.emit()
		return ERR_UNAVAILABLE
	var result: Dictionary = api.steamInitEx(app_id, false)
	if int(result.get("status", -1)) != 0:
		status = "Steam 初始化失败：" + str(result.get("verbal", result))
		changed.emit()
		return ERR_CANT_CONNECT
	if not api.loggedOn() or int(api.getSteamID()) == 0:
		status = "Steam 尚未登录，请检查客户端账号和网络"
		changed.emit()
		return ERR_UNAUTHORIZED
	initialized = true
	api.initRelayNetworkAccess()
	_connect_signals()
	status = "Steam 已就绪 · %s · 测试 App ID %d" % [api.getPersonaName(), app_id]
	print("STEAM_READY app_id=", app_id, " build=", build_id)
	changed.emit()
	return OK

func prepare_if_running() -> void:
	if Engine.has_singleton("Steam") and Engine.get_singleton("Steam").isSteamRunning():
		if initialize() == OK:
			_check_launch_invite()

func _connect_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	api.connect("lobby_created", _on_created)
	api.connect("lobby_joined", _on_joined)
	api.connect("lobby_data_update", _on_data)
	api.connect("lobby_chat_update", _on_member_changed)
	api.connect("join_requested", _on_invite)
	api.connect("lobby_kicked", _on_kicked)

func create_room() -> Error:
	if is_busy() or lobby_id != 0:
		return ERR_BUSY
	if _creating:
		# Steam's create callback has no request ID. Drain it before another create,
		# but keep cancelled requests from locking LAN, solo, or joining another room.
		status = "上次建房仍在取消，请稍后重试；若持续无响应，请重启游戏"
		changed.emit()
		return ERR_BUSY
	var error := initialize()
	if error != OK:
		return error
	_creating = true
	_cancel_create = false
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	status = "正在创建 Steam 好友房间…"
	api.createLobby(1, 5) # Friends-only; never publish into Spacewar's public lobby list.
	changed.emit()
	return OK

func join_room(id: int) -> Error:
	if id <= 0:
		status = "请输入有效的 Steam 房间号"
		changed.emit()
		return ERR_INVALID_PARAMETER
	if is_busy() or lobby_id != 0:
		return ERR_BUSY
	var error := initialize()
	if error != OK:
		return error
	_joining = id
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	status = "正在加入 Steam 房间…"
	api.joinLobby(id)
	changed.emit()
	return OK

func _make_peer(server: bool, steam_owner: int) -> Dictionary:
	if peer_factory.is_valid():
		return peer_factory.call(server, steam_owner)
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	# Use a host/client star, rather than connect_to_lobby's all-member mesh.
	peer.set_server_relay(false)
	var error: int = peer.create_host(0) if server else peer.create_client(steam_owner, 0)
	if error != OK:
		peer.close()
	return {"peer": peer, "error": error}

func _on_created(result: int, id: int) -> void:
	if hosting and lobby_id == id and id != 0:
		return
	if not _creating or _cancel_create:
		if result == 1 and id != 0:
			api.leaveLobby(id)
		_creating = false
		_cancel_create = false
		changed.emit()
		return
	_creating = false
	if result != 1:
		_fail("Steam 创建房间失败（%d），请检查账号与网络" % result)
		return
	lobby_id = id
	owner_id = int(api.getSteamID())
	hosting = true
	var created := _make_peer(true, owner_id)
	if int(created.error) != OK:
		_fail("Steam 游戏传输创建失败：" + error_string(int(created.error)))
		return
	var metadata := {"game": GAME_ID, "protocol": PROTOCOL, "build": build_id,
		"owner": str(owner_id), "phase": "lobby", "name": "雾灯旅店 · 好友测试"}
	for key in metadata:
		if not api.setLobbyData(id, key, metadata[key]):
			created.peer.close()
			_fail("Steam 房间信息发布失败，请重建房间")
			return
	api.setLobbyMemberLimit(id, 5)
	api.setLobbyJoinable(id, true)
	_last_phase = "lobby"
	_deadline = 0
	status = "Steam 房间 %d · 等待好友加入" % id
	print("STEAM_LOBBY_CREATED ", id)
	peer_ready.emit(created.peer, true)
	changed.emit()

func _on_joined(id: int, _permissions: int, _locked: bool, result: int) -> void:
	# Steam also emits lobby_joined for our own createLobby request.
	if (_creating and _joining == 0) or (hosting and id == lobby_id):
		return
	if id != _joining:
		if result == 1 and id != lobby_id:
			api.leaveLobby(id)
		return
	_joining = 0
	if result != 1:
		_fail("Steam 加入失败（%d）：房间可能已满、已开局或不可访问" % result)
		return
	lobby_id = id
	_validating = true
	_try_connect()

func _try_connect() -> void:
	if not _validating or lobby_id == 0:
		return
	var game := str(api.getLobbyData(lobby_id, "game"))
	if game.is_empty():
		api.requestLobbyData(lobby_id)
		return
	if game != GAME_ID or str(api.getLobbyData(lobby_id, "protocol")) != PROTOCOL:
		_fail("该房间不属于当前 A1 游戏或协议不兼容")
		return
	if str(api.getLobbyData(lobby_id, "build")) != build_id:
		_fail("测试包版本不一致，请所有人使用同一个压缩包")
		return
	if str(api.getLobbyData(lobby_id, "phase")) != "lobby":
		_fail("该房间已经开始，请等待下一局")
		return
	owner_id = int(api.getLobbyOwner(lobby_id))
	if owner_id == 0 or owner_id == int(api.getSteamID()) or str(owner_id) != str(api.getLobbyData(lobby_id, "owner")):
		_fail("原房主已离开或房间无效，不支持房主迁移")
		return
	var created := _make_peer(false, owner_id)
	if int(created.error) != OK:
		_fail("Steam 游戏传输连接失败：" + error_string(int(created.error)))
		return
	_validating = false
	_deadline = 0
	status = "已加入 Steam 大厅，正在连接房主游戏传输…"
	peer_ready.emit(created.peer, false)
	changed.emit()

func _on_data(success: int, id: int, _member: int) -> void:
	if success == 1 and id == lobby_id:
		_try_connect()

func set_phase(phase: String) -> void:
	if not initialized or not hosting or lobby_id == 0 or phase == _last_phase:
		return
	_last_phase = phase
	api.setLobbyData(lobby_id, "phase", phase)
	api.setLobbyJoinable(lobby_id, phase == "lobby")

func member_allowed(peer_steam_id: int) -> bool:
	if not initialized or lobby_id == 0 or peer_steam_id == 0:
		return false
	for index in int(api.getNumLobbyMembers(lobby_id)):
		if int(api.getLobbyMemberByIndex(lobby_id, index)) == peer_steam_id:
			return true
	return false

func invite_friends() -> void:
	if initialized and lobby_id != 0 and hosting and _last_phase == "lobby":
		api.activateGameOverlayInviteDialog(lobby_id)

func _on_invite(id: int, _friend: int) -> void:
	join_requested.emit(id) # Session decides whether the current match can be left.

func _on_member_changed(id: int, changed_id: int, _by: int, state: int) -> void:
	if id == lobby_id and not hosting and changed_id == owner_id and (state & 30) != 0:
		_fail("原 Steam 房主已离开，联机结束（不支持房主迁移）")

func _on_kicked(id: int, _admin: int, _disconnected: int) -> void:
	if id == lobby_id:
		_fail("已离开 Steam 大厅，请重新加入")

func _check_launch_invite() -> void:
	var arguments := OS.get_cmdline_args()
	var launch := str(api.getLaunchCommandLine()).split(" ", false)
	arguments.append_array(launch)
	for index in range(arguments.size() - 1):
		if arguments[index] == "+connect_lobby" and arguments[index + 1].is_valid_int():
			join_requested.emit(int(arguments[index + 1]))
			return

func _process(_delta: float) -> void:
	if not initialized:
		return
	api.run_callbacks()
	if lobby_id != 0:
		if not api.loggedOn():
			_fail("Steam 已离线，本次联机结束")
			return
		if not hosting and owner_id != 0 and int(api.getLobbyOwner(lobby_id)) != owner_id:
			_fail("原 Steam 房主已退出，不支持房主迁移")
			return
	if _deadline != 0 and Time.get_ticks_msec() > _deadline:
		_fail("Steam 房间请求超时，请检查网络后重试")

func close() -> void:
	if _creating:
		_cancel_create = true # Drain its callback; never adopt a late-created orphan lobby.
	_joining = 0
	_validating = false
	_deadline = 0
	var previous := lobby_id
	lobby_id = 0
	owner_id = 0
	hosting = false
	_last_phase = ""
	if initialized and previous != 0:
		api.leaveLobby(previous)
	changed.emit()

func _fail(message: String) -> void:
	close()
	status = message
	print("STEAM_FAILURE ", message)
	failed.emit(message)
	changed.emit()

func _exit_tree() -> void:
	close()
	if initialized and is_instance_valid(api) and _signals_connected:
		for pair in [["lobby_created", _on_created], ["lobby_joined", _on_joined],
			["lobby_data_update", _on_data], ["lobby_chat_update", _on_member_changed],
			["join_requested", _on_invite], ["lobby_kicked", _on_kicked]]:
			if api.is_connected(pair[0], pair[1]):
				api.disconnect(pair[0], pair[1])
