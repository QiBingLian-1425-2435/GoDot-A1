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
const FIELDS := ["pos","velocity","aim","stamina","weight","max_weight","sprint","crouch","ads"]
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

func clear() -> void:
	_state.clear(); _input.clear(); _history.clear(); _sent.clear(); _pending.clear()
	_clock = 0; _input_stamp = -100; _last_ack_clock = 0; _barrier = 0; _last_ack = 0; _observed_ack = 0
	_has_authority = false; _offset = Vector2.ZERO; _display_pos = Vector2.ZERO
	_settling = false

func set_input(input: Dictionary) -> void:
	# A new release takes priority over the small tail of a correction that began
	# while walking. Corrections received while already idle still settle normally.
	if not Vector2(_input.get("direction",Vector2.ZERO)).is_zero_approx() and Vector2(input.get("direction",Vector2.ZERO)).is_zero_approx() and _offset.length() <= REST_ERROR_LIMIT:
		_settling = false
	_input = input.duplicate()
	_input_stamp = _clock

func note_sent(seq: int, edge: bool) -> void:
	_sent[seq] = _clock
	if edge:
		_barrier = seq
		_pending.clear()

func confirm(p: Dictionary) -> void:
	if int(p.get("relocation_seq",0))!=_relocation_seq:
		clear()
		_relocation_seq=int(p.get("relocation_seq",0))
	var pose := _copy_motion(p)
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
	pose.weight = p.input_weight
	pose.max_weight = p.input_max_weight
	pose.height = p.get("input_height",p.get("height",0.0))
	pose.roll=p.get("input_roll",Movement.empty_roll()).duplicate(true)
	_pending = {"seq":seq,"start":float(_sent[seq]),"pose":pose}

func advance(delta: float, authoritative: Dictionary) -> void:
	if delta <= 0 or not solver.is_valid(): return
	delta = minf(delta,.1)
	if _state.is_empty(): confirm(authoritative)
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
	if _offset.length() < .001: _offset = Vector2.ZERO; _settling = false
	# Apply the display correction through the same static-world collision shape.
	var corrected_position: Variant = _solve(_state.pos,_offset,_state)
	if corrected_position is Vector3:
		_display_pos = Vector2(corrected_position.x,corrected_position.z)
		_display_height = corrected_position.y
	else: _display_pos = corrected_position
	_offset = _display_pos-Vector2(_state.pos)

func sample_player(authoritative: Dictionary) -> Dictionary:
	var display := authoritative.duplicate()
	if _state.is_empty(): return display
	for key in ["velocity","aim","sprint","crouch","ads"]: display[key] = _state[key]
	display.roll = _state.get("roll",Movement.empty_roll()).duplicate(true)
	display.pos = _display_pos
	if spatial_solver.is_valid(): display.height = _display_height
	return display

func _solve(from: Vector2, offset: Vector2, pose: Dictionary) -> Variant:
	if spatial_solver.is_valid():
		return spatial_solver.call(Vector3(from.x,float(pose.get("height",0)),from.y),offset)
	return solver.call(from,offset)

func _copy_motion(p: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in FIELDS: result[key] = p[key]
	result.height = p.get("height",0.0)
	result.roll=p.get("roll",Movement.empty_roll()).duplicate(true)
	for key in ["reloading","pending_use","loot_uid","hp"]:
		if p.has(key):result[key]=p[key]
	return result
