extends Node
## Identical Session node path on all peers. Every item mutation runs only on host.
signal state_changed()
signal notice(text: String)
signal voice_received(speaker: int, bytes: PackedByteArray)
const VoiceRules=preload("res://features/voice/voice_rules.gd")
var _voice_limits: Dictionary={}
var _voice_sequences: Dictionary={}
const Model = preload("res://features/base/base_model.gd")
const MotionBuffer = preload("res://features/player/motion_buffer.gd")
const RoomStore=preload("res://features/persistence/room_store.gd")
const LocalMovement = preload("res://features/player/local_movement.gd")
const MOTION_INTERVAL := 1.0 / 20.0
const STATE_INTERVAL := 0.5
const MOTION_FIELDS := ["pos","height","velocity","aim","sprint","crouch","ads","reloading","reload_progress","shots","anim_seq","anim_action","anim_time","anim_duration","input_seq","input_origin","input_height","input_stamina","input_weight","input_max_weight"]
const DEFAULT_PORT := 24567
const ACTIONS := ["transfer","split","use","drop","pickup","sort","reload","fire","equip","unequip","select_weapon","rest","craft","buy_ammo","resupply_ammo","set_infinite_reserve","train","reset_targets","travel","door","unstuck"]
var model = Model.new()
var local_id := 1
var mode := "offline"
var connection_status := "离线基地"
var _peer: MultiplayerPeer
var transport := "offline"
var peer_validator: Callable
var peer_name_provider: Callable
var _snapshot_clock := 0.0
var _motion_clock := 0.0
var _snapshot_serial := 0
var _received_serial := -1
var _received_motion_serial := -1
var _snapshot_received_usec := 0
var motion_buffer = MotionBuffer.new()
var local_movement = LocalMovement.new()
var _last_sent_move: Dictionary = {}
var _session_token := 0
var _movement_seq := 0
var _intent_seq := 0
var _last_movement: Dictionary = {}
var _last_intent: Dictionary = {}
var _rate_limits: Dictionary = {}
var _move_clock := 0.0
var _move_pending: Dictionary = {}
var _connect_elapsed := 0.0
var _local_profile: Dictionary = {}
var room_store=RoomStore.new()
var peer_identity_provider: Callable
var _room_save_clock:=0.0

func _init() -> void:
	name = "Session"
	model.add_player(1,"旅鸭")
	local_movement.solver = model.solve_motion.bind(0)

func _ready() -> void:
	name = "Session"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int = DEFAULT_PORT) -> Error:
	offline()
	if port < 1024 or port > 65535:
		connection_status = "端口需要在1024–65535之间"; notice.emit(connection_status)
		return ERR_INVALID_PARAMETER
	var enet := ENetMultiplayerPeer.new()
	_peer = enet
	var error := enet.create_server(port,4)
	if error != OK:
		_peer = null
		connection_status = "建房失败：端口可能被占用（%s）" % error_string(error)
		notice.emit(connection_status)
		return error
	multiplayer.multiplayer_peer = _peer
	multiplayer.server_relay = false
	mode = "host"; transport = "enet"; local_id = 1; _session_token = randi_range(1,2147483647)
	connection_status = "基地房间已开放 · UDP %d · 最多5人" % port
	state_changed.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	offline()
	address = address.strip_edges().left(253)
	if address.is_empty() or port < 1024 or port > 65535:
		connection_status = "请输入房主IP和有效端口"; notice.emit(connection_status)
		return ERR_INVALID_PARAMETER
	var enet := ENetMultiplayerPeer.new()
	_peer = enet
	var error := enet.create_client(address,port)
	if error != OK:
		_peer = null
		connection_status = "连接失败：%s" % error_string(error); notice.emit(connection_status)
		return error
	model.state.players.clear()
	multiplayer.multiplayer_peer = _peer
	mode = "client"; transport = "enet"; local_id = 0; _connect_elapsed = 0.0
	connection_status = "正在连接 %s:%d…" % [address,port]
	state_changed.emit()
	return OK

