extends Node
const Texts = preload("res://features/localization/game_text.gd")
## Steam lobbies are discovery/authorization; Session remains the gameplay authority.
signal changed(info: Dictionary)
signal transport_ready(peer: MultiplayerPeer, as_host: bool)
signal join_requested(lobby_code: String)
signal failed(message: String)
signal overlay_changed(active: bool)

const GAME_KEY := "a1_bunker_base"
const PROTOCOL := "a1_bunker_v19"
const VIRTUAL_PORT := 24567
const MAX_MEMBERS := 5
var app_id := 480
var build_id := "a1_roll_dev_20261022"
var steam: Object
var peer_factory: Callable
var available := false
var initialized := false
var status := "⟦steam_service.001⟧"
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
	if not available: status = "⟦steam_service.002⟧"
	if steam != null:
		for binding in [["lobby_created",_on_created],["lobby_joined",_on_joined],["lobby_data_update",_on_data],["lobby_chat_update",_on_members],["join_requested",_on_invite],["overlay_toggled",_on_overlay]]:
			if steam.has_signal(binding[0]) and not steam.is_connected(binding[0],binding[1]):
				steam.connect(binding[0],binding[1])
	_publish()

func initialize() -> bool:
	if not available:
		status="⟦steam_service.003⟧"
		_publish()
		return false
	if not _api_initialized:
		var result: Dictionary = steam.steamInitEx(app_id,false)
		if int(result.get("status",-1)) != 0:
			status="⟦steam_service.004⟧" + str(result.get("verbal","")).left(180)
			_publish()
			return false
		_api_initialized=true
		steam.initRelayNetworkAccess()
	initialized=bool(steam.loggedOn())
	if initialized:
		steam_id=int(steam.getSteamID())
		persona=Texts.literal(str(steam.getPersonaName()).left(40))
		status="⟦steam_service.005⟧" + persona
	else:
		status="⟦steam_service.006⟧"
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
	status="⟦steam_service.007⟧"
	_publish()
	steam.createLobby(lobby_type,MAX_MEMBERS)
	return OK

func join_room(code: String) -> Error:
	var id:=parse_lobby_code(code)
	if id==0:
		status="⟦steam_service.008⟧"
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
	status="⟦steam_service.009⟧"
	_publish()
	if not steam.requestLobbyData(id):
		_fail("⟦steam_service.010⟧")
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
	status="⟦steam_service.011⟧" if _create_outstanding else ("⟦steam_service.012⟧" if initialized else "⟦steam_service.001⟧")
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
	status="⟦steam_service.013⟧" if _scan_deadline>0 else "⟦steam_service.014⟧"
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
		status="⟦steam_service.015⟧"
		_publish()
		return
	if not initialized or lobby_id==0:
		status="⟦steam_service.016⟧"
	elif not steam.isOverlayEnabled():
		status="⟦steam_service.017⟧"
	else:
		steam.activateGameOverlayInviteDialog(lobby_id)
		status="⟦steam_service.018⟧"
	_publish()

func copy_lobby() -> void:
	if lobby_id>0:
		DisplayServer.clipboard_set(str(lobby_id))
		status="⟦steam_service.019⟧"
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
	if peer==null:return "⟦session.002⟧"
	var id:int=int(peer.call("get_steam_id_for_peer_id",peer_id))
	return Texts.literal(str(steam.getFriendPersonaName(id)).left(24)) if id>0 else "⟦session.002⟧"

func mark_connected() -> void:
	if lobby_id>0:
		_operation=""
		_deadline=0
		status=Texts.format("⟦steam_service.020⟧", [int(steam.getNumLobbyMembers(lobby_id)),MAX_MEMBERS])
		_publish()

