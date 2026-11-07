extends Node3D
## Independent art-layout scene. Original bunker and live party travel remain intact.
const G=preload("res://features/geometry/geometry.gd")
const ROOT="res://assets/worlds/survivor_base/"
var count:=0
var cache:Dictionary={}
func _ready():
 _build()
 print("SURVIVOR_BASE instances=",count," unique_assets=",cache.size())
func _bounds(node:Node3D,relative:Transform3D=Transform3D.IDENTITY)->AABB:
 var result:=AABB();var first:=true
 if node is MeshInstance3D and node.mesh!=null:
  result=relative*node.get_aabb();first=false
 for child in node.get_children():
  if child is Node3D:
   var b:=_bounds(child,relative*child.transform)
   if b.size.length()>0:
    result=b if first else result.merge(b);first=false
 return result
func prop(kind:String,at:Vector3,size:float,angle:float=0,axis:int=1)->Node3D:
 if not cache.has(kind):cache[kind]=load(ROOT+kind+".glb")
 var wrapper:=Node3D.new();wrapper.name=kind+str(count);add_child(wrapper)
 if cache[kind]==null:return wrapper
 var model:Node3D=cache[kind].instantiate();wrapper.add_child(model)
 if kind not in ["curtain","floor_tile","water_tank"]:model.rotation.y-=PI/2
 var b:=_bounds(model,model.transform)
 if kind in ["wall","gate","floor_tile"]:size*=.75
 var factor:float=size/maxf(b.size[axis],.001)
 model.scale*=factor
 model.position-=Vector3(b.get_center().x,b.position.y,b.get_center().z)*factor
 at.x*=.75;at.z*=.75
 wrapper.position=at;wrapper.rotation.y=deg_to_rad(angle);count+=1
 return wrapper
func box(at:Vector3,size:Vector3,color:String):
 at.x*=.75;at.z*=.75;size.x*=.75;size.z*=.75
 return G.box(self,at,size,Color(color))
func lamp(at:Vector3,energy:float=1.4,radius:float=4):
 at.x*=.75;at.z*=.75
 var light:=OmniLight3D.new();light.position=at;light.light_color=Color("ffbd75");light.light_energy=energy;light.omni_range=radius;add_child(light)
