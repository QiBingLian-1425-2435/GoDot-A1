extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var child:=-1
var client:=false
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func wait_for(test:Callable)->bool:
 var end:=Time.get_ticks_msec()+12000
 while not test.call() and Time.get_ticks_msec()<end:await process_frame
 return test.call()
func player()->Dictionary:return session.model.state.players.get(session.local_id,{})
func run():
 client="--feedback-client" in OS.get_cmdline_user_args()
 session=Session.new();root.add_child(session)
 if client:
  session.join("127.0.0.1",29899)
  check(await wait_for(func():return player().get("feedback_ready",false)),"host fixture received")
  session.send("move",{"aim":Vector2.UP});await create_timer(.15).timeout
  for i in 12:
   session.send("fire",{"gun_bloom":0,"spread_angle":0})
   await create_timer(.15).timeout
  check(await wait_for(func():return player().get("shots",0)==12),"twelve remote shots accepted")
  check(float(player().get("gun_bloom",0))>6.5 and player().ammo==28,"confirmed bloom grows with actual ammunition")
  var enemy:Dictionary=session.model.state.enemies[1]
  check(enemy.get("hurt_sound_seq",0)>=12 and not enemy.get("hurt_sound_melee",true),"confirmed gun hit sound events reach guest")
  session.send("hold_throwable",{"index":-1})
  check(await wait_for(func():return player().get("hurt_seq",0)==1 and player().hp==82),"monster hurt sequence reaches guest")
  var initial:float=player().gun_bloom
  await create_timer(.6).timeout
  check(player().gun_bloom>0 and player().gun_bloom<initial,"remote stop gradually recovers accuracy")
  check(await wait_for(func():return player().get("gun_bloom",1)<.01),"remote bloom returns to zero")
  check(player().shots==12 and player().ammo==28,"recovery never creates shots or consumes ammo")
  print("FEEDBACK_CLIENT failures=",failures)
 else:
  session.host(29899);session.model.obstacles.clear();session.model.state.targets=[]
  child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/combat_feedback_client.log","--script","res://tests/base/combat_feedback_network_test.gd","--","--feedback-client"])
  check(await wait_for(func():return session.model.state.players.size()==2),"guest connected")
  var remote_id:=0
  for id in session.model.state.players:
   if id!=1:remote_id=id
  var m=session.model;m.state.world="city";m.enemy_sight=func(_a,_b):return false
  var p:Dictionary=m.state.players[remote_id];p.pos=Vector2.ZERO;p.ammo=40;p.feedback_ready=true
  var e:Dictionary=m.Enemies.create_zombie(1,Vector3(0,0,-4),Vector2.DOWN);e.hp=10000;m.state.enemies[1]=e
  session._broadcast_snapshot(true)
  check(await wait_for(func():return p.has("held_throwable")),"client acknowledges burst")
  check(p.shots==12 and e.hp==9592,"host applies authoritative spread and damage")
  m.enemy_damage(remote_id,18);session._broadcast_snapshot(true)
  check(await wait_for(func():return not OS.is_process_running(child)),"client finished")
  var log:=FileAccess.get_file_as_string("res://artifacts/combat_feedback_client.log")
  check("FEEDBACK_CLIENT failures=0" in log and not "FAIL:" in log,"all remote feedback assertions pass")
  if child>0 and OS.is_process_running(child):OS.kill(child)
 session.offline();session.queue_free();await process_frame
 print("COMBAT_FEEDBACK_NETWORK failures=",failures);quit(1 if failures else 0)
