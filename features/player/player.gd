extends CharacterBody3D
## Authoritative planar collision body; display interpolation lives in motion_buffer.gd.
var direction := Vector2.ZERO
var active := true
var _clearance_query: PhysicsShapeQueryParameters3D
const MAX_STEP := .46
const STEP_REACH := .38
const MAX_SPATIAL_TRAVEL := .03

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
	# Keep collision and floor sampling independent of sprint speed/frame time.
	# A long diagonal sweep can otherwise skip the lip that a walking step sees.
	var steps := maxi(1, ceili(offset.length() / MAX_SPATIAL_TRAVEL))
	var at := from
	for step in range(steps):
		var result := _move_spatial_step(at, offset / steps)
		if result.is_equal_approx(at) and not offset.is_zero_approx(): break
		at = result
	return at

func _move_spatial_step(from: Vector3, offset: Vector2) -> Vector3:
	position = from
	var was_clear:=is_clear(from)
	# A short upward probe preserves the current floor beneath bridges and roofs.
	var support := _support(Vector2(from.x,from.z),from.y)
	if offset.is_zero_approx() and not support.is_empty() and Vector3(support.normal).y>=.55: _move_vertical(_feet_height(support)-position.y)
	for travel in [Vector2(offset.x,0),Vector2(0,offset.y)]:
		if travel.is_zero_approx(): continue
		var next: Vector2 = Vector2(position.x,position.z)+travel
		var floor_hit := _support(next,position.y)
		if floor_hit.is_empty() or Vector3(floor_hit.normal).y<.55 or _feet_height(floor_hit)-position.y < -MAX_STEP:
			floor_hit=_descending_support(next,travel)
		if floor_hit.is_empty(): continue
		var target_y := _feet_height(floor_hit)
		var step_y := _step_height(next,travel,floor_hit)
		var stepping := step_y > target_y+.02
		if stepping: target_y = step_y
		var rise := maxf(0,target_y-position.y)
		if rise>MAX_STEP or target_y-position.y < -MAX_STEP: continue
		if stepping and rise>.001:
			var before_lift := position
			_move_vertical(rise)
			if position.y < target_y-.008 or not is_clear(position):
				position=before_lift
				continue
		# Crossing the edge before lowering the feet avoids sweeping diagonally
		# into the platform being left behind. Continuous slopes keep their sweep.
		var vertical := target_y-position.y
		var remaining:=Vector3(travel.x,0.0 if vertical < -.08 else vertical,travel.y)
		for slide in range(3):
			var collision:=move_and_collide(remaining,false,.02)
			if collision==null:break
			var normal:=collision.get_normal()
			if normal.y<.55:normal=Vector3(normal.x,0,normal.z).normalized()
			remaining=collision.get_remainder().slide(normal)
			if remaining.length_squared()<.0000001:break
		var final_floor := _support(Vector2(position.x,position.z),position.y)
		if not final_floor.is_empty() and Vector3(final_floor.normal).y>=.55:
			var descent := _feet_height(final_floor)-position.y
			if descent<0 and descent>=-MAX_STEP and not stepping: _move_vertical(descent)
	# Concave seams may still penetrate after recovery; keep the last clear pose.
	if was_clear and not is_clear(position):position=from
	if was_clear and not position.is_equal_approx(from):
		var arrived:=position
		# Do not walk into a one-way concave seam: the same capsule must be able
		# to retrace this tiny swept step, including its floor height change.
		move_and_collide(from-arrived,false,.02)
		var retraced:=position.distance_to(from)<.008
		if not retraced:
			# The reverse of a legal step is horizontal first, then down, rather
			# than a diagonal sweep through the edge that was just stepped over.
			position=arrived
			_move_vertical(maxf(from.y,arrived.y)-position.y)
			move_and_collide(Vector3(from.x-position.x,0,from.z-position.z),false,.02)
			_move_vertical(from.y-position.y)
			retraced=position.distance_to(from)<.008
		position=arrived if retraced else from
	return position

