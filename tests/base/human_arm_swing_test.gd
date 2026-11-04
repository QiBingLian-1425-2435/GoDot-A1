extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func sample(actor,data)->float:
 for i in range(90):actor.update_actor(data,1.0/60)
 var low:=100.0;var high:=-100.0
 for i in range(180):
  actor.update_actor(data,1.0/60)
  var angle:float=actor.skeleton.get_bone_pose_rotation(actor.skeleton.find_bone("WingL")).get_euler().x
  low=minf(low,angle);high=maxf(high,angle)
 return high-low
func run():
 for gender in ["male","female"]:
  var actor=load("res://features/player/base_actor.gd").new();actor.human_enabled=true;root.add_child(actor)
  var data={"pos":Vector2.ZERO,"aim":Vector2.UP,"velocity":Vector2(0,-3.7),"equipment":{},"appearance":load("res://features/player/appearance_rules.gd").defaults(gender)}
  var walk:=sample(actor,data)
  data.sprint=true;data.velocity=Vector2(0,-6);var sprint:=sample(actor,data)
  check(walk>.25 and walk<.6,gender+" walk has a restrained arm swing")
  check(sprint>walk*2.0,gender+" running clearly increases swing")
  data.velocity=Vector2.ZERO;data.sprint=false
  check(sample(actor,data)<.05,gender+" stopped arms settle")
  data.equipment={"weapon":{"kind":"rifle"}};data.velocity=Vector2(0,-3.7)
  var armed_walk:=sample(actor,data);data.sprint=true;data.velocity=Vector2(0,-6)
  check(sample(actor,data)>armed_walk,gender+" armed running increases swing")
  data.ads=true
  check(sample(actor,data)<.08,gender+" aiming keeps arms stable")
  actor.free()
 print("ARM_SWING failures=",failures);quit(1 if failures else 0)
