extends Node
## Steam lobbies are discovery/authorization; Session remains the gameplay authority.
signal changed(info: Dictionary)
signal transport_ready(peer: MultiplayerPeer, as_host: bool)
signal join_requested(lobby_code: String)
signal failed(message: String)
signal overlay_changed(active: bool)

const GAME_KEY := "a1_bunker_base"
const PROTOCOL := "a1_bunker_v7"
const VIRTUAL_PORT := 24567
const MAX_MEMBERS := 5
var app_id := 480
var build_id := "a1_dark_vision_dev_20261022"
var steam: Object
var peer_factory: Callable
var available := false
var initialized := false
var status := "点击连接 Steam"
var persona := ""
var lobby_id: int = 0
var host_steam_id: int = 0
var steam_id: int = 0
var peer: MultiplayerPeer
var lobbies: Array = []
var overlay_active := false
var join_allowed := true
var _api_initialized := false
var _operation := ""
var _requested_lobby: int = 0
var _create_outstanding := false
var _deadline := 0.0
var _scan_pending: Dictionary = {}
var _scan_deadline := 0.0
var _health_clock := 0.0
var _clock := 0.0
var _shutting_down := false
var _create_timed_out := false
var _cancelled_joins: Dictionary = {}

func _ready() -> void:
	if steam == null and Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
	available = steam != null and (ClassDB.class_exists("SteamMultiplayerPeer") or peer_factory.is_valid())
	var config := ConfigFile.new()
	if config.load("res://app/network/steam_config.cfg") == OK:
		app_id = int(config.get_value("steam","app_id",480))
		build_id = str(config.get_value("steam","build_id",build_id))
	if not available: status = "Steam 组件未加载；请使用完整试玩包并登录 Steam"
	if steam != null:
		for binding in [["lobby_created",_on_created],["lobby_joined",_on_joined],["lobby_data_update",_on_data],["lobby_chat_update",_on_members],["join_requested",_on_invite],["overlay_toggled",_on_overlay]]:
			if steam.has_signal(binding[0]) and not steam.is_connected(binding[0],binding[1]):
				steam.connect(binding[0],binding[1])
	_publish()

func initialize() -> bool:
	if not available:
		status="Steam 组件未加载；请使用完整 Windows 试玩包"
		_publish()
		return false
	if not _api_initialized:
		var result: Dictionary = steam.steamInitEx(app_id,false)
		if int(result.get("status",-1)) != 0:
			status="Steam 初始化失败：请先打开并登录 Steam，然后重试。" + str(result.get("verbal","")).left(180)
			_publish()
			return false
		_api_initialized=true
		steam.initRelayNetworkAccess()
	initialized=bool(steam.loggedOn())
	if initialized:
		steam_id=int(steam.getSteamID())
		persona=str(steam.getPersonaName()).left(40)
		status="Steam 已连接 · " + persona
	else:
		status="Steam 当前未在线；登录后点击重试"
	_publish()
	return initialized

func info(transport: String = "offline") -> Dictionary:
	return {"available":available,"initialized":initialized,"status":status,"persona":persona,"app_id":app_id,"lobby_id":str(lobby_id) if lobby_id>0 else "","transport":transport,"join_allowed":join_allowed,"pending":not _operation.is_empty(),"scanning":_scan_deadline>0,"lobbies":lobbies.duplicate(true)}

func host_room(lobby_type: int = 1) -> Error:
	if not initialize():return ERR_UNAVAILABLE
	if _create_outstanding or not _operation.is_empty():return _busy()
	leave_room()
	_operation="create"
	_create_outstanding=true
	_create_timed_out=false
	_deadline=_clock+25
	status="正在创建 Steam 好友基地…"
	_publish()
	steam.createLobby(lobby_type,MAX_MEMBERS)
	return OK

