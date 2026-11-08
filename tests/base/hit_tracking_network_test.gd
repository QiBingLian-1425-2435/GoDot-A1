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
 var until:=Time.get_ticks_msec()+12000
 while not test.call() and Time.get_ticks_msec()<until:await process_frame
 return test.call()
func player()->Dictionary:return session.model.state.players.get(session.local_id,{})
func run():
 client="--tracking-client" in OS.get_cmdline_user_args()
 session=Session.new();root.add_child(session)
 if client:
  session.join("127.0.0.1",29902)
  check(await wait_for(func():return player().get("tracking_ready",false)),"fixture received")
  session.send("move",{"aim":Vector2.UP});await create_timer(.15).timeout
  session.send("fire")
  check(await wait_for(func():return session.model.state.enemies[1].get("aggro_target",0)==session.local_id),"host selects unseen remote shooter")
  check(await wait_for(func():return session.model.state.enemies[1].pos.y>1 and session.model.state.enemies[1].mode=="chase"),"confirmed blind chase arrives over transport")
  # Move sideways behind cover; host must follow the changing position.
  session.send("move",{"direction":Vector2.RIGHT,"aim":Vector2.UP})
  await create_timer(.2).timeout
  session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP})
  check(await wait_for(func():return session.model.state.enemies[1].aim.x>.01),"enemy retargets current unseen attacker position")
  check(await wait_for(func():return session.model.state.enemies[1].mode=="return"),"confirmed five second pursuit expires")
  check(await wait_for(func():return session.model.state.enemies[1].get("aggro_target",-1)==0),"expired tracking state reaches client")
  print("TRACKING_CLIENT failures=",failures)
 else:
  session.host(29902);session.model.obstacles.clear();session.model.state.targets=[]
  child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/hit_tracking_client.log","--script","res://tests/base/hit_tracking_network_test.gd","--","--tracking-client"])
  check(await wait_for(func():return session.model.state.players.size()==2),"guest joined")
  var id:=0
  for candidate in session.model.state.players:
   if candidate!=1:id=candidate
  var m=session.model;m.state.world="city";m.bounds=Rect2(-100,-100,200,200)
  m.enemy_sight=func(_a,_b):return false
  m.enemy_move=func(_id,at,offset):return at+Vector3(offset.x,0,offset.y)
  m.enemy_push=m.enemy_move
  m.state.players[1].pos=Vector2(70,70)
  var p:Dictionary=m.state.players[id];p.pos=Vector2(0,20);p.tracking_ready=true
  var e:Dictionary=m.Enemies.create_zombie(1,Vector3.ZERO,Vector2.UP);m.state.enemies[1]=e
  session._broadcast_snapshot(true)
  check(await wait_for(func():return e.get("aggro_target",0)==id),"host resolves attacker from real shot")
  var until:float=e.aggro_until
  check(await wait_for(func():return e.mode=="return"),"host returns after forced window")
  check(m._clock>=until and m._clock-until<.3,"pursuit expires at five host seconds")
  check(await wait_for(func():return not OS.is_process_running(child)),"guest finished")
  var report:=FileAccess.get_file_as_string("res://artifacts/hit_tracking_client.log")
  check("TRACKING_CLIENT failures=0" in report and not "FAIL:" in report,"all remote assertions pass")
  if child>0 and OS.is_process_running(child):OS.kill(child)
 session.offline();session.queue_free();await process_frame
 print("HIT_TRACKING_NETWORK failures=",failures);quit(1 if failures else 0)
