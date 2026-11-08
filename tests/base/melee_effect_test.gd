extends SceneTree
const Slash=preload("res://features/player/animation/melee_slash.gd")
const Sweep=preload("res://features/combat/melee_sweep.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var world:=Node3D.new();root.add_child(world)
	var wall:=StaticBody3D.new();wall.collision_layer=8;wall.collision_mask=0;world.add_child(wall)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(5,2,.1);shape.position=Vector3(0,.98,-.8);wall.add_child(shape)
	var slash=Slash.new();world.add_child(slash)
	await physics_frame;await physics_frame
	slash.update_slash("katana",.55,true,false)
	var vertices:PackedVector3Array=slash.geometry.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var clipped:=true
	for vertex in vertices:clipped=clipped and vertex.z>=-.751 and Vector2(vertex.x,vertex.z).length()<=Sweep.reach("katana")+.001
	check(clipped and vertices.size()>0,"effect clips at real world collision and never exceeds attack reach")
	slash.update_slash("katana",.1,true,false);check(not slash.visible,"windup has no active slash")
	slash.update_slash("katana",.9,true,false);check(not slash.visible,"recovery has no lingering active slash")
	slash.update_slash("katana",.4,false,false);check(not slash.visible,"cancelled attack hides slash immediately")
	world.queue_free();await process_frame
	print("MELEE_EFFECT failures=",failures);quit(0 if failures==0 else 1)
