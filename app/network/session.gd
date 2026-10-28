extends Node
const Texts = preload("res://features/localization/game_text.gd")
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
const MOTION_FIELDS := ["pos","height","velocity","aim","sprint","sprint_exhausted","crouch","ads","reloading","reload_progress","shots","anim_seq","anim_action","anim_time","anim_duration","input_seq","input_origin","input_height","input_stamina","input_sprint_exhausted","input_weight","input_max_weight","roll","input_roll","knockback","hit_seq"]
const DEFAULT_PORT := 24567
const ACTIONS := ["appearance","soul_speed","suicide","soul_wait","possess","release_soul","rescue","rescue_cancel","return_camp","transfer","split","use","drop","pickup","sort","reload","fire","equip","unequip","select_weapon","rest","craft","buy_ammo","resupply_ammo","set_infinite_reserve","set_infinite_stamina","set_infinite_credits","train","reset_targets","travel","door","unstuck","buy","sell","search","loot_view","craft_item","loot_take","loot_close","camp_upgrade"]
var _roll_seq := 0
var _roll_capture := false
var _roll_direction := Vector2.UP
var model = Model.new()
var local_id := 1
var mode := "offline"
var connection_status := "⟦session.001⟧"
var _peer: MultiplayerPeer
var transport := "offline"
var peer_validator: Callable
var peer_name_provider: Callable
var _snapshot_clock := 0.0
var _motion_clock := 0.0
var _snapshot_serial := 0
var _received_serial := -1
var _received_motion_serial := -1
var _received_enemy_serial := -1
var _enemy_serials: Dictionary = {}
var _snapshot_received_usec := 0
# Presentation events survive snapshot replacement; age starts at first receipt.
var _shot_visuals: Array[Dictionary] = []
var _shot_seen: Dictionary = {}
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
var upgrade_checkpoint:Callable
var _local_camp:Dictionary=Model.Camp.initial()
var peer_identity_provider: Callable
var _room_save_clock:=0.0

func _init() -> void:
	name = "Session"
	model.add_player(1,"⟦session.002⟧")
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
		connection_status = "⟦session.003⟧"; notice.emit(connection_status)
		return ERR_INVALID_PARAMETER
	var enet := ENetMultiplayerPeer.new()
	_peer = enet
	var error := enet.create_server(port,4)
	if error != OK:
		_peer = null
		connection_status = Texts.format("⟦session.004⟧", error_string(error))
		notice.emit(connection_status)
		return error
	multiplayer.multiplayer_peer = _peer
	multiplayer.server_relay = false
	mode = "host"; transport = "enet"; local_id = 1; _session_token = randi_range(1,2147483647)
	connection_status = Texts.format("⟦session.005⟧", port)
	state_changed.emit()
	return OK

func join(address: String, port: int = DEFAULT_PORT) -> Error:
	offline()
	address = address.strip_edges().left(253)
	if address.is_empty() or port < 1024 or port > 65535:
		connection_status = "⟦session.006⟧"; notice.emit(connection_status)
		return ERR_INVALID_PARAMETER
	var enet := ENetMultiplayerPeer.new()
	_peer = enet
	var error := enet.create_client(address,port)
	if error != OK:
		_peer = null
		connection_status = Texts.format("⟦session.007⟧", error_string(error)); notice.emit(connection_status)
		return error
	model.state.players.clear()
	multiplayer.multiplayer_peer = _peer
	mode = "client"; transport = "enet"; local_id = 0; _connect_elapsed = 0.0
	connection_status = Texts.format("⟦session.008⟧", [address,port])
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
	connection_status = "⟦session.009⟧" if as_host else "⟦session.010⟧"
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
	if result!=OK:notice.emit("⟦session.011⟧"+error_string(result)+"⟦session.012⟧")
	return result

