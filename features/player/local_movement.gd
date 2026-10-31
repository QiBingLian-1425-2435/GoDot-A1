extends RefCounted
## Provisional motion for this client only. Never writes BaseModel or sends final positions.
const Movement = preload("res://features/player/movement_rules.gd")
const INPUT_TIMEOUT := .35
const HISTORY_SECONDS := 2.0
const MAX_UNCONFIRMED := 1.0
const SNAP_DISTANCE := 3.0
# Less than the 0.32 m collision radius: do not slide a resting duck by one tick
# when the host and client sampled a key edge on adjacent physics frames.
const REST_ERROR_LIMIT := .12
const FIELDS := ["pos","velocity","aim","stamina","weight","max_weight","sprint","sprint_exhausted","crouch","ads"]
var solver: Callable
var spatial_solver: Callable
var _state: Dictionary = {}
var _input: Dictionary = {}
var _history: Array[Dictionary] = []
var _sent: Dictionary = {}
var _clock := 0.0
var _input_stamp := -100.0
var _last_ack_clock := 0.0
var _barrier := 0
var _last_ack := 0
var _observed_ack := 0
var _pending: Dictionary = {}
var _last_authority := Vector2.ZERO
var _has_authority := false
var _offset := Vector2.ZERO
var _display_pos := Vector2.ZERO
var _display_height := 0.0
var _settling := false
var _relocation_seq:=0
var infinite_stamina := false
var _hit_seq:=0
var _recoiling:=false
var _hit_settling:=false

func clear() -> void:
	_state.clear(); _input.clear(); _history.clear(); _sent.clear(); _pending.clear()
	_clock = 0; _input_stamp = -100; _last_ack_clock = 0; _barrier = 0; _last_ack = 0; _observed_ack = 0
	_has_authority = false; _offset = Vector2.ZERO; _display_pos = Vector2.ZERO
	_settling = false
	infinite_stamina = false
	_hit_seq=0;_recoiling=false
	_hit_settling=false

func set_input(input: Dictionary) -> void:
	# A new release takes priority over the small tail of a correction that began
	# while walking. Corrections received while already idle still settle normally.
	if not _hit_settling and not Vector2(_input.get("direction",Vector2.ZERO)).is_zero_approx() and Vector2(input.get("direction",Vector2.ZERO)).is_zero_approx() and _offset.length() <= REST_ERROR_LIMIT:
		_settling = false
	_input = input.duplicate()
	_input_stamp = _clock

func note_sent(seq: int, edge: bool) -> void:
	_sent[seq] = _clock
	if edge:
		_barrier = seq
		_pending.clear()

func confirm(p: Dictionary) -> void:
	if not _state.is_empty() and (_state.get("life","alive")!=p.get("life","alive") or _state.get("soul_speed",2)!=p.get("soul_speed",2)):clear()
	if int(p.get("relocation_seq",0))!=_relocation_seq:
		clear()
		_relocation_seq=int(p.get("relocation_seq",0))
	if not _state.is_empty():
		_state.max_stamina=p.get("max_stamina",100.0)
		_state.stamina=minf(_state.stamina,_state.max_stamina)
		_state.weight=p.weight
		_state.max_weight=p.max_weight
	var pose := _copy_motion(p)
	# A hit invalidates pre-impact input anchors. Resume ordinary replay only
	# after the host confirms recoil ended; never replay walking through a hit.
	var hit_seq:int=int(p.get("hit_seq",0))
	var recoiling:bool=not Vector2(p.get("knockback",Vector2.ZERO)).is_zero_approx()
	if hit_seq!=_hit_seq or recoiling or _recoiling:
		_offset=_display_pos-Vector2(p.pos) if not _state.is_empty() else Vector2.ZERO
		if _offset.length()>SNAP_DISTANCE:_offset=Vector2.ZERO
		_settling=true;_hit_settling=true;_state=pose
		_history.clear();_sent.clear();_pending.clear()
		_last_ack=int(p.get("input_seq",0));_observed_ack=_last_ack;_barrier=_last_ack
		_last_ack_clock=_clock;_last_authority=p.pos;_has_authority=true
		_hit_seq=hit_seq;_recoiling=recoiling
		return
	if _state.is_empty() or (_has_authority and _last_authority.distance_to(p.pos) > SNAP_DISTANCE):
		_state = pose
		_display_pos = p.pos
		_display_height = float(p.get("height",0))
		_offset = Vector2.ZERO
		_settling = false
		_history.clear(); _sent.clear(); _pending.clear()
		_last_ack = 0; _observed_ack = 0; _barrier = 0; _last_ack_clock = _clock
	_last_authority = p.pos
	_has_authority = true
	var seq := int(p.get("input_seq",0))
	if seq <= _last_ack or not _sent.has(seq): return
	if seq > _observed_ack:
		_observed_ack = seq
		_last_ack_clock = _clock
	# A delayed old direction cannot drag a newly stopped/reversed local character.
	if seq < _barrier: return
	pose.pos = p.input_origin
	pose.stamina = p.input_stamina
	pose.sprint_exhausted = p.get("input_sprint_exhausted",false)
	pose.weight = p.input_weight
	pose.max_weight = p.input_max_weight
	pose.height = p.get("input_height",p.get("height",0.0))
	pose.roll=p.get("input_roll",Movement.empty_roll()).duplicate(true)
	_pending = {"seq":seq,"start":float(_sent[seq]),"pose":pose}

