extends Node3D
## Main-scene movement adapter. Rules-only fixtures use the model's rectangle solver.
const PlayerBody = preload("res://features/player/player.tscn")
var bodies: Dictionary = {}
var model
var prediction_body: CharacterBody3D
var spatial_enabled := false
var world_ready := true
var _safe_history: Dictionary = {}
var _recovery_shape: CapsuleShape3D

func configure(match_model) -> void:
	model = match_model
	model.motion_solver = solve
	model.recovery_solver = recover

func solve(id: int, from: Vector2, offset: Vector2) -> Variant:
	if not world_ready: return Vector3(from.x,float(model.state.players.get(id,{}).get("height",0)),from.y)
	if not bodies.has(id):
		var body = PlayerBody.instantiate()
		body.name = "Actor_%d" % id
		add_child(body)
		bodies[id] = body
	if spatial_enabled:
		var result: Vector3=bodies[id].move_spatial(Vector3(from.x,float(model.state.players.get(id,{}).get("height",0)),from.y),offset)
		_remember_safe(id,result)
		return result
	return bodies[id].move_offset(from, offset)

func predict(from: Vector2, offset: Vector2) -> Vector2:
	_ensure_prediction_body()
	return prediction_body.move_offset(from,offset)

func predict_spatial(from: Vector3, offset: Vector2) -> Vector3:
	if not world_ready: return from
	_ensure_prediction_body()
	if spatial_enabled: return prediction_body.move_spatial(from,offset)
	var result: Vector2 = prediction_body.move_offset(Vector2(from.x,from.z),offset)
	return Vector3(result.x,0,result.y)

func reset_world() -> void:
	_safe_history.clear()
	for body in bodies.values(): body.free()
	bodies.clear()
	if is_instance_valid(prediction_body): prediction_body.free()
	prediction_body = null

func safe_standing_position(at: Vector3) -> Dictionary:
	if not model.bounds.grow(-.4).has_point(Vector2(at.x,at.z)):return {}
	_ensure_prediction_body()
	var point:=Vector3(at.x,0,at.z)
	if spatial_enabled:
		var floor_hit: Dictionary=prediction_body._support(Vector2(at.x,at.z),at.y)
		if floor_hit.is_empty() or Vector3(floor_hit.normal).y<.65:return {}
		point.y=prediction_body._feet_height(floor_hit)
	if not prediction_body.is_clear(point):return {}
	if _recovery_shape==null:
		_recovery_shape=CapsuleShape3D.new();_recovery_shape.radius=.34;_recovery_shape.height=1.5
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=_recovery_shape;query.collision_mask=1;query.margin=0
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,.77,0))
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	return {"position":point}

func _remember_safe(id: int, at: Vector3) -> void:
	var history: Array=_safe_history.get(id,[])
	if not history.is_empty() and Vector3(history.back()).distance_to(at)<1.0:return
	if safe_standing_position(at).is_empty():return
	history.append(at)
	if history.size()>16:history.pop_front()
	_safe_history[id]=history

func recover(id: int) -> Dictionary:
	if not world_ready or not model.state.players.has(id):return {}
	var p: Dictionary=model.state.players[id]
	var origin:=Vector3(p.pos.x,float(p.get("height",0)),p.pos.y)
	var candidates: Array=[]
	var history: Array=_safe_history.get(id,[]).duplicate()
	history.reverse();candidates.append_array(history)
	for radius in [.8,1.2,2.0,3.0,5.0,8.0]:
		for i in range(16):
			var angle:=TAU*i/16.0
			candidates.append(origin+Vector3(cos(angle),0,sin(angle))*radius)
	for candidate in candidates:
		if Vector3(candidate).distance_to(origin)<.6 or Vector3(candidate).distance_to(origin)>8.1:continue
		var safe:=safe_standing_position(candidate)
		if safe.is_empty():continue
		# A valid capsule alone is insufficient: it must also have a way to walk out.
		var exits:=0
		for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
			var moved: Vector3=prediction_body.move_spatial(safe.position,direction*.6) if spatial_enabled else Vector3.ZERO
			if not spatial_enabled:
				var planar: Vector2=prediction_body.move_offset(Vector2(candidate.x,candidate.z),direction*.6)
				moved=Vector3(planar.x,0,planar.y)
			if Vector2(moved.x-safe.position.x,moved.z-safe.position.z).length()>.45:exits+=1
		if exits>=2:return safe
	return {}

func shot_hit(origin: Vector3, end: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,end,8))

func _ensure_prediction_body() -> void:
	if not is_instance_valid(prediction_body):
		prediction_body = PlayerBody.instantiate()
		prediction_body.name = "LocalPrediction"
		add_child(prediction_body)
		prediction_body.collision_layer = 0

func _physics_process(_delta: float) -> void:
	for id in bodies.keys():
		if id != 0 and not model.state.players.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
			_safe_history.erase(id)
