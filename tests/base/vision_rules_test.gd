extends SceneTree
const Rules=preload("res://features/visibility/vision_rules.gd")
const Vision=preload("res://features/visibility/exploration_vision.gd")
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok:failures+=1
func run() -> void:
	check(Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,1,-36.9)),"the original 37 m view distance sees forward")
	check(not Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,1,-37.1)),"objects beyond the view distance stay hidden")
	check(not Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,1,4)),"the rear blind spot hides distant targets")
	check(Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,.2,1.4)),"the near circle sees behind the observer")
	check(not Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,.2,1.6)),"the near circle does not grow to pickup distance")
	check(Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(sin(deg_to_rad(49))*8,1,-cos(deg_to_rad(49))*8)),"a target inside the 100 degree cone is seen")
	check(not Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(sin(deg_to_rad(51))*8,1,-cos(deg_to_rad(51))*8)),"a target beyond the cone edge is hidden")
	check(not Rules.contains(Vector3.ZERO,Vector2.UP,Vector3(0,4,-2)),"another floor is not revealed by planar overlap")
	var world:=Node3D.new();root.add_child(world)
	var wall:=StaticBody3D.new();wall.collision_layer=16;wall.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,3,.3);shape.shape=box
	wall.add_child(shape);wall.position=Vector3(0,1.5,-4);world.add_child(wall)
	await physics_frame;await physics_frame
	var vision=Vision.new();vision.enabled=true;vision.space=world.get_world_3d().direct_space_state
	check(not vision.can_see(Vector3(0,1,-8)),"a real opaque wall blocks the forward view")
	check(vision.can_see(Vector3(5,1,-8)),"an exposed sample beside the wall can be seen")
	var excluded: Array[RID]=[wall.get_rid()]
	check(vision.can_see(Vector3(0,1,-4),excluded),"a target's own collider does not hide its visible surface")
	wall.collision_layer=0;await physics_frame;await physics_frame
	check(vision.can_see(Vector3(0,1,-8)),"opening a physical occluder reveals the view immediately")
	vision.aim=Vector2.DOWN
	check(not vision.can_see(Vector3(0,1,-8)),"turning away hides a previously seen target without exploration memory")
	vision.enabled=false
	check(vision.can_see(Vector3(0,20,-90)),"the base bypass restores unrestricted presentation")
	world.queue_free();await process_frame
	print("VISION_RULES ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
