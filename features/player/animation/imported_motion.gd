extends RefCounted
## Retains imported skin/animation tracks; maps existing actions in actor space.
var actor:Node3D
var skin:Skeleton3D
var player:AnimationPlayer
var space:Transform3D
var rest:Array[Transform3D]=[]
var last:Array[Transform3D]=[]
var active_clip:=""
var clip_names:Dictionary={}
var elapsed:=0.0

func configure(owner:Node3D,source:Node3D,skeleton:Skeleton3D)->void:
 actor=owner;skin=skeleton
 space=actor.global_transform.affine_inverse()*skin.global_transform
 for i in skin.get_bone_count():rest.append(space*skin.get_bone_global_rest(i))
 for node in source.find_children("*","AnimationPlayer",true,false):player=node
 if player!=null:
  player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
  for name in player.get_animation_list():
   for kind in ["walk","run","dance"]:
    if kind in name:
     clip_names[kind]=name
     var animation:Animation=player.get_animation(name)
     animation.loop_mode=Animation.LOOP_LINEAR

func _delta(name:String)->Transform3D:
 var i:int=actor.skeleton.find_bone(name)
 return actor.skeleton.get_bone_global_pose(i)*actor.skeleton.get_bone_global_rest(i).affine_inverse() if i>=0 else Transform3D.IDENTITY

func _legacy()->Array[Transform3D]:
 var result:Array[Transform3D]=[]
 for i in skin.get_bone_count():
  var name:String=skin.get_bone_name(i)
  var driver:="Hips"
  if name=="Root":driver="Root"
  elif name=="Head" or name.begins_with("Neck"):driver="Head"
  elif name.begins_with("Spine") or name.ends_with("Clavicle"):driver="Spine"
  elif "Upperarm" in name or "Forearm" in name or "Hand" in name:driver="WingL" if name.begins_with("L_") else "WingR"
  elif "Foot" in name or "Toe" in name:driver="FootL" if name.begins_with("L_") else "FootR"
  result.append(_delta(driver)*rest[i])
 # Two-bone IK retains the previous crouch depth/jump tuck on the new skin.
 for side in ["L","R"]:
  var hi:int=skin.find_bone(side+"_Thigh")
  var ki:int=skin.find_bone(side+"_Calf")
  var ai:int=skin.find_bone(side+"_Foot")
  if mini(hi,mini(ki,ai))<0:continue
  var hip:Vector3=(_delta("Hips")*rest[hi]).origin
  var ankle:Vector3=(_delta("Foot"+side)*rest[ai]).origin
  var upper:float=rest[hi].origin.distance_to(rest[ki].origin)
  var lower:float=rest[ki].origin.distance_to(rest[ai].origin)
  var direction:Vector3=(ankle-hip).normalized()
  var distance:float=clampf(hip.distance_to(ankle),.01,upper+lower-.001)
  var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
  var bend:Vector3=Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
  var knee:Vector3=hip+direction*along+bend.normalized()*sqrt(maxf(0,upper*upper-along*along))
  var thigh_basis:=Basis(Quaternion((rest[ki].origin-rest[hi].origin).normalized(),(knee-hip).normalized()))
  var calf_basis:=Basis(Quaternion((rest[ai].origin-rest[ki].origin).normalized(),(ankle-knee).normalized()))
  for i in skin.get_bone_count():
   var n:String=skin.get_bone_name(i)
   if n.begins_with(side+"_Thigh"):result[i]=Transform3D(thigh_basis*rest[i].basis,hip+thigh_basis*(rest[i].origin-rest[hi].origin))
   elif n.begins_with(side+"_Calf"):result[i]=Transform3D(calf_basis*rest[i].basis,knee+calf_basis*(rest[i].origin-rest[ki].origin))
 # Keep shoulders attached while retaining the legacy hand/action target.
 for side in ["L","R"]:
  var hi:int=skin.find_bone(side+"_Upperarm")
  var ki:int=skin.find_bone(side+"_Forearm")
  var ai:int=skin.find_bone(side+"_Hand")
  if mini(hi,mini(ki,ai))<0:continue
  var shoulder:Vector3=(_delta("Spine")*rest[hi]).origin
  var hand:Vector3=result[ai].origin
  if actor.weapon_kind in ["rifle","pistol","sniper"]:
   var grip_weight:float=1.0-actor._unarmed_blend
   if side=="L" or actor._visual_action!="reload":grip_weight*=1.0-actor._visual_action_weight
   hand=hand.lerp(actor.weapon_grip(side),grip_weight)
  var upper:float=rest[hi].origin.distance_to(rest[ki].origin)
  var lower:float=rest[ki].origin.distance_to(rest[ai].origin)
  var direction:Vector3=(hand-shoulder).normalized()
  var distance:float=clampf(hand.distance_to(shoulder),.01,upper+lower-.001)
  hand=shoulder+direction*distance
  var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
  var outward:=Vector3(-1 if side=="L" else 1,0,.5).normalized()
  var bend:Vector3=(outward-direction*outward.dot(direction)).normalized()
  var elbow:Vector3=shoulder+direction*along+bend*sqrt(maxf(0,upper*upper-along*along))
  var upper_basis:=Basis(Quaternion((rest[ki].origin-rest[hi].origin).normalized(),(elbow-shoulder).normalized()))
  var lower_basis:=Basis(Quaternion((rest[ai].origin-rest[ki].origin).normalized(),(hand-elbow).normalized()))
  for i in skin.get_bone_count():
   var n:String=skin.get_bone_name(i)
   if n.begins_with(side+"_Upperarm"):result[i]=Transform3D(upper_basis*rest[i].basis,shoulder+upper_basis*(rest[i].origin-rest[hi].origin))
   elif n.begins_with(side+"_Forearm"):result[i]=Transform3D(lower_basis*rest[i].basis,elbow+lower_basis*(rest[i].origin-rest[ki].origin))
  result[ai].origin=hand
 return result

