extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Session=preload("res://app/network/session.gd")
const Spread=preload("res://features/combat/firearm_spread.gd")
const Hurt=preload("res://features/player/animation/hurt_pose.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error("COMBAT_FEEDBACK FAIL: "+label)
func fixture():
 var m=Model.new();m.add_player(1,"test");m.state.world="city";m.bounds=Rect2(-100,-100,200,200);m.obstacles.clear();m.state.targets=[];m.state.players[1].pos=Vector2.ZERO
 return m
func run():
 seed(1234)
 for kind in ["rifle","pistol"]:
  var m=fixture();var p:Dictionary=m.state.players[1];p.equipment.weapon=m._item(kind,1);p.ammo=40;p.aim=Vector2.UP
  var previous:=0.0;var widest:=0.0
  for shot in 18:
   check(m.command(1,"fire"),kind+" accepts shot")
   var trace:Dictionary=m.state.shots.back();var cone:float=trace.spread_angle
   var error:float=absf(Vector2(p.aim).angle_to((Vector2(trace.to)-Vector2(trace.from)).normalized()))
   check(cone>=previous and cone<=deg_to_rad(Spread.LIMITS[kind])+.00001,"cone grows within cap")
   check(error<=cone+.00001,"authoritative bullet stays within current cone")
   if shot==0:check(is_zero_approx(error),"fresh first shot uses original aim")
   widest=maxf(widest,error);previous=cone
   var heat:float=p.gun_bloom;var ammo:int=p.ammo
   check(not m.command(1,"fire") and p.ammo==ammo and p.gun_bloom==heat,"cooldown rejection cannot grow bloom")
   var interval:float=m.Items.definition(kind).fire_interval
   for tick in ceili((interval+.01)/.01):m.tick(.01)
  check(is_equal_approx(p.gun_bloom,Spread.LIMITS[kind]) and widest>deg_to_rad(1),"sustained stream reaches wide distribution")
  var heat:float=p.gun_bloom;m.tick(.05);check(p.gun_bloom==heat,"brief intershot pause does not cool")
  for i in 8:m.tick(.1)
  check(p.gun_bloom>0 and p.gun_bloom<heat,"stopped firing recovers gradually")
  for i in 40:m.tick(.1)
  check(is_zero_approx(p.gun_bloom),"long pause returns original accuracy")
  p.gun_bloom=5;p.equipment.weapon=m._item("sniper",1);p.ammo=5;p.fire_timer=0
  check(m.command(1,"fire") and m.state.shots.back().spread_angle==0 and Spread.angle(p)==0,"sniper retains original accuracy and reticle")
 var m=fixture();var p:Dictionary=m.state.players[1]
 check(m.enemy_damage(1,18) and p.hurt_seq==1 and p.hp==82,"monster damage confirms hurt sequence")
 check(not m.enemy_damage(1,-10) and p.hurt_seq==1,"rejected damage cannot animate")
 var host=Session.new();host.model=m
 p.gun_bloom=4.35;p.gun_bloom_wait=.17;p.hurt_seq=254
 var client=Session.new();client.mode="client";client._session_token=4;client.local_id=1;client.model=fixture()
 client._apply_motion(host._motion_rows(),4,1,0,0)
 var received:Dictionary=client.model.state.players[1]
 check(is_equal_approx(received.gun_bloom,4.35) and is_equal_approx(received.gun_bloom_wait,.17) and received.hurt_seq==254,"compact movement carries recoil and hurt without growing packet")
 m.mark_player_hurt(p);m.mark_player_hurt(p)
 client._apply_motion(host._motion_rows(),4,2,0,0)
 check(received.hurt_seq==0,"hurt sequence wrap is consistent")
 m.state.enemies[1]=m.Enemies.create_zombie(1,Vector3(0,0,-2),Vector2.DOWN)
 var e:Dictionary=m.state.enemies[1];e.hp=0;m.Enemies.hit(e,Vector2.UP,true)
 check(e.hurt_sound_seq==1 and e.hurt_sound_melee,"killing hit retains melee sound event")
 client.model.state.enemies[1]=e.duplicate(true)
 host._session_token=4;client._apply_enemies(host._enemy_rows(),4,3,0)
 check(client.model.state.enemies[1].hurt_sound_seq==1,"compact enemy stream carries confirmed hit sound")
 host.free();client.free()
 print("COMBAT_FEEDBACK_RULES ",checks," checks failures=",failures);quit(1 if failures else 0)
