extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var failures:=0
var child:=-1
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func wait_for(test:Callable)->bool:
 var end:=Time.get_ticks_msec()+12000
 while not test.call() and Time.get_ticks_msec()<end:await process_frame
 return test.call()
func run():
 session=Session.new();root.add_child(session)
 var args:=OS.get_cmdline_user_args();var client:=not args.is_empty()
 var run_id:=args[0] if client else str(Time.get_ticks_usec())
 var result_path:="user://departure_"+run_id+".json"
 if client:
  check(session.join("127.0.0.1",29879)==OK,"client connects")
  if not await wait_for(func():return session.local_id>1 and session.model.state.get("departure_fixture",false)):
   check(false,"fixture arrives");quit(1);return
  session.send("travel",{"route":"bunker_to_city"})
  check(await wait_for(func():return session.model.state.get("departure_ready",{}).get(session.local_id,false)),"client receives authoritative ready")
  check(session.model.state.world=="bunker","one player cannot launch party")
  session.send("travel",{"route":"bunker_to_city"})
  check(await wait_for(func():return not session.model.state.get("departure_ready",{}).get(session.local_id,false)),"client receives cancellation")
  FileAccess.open(result_path+".cancel",FileAccess.WRITE).store_string("ok")
  check(await wait_for(func():return session.model.state.get("departure_ready",{}).get(1,false)),"client sees host readiness")
  session.send("travel",{"route":"bunker_to_city"})
  check(await wait_for(func():return session.model.state.world=="city"),"last client readiness changes both maps")
  check(session.model.state.departure_ready.is_empty(),"new map has no stale ready flags")
  FileAccess.open(result_path,FileAccess.WRITE).store_string(JSON.stringify({"failures":failures}))
 else:
  check(session.host(29879)==OK,"host starts")
  child=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",ProjectSettings.globalize_path("res://artifacts/base_tests/departure_client.log"),"--script","res://tests/base/departure_network_test.gd","--",run_id])
  if not await wait_for(func():return session.model.state.players.size()==2):
   check(false,"client joins");if child>0:OS.kill(child)
   quit(1);return
  var m=session.model
  for member in m.state.players.values():member.pos=Vector2.ZERO
  m.stations=[{"kind":"travel","uid":"bunker_to_city","world":"bunker","destination":"city","pos":Vector2.ZERO,"height":0,"spawn":Vector3(10,0,10)}]
  var start_revision:int=m.state.world_revision
  m.state.departure_fixture=true;session._broadcast_snapshot(true)
  check(await wait_for(func():return FileAccess.file_exists(result_path+".cancel")),"client toggles readiness twice over RPC")
  session.send("travel",{"route":"bunker_to_city"})
  check(await wait_for(func():return FileAccess.file_exists(result_path)),"client completes city transition")
  check(m.state.world=="city" and m.state.world_revision==start_revision+1,"authority transitions exactly once")
  if FileAccess.file_exists(result_path):check(int(JSON.parse_string(FileAccess.get_file_as_string(result_path)).failures)==0,"all remote assertions pass")
  if child>0 and OS.is_process_running(child):OS.kill(child)
 session.offline();session.queue_free();await process_frame
 print("DEPARTURE_NETWORK failures=",failures);quit(1 if failures else 0)
