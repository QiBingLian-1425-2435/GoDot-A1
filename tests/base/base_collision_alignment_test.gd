extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func bounds(n:Node3D,root_node:Node3D,collision:bool=false)->AABB:
 var found:=false;var result:=AABB()
 var nodes:Array=[n];nodes.append_array(n.find_children("*","Node3D",true,false))
 for node in nodes:
  var b:AABB
  if not collision and node is MeshInstance3D and node.mesh!=null:b=node.mesh.get_aabb()
  elif collision and node is CollisionShape3D and node.shape is BoxShape3D:b=AABB(-node.shape.size*.5,node.shape.size)
  else:continue
  b=root_node.global_transform.affine_inverse()*node.global_transform*b
  result=b if not found else result.merge(b);found=true
 return result
func run():
 var map=load("res://worlds/survivor_base/playable_base.tscn").instantiate();root.add_child(map)
 var checked:=0;var beds:=0
 for p in map.get_children():
  if not p.has_meta("prop_kind"):continue
  var kind:String=p.get_meta("prop_kind")
  var v:=bounds(p,map);var c:=bounds(p,map,true)
  if kind=="bed":
   beds+=1
   if p.get_node_or_null("RepairedBed")==null:failures+=1;print("FAIL: old bed mesh ",p.name)
  if c.size.length()==0 or kind=="canopy":continue
  checked+=1
  var delta:=v.get_center()-c.get_center()
  var ratio:=Vector2(c.size.x/v.size.x,c.size.z/v.size.z)
  if Vector2(delta.x,delta.z).length()>.05 or absf(ratio.x-.9)>.06 or absf(ratio.y-.9)>.06:
   failures+=1;print("FAIL: collision offset ",p.name," offset=",delta," ratio=",ratio)
 print("BASE_COLLISION checked=",checked," repaired_beds=",beds," failures=",failures)
 map.free();quit(1 if failures else 0)
