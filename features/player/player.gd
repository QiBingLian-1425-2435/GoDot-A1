extends CharacterBody3D
## Authoritative planar collision body; display interpolation lives in motion_buffer.gd.
var direction := Vector2.ZERO
var active := true

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	safe_margin = 0.001
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.5
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.75
	add_child(collider)

func move_offset(from: Vector2, offset: Vector2) -> Vector2:
	position = Vector3(from.x, 0.0, from.y)
	# Separate axes retain the reference's furniture-sliding behaviour.
	move_and_collide(Vector3(offset.x, 0.0, 0.0))
	move_and_collide(Vector3(0.0, 0.0, offset.y))
	return Vector2(position.x, position.z)

func move_spatial(from: Vector3, offset: Vector2) -> Vector3:
	position = from
	# A short upward probe preserves the current floor beneath bridges and roofs.
	var support := _support(Vector2(from.x,from.z),from.y)
	if not support.is_empty(): position.y = _feet_height(support)
	for travel in [Vector2(offset.x,0),Vector2(0,offset.y)]:
		if travel.is_zero_approx(): continue
		var next: Vector2 = Vector2(position.x,position.z)+travel
		var floor_hit := _support(next,position.y)
		if floor_hit.is_empty() or Vector3(floor_hit.normal).y<.55: continue
		var target_y := _feet_height(floor_hit)
		var rise := maxf(0,target_y-position.y)
		if rise>.46: continue
		if rise>0: move_and_collide(Vector3(0,rise,0))
		move_and_collide(Vector3(travel.x,0,travel.y))
		var final_floor := _support(Vector2(position.x,position.z),position.y)
		if not final_floor.is_empty():
			var descent := _feet_height(final_floor)-position.y
			if descent<0: move_and_collide(Vector3(0,descent,0))
	return position

func _feet_height(hit: Dictionary) -> float:
	# A capsule touching an incline needs more center clearance than on a flat
	# floor. Resetting its feet onto the plane each frame would wedge it uphill.
	var normal_y := maxf(.55,float(hit.normal.y))
	return float(hit.position.y)+.015+.32*(1.0/normal_y-1.0)

func _support(at: Vector2, reference: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x,reference+.45,at.y),Vector3(at.x,reference-1.25,at.y),1)
	return get_world_3d().direct_space_state.intersect_ray(query)

func simulate(delta: float) -> void:
	velocity = Vector3(direction.x, 0.0, direction.y) * (3.5 if active else 0.0)
	move_offset(Vector2(position.x, position.z), Vector2(velocity.x, velocity.z) * delta)