func use_steam_peer(peer: MultiplayerPeer, as_host: bool, validator: Callable = Callable(), names: Callable = Callable(), identities: Callable = Callable(), room_path: String="", owner_key: String="", legacy_path: String="") -> Error:
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return ERR_CANT_CONNECT
	offline()
	if as_host and not room_path.is_empty():
		var error:=configure_room(room_path,owner_key,identities,legacy_path)
		if error!=OK:peer.close();return error
	_peer = peer
	peer_validator = validator
	peer_name_provider = names
	transport = "steam"
	mode = "host" if as_host else "client"
	local_id = 1 if as_host else 0
	if as_host:
		_session_token = randi_range(1,2147483647)
	else:
		model.state.players.clear()
	multiplayer.multiplayer_peer = _peer
	multiplayer.server_relay = false
	connection_status = "Steam 好友基地已开放 · 最多5人" if as_host else "Steam P2P 连接中…"
	state_changed.emit()
	return OK

func configure_room(path: String, owner_key: String, identities: Callable, legacy_path: String="") -> Error:
	if mode=="client" or not identities.is_valid():return ERR_UNAUTHORIZED
	var result: Error=room_store.begin(model,path,owner_key,legacy_path)
	if result!=OK:
		room_store.clear()
		return result
	peer_identity_provider=identities
	_room_save_clock=0
	return OK

func save_room() -> Error:
	var result: Error=room_store.checkpoint(model)
	if result!=OK:notice.emit("房主房间存档失败："+error_string(result)+"，请检查存档目录")
	return result

func offline() -> void:
	if not room_store.path.is_empty():save_room()
	room_store.clear();peer_identity_provider=Callable()
	if mode == "client": model.state.infinite_reserve = false
	if mode != "client" and model.state.players.has(local_id):
		_local_profile = model.state.players[local_id].duplicate(true)
	if is_inside_tree(): multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _peer != null: _peer.close(); _peer = null
	mode = "offline"; transport = "offline"; local_id = 1; connection_status = "离线基地"
	peer_validator = Callable(); peer_name_provider = Callable()
	model.state.players.clear(); model.state.drops.clear(); model.state.shots.clear()
	model.state.world = "bunker"; model.state.phase = "base"
	model.state.world_revision = int(model.state.get("world_revision",0))+1
	if model.world_cache.has("bunker"): model.state.targets = model.world_cache.bunker.targets
	model.world_cache.clear()
	model.state.doors={}
	model._inputs.clear()
	model._recovery_after.clear()
	model.add_player(1,"旅鸭")
	if not _local_profile.is_empty():
		model.state.players[1] = _local_profile.duplicate(true)
		model.state.players[1].id = 1
		model.state.players[1].pos = Vector2(-1,4)
		model.state.players[1].height = 0.0
		model.state.players[1].reloading = false
		model.state.players[1].fire_timer = 0.0
	model.reset_transients(1)
	_voice_limits.clear(); _voice_sequences.clear()
	_last_movement.clear(); _last_intent.clear(); _rate_limits.clear(); _move_pending.clear()
	_snapshot_clock = 0.0; _snapshot_serial = 0; _received_serial = -1; _session_token = 0
	_motion_clock = 0.0; _move_clock = 0.0; _received_motion_serial = -1
	motion_buffer.clear()
	local_movement.clear(); _last_sent_move.clear()
	_snapshot_received_usec = 0
	_movement_seq = 0; _intent_seq = 0; _connect_elapsed = 0.0
	state_changed.emit()

func start_solo() -> void:
	if mode != "offline": offline()
	connection_status = "离线基地 · 自动保存在本机"
	state_changed.emit()

func send(action: String, payload: Dictionary = {}) -> void:
	var clean := _clean_payload(action,payload)
	if action=="unstuck":clean.world_revision=int(model.state.get("world_revision",0))
	if action != "move" and not action in ACTIONS: return
	if action == "move" and clean.is_empty(): return
	if mode == "client":
		if local_id == 0 or _session_token == 0 or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
		if action == "move":
			local_movement.set_input(clean)
			_move_pending = clean
			var edge := _is_movement_edge(clean)
			if edge: _flush_movement(true)
		else:
			_intent_seq += 1
			_intent.rpc_id(1,action,clean,_session_token,_intent_seq)
	else:
		var accepted: bool=model.command(local_id,action,clean)
		if accepted and action not in ["move","fire"] and not room_store.path.is_empty():save_room()
		if not model.last_notice.is_empty(): notice.emit(model.last_notice)
		if action != "move":
			state_changed.emit()
			if mode == "host": _broadcast_snapshot(true)

