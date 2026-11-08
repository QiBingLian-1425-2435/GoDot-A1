extends RefCounted
static func spawn(world:String)->Vector3:
 var path:String={"bunker":"res://worlds/survivor_base/playable_base.tscn","city":"res://worlds/city/city.tscn"}.get(world,"")
 if path.is_empty():return Vector3.ZERO
 var scene:PackedScene=load(path)
 var state:SceneState=scene.get_state()
 for i in state.get_node_count():
  if state.get_node_name(i)!=&"Spawn":continue
  for j in state.get_node_property_count(i):
   if state.get_node_property_name(i,j)==&"position":return state.get_node_property_value(i,j)
   if state.get_node_property_name(i,j)==&"transform":return state.get_node_property_value(i,j).origin
 return Vector3.ZERO
