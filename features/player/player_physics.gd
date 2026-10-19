extends Node3D
## Main-scene movement adapter. Rules-only fixtures use the model's rectangle solver.
const PlayerBody = preload("res://features/player/player.tscn")
var bodies: Dictionary = {}
var model
var prediction_body: CharacterBody3D

func configure(match_model) -> void:
	model = match_model
	model.motion_solver = solve

func solve(id: int, from: Vector2, offset: Vector2) -> Vector2:
	if not bodies.has(id):
		var body = PlayerBody.instantiate()
		body.name = "Actor_%d" % id
		add_child(body)
		bodies[id] = body
	return bodies[id].move_offset(from, offset)

func predict(from: Vector2, offset: Vector2) -> Vector2:
	if not is_instance_valid(prediction_body):
		prediction_body = PlayerBody.instantiate()
		prediction_body.name = "LocalPrediction"
		add_child(prediction_body)
		prediction_body.collision_layer = 0
	return prediction_body.move_offset(from,offset)

func _physics_process(_delta: float) -> void:
	for id in bodies.keys():
		if id != 0 and not model.state.players.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