func advance(delta: float, authoritative: Dictionary) -> void:
	if (authoritative.get("life","")=="soul" and int(authoritative.get("possessing",0))>0) or (float(authoritative.get("hp",100))<=0 and authoritative.get("life","alive") not in ["soul","zombie"]):
		clear()
		return
	if delta <= 0 or not solver.is_valid(): return
	delta = minf(delta,.1)
	if _state.is_empty(): confirm(authoritative)
	_state.infinite_stamina = infinite_stamina
	if not _pending.is_empty():
		var corrected: Dictionary = _pending.pose
		for frame in _history:
			var duration := float(frame.end)-maxf(float(frame.start),float(_pending.start))
			if duration > .000001: Movement.step(corrected,frame.input,duration,_solve.bind(corrected))
		var error: Vector2 = _state.pos-corrected.pos
		_offset += error
		if _offset.length() > REST_ERROR_LIMIT: _settling = true
		if _offset.length() > SNAP_DISTANCE: _offset = Vector2.ZERO; _settling = false
		_state = corrected
		_last_ack = _pending.seq
		_pending.clear()
	var input := _input if _clock-_input_stamp <= INPUT_TIMEOUT else {}
	if _clock-_last_ack_clock > MAX_UNCONFIRMED:
		# A lost outbound stream must not accumulate unbounded prediction.
		input = {}
		_state = _copy_motion(authoritative)
		_offset = Vector2.ZERO
		_settling = false
	# Capacity drifts with hunger. Updating stats must not discard unacknowledged
	# movement or snap presentation back by the network round-trip distance.
	_state.max_stamina=authoritative.get("max_stamina",100.0)
	_state.weight=authoritative.get("weight",_state.weight)
	_state.max_weight=authoritative.get("max_weight",_state.max_weight)
	_state.hp=authoritative.get("hp",100.0)
	_state.jump_chain_bonus=authoritative.get("jump_chain_bonus",150)
	_state.jump_chain_max_speed=authoritative.get("jump_chain_max_speed",18)
	_state.jump_reward_window_ms=authoritative.get("jump_reward_window_ms",70)
	Movement.step(_state,input,delta,_solve.bind(_state))
	_history.append({"start":_clock,"end":_clock+delta,"input":input.duplicate()})
	_clock += delta
	while not _history.is_empty() and float(_history.front().end) < _clock-HISTORY_SECONDS: _history.pop_front()
	for seq in _sent.keys():
		if float(_sent[seq]) < _clock-HISTORY_SECONDS: _sent.erase(seq)
	if _settling:
		_offset *= exp(-delta*25.0)
	elif not Vector2(input.get("direction",Vector2.ZERO)).is_zero_approx():
		# Releasing a held offset must not overpower a slow crouched step or a wall.
		var correction := minf(_offset.length()*(1.0-exp(-delta*25.0)),Vector2(_state.velocity).length()*delta*.5)
		_offset = _offset.move_toward(Vector2.ZERO,correction)
	if _offset.length() < .001: _offset = Vector2.ZERO; _settling = false;_hit_settling=false
	# Apply the display correction through the same static-world collision shape.
	var display_pose:Dictionary=_state.duplicate(true)
	display_pose.roll.vertical_delta=0.0
	var corrected_position: Variant = _solve(_state.pos,_offset,display_pose)
	if corrected_position is Vector3:
		_display_pos = Vector2(corrected_position.x,corrected_position.z)
		_display_height = corrected_position.y
	else:
		_display_pos = corrected_position
		_display_height=float(_state.get("height",0))
	_offset = _display_pos-Vector2(_state.pos)

func sample_player(authoritative: Dictionary) -> Dictionary:
	var display := authoritative.duplicate()
	if (authoritative.get("life","")=="soul" and int(authoritative.get("possessing",0))>0) or (float(authoritative.get("hp",100))<=0 and authoritative.get("life","alive") not in ["soul","zombie"]): return display
	if _state.is_empty(): return display
	for key in ["velocity","aim","sprint","crouch","ads"]: display[key] = _state[key]
	display.roll = _state.get("roll",Movement.empty_roll()).duplicate(true)
	display.pos = _display_pos
	display.height = _display_height
	return display

func _solve(from: Vector2, offset: Vector2, pose: Dictionary) -> Variant:
	if pose.get("life","")=="soul":
		var bounds: Rect2=pose.get("soul_bounds",Rect2(-10000,-10000,20000,20000))
		var point: Vector2=(from+offset).clamp(bounds.position,bounds.end)
		return Vector3(point.x,float(pose.get("height",0)),point.y)
	if spatial_solver.is_valid():
		return spatial_solver.call(Vector3(from.x,float(pose.get("height",0)),from.y),offset,pose.get("roll",{}))
	return solver.call(from,offset)

func _copy_motion(p: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in FIELDS: result[key] = p[key]
	result.max_stamina = p.get("max_stamina",100.0)
	result.jump_chain_bonus=p.get("jump_chain_bonus",150)
	result.jump_chain_max_speed=p.get("jump_chain_max_speed",18)
	result.jump_reward_window_ms=p.get("jump_reward_window_ms",70)
	result.height = p.get("height",0.0)
	result.roll=p.get("roll",Movement.empty_roll()).duplicate(true)
	result.infinite_stamina = infinite_stamina
	result.knockback=p.get("knockback",Vector2.ZERO)
	result.hit_seq=p.get("hit_seq",0)
	for key in ["reloading","pending_use","loot_uid","hp","life","soul_speed","soul_bounds","possessing"]:
		if p.has(key):result[key]=p[key]
	return result
