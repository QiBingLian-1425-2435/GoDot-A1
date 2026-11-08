extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var child_pid:=-1
var client:=false
var elapsed:=0.0
var phase:=0
var tried_at:=0.0
var remote_id:=0
var rejected_running:=false
var confirmed_shot:=false
func _initialize():call_deferred("start")
func start():
	client="--sprint-fire-client" in OS.get_cmdline_user_args()
	session=Session.new();root.add_child(session)
	if client:session.join("127.0.0.1",29857)
	else:
		session.host(29857);session.model.obstacles.clear()
		child_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/sprint_fire_client.log","--script","res://tests/base/sprint_fire_network_test.gd","--","--sprint-fire-client"])
func _process(dt:float):
	elapsed+=dt
	if elapsed>12:finish(false);return
	if session==null:return
	if client:
		if session.local_id<=1 or not session.model.state.players.has(session.local_id):return
		var p:Dictionary=session.model.state.players[session.local_id]
		session.send("move",{"direction":Vector2.UP if phase<2 else Vector2.ZERO,"aim":Vector2.UP,"sprint":phase<2})
		if phase==0 and p.sprint:session.send("fire");tried_at=elapsed;phase=1
		if phase==1 and elapsed-tried_at>.45:
			rejected_running=p.shots==0 and p.ammo==20;phase=2
		if phase==2 and not p.sprint:session.send("fire");phase=3
		if phase==3 and p.shots==1:
			var ok:bool=rejected_running and p.ammo==19
			print("PASS: sprint blocks remote shot and stopping permits it" if ok else "FAIL: sprint fire mismatch")
			phase=4;quit(0 if ok else 1)
	else:
		for id in session.model.state.players:
			if id!=1 and remote_id==0:remote_id=id;session.model.state.players[id].pos=Vector2.ZERO
		if remote_id!=0 and session.model.state.players.has(remote_id):
			var p:Dictionary=session.model.state.players[remote_id]
			if p.sprint and p.shots==0:rejected_running=true
			if not p.sprint and p.shots==1 and p.ammo==19:confirmed_shot=true
		if remote_id!=0 and not OS.is_process_running(child_pid):
			var report:=FileAccess.get_file_as_string("res://artifacts/sprint_fire_client.log")
			finish(rejected_running and confirmed_shot and "PASS: sprint blocks" in report and not "FAIL:" in report)
func finish(ok:bool):
	if child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
	session.offline();print("SPRINT_FIRE_NETWORK failures=",0 if ok else 1);quit(0 if ok else 1)