func join_room(code: String) -> Error:
	var id:=parse_lobby_code(code)
	if id==0:
		status="房间号无效，请粘贴完整的 Steam 数字房间号"
		_publish()
		return ERR_INVALID_PARAMETER
	if not initialize():return ERR_UNAVAILABLE
	if _create_outstanding or not _operation.is_empty():return _busy()
	if id==lobby_id and peer!=null:return ERR_ALREADY_IN_USE
	leave_room()
	_requested_lobby=id
	_cancelled_joins.erase(id)
	_operation="validate"
	_deadline=_clock+25
	status="正在校验 Steam 房间与版本…"
	_publish()
	if not steam.requestLobbyData(id):
		_fail("无法读取 Steam 房间，请确认房主在线且房间仍开放")
		return ERR_CANT_CONNECT
	return OK

static func parse_lobby_code(code: String) -> int:
	code=code.strip_edges()
	if code.length()<16 or code.length()>19:return 0
	for character in code:
		if character<"0" or character>"9":return 0
	var value:=code.to_int()
	if value<=0 or str(value)!=code:return 0
	return value

func leave_room() -> void:
	if _operation=="join" and _requested_lobby>0:_cancelled_joins[_requested_lobby]=true
	_operation=""
	_requested_lobby=0
	_deadline=0
	if peer!=null:
		peer.close()
		peer=null
	var old_lobby:=lobby_id
	lobby_id=0
	if _api_initialized and old_lobby>0:
		if host_steam_id==steam_id:steam.setLobbyJoinable(old_lobby,false)
		steam.leaveLobby(old_lobby)
		steam.clearRichPresence()
	host_steam_id=0
	status="已取消，正在等待 Steam 完成上一个请求…" if _create_outstanding else ("Steam 已就绪" if initialized else "点击连接 Steam")
	_publish()

func refresh_friends() -> void:
	if not initialize():return
	if _scan_deadline>0:return
	lobbies.clear()
	_scan_pending.clear()
	# Friends-only lobbies are not returned by RequestLobbyList. Query friends' current lobby IDs.
	for i in range(mini(int(steam.getFriendCount(4)),512)):
		var friend_id:int=int(steam.getFriendByIndex(i,4))
		var game:Dictionary=steam.getFriendGamePlayed(friend_id)
		var id:int=int(game.get("lobby",0))
		if int(game.get("id",0))==app_id and id>0 and not _scan_pending.has(id):
			_scan_pending[id]=true
	_scan_deadline=_clock+6 if not _scan_pending.is_empty() else 0.0
	for id in _scan_pending.keys():
		if not steam.requestLobbyData(id):_scan_pending.erase(id)
	if _scan_pending.is_empty():_scan_deadline=0
	status="正在查询好友房间…" if _scan_deadline>0 else "未发现本项目好友房间；也可粘贴房间号加入"
	_publish()

func set_join_allowed(value: bool) -> void:
	if join_allowed==value:return
	join_allowed=value
	if initialized and lobby_id>0 and host_steam_id==steam_id:
		steam.setLobbyJoinable(lobby_id,value)
		steam.setLobbyData(lobby_id,"join_state","base" if value else "exploration")
	_publish()

func invite_friends() -> void:
	if not join_allowed:
		status="队伍正在探索，回到基地后才能邀请好友加入"
		_publish()
		return
	if not initialized or lobby_id==0:
		status="请先创建或加入 Steam 房间"
	elif not steam.isOverlayEnabled():
		status="Steam 界面尚未可用；可复制房间号交给好友，或通过 Steam 启动本试玩包"
	else:
		steam.activateGameOverlayInviteDialog(lobby_id)
		status="已打开 Steam 好友邀请界面"
	_publish()

func copy_lobby() -> void:
	if lobby_id>0:
		DisplayServer.clipboard_set(str(lobby_id))
		status="房间号已复制，请让好友先打开同版本试玩包"
		_publish()

func accept_peer(peer_id: int) -> bool:
	if peer==null or lobby_id==0 or not initialized:return false
	if int(steam.getLobbyOwner(lobby_id))!=host_steam_id:return false
	var id:int=int(peer.call("get_steam_id_for_peer_id",peer_id))
	if id<=0:return false
	for i in range(int(steam.getNumLobbyMembers(lobby_id))):
		if int(steam.getLobbyMemberByIndex(lobby_id,i))==id:return true
	return false

