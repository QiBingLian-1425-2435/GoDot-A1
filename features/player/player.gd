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

func simulate(delta: float) -> void:
	velocity = Vector3(direction.x, 0.0, direction.y) * (3.5 if active else 0.0)
	move_offset(Vector2(position.x, position.z), Vector2(velocity.x, velocity.z) * delta)
