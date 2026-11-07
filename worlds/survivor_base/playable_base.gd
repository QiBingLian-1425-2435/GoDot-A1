extends "res://worlds/survivor_base/survivor_base.gd"
## Production adapter for the existing base station and authoritative movement contracts.
var _blocks:Array=[]
var _visuals:Dictionary={}
var target_nodes:Dictionary={}
const TARGETS=[Vector2(-3,8.6),Vector2(0,8.6),Vector2(3,8.6)]
func obstacles()->Array:return _blocks
func play_bounds()->Rect2:return Rect2(-11.8,-11.8,23.6,23.6)
func spawn_position()->Vector2:return Vector2(-1,4)
func interactions()->Array:
 return [
  {"id":"camp_management","kind":"camp_management","title":"⟦bunker.001⟧","pos":Vector2(7.2,8.35)},
  {"id":"stash","kind":"stash","title":"⟦bunker.002⟧","pos":Vector2(7.3,-6.2)},
  {"id":"workbench","kind":"workbench","title":"⟦bunker.003⟧","pos":Vector2(7.7,1.6)},
  {"id":"medical","kind":"medical","title":"⟦bunker.004⟧","pos":Vector2(-5.2,2.4)},
  {"id":"exit","kind":"exit","title":"⟦bunker.city_exit⟧","pos":Vector2(0,-10.5),"height":0},
  {"id":"trader","kind":"trader","title":"⟦bunker.008⟧","pos":Vector2(-7.6,8.8)},
  {"id":"ammo_supply","kind":"ammo_supply","title":"⟦bunker.007⟧","pos":Vector2(4.6,6.5)},
  {"id":"range","kind":"range","title":"⟦bunker.006⟧","pos":Vector2(0,6.4)}]
func _ready():
 super._ready()
 _solid(Vector2(0,-12),Vector2(24.5,.45),3)
 _solid(Vector2(0,12),Vector2(24.5,.45),3)
 _solid(Vector2(-12,0),Vector2(.45,24.5),3)
 _solid(Vector2(12,0),Vector2(.45,24.5),3)
 prop("crate",Vector3(6.2,0,7.2),.6)
 for i in range(3):
  var target:=Node3D.new();target.position=Vector3(TARGETS[i].x,0,TARGETS[i].y);add_child(target);target_nodes[i]=target
  G.box(target,Vector3(0,.55,0),Vector3(.1,1.1,.12),Color("62503e"))
  G.box(target,Vector3(0,1.45,0),Vector3(.85,1.1,.12),Color("9b8668"))
  var ring=G.cylinder(target,Vector3(0,1.5,.09),.27,.025,Color("c6ad83"));ring.rotation.x=PI/2
  var bull=G.cylinder(target,Vector3(0,1.5,.11),.10,.028,Color("934f3c"));bull.rotation.x=PI/2
func prop(kind:String,at:Vector3,size:float,angle:float=0,axis:int=1)->Node3D:
 var result=super.prop(kind,at,size,angle,axis)
 if not _visuals.has(kind):_visuals[kind]=[]
 _visuals[kind].append(result)
 if kind=="floor_tile":result.scale.y=.15;result.position.y=0
 if kind in ["floor_tile","banner","medical_banner","lantern","water_tower"]:return result
 var b:=_bounds(result,result.transform)
 if kind=="canopy":
  for x in [b.position.x+.12,b.end.x-.12]:
   for z in [b.position.z+.12,b.end.z-.12]:_solid(Vector2(x,z),Vector2(.24,.24),2.8)
  return result
 if b.size.length()>0:
  _solid(Vector2(b.get_center().x,b.get_center().z),Vector2(b.size.x,b.size.z)*.9,maxf(.6,b.size.y))
 return result
func _solid(at:Vector2,size:Vector2,height:float):
 _blocks.append(Rect2(at-size*.5,size))
 var body:=StaticBody3D.new();body.position=Vector3(at.x,height*.5,at.y);body.collision_layer=1;body.collision_mask=2
 var shape:=CollisionShape3D.new();var box_shape:=BoxShape3D.new();box_shape.size=Vector3(size.x,height,size.y);shape.shape=box_shape;body.add_child(shape);add_child(body)
func update_targets(targets:Array):
 for i in range(mini(3,targets.size())):
  target_nodes[i].position=Vector3(targets[i].pos.x,0,targets[i].pos.y)
  target_nodes[i].rotation.x=-.65 if targets[i].hp<=0 else 0
func interaction_visuals(target:Dictionary)->Array:
 var kind:String=str(target.get("id",target.get("kind","")))
 var mapping={"exit":"gate","medical":"doctor","trader":"merchant","workbench":"blacksmith","camp_management":"administrator","stash":"locker","ammo_supply":"crate"}
 var found:Array=[]
 for node in _visuals.get(mapping.get(kind,""),[]):
  if kind=="exit" or Vector2(node.position.x,node.position.z).distance_to(target.pos)<3: _meshes(node,found)
 return found
func _meshes(node:Node,result:Array):
 if node is MeshInstance3D:result.append(node)
 for child in node.get_children():_meshes(child,result)
static func apply_lighting(environment:Environment,sun:DirectionalLight3D):
 if environment!=null:
  environment.background_color=Color("9c9482");environment.ambient_light_color=Color("d7d1bc");environment.ambient_light_energy=.45;environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
 if sun!=null:
  sun.rotation_degrees=Vector3(-48,-30,0);sun.light_color=Color("fff1da");sun.light_energy=.75
