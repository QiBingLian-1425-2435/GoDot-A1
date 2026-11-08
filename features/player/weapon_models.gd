extends RefCounted
const SPECS={
 "rifle":{"scale":.88,"yaw":PI-.591,"grip":Vector3(-.128,.12,-.19),"support":Vector3(-.035,.025,-.27),"muzzle":Vector3(.349,.225,.5)},
 "pistol":{"scale":.42,"yaw":PI,"grip":Vector3(0,.16,-.35),"support":Vector3(-.045,-.025,.015),"muzzle":Vector3(0,.43,.5)},
 "sniper":{"scale":1.25,"yaw":PI,"grip":Vector3(0,.075,-.26),"support":Vector3(-.035,.01,-.20),"muzzle":Vector3(0,.10,.5)}}
static func create(kind:String)->Node3D:
 var root:=Node3D.new();root.name=kind.capitalize()+"Model"
 root.position=Vector3(-.15,.10,.16)
 var model:Node3D=load("res://assets/weapons/firearms/"+kind+".glb").instantiate();root.add_child(model)
 var spec:Dictionary=SPECS[kind];var factor:float=spec.scale
 model.rotation.y=spec.yaw;model.scale=Vector3.ONE*factor
 var pivot:Vector3=Basis(Vector3.UP,spec.yaw)*spec.grip*factor
 model.position=-pivot
 var muzzle:=Marker3D.new();muzzle.name="Muzzle";muzzle.position=Basis(Vector3.UP,spec.yaw)*spec.muzzle*factor-pivot;root.add_child(muzzle)
 var grip:=Marker3D.new();grip.name="RightGrip";grip.position=Vector3(0,-.015,0);root.add_child(grip)
 var support:=Marker3D.new();support.name="LeftGrip";support.position=spec.support;root.add_child(support)
 return root