func _physics_process(delta: float) -> void:
	if mode == "client":
		if local_id == 0 or _session_token == 0:
			_connect_elapsed += delta
			if _connect_elapsed > (25.0 if transport == "steam" else 10.0): _on_connection_failed()
		_move_clock += delta
		if _move_clock >= 0.05:
			_flush_movement(false)
		if model.state.players.has(local_id): local_movement.advance(delta,model.state.players[local_id])
		return
	_room_save_clock+=delta
	if _room_save_clock>=5.0:
		_room_save_clock=0
		if not room_store.path.is_empty():save_room()
	var reloading: Array[int] = []
	for id in model.state.players:
		if model.state.players[id].reloading: reloading.append(id)
	model.tick(delta)
	# Reload completion mutates ammunition/inventory in tick, outside the intent path.
	for id in reloading:
		if not model.state.players[id].reloading:
			if mode == "host": _broadcast_snapshot(true)
			break
	_motion_clock += delta
	if _motion_clock >= MOTION_INTERVAL:
		_motion_clock = fmod(_motion_clock,MOTION_INTERVAL)
		if mode == "host": _broadcast_motion()
	_snapshot_clock += delta
	if _snapshot_clock >= STATE_INTERVAL:
		_snapshot_clock = fmod(_snapshot_clock,STATE_INTERVAL)
		state_changed.emit()
		if mode == "host": _broadcast_snapshot(false)

func _is_movement_edge(input: Dictionary) -> bool:
	if _last_sent_move.is_empty(): return true
	# The camera basis can introduce tiny float noise during an otherwise held key.
	if Vector2(input.direction).distance_squared_to(_last_sent_move.direction) > .00000001: return true
	for key in ["sprint","crouch","ads"]:
		if input.get(key) != _last_sent_move.get(key): return true
	return false

func _flush_movement(edge: bool) -> void:
	if _move_pending.is_empty() or local_id <= 0 or _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	_move_clock = 0.0
	_movement_seq += 1
	local_movement.note_sent(_movement_seq,edge)
	_movement.rpc_id(1,_move_pending,_session_token,_movement_seq,int(model.state.get("world_revision",0)))
	_last_sent_move = _move_pending
	_move_pending = {}

