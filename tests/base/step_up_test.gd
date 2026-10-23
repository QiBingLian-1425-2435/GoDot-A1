extends SceneTree
const Body=preload("res://features/player/player.tscn")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func box(parent:Node3D,at:Vector3,size:Vector3):
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape
	body.position=at;body.add_child(collision);parent.add_child(body)
func run():
	var world:=Node3D.new();root.add_child(world)
	box(world,Vector3(0,-.1,0),Vector3(30,.2,30))
	for lane in range(3):
		var height:float=[.12,.30,.44][lane]
		box(world,Vector3(2,height*.5,lane*3),Vector3(4,height,2))
	box(world,Vector3(2,.35,9),Vector3(4,.7,2))
	box(world,Vector3(2,.15,-3),Vector3(4,.3,2))
	box(world,Vector3(-.2,1.62,-3),Vector3(2,.15,2))
	# Door sills and short treads can be much narrower than the old single
	# forward probe distance. Jambs make this representative of a real doorway.
	box(world,Vector3(0,.08,12),Vector3(.12,.16,1.5))
	box(world,Vector3(0,1.0,10.9),Vector3(.25,2.0,.35))
	box(world,Vector3(0,1.0,13.1),Vector3(.25,2.0,.35))
	var body=Body.instantiate();world.add_child(body)
	await physics_frame;await physics_frame
	for lane in range(3):
		var height:float=[.12,.30,.44][lane]
		for speed in [.018,.0616667,.10175]:
			var at:=Vector3(-1,.04,lane*3)
			for i in range(ceili(2.4/speed)):at=body.move_spatial(at,Vector2(speed,0))
			print("STEP height=",height," speed=",speed," end=",at)
			check(at.x>1.1 and absf(at.y-height-.04)<.08,"small step %.2f climbs with per-frame travel %.3f"%[height,speed])
			for i in range(ceili(2.4/speed)):at=body.move_spatial(at,Vector2(-speed,0))
			check(at.x<-.8 and at.y<.1,"step can be safely descended at same speed")
	var at:=Vector3(-1,.04,9)
	for i in range(100):at=body.move_spatial(at,Vector2(.04,0))
	check(at.x<0,"high obstacle is not a small step")
	at=Vector3(-1,.04,-3)
	for i in range(100):at=body.move_spatial(at,Vector2(.04,0))
	check(at.x<0 and at.y<.1,"low overhead clearance prevents stepping into ceiling")
	for travel in [Vector2(.04,0),Vector2(.04,.012)]:
		at=Vector3(-1,.04,12)
		for i in range(55):at=body.move_spatial(at,travel)
		check(at.x>.8,"narrow door sill is crossed at direction "+str(travel.normalized()))
		check(body.is_clear(at),"door-sill crossing leaves the capsule clear")
	world.queue_free();await process_frame
	print("STEP_UP checks=",checks," failures=",failures);quit(1 if failures else 0)
