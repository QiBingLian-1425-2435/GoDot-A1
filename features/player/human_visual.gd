extends RefCounted
const Appearance=preload("res://features/player/appearance_rules.gd")
const TEXTURE_BASE := {"male":{"hair":"#493329","skin":"#d9ad83","shirt":"#706847","pants":"#967e53"},"female":{"hair":"#493329","skin":"#d9ad83","shirt":"#b58a4b","pants":"#736e4c"}}
var actor:Node3D
var source:Node3D
var skin:Skeleton3D
var meshes:Array[MeshInstance3D]=[]
var materials:Dictionary={}
var gender:=""
var current:Dictionary={}
func configure(owner:Node3D)->void:
 actor=owner
 var keep:Array=[actor.helmet,actor.backpack,actor.armor,actor.weapon]
 keep.append_array(actor.held_props.values())
 for attachment in actor.skeleton.get_children():
  if attachment is BoneAttachment3D:
   for child in attachment.get_children():
    if child not in keep:child.visible=false
 update(Appearance.defaults())
func update(value:Variant)->void:
 var appearance:Dictionary=Appearance.normalized(value)
 if appearance!=current:
  if gender!=appearance.gender:
   if is_instance_valid(source):source.free()
   meshes.clear();materials.clear();skin=null
   gender=appearance.gender
   source=load("res://assets/characters/adventurers/%s.glb"%gender).instantiate();actor.add_child(source)
   for node in source.find_children("*","Skeleton3D",true,false):skin=node
   for child in source.find_children("*","MeshInstance3D",true,false):
    meshes.append(child)
    for surface in child.mesh.get_surface_count():
     var material:StandardMaterial3D=child.mesh.surface_get_material(surface).duplicate()
     child.set_surface_override_material(surface,material)
     var part:String=material.resource_name.get_slice(".",0)
     if not materials.has(part):materials[part]=[]
     materials[part].append(material)
  var defaults:Dictionary=TEXTURE_BASE[gender]
  for part in Appearance.PARTS:
   var color:=Color(appearance[part]);var base:=Color(defaults[part])
   for material in materials.get(part,[]):material.albedo_color=Color(color.r/base.r,color.g/base.g,color.b/base.b,1)
  current=appearance.duplicate(true)
 sync_pose()
func sync_pose()->void:
 if not is_instance_valid(skin):return
 for i in skin.get_bone_count():
  var driver:int=actor.skeleton.find_bone(skin.get_bone_name(i))
  if driver<0:continue
  var delta:Transform3D=actor.skeleton.get_bone_global_pose(driver)*actor.skeleton.get_bone_global_rest(driver).affine_inverse()
  # Existing action clips pivot near the elbow. Only locomotion swing is
  # translated to a shoulder pivot so equipment/action poses keep their anchors.
  var bone_name:String=skin.get_bone_name(i)
  if bone_name in ["WingL","WingR"]:
   var left:bool=bone_name=="WingL"
   var angle:float=actor.locomotion_arm_angles.x if left else actor.locomotion_arm_angles.y
   var swing_basis:=Basis(Vector3.RIGHT,angle)
   var elbow:Vector3=actor.skeleton.get_bone_global_rest(driver).origin
   var shoulder:=Vector3(-.28 if left else .28,1.20,0.0)
   var offset:Vector3=shoulder-elbow
   var before_swing:Basis=delta.basis*swing_basis.inverse()
   delta.origin+=before_swing*(offset-swing_basis*offset)
  skin.set_bone_global_pose_override(i,delta*skin.get_bone_global_rest(i),1.0,true)
 _bend_legs()
func _bend_legs()->void:
 var crouch:float=actor._crouch_blend
 for side in ["L","R"]:
  var foot:int=skin.find_bone("Foot"+side)
  var thigh:int=skin.find_bone("Thigh"+side)
  var shin:int=skin.find_bone("Shin"+side)
  if thigh<0 or shin<0 or foot<0:continue
  var driver:int=actor.skeleton.find_bone("Foot"+side)
  var step:Transform3D=actor.skeleton.get_bone_global_pose(driver)*actor.skeleton.get_bone_global_rest(driver).affine_inverse()
  var rest_hip:Vector3=skin.get_bone_global_rest(thigh).origin
  var rest_knee:Vector3=skin.get_bone_global_rest(shin).origin
  var rest_ankle:Vector3=skin.get_bone_global_rest(foot).origin
  var hip_driver:int=actor.skeleton.find_bone("Hips")
  var hip_delta:Vector3=actor.skeleton.get_bone_global_pose(hip_driver).origin-actor.skeleton.get_bone_global_rest(hip_driver).origin
  var hip:Vector3=rest_hip+hip_delta
  var ankle:Vector3=step*rest_ankle
  var upper:float=rest_hip.distance_to(rest_knee)
  var lower:float=rest_knee.distance_to(rest_ankle)
  var direction:Vector3=(ankle-hip).normalized()
  var distance:float=clampf(hip.distance_to(ankle),.02,upper+lower-.001)
  var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
  var bend:Vector3=Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
  if bend.length_squared()<.001:bend=Vector3.FORWARD
  var knee:Vector3=hip+direction*along+bend.normalized()*sqrt(maxf(0,upper*upper-along*along))
  for entry in [[thigh,rest_hip,rest_knee,hip,knee],[shin,rest_knee,rest_ankle,knee,ankle]]:
   var index:int=entry[0]
   var rest:Transform3D=skin.get_bone_global_rest(index)
   var pose:=Transform3D(Basis(Quaternion((entry[2]-entry[1]).normalized(),(entry[4]-entry[3]).normalized()))*rest.basis,entry[3])
   skin.set_bone_global_pose_override(index,pose,1.0,true)
  var foot_rest:Transform3D=skin.get_bone_global_rest(foot)
  var planted:=Transform3D(step.basis.slerp(Basis.IDENTITY,crouch)*foot_rest.basis,ankle)
  skin.set_bone_global_pose_override(foot,planted,1.0,true)

func set_helmet(visible:bool)->void:
 for material in materials.get("hair",[]):
  material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if visible else BaseMaterial3D.TRANSPARENCY_DISABLED
  material.albedo_color.a=0.0 if visible else 1.0