func _clean_payload(action: String, payload: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	match action:
		"unstuck":
			if payload.get("world_revision") is int:clean.world_revision=payload.world_revision
		"set_infinite_reserve":
			if payload.get("enabled") is bool: clean.enabled = payload.enabled
		"travel":
			if payload.get("route") is String: clean.route = str(payload.route).left(64)
		"move":
			var direction: Variant = payload.get("direction",Vector2.ZERO)
			var aim: Variant = payload.get("aim",Vector2.UP)
			if not direction is Vector2 or not aim is Vector2 or not direction.is_finite() or not aim.is_finite(): return {}
			return {"direction":direction.limit_length(1.0),"aim":aim.limit_length(1.0),"sprint":payload.get("sprint",false) == true,"crouch":payload.get("crouch",false) == true,"ads":payload.get("ads",false) == true}
		"transfer":
			for key in ["from","to","slot"]:
				if payload.get(key) is String: clean[key] = str(payload[key]).left(16)
			for key in ["index","target"]:
				if payload.get(key) is int: clean[key] = payload[key]
				elif payload.get(key) is String: clean[key] = str(payload[key]).left(16)
		"use","drop","equip":
			if payload.get("index") is int: clean.index = payload.index
		"split":
			if payload.get("container") is String: clean.container = str(payload.container).left(16)
			if payload.get("index") is int: clean.index = payload.index
			if payload.has("count"): clean.count = payload.count if payload.count is int else 0
		"pickup","door":
			if payload.get("uid") is String: clean.uid = str(payload.uid).left(64)
		"sort":
			if payload.get("container") is String: clean.container = str(payload.container).left(16)
		"unequip":
			if payload.get("slot") is String: clean.slot = str(payload.slot).left(16)
	return clean

func _allowed(sender: int, token: int, action: String) -> bool:
	if mode != "host" or token != _session_token or sender <= 1 or not model.state.players.has(sender): return false
	if action != "move" and not action in ACTIONS: return false
	var second := int(Time.get_ticks_msec() / 1000)
	var counter: Dictionary = _rate_limits.get(sender,{"second":second,"count":0})
	if int(counter.second) != second: counter = {"second":second,"count":0}
	counter.count += 1; _rate_limits[sender] = counter
	return counter.count <= 100

# GodotSteam 4.23.1 maps unreliable_ordered to reliable. Sequence checks below
# provide ordering while plain unreliable keeps movement out of retransmit queues.
@rpc("any_peer","call_remote","unreliable",1)
func _movement(payload: Dictionary, token: int, seq: int, world_revision: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if world_revision!=int(model.state.get("world_revision",0)): return
	if not _allowed(sender,token,"move") or seq <= int(_last_movement.get(sender,-1)): return
	var clean := _clean_payload("move",payload)
	if clean.is_empty(): return
	_last_movement[sender] = seq
	# This is an accepted input's authoritative starting point, not a client position.
	var p: Dictionary = model.state.players[sender]
	p.input_seq = seq; p.input_origin = p.pos; p.input_stamina = p.stamina
	p.input_weight = p.weight; p.input_max_weight = p.max_weight
	p.input_height = p.get("height",0.0)
	model.command(sender,"move",clean)

@rpc("any_peer","call_remote","reliable",0)
func _intent(action: String, payload: Dictionary, token: int, seq: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _allowed(sender,token,action) or seq <= int(_last_intent.get(sender,-1)): return
	if action=="unstuck" and payload.get("world_revision",-1)!=int(model.state.get("world_revision",0)):return
	_last_intent[sender] = seq
	var accepted: bool=model.command(sender,action,_clean_payload(action,payload))
	if accepted and action!="fire" and not room_store.path.is_empty():save_room()
	if not model.last_notice.is_empty(): _notice.rpc_id(sender,model.last_notice)
	state_changed.emit()
	_broadcast_snapshot(true)

@rpc("authority","call_remote","reliable",2)
func _snapshot(snapshot: Dictionary, token: int, seq: int, stamp: float) -> void:
	_receive_snapshot(snapshot,token,seq,stamp)

@rpc("authority","call_remote","reliable",0)
func _snapshot_control(snapshot: Dictionary, token: int, seq: int, stamp: float) -> void:
	_receive_snapshot(snapshot,token,seq,stamp)

func _receive_snapshot(snapshot: Dictionary, token: int, seq: int, stamp: float) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_apply_snapshot(snapshot,token,seq,stamp)

func _apply_snapshot(snapshot: Dictionary, token: int, seq: int, stamp: float) -> void:
	if mode != "client" or token == 0 or seq <= _received_serial: return
	if _session_token != 0 and token != _session_token: return
	_session_token = token; _received_serial = seq
	var changed_world: bool = int(snapshot.get("world_revision",0))!=int(model.state.get("world_revision",0)) or snapshot.get("world","bunker")!=model.state.get("world","bunker")
	if changed_world:
		reset_world_motion()
	# Reliable inventory can arrive behind a newer movement packet on another channel.
	# Apply its inventory/membership, but never rewind the already confirmed position.
	if seq < _received_motion_serial and not changed_world:
		for id in snapshot.players:
			if not model.state.players.has(id): continue
			snapshot.players[id].relocation_seq=model.state.players[id].get("relocation_seq",0)
			for key in MOTION_FIELDS:
				snapshot.players[id][key] = model.state.players[id][key]
	model.state = snapshot
	_snapshot_received_usec = Time.get_ticks_usec()
	motion_buffer.retain(model.state.players.keys())
	if seq > _received_motion_serial:
		_received_motion_serial = seq
		motion_buffer.push(model.state.players,stamp)
	_confirm_local_motion()
	state_changed.emit()

@rpc("authority","call_remote","unreliable",1)
func _motion_snapshot(rows: Array, token: int, seq: int, stamp: float, world_revision: int) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	_apply_motion(rows,token,seq,stamp,world_revision)

func _apply_motion(rows: Array, token: int, seq: int, stamp: float, world_revision: int = -1) -> void:
	if mode != "client" or _session_token == 0 or token != _session_token or seq <= _received_motion_serial: return
	if world_revision>=0 and world_revision!=int(model.state.get("world_revision",0)): return
	_received_motion_serial = seq
	for row in rows:
		if not model.state.players.has(row[0]): continue
		var p: Dictionary = model.state.players[row[0]]
		p.pos = row[1]; p.velocity = row[2]; p.aim = row[3]
		p.sprint = (int(row[4]) & 1) != 0
		p.crouch = (int(row[4]) & 2) != 0
		p.ads = (int(row[4]) & 4) != 0
		p.reloading = (int(row[4]) & 8) != 0
		p.anim_seq = row[5]; p.anim_action = row[6]; p.anim_time = row[7]; p.anim_duration = row[8]
		p.shots = row[9]; p.reload_progress = row[10]
		p.input_seq = row[11]; p.input_origin = row[12]; p.input_stamina = row[13]
		p.input_weight = row[14]; p.input_max_weight = row[15]
		p.height = row[16]; p.input_height = row[17]
		p.relocation_seq=int(row[18]) if row.size()>18 else 0
	motion_buffer.push(model.state.players,stamp)
	_confirm_local_motion()

func _confirm_local_motion() -> void:
	if model.state.players.has(local_id): local_movement.confirm(model.state.players[local_id])

func reset_world_motion() -> void:
	motion_buffer.clear(); local_movement.clear()
	_last_sent_move.clear(); _move_pending.clear()

func _motion_rows() -> Array:
	var rows: Array = []
	for id in model.state.players:
		var p: Dictionary = model.state.players[id]
		var flags := int(p.sprint) | (int(p.crouch) << 1) | (int(p.ads) << 2) | (int(p.reloading) << 3)
		rows.append([id,p.pos,p.velocity,p.aim,flags,p.anim_seq,p.anim_action,p.anim_time,p.anim_duration,p.shots,p.reload_progress,p.input_seq,p.input_origin,p.input_stamina,p.input_weight,p.input_max_weight,p.get("height",0.0),p.get("input_height",0.0),p.get("relocation_seq",0)])
	return rows

func snapshot_age() -> float:
	return (Time.get_ticks_usec() - _snapshot_received_usec) / 1000000.0 if mode == "client" else 0.0

func _broadcast_motion() -> void:
	if mode != "host" or _peer == null: return
	_snapshot_serial += 1
	var rows := _motion_rows()
	for peer_id in _connected_peers():
		_motion_snapshot.rpc_id(peer_id,rows,_session_token,_snapshot_serial,model._clock,int(model.state.get("world_revision",0)))

func _broadcast_snapshot(control: bool) -> void:
	if mode != "host" or _peer == null: return
	_snapshot_serial += 1
	for peer_id in _connected_peers():
		if control: _snapshot_control.rpc_id(peer_id,model.state,_session_token,_snapshot_serial,model._clock)
		else: _snapshot.rpc_id(peer_id,model.state,_session_token,_snapshot_serial,model._clock)

func _connected_peers() -> Array[int]:
	var peers: Array[int] = []
	for peer_id in multiplayer.get_peers():
		if _peer is ENetMultiplayerPeer:
			var enet_transport := (_peer as ENetMultiplayerPeer).get_peer(peer_id)
			if enet_transport == null or enet_transport.get_state() != ENetPacketPeer.STATE_CONNECTED: continue
		peers.append(peer_id)
	return peers

@rpc("authority","call_remote","reliable",0)
func _notice(message: String) -> void:
	if mode == "client" and multiplayer.get_remote_sender_id() == 1: notice.emit(message)

func can_accept_join() -> bool:
	return model.world_ready and model.state.get("world","bunker")=="bunker" and model.state.players.size()<5

func _on_peer_connected(peer_id: int) -> void:
	if mode != "host" or model.state.players.has(peer_id): return
	if not can_accept_join() or (peer_validator.is_valid() and not peer_validator.call(peer_id)):
		_peer.disconnect_peer(peer_id)
		return
	var player_name := "旅鸭 %d" % model.state.players.size()
	if peer_name_provider.is_valid(): player_name = str(peer_name_provider.call(peer_id)).left(24)
	model.add_player(peer_id,player_name)
	if not room_store.path.is_empty():
		var identity:=str(peer_identity_provider.call(peer_id)) if peer_identity_provider.is_valid() else ""
		if room_store.admit(model,peer_id,identity)!=OK:
			model.remove_player(peer_id);_peer.disconnect_peer(peer_id);return
		save_room()
	_broadcast_snapshot(true)
	notice.emit("一位旅鸭加入了基地")
	state_changed.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if mode != "host" or not model.state.players.has(peer_id): return
	if not room_store.path.is_empty():
		var saved: Error=room_store.detach(model,peer_id)
		if saved!=OK:notice.emit("离开玩家的房间存档失败："+error_string(saved))
	model.remove_player(peer_id)
	_voice_limits.erase(peer_id);_voice_sequences.erase(peer_id);voice_received.emit(peer_id,PackedByteArray())
	_last_movement.erase(peer_id); _last_intent.erase(peer_id); _rate_limits.erase(peer_id)
	_broadcast_snapshot(true)
	notice.emit("一位旅鸭离开了基地")
	state_changed.emit()

func _on_connected() -> void:
	if mode != "client": return
	local_id = multiplayer.get_unique_id()
	connection_status = "Steam 已连接 · 共建基地" if transport == "steam" else "已连接 · 共建基地"
	state_changed.emit()

func _on_connection_failed() -> void:
	if mode != "client": return
	var was_steam := transport == "steam"
	offline()
	connection_status = "Steam 连接失败：确认双方在线、使用不同账号且版本一致" if was_steam else "连接失败：检查房主IP、端口和防火墙"
	notice.emit(connection_status)
	state_changed.emit()

func _on_server_disconnected() -> void:
	if mode != "client": return
	var was_joining:=_session_token==0
	offline()
	connection_status = "房间暂不接受加入，请等房主回到基地后重试" if was_joining else "房主已离开，已返回本机离线基地"
	notice.emit(connection_status)
	state_changed.emit()

# Independent unreliable channel: voice loss must not delay movement/actions/snapshots.
func send_voice(bytes: PackedByteArray, sequence: int) -> void:
	if mode=="offline" or _session_token<=0:return
	if not is_inside_tree() or multiplayer.multiplayer_peer==null or multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
	var revision:=int(model.state.get("world_revision",0))
	if mode=="host":_route_voice(local_id,bytes,sequence,_session_token,revision)
	elif local_id>0:_voice_up.rpc_id(1,bytes,sequence,_session_token,revision)

@rpc("any_peer","call_remote","unreliable",3)
func _voice_up(bytes: PackedByteArray, sequence: int, token: int, revision: int) -> void:
	if mode=="host":_route_voice(multiplayer.get_remote_sender_id(),bytes,sequence,token,revision)

func _route_voice(speaker: int, bytes: PackedByteArray, sequence: int, token: int, revision: int) -> void:
	if not _accept_voice(speaker,bytes,sequence,token,revision):return
	for id in model.state.players:
		if int(id)==speaker:continue
		if not bytes.is_empty() and VoiceRules.gain(model.state.players,speaker,int(id))<=0:continue
		if int(id)==local_id:voice_received.emit(speaker,bytes)
		elif int(id) in _connected_peers():_voice_down.rpc_id(int(id),speaker,bytes,sequence,token,revision)

func _accept_voice(speaker: int, bytes: PackedByteArray, sequence: int, token: int, revision: int) -> bool:
	if token!=_session_token or token<=0 or revision!=int(model.state.get("world_revision",0)) or not model.world_ready:return false
	if not model.state.players.has(speaker) or bytes.size()>VoiceRules.MAX_PACKET:return false
	if sequence<=int(_voice_sequences.get(speaker,-1)):return false
	var now:=Time.get_ticks_msec()
	var budget: Dictionary=_voice_limits.get(speaker,{"since":now,"bytes":0,"packets":0})
	if now-int(budget.since)>=1000:budget={"since":now,"bytes":0,"packets":0}
	budget.bytes+=bytes.size();budget.packets+=1;_voice_limits[speaker]=budget
	if budget.bytes>65536 or budget.packets>80:return false
	_voice_sequences[speaker]=sequence
	return true

@rpc("authority","call_remote","unreliable",3)
func _voice_down(speaker: int, bytes: PackedByteArray, sequence: int, token: int, revision: int) -> void:
	if mode!="client" or multiplayer.get_remote_sender_id()!=1 or speaker==local_id:return
	if _accept_voice(speaker,bytes,sequence,token,revision):voice_received.emit(speaker,bytes)
