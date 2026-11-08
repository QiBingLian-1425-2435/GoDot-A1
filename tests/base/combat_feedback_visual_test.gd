extends SceneTree
const Main=preload("res://app/main.gd")
const Hurt=preload("res://features/player/animation/hurt_pose.gd")
const Appearance=preload("res://features/player/appearance_rules.gd")
var game
var failures:=0
var sounds:Array[String]=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func capture(name:String):
 if DisplayServer.get_name()=="headless":return
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/feedback_"+name+".png")
func run():
 game=Main.new();game.smoke=true;game.elapsed=-10000;root.add_child(game);game._start_solo();game.sound.muted=false
 game.set_process(false);game.set_physics_process(false);game.session.set_physics_process(false)
 game.sound.sound_played.connect(func(kind):sounds.append(kind))
 var m=game.session.model
 for route in m.stations:
  if route.get("destination","")!="city":continue
  var p:Dictionary=m.state.players[1];p.pos=route.pos;p.height=route.height;m.command(1,"travel",{"route":route.uid});break
 game._sync_world()
 while game.world_loading:await process_frame
 await physics_frame;await physics_frame
 game.enemy_director.update(game,.016)
 var probe=game.enemy_director.body_for(-1);var e:Dictionary={};var player_at:=Vector3.ZERO
 for candidate in m.state.enemies.values():
  for i in 16:
   var dir:=Vector2.from_angle(TAU*i/16);var at:Vector3=m.Enemies.at(candidate)
   for j in 10:at=probe.move_spatial(at,dir*.3)
   if at.distance_to(m.Enemies.at(candidate))>2.8 and game.enemy_director.clear_sight(m.Enemies.at(candidate)+Vector3.UP,at+Vector3.UP):e=candidate;player_at=at;break
  if not e.is_empty():break
 check(not e.is_empty(),"actual city has visible firing lane")
 if e.is_empty():game.queue_free();quit(1);return
 for enemy in m.state.enemies.values():
  if enemy.id!=e.id:enemy.hp=0
 var p:Dictionary=m.state.players[1];p.pos=Vector2(player_at.x,player_at.z);p.height=player_at.y;p.aim=(e.pos-p.pos).normalized();m.enemy_sight=func(_a,_b):return false
 for i in 15:game._process(.03)
 sounds.clear();p.fire_timer=0
 check(m.command(1,"fire"),"confirmed gun hit")
 game._process(.02)
 check(sounds.count("enemy_hit")==1,"gun hit plays one creature impact")
 for i in 10:game._process(.02)
 check(sounds.count("enemy_hit")==1,"repeated confirmed frames do not replay hit")
 e.hp=100;e.mode="idle";e.timer=0
 # Exercise a real confirmed melee event using the normal host rule at close range.
 var toward:Vector2=(p.pos-e.pos).normalized()
 var close:Vector3=probe.move_spatial(m.Enemies.at(e),toward*1.05);p.pos=Vector2(close.x,close.z);p.height=close.y;p.aim=(e.pos-p.pos).normalized()
 p.equipment.weapon=m._item("baton",1);p.ammo=0;p.fire_timer=0
 m.command(1,"move",{"aim":p.aim,"ads":true});m.tick(.01);m.command(1,"fire")
 for i in 28:
  m.command(1,"move",{"aim":p.aim,"ads":true});m.tick(.01);game._process(.01)
 check(sounds.count("enemy_slash")==1,"melee hit plays one distinct creature impact")
 for gender in ["male","female"]:
  p.appearance=Appearance.defaults(gender);p.velocity=Vector2.ZERO;p.ads=false;p.equipment.weapon={};p.held_throwable="";p.anim_action="";p.anim_duration=0
  for i in 25:game._process(.025)
  var actor=game.actors[1];var motion=actor.human_visual.imported_motion
  var baseline:Array[Transform3D]=motion.rest.duplicate()
  var posed:Array[Transform3D]=baseline.duplicate()
  var hurt=Hurt.new();hurt.observe({"hurt_seq":0},.01);hurt.observe({"hurt_seq":1},.05);hurt.apply(posed,motion.skin)
  var hand:int=motion.skin.find_bone("Head");var foot:int=motion.skin.find_bone("R_Foot");var hip:int=motion.skin.find_bone("Hip")
  check(posed[hand].origin.distance_to(baseline[hand].origin)>.015 and posed[foot]==baseline[foot] and posed[hip]==baseline[hip],gender+" hurt moves upper body but preserves hip and feet")
  p.hp=100;m.enemy_damage(1,18)
  game._process(.05)
  check(motion.hurt.time<Hurt.DURATION,gender+" actual player damage starts flinch")
  await capture(gender+"_hurt")
  for i in 14:game._process(.025)
  check(motion.hurt.time>=Hurt.DURATION,gender+" flinch ends automatically")
 p.equipment.weapon=m._item("rifle",1);p.ammo=40;p.fire_timer=0;p.gun_bloom=0;p.gun_bloom_wait=0
 game.crosshair.active=true;game.crosshair.aiming=true
 var target:=Vector3(p.pos.x,p.height+.75,p.pos.y)+Vector3(p.aim.x,0,p.aim.y)*10
 game.crosshair.set_accuracy(p,game.camera,target);game.crosshair._process(.1)
 var narrow:float=game.crosshair.spread_target
 for i in 14:
  p.fire_timer=0;m.command(1,"fire");m.tick(.1)
 game.crosshair.set_accuracy(p,game.camera,target);game.crosshair._process(.1)
 check(game.crosshair.spread_target>narrow+10,"crosshair matches expanded physical cone")
 await capture("wide_crosshair")
 for i in 40:m.tick(.1)
 game.crosshair.set_accuracy(p,game.camera,target);game.crosshair._process(.1)
 check(game.crosshair.spread_target<.01,"crosshair recovers with cooled weapon")
 game.queue_free();await process_frame
 print("COMBAT_FEEDBACK_VISUAL failures=",failures);quit(1 if failures else 0)
