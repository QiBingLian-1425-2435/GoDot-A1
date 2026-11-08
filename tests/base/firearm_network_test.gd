extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var child_pid:=-1
var client:=false
var elapsed:=0.0
var phase:=0
var remote_id:=0
var saw_reload:=false
var confirmed_shot:=false
func _initialize():call_deferred("start")
func start():
 client="--firearm-client" in OS.get_cmdline_user_args()
 session=Session.new();root.add_child(session)
 if client:session.join("127.0.0.1",29839)
 else:
  session.host(29839)
  child_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/firearm_network_client.log","--script","res://tests/base/firearm_network_test.gd","--","--firearm-client"])
func _process(dt:float):
 elapsed+=dt
 if elapsed>15:finish(false);return
 if session==null:return
 if client:
  if session.local_id<=1 or not session.model.state.players.has(session.local_id):return
  var p:Dictionary=session.model.state.players[session.local_id]
  if p.equipment.weapon.get("kind","")!="sniper":return
  if phase==0:session.send("fire");phase=1
  if p.reloading:saw_reload=true
  if phase==1 and p.ammo==5 and not p.reloading:session.send("fire");phase=2
  if phase==2 and p.shots==1 and p.ammo==4:
   print("PASS: client observed sniper reload and shot" if saw_reload else "FAIL: client missed sniper reload")
   phase=3;quit(0 if saw_reload else 1)
 else:
  for id in session.model.state.players:
   if id!=1 and remote_id==0:
    remote_id=id
    var p:Dictionary=session.model.state.players[id]
    p.equipment.weapon=session.model._item("sniper",1);p.ammo=0;p.magazines[p.equipment.weapon.uid]=0
  if remote_id!=0 and session.model.state.players.has(remote_id):
   var p:Dictionary=session.model.state.players[remote_id]
   if p.reloading:saw_reload=true
   if p.shots==1 and p.ammo==4 and p.equipment.weapon.kind=="sniper":confirmed_shot=true
  if remote_id!=0 and not OS.is_process_running(child_pid):
   var report:=FileAccess.get_file_as_string("res://artifacts/firearm_network_client.log")
   finish(saw_reload and confirmed_shot and "PASS: client observed" in report and not "FAIL:" in report)
func finish(ok:bool):
 if child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
 session.offline()
 print("FIREARM_NETWORK failures=",0 if ok else 1)
 quit(0 if ok else 1)