func _build():
 box(Vector3(0,-.32,0),Vector3(34,.6,34),"665f55")
 box(Vector3(0,-.7,0),Vector3(38,.35,38),"716b5b")
 # Continuous paved lanes, with subtle individual tile variation.
 var rng:=RandomNumberGenerator.new();rng.seed=711
 for x in range(-16,16,2):
  for z in range(-16,16,2):
   var tile=box(Vector3(x+1,.015,z+1),Vector3(1.96,.07,1.96),"8d8779")
   tile.material_override=G.material(Color("928a7c").darkened(rng.randf_range(0,.12)))
 for x in [-2.2,0,2.2]:
  for z in [-13.5,-11.3]:prop("floor_tile",Vector3(x,.07,z),2.1,0,0)
 # Taller rear perimeter, low foreground cutaway to keep every room visible.
 for x in [-13.6,-9.2,-4.8,4.8,9.2,13.6]:prop("wall",Vector3(x,0,-16),4.4,0,0)
 for z in range(-13,15,4):
  prop("wall",Vector3(-16,0,z),4,90,0)
  prop("wall",Vector3(16,0,z),4,90,0)
 for x in range(-14,16,4):
  var w=prop("wall",Vector3(x,0,16),4,0,0);w.scale.y=.40
 prop("gate",Vector3(0,0,-16),6.4,0,0)
 for x in [-3.8,3.8]:prop("warning_light",Vector3(x,0,-14.8),1.35);lamp(Vector3(x,1,-14.8))
 for x in [-3.2,3.2]:box(Vector3(x,.065,-11.6),Vector3(.12,.025,5.4),"c5a35a")
 for z in [-14.3,-8.9]:box(Vector3(0,.065,z),Vector3(6.5,.025,.12),"c5a35a")
 # Radial common space, heater as the visual anchor.
 G.cylinder(self,Vector3(0,.065,0),3.9,.05,Color("777268"))
 for i in range(32):
  var a:=i*TAU/32;var tile=box(Vector3(sin(a)*5,.10,cos(a)*5),Vector3(.12,.025,.58),"c5a35a");tile.rotation.y=a
 prop("heater",Vector3(0,.1,0),3.5);lamp(Vector3(0,1,0),2.0,8)
 for x in [-4,4]:
  prop("desk",Vector3(x,0,1.5),1.0)
  for z in [.25,2.7]:prop("stool",Vector3(x,0,z),.52)
 prop("desk",Vector3(3.6,0,-4),1.05)
 box(Vector3(3.6,1.12,-4),Vector3(1.5,.025,.9),"c3b998")
 for i in range(5):G.cylinder(self,Vector3(2.3+i*.21,1.18,-3+.12*sin(i)),.04,.1,Color("9f5940"))
 # Dormitory: two beds along the west back wall, baggage between.
 for x in [-13.5,-10.3]:
  for z in [-12.5,-8.7]:prop("bed",Vector3(x,0,z),1.0,90)
 prop("bedside",Vector3(-7.6,0,-12.5),.85)
 prop("locker",Vector3(-7.7,0,-9),1.8)
 prop("banner",Vector3(-11.5,1.2,-15.1),1.8)
 # Medical station: beds, privacy curtains, medicine cabinets and staffed desk.
 for z in [-3.8,.1]:
  prop("bed",Vector3(-13,0,z),.95,90)
  prop("curtain",Vector3(-10.8,0,z),1.9,90)
 prop("medicine_cabinet",Vector3(-14.5,0,3.2),1.9)
 prop("medicine_cabinet",Vector3(-14.6,0,-6),1.7)
 prop("desk",Vector3(-8.7,0,1.8),1.0)
 prop("doctor",Vector3(-9.2,0,.4),1.72,0)
 prop("medical_banner",Vector3(-15,1.4,-1.8),1.5,90)
 # Merchant stall with an open walk-up counter.
 prop("canopy",Vector3(-10.8,0,8.4),3.2)
 prop("counter",Vector3(-10.6,0,9.7),1.05)
 prop("shelf",Vector3(-13.5,0,7),2.0)
 prop("merchant",Vector3(-10.5,0,8.1),1.72,0)
 for entry in [[-8,7],[-8,10],[-13,11.4]]:
  var x:float=entry[0];var z:float=entry[1]
  prop("crate",Vector3(x,0,z),.75)
 # Stock room on the opposite side of the gate.
 for x in [8,11,14]:
  prop("shelf",Vector3(x,0,-13.6),2.4)
  for y in [.45,1.15,1.85]:prop("crate",Vector3(x,y,-13.4),.55)
 for x in [8,10.5,13]:prop("locker",Vector3(x,0,-9.5),1.9)
 for entry in [[7,-6.7],[10,-6.8],[13.4,-6.5]]:
  var x:float=entry[0];var z:float=entry[1]
  prop("pallet",Vector3(x,0,z),1.5,0,0);prop("crate",Vector3(x,.15,z),.8)
 # Forge and repair station.
 prop("forge",Vector3(13.8,0,-2),3.0);lamp(Vector3(13,1.0,-1.2),2,6)
 prop("desk",Vector3(10.8,0,.6),1.0)
 prop("blacksmith",Vector3(11.2,0,-.8),1.76,0)
 prop("shelf",Vector3(14.3,0,2.5),2)
 prop("crate",Vector3(8.3,0,2.4),.7)
 # Supplemental anvil and tool rack use the same muted faceted palette.
 G.cylinder(self,Vector3(6.75,.4,-1.2),.36,.8,Color("69533b"))
 box(Vector3(9,.94,-1.6),Vector3(.85,.25,.35),"485253")
 box(Vector3(14.8,1.8,.4),Vector3(.15,1.2,2.5),"70583e")
 for z in [-.4,.1,.6,1.1]:
  box(Vector3(14.6,1.7,z),Vector3(.08,.65,.08),"485253")
  box(Vector3(14.6,2,z),Vector3(.10,.12,.30),"596061")
 # Administration, separated by low walls but open toward the plaza.
 prop("desk",Vector3(10.2,0,9.5),1.05)
 prop("administrator",Vector3(10.3,0,8.1),1.72,0)
 prop("chair",Vector3(10.2,0,7.0),1)
 prop("notice_board",Vector3(13.8,0,7),2.4)
 prop("filing_cabinet",Vector3(14,0,10.5),1.5)
 prop("filing_cabinet",Vector3(14,0,12.5),1.5)
 # Front utility strip: kitchen, water supply and power.
 prop("kitchen_counter",Vector3(-10.5,0,13.6),1.0)
 prop("stove",Vector3(-10.5,1.02,13.6),.40)
 prop("water_tank",Vector3(-3.8,0,13.8),2.0)
 prop("generator",Vector3(2,0,13.7),1.4)
 prop("water_tower",Vector3(-20,0,-12),6)
 # Low room dividers preserve sightlines and entry gaps.
 for entry in [[-11,-6.5,0],[-11,4.6,0],[11,5,0],[11,-5,0]]:
  var x:float=entry[0];var z:float=entry[1];var angle:float=entry[2]
  var w=prop("wall",Vector3(x,0,z),5.6,angle,0);w.scale.y=.34
 for entry in [[-15,-13],[-15,-5],[-15,5],[15,-13],[15,-5],[15,5],[-7,12],[7,12]]:
  var x:float=entry[0];var z:float=entry[1]
  box(Vector3(x,1.4,z),Vector3(.12,2.8,.12),"5e5445")
  prop("lantern",Vector3(x,2.5,z),.65);lamp(Vector3(x,2.5,z),1,5)
 # Scattered supplies avoid blocking central circulation.
 for entry in [[-6,-13],[6,-13],[-14,13],[5,13],[-18,8],[18,-9]]:
  var x:float=entry[0];var z:float=entry[1]
  prop("crate",Vector3(x,0,z),.65)
 # Loose provisions, bedding and practical furniture bring each room to life.
 for entry in [[-12.5,-14.2],[-9.5,-14.2],[-13.5,12],[-7.7,10.5],[12,-11.5],[6.4,-8.8]]:
  prop("crate",Vector3(entry[0],0,entry[1]),.55)
 for entry in [[-12.4,9.8],[-11.2,9.8],[-10,9.8]]:
  prop("crate",Vector3(entry[0],1.06,entry[1]),.28)
 for entry in [[-8.4,3.5],[8.3,10.5],[3,3.8],[-3,-2.5]]:
  prop("chair",Vector3(entry[0],0,entry[1]),1,180)
 for entry in [[-12.8,-11],[-9.5,-11],[-13.8,-7.5]]:
  prop("bedside",Vector3(entry[0],0,entry[1]),.65)
 # A sparse ruined skyline frames the enclosed shelter.
 for i in range(13):
  var x:float=-32+i*5.4;var h:float=rng.randf_range(5,12)
  box(Vector3(x,h/2,-28-rng.randf_range(0,4)),Vector3(3.8,h,4),"77736a")
  for level in range(1,int(h/2)):
   for dx in [-.9,.9]:box(Vector3(x+dx,level*2,-25.9),Vector3(.7,1,.04),"4e524e")
