extends SceneTree
const Session=preload("res://app/network/session.gd")
const Rules=preload("res://features/combat/throwable_system.gd")
var session
var client:=false
var child_pid:=-1
var elapsed:=0.0
var round_index:=0
var phase:=0
var remote_id:=0
var stamp:=0.0
var failures:=0
func _initialize():call_deferred("start")
func check(ok:bool,label:String):
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func start():
 client="--throw-client" in OS.get_cmdline_user_args()
 session=Session.new();root.add_child(session)
 if client:session.join("127.0.0.1",29863)
 else:
  session.host(29863);session.model.obstacles.clear();session.model.state.throw_round=0
  child_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/throwable_client.log","--script","res://tests/base/throwable_network_test.gd","--","--throw-client"])
func _process(dt:float):
 elapsed+=dt
 if elapsed>22:finish(false);return
 if session==null:return
 if client:
  if session.local_id<=1 or not session.model.state.players.has(session.local_id):return
  var p:Dictionary=session.model.state.players[session.local_id]
  if p.bag[round_index].get("kind","")!=Rules.KINDS[round_index]:return
  session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP,"ads":phase>=2})
  if phase==0:session.send("use",{"index":round_index});phase=1;stamp=elapsed
  if phase==1 and elapsed-stamp>.25:
   session.send("fire",{"target":Vector3(0,0,-6)});phase=2;stamp=elapsed
  if phase==2 and elapsed-stamp>.25:
   check(session.model.state.field_effects.is_empty() and p.bag[round_index].count==3,"remote no-aim rejected")
   session.send("fire",{"target":Vector3(0,999,-6)})
   session._intent.rpc_id(1,"fire",{"target":Vector3(0,999,-6),"world_revision":int(session.model.state.world_revision)},session._session_token,session._intent_seq)
   phase=3
  if phase==3 and not session.model.state.field_effects.is_empty():
   var e:Dictionary=session.model.state.field_effects[0]
   if e.get("phase","")=="active":
    check(e.owner==session.local_id and Vector3(e.pos).distance_to(Vector3(0,0,-6))<.05,"confirmed owner and landing")
    check(p.bag[round_index].count==2 and session.model.state.field_effects.size()==1,"duplicate sequence consumes once")
    check(float(e.ttl)<=Rules.DURATIONS[e.kind] and float(e.ttl)>0,"confirmed active duration")
    session.send("hold_throwable",{"index":-1});phase=4
  if phase==4 and int(session.model.state.get("throw_round",0))>round_index:
   check(session.model.state.field_effects.is_empty(),"host expiration clears client effect")
   round_index+=1;phase=0
   if round_index==3:print("THROWABLE_CLIENT failures=",failures);quit(1 if failures else 0)
 else:
  for id in session.model.state.players:
   if id!=1 and remote_id==0:
    remote_id=id
    var p:Dictionary=session.model.state.players[id];p.pos=Vector2.ZERO;p.bag=session.model._empty_slots(24)
    for i in 3:p.bag[i]=session.model._item(Rules.KINDS[i],3)
  if remote_id!=0 and session.model.state.players.has(remote_id):
   var p:Dictionary=session.model.state.players[remote_id]
   if not session.model.state.field_effects.is_empty() and session.model.state.field_effects[0].get("phase","")=="active" and p.get("held_throwable","")=="":
    for i in 160:session.model.tick(.1)
    session.model.state.throw_round+=1
  if remote_id!=0 and not OS.is_process_running(child_pid):
   var report:=FileAccess.get_file_as_string("res://artifacts/throwable_client.log")
   finish("THROWABLE_CLIENT failures=0" in report and not "FAIL:" in report)
func finish(ok:bool):
 if child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
 if session!=null:session.offline()
 print("THROWABLE_NETWORK failures=",0 if ok else 1);quit(0 if ok else 1)
