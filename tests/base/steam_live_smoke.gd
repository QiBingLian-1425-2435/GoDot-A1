extends SceneTree
## Opt-in real Steam smoke test. Creates one PRIVATE room, never sends invites.
const Service=preload("res://app/network/steam_service.gd")
var service
var elapsed:=0.0
var ready_at:=-1.0
var checks:=0
var failures:=0
var started:=false
func _initialize()->void:
	call_deferred("start")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("STEAM LIVE FAIL: "+label)
	else:print("STEAM LIVE PASS: "+label)
func start()->void:
	if not "--steam-live-test" in OS.get_cmdline_user_args():
		print("SKIP: explicitly pass --steam-live-test with logged-in Steam")
		quit(2)
		return
	service=Service.new()
	root.add_child(service)
	check(service.available,"native singleton and peer class available on Godot 4.5.2")
	if not service.initialize():
		check(false,"Steam client initialization / online status")
		print(service.status)
		finish()
		return
	check(service.initialized and service.steam_id>0,"Steam 480 initialized and user online")
	service.transport_ready.connect(ready)
	service.failed.connect(func(message:String)->void:
		check(false,message)
		finish())
	started=true
	check(service.host_room(0)==OK,"private lobby create requested")
func ready(peer:MultiplayerPeer,as_host:bool)->void:
	check(as_host and service.lobby_id>0,"actual Steam callback created private lobby")
	check(peer.get_unique_id()==1 and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED,"native Steam host socket connected with authority id 1")
	check(service._compatible(service.lobby_id,true),"project protocol and original host metadata verified")
	check(int(service.steam.getNumLobbyMembers(service.lobby_id))==1,"private room has only this test user")
	ready_at=elapsed
func _process(delta:float)->bool:
	elapsed+=delta
	if started and ready_at>=0 and elapsed-ready_at>1.0:
		started=false
		service.leave_room()
		check(service.lobby_id==0 and service.peer==null,"explicitly left lobby and closed peer")
		check(service.initialized,"Steam stays initialized for next room")
		finish()
	elif elapsed>30:
		started=false
		check(false,"Steam callback timeout")
		finish()
	return false
func finish()->void:
	print("STEAM_LIVE_SMOKE ",checks," checks, ",failures," failures; private host only; two-account transport NOT TESTED")
	if is_instance_valid(service):
		service.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