func offline() -> void:
	_roll_seq=0;_roll_capture=false
	if not room_store.path.is_empty():save_room()
	if mode!="client" and room_store.path.is_empty():_local_camp=model.state.camp.duplicate()
	room_store.clear();peer_identity_provider=Callable()
	if mode == "client":
		model.state.infinite_reserve = false
		model.state.infinite_credits = false
	if mode != "client" and model.state.players.has(local_id):
		_local_profile = model.state.players[local_id].duplicate(true)
	if is_inside_tree(): multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _peer != null: _peer.close(); _peer = null
	mode = "offline"; transport = "offline"; local_id = 1; connection_status = "⟦session.001⟧"
	peer_validator = Callable(); peer_name_provider = Callable()
	model.state.field_effects=[];model.state.containers={}
	model.state.corpses={}
	model.state.camp=_local_camp.duplicate()
	model.state.enemies={};model.state.enemies_seeded=false
	_received_enemy_serial=-1
	_enemy_serials.clear()
	model.state.players.clear(); model.state.drops.clear(); model.state.shots.clear()
	model.state.world = "bunker"; model.state.phase = "base"
	model.state.world_revision = int(model.state.get("world_revision",0))+1
	if model.world_cache.has("bunker"): model.state.targets = model.world_cache.bunker.targets
	model.world_cache.clear()
	model.state.doors={}
	model._inputs.clear()
	model._recovery_after.clear()
	model.add_player(1,"⟦session.002⟧")
	if not _local_profile.is_empty():
		model.state.players[1] = _local_profile.duplicate(true)
		model.state.players[1].id = 1
		model.state.players[1].pos = Vector2(-1,4)
		model.state.players[1].height = 0.0
		model.state.players[1].reloading = false
		model.state.players[1].fire_timer = 0.0
	model.Camp.refresh_player(model,model.state.players[1])
	model.reset_transients(1)
	if not model.Souls.alive(model.state.players[1]): model.Souls.revive(model,model.state.players[1])
	_voice_limits.clear(); _voice_sequences.clear()
	_shot_visuals.clear(); _shot_seen.clear()
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
	connection_status = "⟦session.013⟧"
	state_changed.emit()

func request_roll() -> void:
	_roll_capture=true
	_roll_seq = maxi(_roll_seq,int(model.state.players.get(local_id,{}).get("roll",{}).get("seen",0)))+1

