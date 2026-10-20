extends SceneTree
const Body = preload("res://features/player/player.tscn")
var failures := 0
var checks := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1;print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures+=1
func box(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape
	body.position=position;body.add_child(collider);parent.add_child(body)
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	box(world,Vector3(0,-.1,0),Vector3(30,.2,30))
	# An actual rising concave floor, with the same capsule and solver as the map.
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,-2),Vector3(6,3,-2),Vector3(0,0,2),Vector3(6,3,2)])
	# Godot's front faces wind clockwise, matching the converted source meshes.
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,3,2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var floor:=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=0
	var collision:=CollisionShape3D.new();collision.shape=mesh.create_trimesh_shape();floor.add_child(collision);world.add_child(floor)
	box(world,Vector3(-5,3,0),Vector3(6,.2,6))
	box(world,Vector3(-5,1,4),Vector3(6,2,.2))
	var body=Body.instantiate();world.add_child(body)
	await physics_frame;await physics_frame
	var at:=Vector3(.1,.065,0)
	for i in range(100):at=body.move_spatial(at,Vector2(.03,0))
	print("SPATIAL_RAMP ",at)
	check(at.x>2.5 and absf(at.y-at.x*.5)<.08,"the real capsule climbs a sloping mesh without flattening its height")
	for i in range(60):at=body.move_spatial(at,Vector2(-.03,0))
	check(at.x<1.6 and absf(at.y-at.x*.5)<.08,"the same capsule descends the slope")
	at=Vector3(-5,.015,0)
	for i in range(20):at=body.move_spatial(at,Vector2(.03,0))
	check(absf(at.y-.015)<.03,"ground movement remains beneath an overhead bridge")
	at=Vector3(-5,3.115,0)
	for i in range(20):at=body.move_spatial(at,Vector2(.03,0))
	check(absf(at.y-3.115)<.03,"movement on the bridge remains on its own floor")
	at=Vector3(-5,.015,3)
	for i in range(60):at=body.move_spatial(at,Vector2(0,.03))
	check(at.z<3.65,"a wall stops movement instead of being mistaken for a step")
	world.queue_free();await process_frame
	print("SPATIAL_MOVEMENT ",checks," checks; ",failures," failures")
	quit(0 if failures==0 else 1)