func _step_height(next: Vector2, travel: Vector2, floor_hit: Dictionary) -> float:
	var current := _feet_height(floor_hit)
	var direction := travel.normalized()
	var step_height := current
	# A single probe at the far edge skips narrow door sills and short stair
	# treads. Sample the capsule's whole forward reach so their top is seen before
	# the capsule side reaches the vertical face.
	var side := Vector2(-direction.y,direction.x)
	var needs_shoulder_clearance := not is_clear(Vector3(next.x,current,next.y))
	for distance: float in PackedFloat32Array([.08, .16, .24, .32, STEP_REACH]):
		# Cover the leading capsule footprint, not only its center line. A diagonal
		# lip can hit the shoulder before any center probe reaches its top.
		var width := sqrt(maxf(0.0,STEP_REACH*STEP_REACH-distance*distance))*.85
		for lateral: float in ([0.0,-width,width] if needs_shoulder_clearance else [0.0]):
			var ahead: Vector2 = next+direction*distance+side*lateral
			var hit := _support(ahead,position.y)
			if hit.is_empty() or Vector3(hit.normal).y<.55: continue
			# Shoulder-only support must be a tread, not the flank of a curved rock.
			if lateral!=0.0 and Vector3(hit.normal).y<.95: continue
			var height := _feet_height(hit)
			# Bound against direct support too: repeated probes must not ratchet
			# the capsule upward while its center remains over the lower floor.
			if height-position.y > MAX_STEP or height-current > MAX_STEP or height<=current+.02: continue
			var normal:Vector3=floor_hit.normal
			var offset: Vector2=ahead-Vector2(floor_hit.position.x,floor_hit.position.z)
			var expected:float=floor_hit.position.y-(normal.x*offset.x+normal.z*offset.y)/maxf(.55,normal.y)
			if float(hit.position.y)>expected+.055: step_height=maxf(step_height,height)
	return step_height

func _descending_support(next: Vector2, travel: Vector2) -> Dictionary:
	# At a downhill triangle seam or a narrow stair gap the ray directly below
	# the next point can briefly miss the visible floor and hit a deeper backing
	# surface. Look ahead for a nearby reachable landing so the horizontal sweep
	# can cross the seam; vertical snapping still waits for direct support.
	var direction := travel.normalized()
	for distance: float in PackedFloat32Array([.08, .16, .24, .32, STEP_REACH]):
		var hit := _support(next+direction*distance,position.y)
		if hit.is_empty() or Vector3(hit.normal).y<.55: continue
		var height := _feet_height(hit)
		if height<=position.y+.02 and height-position.y>=-MAX_STEP: return hit
	return {}

func _move_vertical(amount: float) -> void:
	var previous:=position
	var clear:=is_clear(previous)
	move_and_collide(Vector3(0,amount,0),false,.02)
	if clear and not is_clear(position):position=previous

func is_clear(at: Vector3) -> bool:
	if _clearance_query==null:
		_clearance_query=PhysicsShapeQueryParameters3D.new()
		_clearance_query.shape=get_child(0).shape
		_clearance_query.collision_mask=1
		_clearance_query.margin=.025
	_clearance_query.transform=Transform3D(Basis.IDENTITY,at+Vector3(0,.75,0))
	return get_world_3d().direct_space_state.intersect_shape(_clearance_query,1).is_empty()

func _feet_height(hit: Dictionary) -> float:
	# A capsule touching an incline needs more center clearance than on a flat
	# floor. Resetting its feet onto the plane each frame would wedge it uphill.
	var normal_y := maxf(.55,float(hit.normal.y))
	return float(hit.position.y)+.04+.32*(1.0/normal_y-1.0)

func _support(at: Vector2, reference: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x,reference+.45,at.y),Vector3(at.x,reference-1.25,at.y),1)
	return get_world_3d().direct_space_state.intersect_ray(query)

func simulate(delta: float) -> void:
	velocity = Vector3(direction.x, 0.0, direction.y) * (3.5 if active else 0.0)
	move_offset(Vector2(position.x, position.z), Vector2(velocity.x, velocity.z) * delta)