func peer_identity(peer_id: int) -> String:
	if not accept_peer(peer_id):return ""
	return "steam_"+str(int(peer.call("get_steam_id_for_peer_id",peer_id)))

func peer_name(peer_id: int) -> String:
	if peer==null:return "旅鸭"
	var id:int=int(peer.call("get_steam_id_for_peer_id",peer_id))
	return str(steam.getFriendPersonaName(id)).left(24) if id>0 else "旅鸭"

func mark_connected() -> void:
	if lobby_id>0:
		_operation=""
		_deadline=0
		status="Steam 基地已连接 · %d / %d 人"%[int(steam.getNumLobbyMembers(lobby_id)),MAX_MEMBERS]
		_publish()

func _on_created(result: int,id: int) -> void:
	_create_outstanding=false
	_create_timed_out=false
	if _operation!="create":
		if result==1 and id>0:steam.leaveLobby(id)
		_publish()
		return
	if result!=1 or id<=0:
		_fail("Steam 建房失败（%d），请确认网络后重试"%result)
		return
	lobby_id=id
	host_steam_id=steam_id
	var values:Dictionary={"game":GAME_KEY,"protocol":PROTOCOL,"build":build_id,"host_id":str(steam_id),"join_state":"base","name":persona+" 的鸭科夫基地"}
	for key in values:
		if not steam.setLobbyData(id,key,values[key]):
			_fail("无法写入 Steam 房间版本信息")
			return
	join_allowed=true
	steam.setLobbyJoinable(id,true)
	_start_transport(true)

func _on_data(success: int,id: int,_member: int) -> void:
	if _scan_pending.has(id):
		_scan_pending.erase(id)
		if success==1 and _compatible(id):
			lobbies.append({"id":str(id),"name":str(steam.getLobbyData(id,"name")).left(64),"members":int(steam.getNumLobbyMembers(id)),"limit":int(steam.getLobbyMemberLimit(id)),"join_allowed":str(steam.getLobbyData(id,"join_state"))!="exploration"})
		if _scan_pending.is_empty():
			_scan_deadline=0
			status="找到 %d 个本项目好友房间"%lobbies.size()
		_publish()
	if _operation!="validate" or id!=_requested_lobby:return
	if success!=1 or not _compatible(id):
		_fail("这不是相同版本的鸭科夫基地房间，或原房主已离开")
		return
	if str(steam.getLobbyData(id,"join_state"))=="exploration":
		_fail("队伍正在探索，请等房主回到基地后再加入")
		return
	if str(steam.getLobbyData(id,"host_id"))==str(steam_id):
		_fail("不能加入自己另一个进程的房间；Steam 联机需不同账号")
		return
	_operation="join"
	status="正在进入 Steam 房间…"
	_publish()
	steam.joinLobby(id)

func _compatible(id: int, joined: bool = false) -> bool:
	if str(steam.getLobbyData(id,"game"))!=GAME_KEY or str(steam.getLobbyData(id,"protocol"))!=PROTOCOL or str(steam.getLobbyData(id,"build"))!=build_id:return false
	var declared_host:=parse_lobby_code(str(steam.getLobbyData(id,"host_id")))
	if declared_host==0 or int(steam.getLobbyMemberLimit(id))!=MAX_MEMBERS:return false
	# GetLobbyOwner is only valid after joining; RequestLobbyData alone does not authorize it.
	return not joined or int(steam.getLobbyOwner(id))==declared_host

func _on_joined(id: int,_permissions: int,_locked: bool,response: int) -> void:
	if _cancelled_joins.has(id):
		_cancelled_joins.erase(id)
		if response==1:steam.leaveLobby(id)
		return
	# Creating a lobby also fires this callback. Do not turn its host into a client.
	if id==lobby_id and host_steam_id==steam_id:return
	if _operation=="create":
		if response==1 and int(steam.getLobbyOwner(id))!=steam_id:steam.leaveLobby(id)
		return
	if _operation!="join" or id!=_requested_lobby:
		if response==1 and id!=lobby_id:steam.leaveLobby(id)
		return
	if response!=1:
		_fail("加入 Steam 房间失败（%d），房间可能已满或不可访问"%response)
		return
	if str(steam.getLobbyData(id,"join_state"))=="exploration":
		steam.leaveLobby(id)
		_fail("队伍已出发，请等回到基地后再加入")
		return
	if not _compatible(id,true):
		steam.leaveLobby(id)
		_fail("房间版本或房主已变化，请重新加入")
		return
	lobby_id=id
	host_steam_id=int(steam.getLobbyOwner(id))
	_start_transport(false)

