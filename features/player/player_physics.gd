extends Node3D
## Main-scene movement adapter. Rules-only fixtures use the model's rectangle solver.
const PlayerBody = preload("res://features/player/player.tscn")
var bodies: Dictionary = {}
var model
var prediction_body: CharacterBody3D
var spatial_enabled := false
var world_ready := true

func configure(match_model) -> void:
	model = match_model
	model.motion_solver = solve

func solve(id: int, from: Vector2, offset: Vector2) -> Variant:
	if not world_ready: return Vector3(from.x,float(model.state.players.get(id,{}).get("height",0)),from.y)
	if not bodies.has(id):
		var body = PlayerBody.instantiate()
		body.name = "Actor_%d" % id
		add_child(body)
		bodies[id] = body
	if spatial_enabled:
		return bodies[id].move_spatial(Vector3(from.x,float(model.state.players.get(id,{}).get("height",0)),from.y),offset)
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
	for body in bodies.values(): body.free()
	bodies.clear()
	if is_instance_valid(prediction_body): prediction_body.free()
	prediction_body = null

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