func send(action: String, payload: Dictionary = {}) -> void:
	if action == "move":
		payload=payload.duplicate(); payload.roll_seq=_roll_seq
		if _roll_capture:
			var direction:Vector2=payload.get("direction",Vector2.ZERO)
			_roll_direction=direction.normalized() if not direction.is_zero_approx() else Vector2(payload.get("aim",Vector2.UP)).normalized()
			_roll_capture=false
		payload.roll_direction=_roll_direction
	var clean := _clean_payload(action,payload)
	if action in ["soul_speed","suicide","soul_wait","possess","release_soul","rescue","rescue_cancel","return_camp","unstuck","use","search","loot_view","buy","sell","craft_item","loot_take","loot_close","camp_upgrade"]:clean.world_revision=int(model.state.get("world_revision",0))
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
		var accepted: bool=_execute_command(local_id,action,clean)
		if accepted and action not in ["move","fire","camp_upgrade"] and not room_store.path.is_empty():save_room()
		if not model.last_notice.is_empty():
			notice.emit(model.last_notice)
			if accepted and action=="camp_upgrade" and mode=="host":_notice.rpc(model.last_notice)
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
		local_movement.infinite_stamina = bool(model.state.get("infinite_stamina",false))
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
	for key in ["sprint","crouch","ads","roll_seq"]:
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
	if payload.get("world_revision") is int:clean.world_revision=payload.world_revision
	match action:
		"soul_speed":
			if payload.get("speed") is int:clean.speed=payload.speed
		"appearance":
			if Model.Appearance.valid(payload):return Model.Appearance.normalized(payload)
		"possess","rescue":
			if payload.get("target") is int: clean.target = payload.target
			if action=="rescue" and payload.get("uid") is String: clean.uid=str(payload.uid).left(64)
		"camp_upgrade":
			if payload.get("facility") is String:clean.facility=str(payload.facility).left(24)
			if payload.get("expected_level") is int:clean.expected_level=payload.expected_level
		"unstuck":
			if payload.get("world_revision") is int:clean.world_revision=payload.world_revision
		"set_infinite_reserve":
			if payload.get("enabled") is bool: clean.enabled = payload.enabled
		"set_infinite_stamina", "set_infinite_credits":
			if payload.get("enabled") is bool: clean.enabled = payload.enabled
		"travel":
			if payload.get("route") is String: clean.route = str(payload.route).left(64)
		"move":
			var direction: Variant = payload.get("direction",Vector2.ZERO)
			var aim: Variant = payload.get("aim",Vector2.UP)
			var roll_direction:Variant=payload.get("roll_direction",direction)
			if not roll_direction is Vector2 or not roll_direction.is_finite():return {}
			if not direction is Vector2 or not aim is Vector2 or not direction.is_finite() or not aim.is_finite(): return {}
			return {"roll_direction":roll_direction.limit_length(1.0),"direction":direction.limit_length(1.0),"aim":aim.limit_length(1.0),"sprint":payload.get("sprint",false) == true,"crouch":payload.get("crouch",false) == true,"ads":payload.get("ads",false) == true,"roll_seq":clampi(int(payload.get("roll_seq",0)),0,2147483647) if payload.get("roll_seq",0) is int else 0}
		"transfer":
			for key in ["from","to","slot"]:
				if payload.get(key) is String: clean[key] = str(payload[key]).left(16)
			for key in ["index","target"]:
				if payload.get(key) is int: clean[key] = payload[key]
				elif payload.get(key) is String: clean[key] = str(payload[key]).left(16)
		"use","drop","equip","sell":
			if action=="sell":clean.count=payload.get("count") if payload.get("count") is int else 0
			if payload.get("index") is int: clean.index = payload.index
			if payload.get("uid") is String:clean.uid=str(payload.uid).left(64)
		"split":
			if payload.get("container") is String: clean.container = str(payload.container).left(16)
			if payload.get("index") is int: clean.index = payload.index
			if payload.has("count"): clean.count = payload.count if payload.count is int else 0
		"pickup","door","search","loot_view":
			if payload.get("uid") is String: clean.uid = str(payload.uid).left(64)
		"loot_take","loot_close":
			if payload.get("uid") is String:clean.uid=str(payload.uid).left(64)
			if payload.get("item_uid") is String:clean.item_uid=str(payload.item_uid).left(64)
			if payload.get("index") is int:clean.index=payload.index
		"buy","craft_item":
			if payload.get("kind") is String:clean.kind=str(payload.kind).left(32)
			if payload.has("count"):clean.count=payload.count if payload.count is int else 0
		"sort":
			if payload.get("mode") is String:clean.mode=str(payload.mode).left(16)
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
	p.input_seq = seq; p.input_origin = p.pos; p.input_stamina = p.stamina; p.input_sprint_exhausted = p.get("sprint_exhausted",false)
	p.input_weight = p.weight; p.input_max_weight = p.max_weight
	p.input_height = p.get("height",0.0)
	p.input_roll=p.get("roll",Model.Movement.empty_roll()).duplicate(true)
	model.command(sender,"move",clean)

