extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func run():
 var base:Node3D=load("res://worlds/survivor_base/playable_base.tscn").instantiate()
 var count:int=base.find_children("*","Node",true,false).size()
 var doctor:Node3D=base.find_children("doctor*","Node3D",true,false)[0]
 doctor.position.x+=1
 root.add_child(base)
 check(base.find_children("*","Node",true,false).size()==count,"base ready does not generate geometry")
 for spec in base.interactions():
  if spec.id=="medical":check(is_equal_approx(spec.pos.x,-4.2),"moved doctor carries its interaction marker")
 check(base.obstacles().size()==base._blocks.size() or base.obstacles().size()>100,"scene collision shapes supply authoritative obstacles")
 var packed:=PackedScene.new();check(packed.pack(base)==OK,"edited base can be packed normally")
 check(base.get_node("Spawn").position==preload("res://features/exploration/scene_points.gd").spawn("bunker"),"base spawn read from scene")
 base.queue_free();await process_frame
 var city:Node3D=load("res://worlds/city/city.tscn").instantiate()
 count=city.find_children("*","Node",true,false).size();root.add_child(city)
 await process_frame
 check(city.loaded and city.scene_layout,"city uses editable scene branch")
 check(city.find_children("*","Node",true,false).size()==count,"city ready does not generate geometry")
 check(city._door_nodes.size()==52,"city restores all 52 functional doors")
 check(city.interactions().size()==53,"city restores doors and extraction")
 check(city.find_children("*","CollisionShape3D",true,false).size()>=1833,"city keeps all static physics shapes")
 city.queue_free();await process_frame
 print("EDITABLE_WORLDS failures=",failures);quit(1 if failures else 0)
