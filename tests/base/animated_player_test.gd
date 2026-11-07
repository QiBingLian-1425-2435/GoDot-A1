extends SceneTree
const Main=preload("res://app/main.gd")
const Rules=preload("res://features/player/appearance_rules.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if not "finite bone" in label or not ok:print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func key(code:int)->InputEventKey:
 var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=true;return e
func run():
 var game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game)
 game.profile_path="user://dance_test_%s.json"%Time.get_ticks_usec()
 game._start_solo();game.sound.muted=true
 game.session.set_physics_process(false);game.set_physics_process(false)
 var m=game.session.model;var p:Dictionary=m.state.players[1]
 p.pos=Vector2(-2,-5);p.aim=Vector2.UP
 p.equipment.weapon={};p.equipment.helmet={};p.equipment.armor={}
 game._unhandled_input(key(KEY_F2))
 check(p.get("dancing",false),"F2 starts authoritative dance")
 game._input(key(KEY_TAB))
 check(not p.dancing,"inventory key cancels before UI consumes event")
 game._unhandled_input(key(KEY_F2));game._unhandled_input(key(KEY_F2))
 check(not p.dancing,"F2 toggles dance off")
 game._unhandled_input(key(KEY_F2))
 var mouse:=InputEventMouseMotion.new();mouse.relative=Vector2(5,0);game._input(mouse)
 check(not p.dancing,"mouse aiming cancels dance")
 m.reset_transients(1);m.command(1,"dance")
 m.command(1,"move",{"roll_seq":1});m.tick(.016)
 check(not p.dancing,"jump request cancels dance")
 for action in ["move","reload","fire","travel","use"]:
  m.reset_transients(1);m.command(1,"dance")
  m.command(1,action,{"direction":Vector2.UP});m.tick(.016)
  check(not p.dancing,"operation cancels dance: "+action)
 m.reset_transients(1);m.command(1,"dance");m.reset_transients(1)
 check(not p.dancing,"world/session reset clears dance")
 for gender in ["male","female"]:
  p.appearance=Rules.defaults(gender);game._update_actors(.016)
  var a=game.actors[1];var motion=a.human_visual.imported_motion
  check(motion.clip_names.size()==3,gender+" includes walk run dance")
  for action in ["walk","run","dance","crouch","jump","idle"]:
   p.velocity=Vector2(0,-6.1 if action=="run" else -3.7) if action in ["walk","run"] else Vector2.ZERO
   p.dancing=action=="dance";p.dance_time=2.0;p.sprint=action=="run";p.crouch=action=="crouch"
   p.roll={"active":true,"time":.25} if action=="jump" else {}
   for i in 40:a.update_actor(p,.016,true)
   if action in ["walk","run","dance"]:check(motion.active_clip==action,gender+" plays imported "+action)
   var sk:Skeleton3D=a.human_visual.skin
   var hip:Vector3=(motion.space*sk.get_bone_global_pose(sk.find_bone("Hip"))).origin
   check(Vector2(hip.x,hip.z).length()<.35,gender+" in-place "+action)
   var before:Transform3D=sk.get_bone_global_pose(sk.find_bone("L_Foot"))
   for i in 12:
    p.dance_time+=.016;a.update_actor(p,.016,true)
   var after:Transform3D=sk.get_bone_global_pose(sk.find_bone("L_Foot"))
   if action in ["walk","run","dance"]:check(not before.is_equal_approx(after),gender+" animated foot changes "+action)
   for i in sk.get_bone_count():check(sk.get_bone_global_pose(i).is_finite(),gender+" finite bone "+str(i))
   if DisplayServer.get_name()!="headless":
    game.camera.position=a.position+Vector3(2.6,1.9,-4.2);game.camera.look_at(a.position+Vector3(0,.8,0));game.camera.size=3.5
    game.set_process(false)
    await process_frame;await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://artifacts/animated_%s_%s.png"%[gender,action])
 print("ANIMATED_PLAYER failures=",failures)
 game.queue_free();await process_frame;quit(1 if failures else 0)
