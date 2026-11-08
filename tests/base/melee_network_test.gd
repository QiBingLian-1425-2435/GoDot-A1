extends SceneTree
const Session=preload("res://app/network/session.gd")
var session
var child_pid:=-1
var client:=false
var elapsed:=0.0
var equipped_at:=-1.0
var next_fire:=0.0
var phase:=0
var remote_id:=0
var saw_forward:=false
var saw_back:=false
var host_saw_ads:=false
var confirmed_hits:=0
func _initialize():call_deferred("start")
func start():
	client="--melee-client" in OS.get_cmdline_user_args()
	session=Session.new();root.add_child(session)
	if client:session.join("127.0.0.1",29849)
	else:
		session.host(29849)
		session.model.obstacles.clear()
		session.model.state.targets=[{"id":1,"pos":Vector2(0,-1),"hp":1000,"hits":0}]
		child_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file","res://artifacts/melee_network_client.log","--script","res://tests/base/melee_network_test.gd","--","--melee-client"])
func _process(dt:float):
	elapsed+=dt
	if elapsed>15:finish(false);return
	if session==null:return
	if client:
		if session.local_id<=1 or not session.model.state.players.has(session.local_id):return
		var p:Dictionary=session.model.state.players[session.local_id]
		if phase==0 and p.bag[0].get("kind","")=="fire_axe":session.send("equip",{"index":0});phase=1
		if phase==1 and p.equipment.weapon.get("kind","")=="fire_axe":equipped_at=elapsed;phase=2
		if phase!=2:return
		session.send("move",{"direction":Vector2.ZERO,"aim":Vector2.UP,"ads":true})
		if elapsed>=next_fire and elapsed-equipped_at<2.8:session.send("fire");next_fire=elapsed+.13
		saw_forward=saw_forward or p.get("anim_action","")=="melee_forward"
		saw_back=saw_back or p.get("anim_action","")=="melee_back"
		if elapsed-equipped_at>3.6:
			var ok:bool=saw_forward and saw_back and p.ammo==0 and session.model.state.targets[0].hits>=3 and p.shots==0
			print("PASS: remote equipment, alternating swings, hits and no ammunition" if ok else "FAIL: client melee state mismatch")
			phase=3;quit(0 if ok else 1)
	else:
		for id in session.model.state.players:
			if id!=1 and remote_id==0:
				remote_id=id
				var p:Dictionary=session.model.state.players[id]
				p.pos=Vector2.ZERO;p.bag[0]=session.model._item("fire_axe",1)
		if remote_id!=0 and session.model.state.players.has(remote_id):
			var p:Dictionary=session.model.state.players[remote_id]
			host_saw_ads=host_saw_ads or p.ads
			confirmed_hits=int(session.model.state.targets[0].hits)
		if remote_id!=0 and not OS.is_process_running(child_pid):
			var report:=FileAccess.get_file_as_string("res://artifacts/melee_network_client.log")
			finish(host_saw_ads and confirmed_hits>=3 and "PASS: remote equipment" in report and not "FAIL:" in report)
func finish(ok:bool):
	if child_pid>0 and OS.is_process_running(child_pid):OS.kill(child_pid)
	session.offline();print("MELEE_NETWORK failures=",0 if ok else 1);quit(0 if ok else 1)
