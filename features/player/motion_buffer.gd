extends RefCounted
## Presentation only: interpolate confirmed positions; never write model/physics state.
const DELAY := 0.10
const TELEPORT_DISTANCE := 3.0
const MAX_SAMPLES := 32
var _samples: Array[Dictionary] = []
var _render_time := 0.0
var _since_snapshot := 0.0

func clear() -> void:
	_samples.clear()
	_render_time = 0.0
	_since_snapshot = 0.0

func push(players: Dictionary, stamp: float) -> void:
	if not _samples.is_empty() and stamp < float(_samples.back().time): return
	var poses: Dictionary = {}
	for id in players:
		var p: Dictionary = players[id]
		poses[id] = {"pos":p.pos,"height":p.get("height",0.0),"velocity":p.get("velocity",Vector2.ZERO),"aim":p.aim,"relocation_seq":p.get("relocation_seq",0)}
	if _samples.is_empty(): _render_time = stamp - DELAY
	elif stamp == float(_samples.back().time):
		_samples.back().players = poses
		return
	_samples.append({"time":stamp,"players":poses})
	_since_snapshot = 0.0
	while _samples.size() > MAX_SAMPLES: _samples.pop_front()

func retain(ids: Array) -> void:
	for sample in _samples:
		for id in sample.players.keys():
			if not id in ids: sample.players.erase(id)

func advance(delta: float) -> void:
	if _samples.is_empty(): return
	_since_snapshot += delta
	var latest := float(_samples.back().time)
	var target := latest + _since_snapshot - DELAY
	# A small clock correction absorbs arrival jitter without rewinding on a late packet.
	var rate := clampf(1.0 + (target - _render_time) * 2.0, 0.9, 1.1)
	_render_time = minf(_render_time + delta * rate, latest)
	# After a long outage, resume near the live stream instead of replaying the backlog.
	if latest - _render_time > 0.35: _render_time = latest - DELAY
	while _samples.size() > 2 and float(_samples[1].time) <= _render_time:
		_samples.pop_front()

func sample_player(id: int, authoritative: Dictionary) -> Dictionary:
	var result := authoritative.duplicate()
	if _samples.is_empty(): return result
	var newest: Dictionary = _samples.back().players.get(id,{})
	if newest.is_empty(): return result
	var before: Dictionary = {}
	var after: Dictionary = {}
	for sample in _samples:
		if not sample.players.has(id): continue
		if float(sample.time) <= _render_time: before = sample
		elif after.is_empty(): after = sample; break
	if before.is_empty(): before = after
	if after.is_empty(): after = before
	if before.is_empty(): return result
	var a: Dictionary = before.players[id]
	var b: Dictionary = after.players[id]
	# Spawns/teleports must not sweep a character through the intervening geometry.
	if a.get("relocation_seq",0)!=newest.get("relocation_seq",0) or Vector2(a.pos).distance_to(newest.pos) > TELEPORT_DISTANCE:
		result.pos = newest.pos
		result.height = newest.height
		return result
	var span := float(after.time) - float(before.time)
	var weight := clampf((_render_time - float(before.time)) / span,0,1) if span > 0 else 1.0
	result.pos = Vector2(a.pos).lerp(b.pos,weight)
	result.height = lerpf(float(a.height),float(b.height),weight)
	result.velocity = Vector2(a.velocity).lerp(b.velocity,weight)
	result.aim = Vector2(a.aim).slerp(b.aim,weight)
	return result
