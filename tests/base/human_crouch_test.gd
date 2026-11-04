extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func settle(actor,data):
 for i in range(120):actor.update_actor(data,1.0/60)
 actor.human_visual.skin.force_update_all_bone_transforms()
func run():
 for gender in ["male","female"]:
  var actor=load("res://features/player/base_actor.gd").new();actor.human_enabled=true;root.add_child(actor)
  var data={"pos":Vector2.ZERO,"aim":Vector2.UP,"velocity":Vector2.ZERO,"equipment":{},"appearance":load("res://features/player/appearance_rules.gd").defaults(gender)}
  settle(actor,data)
  var skin:Skeleton3D=actor.human_visual.skin
  var head:int=skin.find_bone("Head");var foot:int=skin.find_bone("FootL")
  var standing:float=skin.get_bone_global_pose(head).origin.y
  var foot_y:float=skin.get_bone_global_pose(foot).origin.y
  data.crouch=true;settle(actor,data)
  check(standing-skin.get_bone_global_pose(head).origin.y>.35,gender+" crouch visibly lowers head")
  check(absf(skin.get_bone_global_pose(foot).origin.y-foot_y)<.08,gender+" crouch keeps feet grounded")
  var h:Vector3=skin.get_bone_global_pose(skin.find_bone("ThighL")).origin
  var k:Vector3=skin.get_bone_global_pose(skin.find_bone("ShinL")).origin
  var a:Vector3=skin.get_bone_global_pose(foot).origin
  check((k-h).angle_to(a-k)>deg_to_rad(65),gender+" has a clearly bent knee")
  data.crouch=false;settle(actor,data)
  check(absf(skin.get_bone_global_pose(head).origin.y-standing)<.03,gender+" returns to standing height")
  actor.free()
 print("CROUCH failures=",failures);quit(1 if failures else 0)
