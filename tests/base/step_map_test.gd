extends SceneTree
## Real source-map slopes near the bunker entrance, at walking and running speeds.
const Map = preload("res://worlds/ground_zero/ground_zero.gd")
const Body = preload("res://features/player/player.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func run() -> void:
	var map = Map.new()
	root.add_child(map)
	while not map.loaded: await process_frame
	var body = Body.instantiate()
	map.add_child(body)
	await physics_frame
	await physics_frame
	for route in [
		[Vector2(450, -104), Vector2.DOWN],
		[Vector2(450, -98), Vector2(-1, -1).normalized()]
	]:
		var point: Vector2 = route[0]
		var direction: Vector2 = route[1]
		var hit = body._support(point, map.terrain_height(point) + .1)
		check(not hit.is_empty(), "entrance-area slope has real source collision")
		if hit.is_empty(): continue
		var start := Vector3(point.x, body._feet_height(hit), point.y)
		var endpoints: Array[Vector3] = []
		for distance in [.03, 3.7 / 60.0, 3.7 * 1.65 / 60.0]:
			var at := start
			for frame in range(ceili(2.75 / distance)):
				at = body.move_spatial(at, direction * distance)
			print("MAP_STEP start=", start, " travel=", distance, " end=", at)
			check(at.y > start.y + .25 and Vector2(at.x-start.x, at.z-start.z).length() > 2,
				"entrance-area uphill works without sprint at travel %.3f" % distance)
			check(body.is_clear(at), "uphill capsule remains outside map collision")
			endpoints.append(at)
		check(endpoints[0].distance_to(endpoints[2]) < .25, "walking and sprint reach the same slope surface")
	map.queue_free()
	await process_frame
	# These rocks/fences exposed repeated pre-lift above the floor during audit.
	# Approaching a seam must not leave the capsule suspended and unable to return.
	map = Map.new()
	map.zone = "cave"
	root.add_child(map)
	while not map.loaded: await process_frame
	body = Body.instantiate()
	map.add_child(body)
	await physics_frame
	await physics_frame
	for route in [
		[Vector3(567.8295, -2.799449, -546.455), Vector2.DOWN],
		[Vector3(580.6, .0379, -514.0815), Vector2.LEFT],
		[Vector3(576.9044, -2.9652, -552.5767), Vector2.RIGHT]
	]:
		var start: Vector3 = route[0]
		var direction: Vector2 = route[1]
		var at := start
		for frame in range(35): at = body.move_spatial(at, direction * .06)
		for frame in range(60):
			at = body.move_spatial(at, Vector2(start.x-at.x, start.z-at.z).limit_length(.06))
		var escaped := Vector2(at.x-start.x, at.z-start.z).length() < .3
		# Curved rocks may require turning, as in the existing full collision audit.
		if not escaped:
			for side in range(8):
				var exit_at := at
				var exit_direction := Vector2.from_angle(TAU * side / 8)
				for frame in range(30): exit_at = body.move_spatial(exit_at, exit_direction * .06)
				if Vector2(exit_at.x-at.x, exit_at.z-at.z).length() > .75:
					escaped = true
					break
		check(escaped, "approaching cave seam preserves a way out at " + str(start))
	map.queue_free()
	await process_frame
	print("STEP_MAP checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
