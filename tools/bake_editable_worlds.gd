extends SceneTree
var mesh_index:=0
var saved_meshes:Dictionary={}
var asset_folder:=""
func _initialize():call_deferred("run")
func marker(parent:Node,name:String,at:Vector3,spec:Dictionary={})->Marker3D:
 var n:=Marker3D.new();n.name=name;parent.add_child(n);n.position=at
 if not spec.is_empty():n.set_meta("interaction",spec)
 return n
func own(node:Node,top:Node):
 for child in node.get_children():
  if child is MeshInstance3D and child.mesh!=null:
   var id:int=child.mesh.get_instance_id()
   if not saved_meshes.has(id):
    var path:String=asset_folder+"mesh_%04d.res"%mesh_index
    mesh_index+=1
    if ResourceSaver.save(child.mesh,path,ResourceSaver.FLAG_CHANGE_PATH)!=OK:quit(1);return
    child.mesh.take_over_path(path)
    saved_meshes[id]=path
  child.owner=top
  # Flatten node ownership so imported mesh children are directly editable.
  child.scene_file_path=""
  own(child,top)
func save_scene(node:Node,path:String):
 asset_folder="res://assets/worlds/editable/"+node.name.to_snake_case()+"/"
 DirAccess.make_dir_recursive_absolute(asset_folder)
 saved_meshes.clear();mesh_index=0
 own(node,node)
 var scene:=PackedScene.new();var err:=scene.pack(node)
 if err==OK:err=ResourceSaver.save(scene,path)
 print("EDITABLE_SCENE ",path," status=",err," children=",node.get_child_count())
 if err!=OK:quit(1)
func run():
 var base=load("res://worlds/survivor_base/playable_base.gd").new();base.name="SurvivorBase";root.add_child(base)
 var interactions:Array=base.interactions()
 var points:=Node3D.new();points.name="Interactions";base.add_child(points)
 for spec in interactions:
  var mapping={"medical":"doctor","trader":"merchant","workbench":"blacksmith","camp_management":"administrator","stash":"locker","exit":"gate","ammo_supply":"crate"}
  var nearest:Node3D;var distance:=INF
  for n in base._visuals.get(mapping.get(spec.id,""),[]):
   var d:float=Vector2(n.position.x,n.position.z).distance_to(spec.pos)
   if d<distance:nearest=n;distance=d
  var m=marker(points,spec.id,Vector3(spec.pos.x,0,spec.pos.y),spec)
  if nearest!=null:m.reparent(nearest,true)
 marker(base,"Spawn",Vector3(-1,0,4))
 for i in base.target_nodes:
  base.target_nodes[i].name="TrainingTarget_"+str(i);base.target_nodes[i].set_meta("training_target",i)
 base.scene_layout=true
 save_scene(base,"res://worlds/survivor_base/playable_base.tscn")
 base.free()
 var city=load("res://worlds/city/city.gd").new();city.name="City";root.add_child(city)
 if not city.loaded:await city.map_loaded
 city.scene_rooms=city.layout.get("buildings",[])+city.layout.get("open_buildings",[])
 city.scene_bounds=city.play_bounds()
 for uid in city._door_nodes:
  var part:Dictionary=city._door_nodes[uid]
  part.body.name="Body";part.body.get_parent().set_meta("door_uid",uid)
 var poi:=Node3D.new();poi.name="Interactions";city.add_child(poi)
 for spec in city.interactions():
  var m=marker(poi,str(spec.uid),Vector3(spec.pos.x,spec.height,spec.pos.y),spec)
  if spec.kind=="door":m.reparent(city._door_nodes[spec.uid].body.get_parent(),true)
 var spawn:Array=city.layout.spawn
 marker(city,"Spawn",Vector3(spawn[0],spawn[1],spawn[2]))
 city.scene_layout=true
 save_scene(city,"res://worlds/city/city.tscn")
 city.queue_free();quit.call_deferred()