func _on_created(result: int,id: int) -> void:
	_create_outstanding=false
	_create_timed_out=false
	if _operation!="create":
		if result==1 and id>0:steam.leaveLobby(id)
		_publish()
		return
	if result!=1 or id<=0:
		_fail(Texts.format("⟦steam_service.021⟧", result))
		return
	lobby_id=id
	host_steam_id=steam_id
	var values:Dictionary={"game":GAME_KEY,"protocol":PROTOCOL,"build":build_id,"host_id":str(steam_id),"join_state":"base","name":Texts.resolve(persona+"⟦steam_service.022⟧")}
	for key in values:
		if not steam.setLobbyData(id,key,values[key]):
			_fail("⟦steam_service.023⟧")
			return
	join_allowed=true
	steam.setLobbyJoinable(id,true)
	_start_transport(true)

func _on_data(success: int,id: int,_member: int) -> void:
	if _scan_pending.has(id):
		_scan_pending.erase(id)
		if success==1 and _compatible(id):
			lobbies.append({"id":str(id),"name":Texts.literal(str(steam.getLobbyData(id,"name")).left(64)),"members":int(steam.getNumLobbyMembers(id)),"limit":int(steam.getLobbyMemberLimit(id)),"join_allowed":str(steam.getLobbyData(id,"join_state"))!="exploration"})
		if _scan_pending.is_empty():
			_scan_deadline=0
			status=Texts.format("⟦steam_service.024⟧", lobbies.size())
		_publish()
	if _operation!="validate" or id!=_requested_lobby:return
	if success!=1 or not _compatible(id):
		_fail("⟦steam_service.025⟧")
		return
	if str(steam.getLobbyData(id,"join_state"))=="exploration":
		_fail("⟦steam_service.026⟧")
		return
	if str(steam.getLobbyData(id,"host_id"))==str(steam_id):
		_fail("⟦steam_service.027⟧")
		return
	_operation="join"
	status="⟦steam_service.028⟧"
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
		_fail(Texts.format("⟦steam_service.029⟧", response))
		return
	if str(steam.getLobbyData(id,"join_state"))=="exploration":
		steam.leaveLobby(id)
		_fail("⟦steam_service.030⟧")
		return
	if not _compatible(id,true):
		steam.leaveLobby(id)
		_fail("⟦steam_service.031⟧")
		return
	lobby_id=id
	host_steam_id=int(steam.getLobbyOwner(id))
	_start_transport(false)

func _start_transport(as_host: bool) -> void:
	peer=peer_factory.call() if peer_factory.is_valid() else ClassDB.instantiate("SteamMultiplayerPeer")
	if peer==null:
		_fail("⟦steam_service.032⟧")
		return
	peer.call("set_server_relay",false)
	var result:int=int(peer.call("create_host",VIRTUAL_PORT)) if as_host else int(peer.call("create_client",host_steam_id,VIRTUAL_PORT))
	if result!=OK:
		_fail("⟦steam_service.033⟧"+error_string(result)+"⟦steam_service.034⟧")
		return
	_operation="" if as_host else "transport"
	_deadline=0 if as_host else _clock+25
	steam.setRichPresence("connect","+connect_lobby "+str(lobby_id))
	status="⟦steam_service.035⟧" if as_host else "⟦steam_service.036⟧"
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
		_fail("⟦steam_service.037⟧" if _create_timed_out else "⟦steam_service.038⟧")
	if _scan_deadline>0 and _clock>=_scan_deadline:
		_scan_deadline=0
		_scan_pending.clear()
		status="⟦steam_service.039⟧"
		_publish()
	_health_clock+=delta
	if _health_clock>=1:
		_health_clock=0
		if initialized and not steam.loggedOn():
			initialized=false
			_fail("⟦steam_service.040⟧")
		elif lobby_id>0:_check_room()

func _check_room() -> void:
	if lobby_id>0 and int(steam.getLobbyOwner(lobby_id))!=host_steam_id:
		_fail("⟦steam_service.041⟧")

func _fail(message: String) -> void:
	leave_room()
	status=message
	_publish()
	failed.emit(message)

func _busy() -> Error:
	status="⟦steam_service.037⟧" if _create_timed_out else "⟦steam_service.042⟧"
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