func advance(data:Dictionary,dt:float)->void:
 skin.clear_bones_global_pose_override()
 var clip:=""
 var dancing:bool=data.get("dancing",false) and float(data.get("hp",100))>0 and not data.get("roll",{}).get("active",false) and Vector2(data.get("velocity",Vector2.ZERO)).length()<.1
 if dancing:clip="dance"
 elif actor.animation_state in ["walk","run"]:clip=actor.animation_state
 var legacy:=_legacy()
 var result:Array[Transform3D]=legacy.duplicate()
 if not clip.is_empty() and player!=null and clip_names.has(clip):
  if active_clip!=clip:
   player.play(clip_names[clip]);elapsed=0.0
  var speed:float=clampf(actor._speed/(6.1 if clip=="run" else 1.85),.65,1.5)
  if clip=="dance":speed=1.0
  # Backpedalling preserves facing and reduced movement speed.
  if clip!="dance" and actor._backward_blend>.5:speed=-speed
  elapsed+=dt*speed
  var animation:Animation=player.get_animation(clip_names[clip])
  if clip=="dance":elapsed=maxf(elapsed,float(data.get("dance_time",0)))
  var time:float=elapsed
  player.seek(fposmod(time,animation.length),true)
  for i in skin.get_bone_count():result[i]=space*skin.get_bone_global_pose(i)
  var root_id:int=skin.find_bone("Hip")
  if root_id>=0:
   var offset:Vector3=result[root_id].origin-rest[root_id].origin
   offset.y=0
   for i in result.size():result[i].origin-=offset
  if not dancing:
   var upper:float=maxf(actor._visual_action_weight,1.0-actor._unarmed_blend)
   for i in skin.get_bone_count():
    var n:String=skin.get_bone_name(i)
    if "arm" in n or "Hand" in n or "Clavicle" in n or n.begins_with("Spine") or n.begins_with("Neck") or n=="Head":
     result[i]=result[i].interpolate_with(legacy[i],upper)
 else:
  if player!=null:player.stop()
  skin.reset_bone_poses()
 active_clip=clip
 var blend:float=1.0-exp(-dt*25)
 for i in skin.get_bone_count():
  if last.size()==result.size():result[i]=last[i].interpolate_with(result[i],blend)
  skin.set_bone_global_pose_override(i,space.affine_inverse()*result[i],1.0,true)
 last=result
 var left_hand:int=skin.find_bone("L_Hand")
 if left_hand>=0:
  var hand_world:Vector3=skin.global_transform*skin.get_bone_global_pose(left_hand).origin
  actor.held_props.reload.global_transform=Transform3D(actor.global_basis,hand_world+actor.global_basis*Vector3(0,-.04,-.02))
 if dancing:
  actor.weapon.visible=false;actor.flash.visible=false;actor.flash_light.visible=false
  actor.animation_state="dance"