@rpc("any_peer","call_remote","reliable",0)
func _intent(action: String, payload: Dictionary, token: int, seq: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _allowed(sender,token,action) or seq <= int(_last_intent.get(sender,-1)): return
	if action=="unstuck" and payload.get("world_revision",-1)!=int(model.state.get("world_revision",0)):return
	_last_intent[sender] = seq
	if action in ["soul_speed","suicide","soul_wait","possess","release_soul","rescue","rescue_cancel","return_camp","use","search","loot_view","buy","sell","craft_item","loot_take","loot_close","camp_upgrade"] and payload.get("world_revision",-1)!=int(model.state.get("world_revision",0)):return
	var accepted: bool=_execute_command(sender,action,_clean_payload(action,payload))
	if accepted and action not in ["fire","camp_upgrade"] and not room_store.path.is_empty():save_room()
	if not model.last_notice.is_empty():
		if accepted and action=="camp_upgrade":
			notice.emit(model.last_notice);_notice.rpc(model.last_notice)
		else:_notice.rpc_id(sender,model.last_notice)
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
	if mode != "client" or token == 0: return
	if _session_token != 0 and token != _session_token: return
	if seq <= _received_serial:
		# An inventory snapshot on another reliable channel may overtake a fire
		# snapshot. Keep its unseen shot events without rewinding shared state.
		if int(snapshot.get("world_revision",0))==int(model.state.get("world_revision",0)) and snapshot.get("world","bunker")==model.state.get("world","bunker"):
			_capture_shot_visuals(snapshot.get("shots",[]))
		return
	_session_token = token; _received_serial = seq
	var changed_world: bool = int(snapshot.get("world_revision",0))!=int(model.state.get("world_revision",0)) or snapshot.get("world","bunker")!=model.state.get("world","bunker")
	if changed_world:
		reset_world_motion()
	if not changed_world:
		for enemy_id in snapshot.get("enemies",{}):
			if int(_enemy_serials.get(enemy_id,-1))>seq and model.state.get("enemies",{}).has(enemy_id):
				snapshot.enemies[enemy_id]=model.state.enemies[enemy_id].duplicate(true)
	_received_enemy_serial=maxi(_received_enemy_serial,seq)
	# Reliable inventory can arrive behind a newer movement packet on another channel.
	# Apply its inventory/membership, but never rewind the already confirmed position.
	if seq < _received_motion_serial and not changed_world:
		for id in snapshot.players:
			if not model.state.players.has(id): continue
			snapshot.players[id].relocation_seq=model.state.players[id].get("relocation_seq",0)
			for key in MOTION_FIELDS:
				snapshot.players[id][key] = model.state.players[id][key]
	model.state = snapshot
	_capture_shot_visuals(snapshot.get("shots",[]))
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
		p.roll=_unpack_roll(row[19],0) if row.size()>19 else Model.Movement.empty_roll()
		p.input_roll=_unpack_roll(row[19],10) if row.size()>19 else p.roll.duplicate(true)
		p.sprint_exhausted=bool(int(row[4]) & 16)
		p.input_sprint_exhausted=bool(int(row[4]) & 32)
		p.knockback=Vector2(int(row[19][20])-128,int(row[19][21])-128)/20.0 if row[19].size()>=24 else Vector2.ZERO
		p.hit_seq=row[19].decode_u16(22) if row[19].size()>=24 else 0
	motion_buffer.push(model.state.players,stamp)
	_confirm_local_motion()

func _confirm_local_motion() -> void:
	if model.state.players.has(local_id): local_movement.confirm(model.state.players[local_id])

func reset_world_motion() -> void:
	_shot_visuals.clear(); _shot_seen.clear()
	_received_enemy_serial=-1
	_enemy_serials.clear()
	_roll_capture=false
	_roll_seq=int(model.state.players.get(local_id,{}).get("roll",{}).get("seen",0))
	motion_buffer.clear(); local_movement.clear()
	_last_sent_move.clear(); _move_pending.clear()

func _pack_roll(p: Dictionary) -> PackedByteArray:
	# Millisecond timers and quantized angle keep the five-player motion packet below MTU.
	var bytes := PackedByteArray(); bytes.resize(24)
	for index in range(2):
		var roll: Dictionary = p.get("roll" if index==0 else "input_roll",Model.Movement.empty_roll())
		var offset := index*10
		bytes.encode_u32(offset,int(roll.seen))
		bytes.encode_u16(offset+4,roundi(float(roll.time)*1000) | (32768 if roll.active else 0))
		bytes.encode_u16(offset+6,roundi(float(roll.cooldown)*1000))
		bytes.encode_u16(offset+8,roundi(fposmod(Vector2(roll.direction).angle(),TAU)/TAU*65535))
	var recoil:Vector2=p.get("knockback",Vector2.ZERO)
	bytes[20]=clampi(roundi(recoil.x*20)+128,0,255)
	bytes[21]=clampi(roundi(recoil.y*20)+128,0,255)
	bytes.encode_u16(22,int(p.get("hit_seq",0))%65536)
	return bytes

func _unpack_roll(bytes: PackedByteArray, offset: int) -> Dictionary:
	if bytes.size() not in [20,24]:return Model.Movement.empty_roll()
	var time_and_flag := bytes.decode_u16(offset+4)
	return {"seen":bytes.decode_u32(offset),"active":bool(time_and_flag & 32768),"time":float(time_and_flag & 32767)/1000.0,"cooldown":float(bytes.decode_u16(offset+6))/1000.0,"direction":Vector2.from_angle(float(bytes.decode_u16(offset+8))/65535.0*TAU)}

func _motion_rows() -> Array:
	var rows: Array = []
	for id in model.state.players:
		var p: Dictionary = model.state.players[id]
		var flags := int(p.sprint) | (int(p.crouch) << 1) | (int(p.ads) << 2) | (int(p.reloading) << 3) | (int(p.get("sprint_exhausted",false)) << 4) | (int(p.get("input_sprint_exhausted",false)) << 5)
		rows.append([id,p.pos,p.velocity,p.aim,flags,p.anim_seq,p.anim_action,p.anim_time,p.anim_duration,p.shots,p.reload_progress,p.input_seq,p.input_origin,p.input_stamina,p.input_weight,p.input_max_weight,p.get("height",0.0),p.get("input_height",0.0),p.get("relocation_seq",0),_pack_roll(p)])
	return rows

func _capture_shot_visuals(shots: Array) -> void:
	for shot in shots:
		var id:=int(shot.get("player_id",0))
		var sequence:=int(shot.get("sequence",0))
		var seen:Dictionary=_shot_seen.get(id,{"latest":0,"sequences":{}})
		if sequence<=0 or sequence<int(seen.latest)-64 or seen.sequences.has(sequence) or float(shot.get("ttl",0))<=0: continue
		seen.latest=maxi(seen.latest,sequence)
		seen.sequences[sequence]=true
		for previous in seen.sequences.keys():
			if int(previous)<int(seen.latest)-64:seen.sequences.erase(previous)
		_shot_seen[id]=seen
		_shot_visuals.append({"shot":shot.duplicate(true),"received":Time.get_ticks_usec()})
		while _shot_visuals.size()>64:_shot_visuals.pop_front()

func visual_shots() -> Array:
	if mode!="client":return model.state.get("shots",[])
	var result:Array=[]
	var now:=Time.get_ticks_usec()
	for i in range(_shot_visuals.size()-1,-1,-1):
		var event:Dictionary=_shot_visuals[i]
		var age:float=(now-int(event.received))/1000000.0
		if age>=.16:
			_shot_visuals.remove_at(i);continue
		var shot:Dictionary=event.shot.duplicate(true)
		shot.ttl=.16-age
		result.push_front(shot)
	return result

func snapshot_age() -> float:
	return (Time.get_ticks_usec() - _snapshot_received_usec) / 1000000.0 if mode == "client" else 0.0

func _broadcast_motion() -> void:
	if mode != "host" or _peer == null: return
	_snapshot_serial += 1
	var rows := _motion_rows()
	for peer_id in _connected_peers():
		_motion_snapshot.rpc_id(peer_id,rows,_session_token,_snapshot_serial,model._clock,int(model.state.get("world_revision",0)))
		if not model.state.get("enemies",{}).is_empty():
			for batch in _enemy_batches():
				_enemy_snapshot.rpc_id(peer_id,batch,_session_token,_snapshot_serial,int(model.state.get("world_revision",0)))

func _enemy_batches() -> Array:
	var rows:=_enemy_rows()
	var batches:Array=[]
	for start in range(0,rows.size(),4):batches.append(rows.slice(start,start+4))
	return batches

func _enemy_rows() -> Array:
	var rows:Array=[]
	for e in model.state.get("enemies",{}).values():
		rows.append([e.id,e.pos,e.height,e.velocity,e.hp,e.mode,e.timer,e.attack_seq,e.aim])
	return rows

@rpc("authority","call_remote","unreliable",1)
func _enemy_snapshot(rows:Array, token:int, seq:int, revision:int) -> void:
	if multiplayer.get_remote_sender_id()!=1:return
	_apply_enemies(rows,token,seq,revision)

func _apply_enemies(rows:Array, token:int, seq:int, revision:int) -> void:
	if mode!="client" or _session_token==0 or token!=_session_token or seq<=_received_serial or revision!=int(model.state.get("world_revision",0)):return
	_received_enemy_serial=maxi(_received_enemy_serial,seq)
	for row in rows:
		if not model.state.get("enemies",{}).has(row[0]):continue
		if seq<=int(_enemy_serials.get(row[0],-1)):continue
		_enemy_serials[row[0]]=seq
		var e:Dictionary=model.state.enemies[row[0]]
		e.pos=row[1];e.height=row[2];e.velocity=row[3];e.hp=row[4];e.mode=row[5];e.timer=row[6];e.attack_seq=row[7];e.aim=row[8]

func _broadcast_snapshot(control: bool) -> void:
	if mode != "host" or _peer == null: return
	_snapshot_serial += 1
	var public:Dictionary=model.Loot.public_state(model.state)
	for peer_id in _connected_peers():
		if control: _snapshot_control.rpc_id(peer_id,public,_session_token,_snapshot_serial,model._clock)
		else: _snapshot.rpc_id(peer_id,public,_session_token,_snapshot_serial,model._clock)

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
	var player_name := Texts.format("⟦session.014⟧", model.state.players.size())
	if peer_name_provider.is_valid(): player_name = Texts.clip(str(peer_name_provider.call(peer_id)),24)
	model.add_player(peer_id,player_name)
	if not room_store.path.is_empty():
		var identity:=str(peer_identity_provider.call(peer_id)) if peer_identity_provider.is_valid() else ""
		if room_store.admit(model,peer_id,identity)!=OK:
			model.remove_player(peer_id);_peer.disconnect_peer(peer_id);return
		save_room()
	_broadcast_snapshot(true)
	notice.emit("⟦session.015⟧")
	state_changed.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if mode != "host" or not model.state.players.has(peer_id): return
	if not room_store.path.is_empty():
		var saved: Error=room_store.detach(model,peer_id)
		if saved!=OK:notice.emit("⟦session.016⟧"+error_string(saved))
	model.remove_player(peer_id)
	_voice_limits.erase(peer_id);_voice_sequences.erase(peer_id);voice_received.emit(peer_id,PackedByteArray())
	_last_movement.erase(peer_id); _last_intent.erase(peer_id); _rate_limits.erase(peer_id)
	_broadcast_snapshot(true)
	notice.emit("⟦session.017⟧")
	state_changed.emit()

func _on_connected() -> void:
	if mode != "client": return
	local_id = multiplayer.get_unique_id()
	connection_status = "⟦session.018⟧" if transport == "steam" else "⟦session.019⟧"
	state_changed.emit()

func _on_connection_failed() -> void:
	if mode != "client": return
	var was_steam := transport == "steam"
	offline()
	connection_status = "⟦session.020⟧" if was_steam else "⟦session.021⟧"
	notice.emit(connection_status)
	state_changed.emit()

func _on_server_disconnected() -> void:
	if mode != "client": return
	var was_joining:=_session_token==0
	offline()
	connection_status = "⟦session.022⟧" if was_joining else "⟦session.023⟧"
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

# Candidate state is never published until the matching assets and camp save succeeds.
func _execute_command(id:int,action:String,payload:Dictionary) -> bool:
	if action!="camp_upgrade":return model.command(id,action,payload)
	var trial=Model.new()
	trial.state=model.state.duplicate(true);trial.stations=model.stations;trial.world_ready=model.world_ready
	if not trial.command(id,action,payload):return model._reject(trial.last_notice)
	var result:Error=ERR_UNCONFIGURED
	if not room_store.path.is_empty():result=room_store.checkpoint(trial)
	elif upgrade_checkpoint.is_valid():result=upgrade_checkpoint.call(trial)
	if result!=OK:return model._reject("⟦session.024⟧"+error_string(result))
	model.state.camp=trial.state.camp
	model.state.players[id].bag=trial.state.players[id].bag
	model.state.players[id].credits=trial.state.players[id].credits
	model.Camp.refresh_all(model)
	model.last_notice=trial.last_notice
	return true