func _start_transport(as_host: bool) -> void:
	peer=peer_factory.call() if peer_factory.is_valid() else ClassDB.instantiate("SteamMultiplayerPeer")
	if peer==null:
		_fail("无法创建 Steam 网络组件")
		return
	peer.call("set_server_relay",false)
	var result:int=int(peer.call("create_host",VIRTUAL_PORT)) if as_host else int(peer.call("create_client",host_steam_id,VIRTUAL_PORT))
	if result!=OK:
		_fail("Steam P2P 创建失败："+error_string(result)+"。请勿用同一 Steam 账号双开。")
		return
	_operation="" if as_host else "transport"
	_deadline=0 if as_host else _clock+25
	steam.setRichPresence("connect","+connect_lobby "+str(lobby_id))
	status="Steam 好友基地已开放" if as_host else "正在建立 Steam P2P 连接…"
	_publish()
	transport_ready.emit(peer,as_host)

func _on_invite(id: int,_friend: int) -> void:
	if id>0:join_requested.emit(str(id))

func _on_overlay(active: bool,_user_initiated: bool,_app: int) -> void:
	overlay_active=active
	overlay_changed.emit(active)

func _on_members(id: int,_changed: int,_making_change: int,_state: int) -> void:
	if lobby_id==0 or id!=lobby_id:return
	_check_room()
	if peer!=null and host_steam_id==steam_id:
		# A transport socket is not sufficient authority: member must remain in this lobby.
		for peer_id in multiplayer.get_peers():
			if not accept_peer(peer_id):peer.disconnect_peer(peer_id)
	_publish()

func _process(delta: float) -> void:
	_clock+=delta
	if not _api_initialized:return
	steam.run_callbacks()
	if _deadline>0 and _clock>=_deadline:
		_create_timed_out=_create_outstanding
		_fail("Steam 建房请求未返回，请重启试玩包后再试；请使用完整试玩包并登录 Steam" if _create_timed_out else "Steam 请求超时，请检查双方网络并重试")
	if _scan_deadline>0 and _clock>=_scan_deadline:
		_scan_deadline=0
		_scan_pending.clear()
		status="已显示可读取的好友房间；也可粘贴房间号加入"
		_publish()
	_health_clock+=delta
	if _health_clock>=1:
		_health_clock=0
		if initialized and not steam.loggedOn():
			initialized=false
			_fail("Steam 已离线，请重新登录后连接")
		elif lobby_id>0:_check_room()

func _check_room() -> void:
	if lobby_id>0 and int(steam.getLobbyOwner(lobby_id))!=host_steam_id:
		_fail("原房主已离开，Steam 房间已结束；请重新建房")

func _fail(message: String) -> void:
	leave_room()
	status=message
	_publish()
	failed.emit(message)

func _busy() -> Error:
	status="Steam 建房请求未返回，请重启试玩包后再试；请使用完整试玩包并登录 Steam" if _create_timed_out else "Steam 尚在处理上一个请求，请稍后重试"
	_publish()
	return ERR_BUSY

func _publish() -> void:
	changed.emit(info("steam" if lobby_id>0 else "offline"))

func _exit_tree() -> void:
	if _shutting_down:return
	_shutting_down=true
	leave_room()
	if steam!=null:
		for binding in [["lobby_created",_on_created],["lobby_joined",_on_joined],["lobby_data_update",_on_data],["lobby_chat_update",_on_members],["join_requested",_on_invite],["overlay_toggled",_on_overlay]]:
			if steam.has_signal(binding[0]) and steam.is_connected(binding[0],binding[1]):steam.disconnect(binding[0],binding[1])
	if _api_initialized:steam.steamShutdown()
