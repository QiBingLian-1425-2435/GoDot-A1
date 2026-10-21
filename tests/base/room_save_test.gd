extends SceneTree
const Model=preload("res://features/base/base_model.gd")
const Store=preload("res://features/persistence/room_store.gd")
const Profile=preload("res://features/persistence/profile_store.gd")
const Main=preload("res://app/main.gd")
const FakeSteam=preload("res://tests/base/fake_steam.gd")
const FakePeer=preload("res://tests/base/fake_peer.gd")
const Service=preload("res://app/network/steam_service.gd")
var checks:=0
var failures:=0
var folder:=""
func _initialize():call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func count(items: Array, kind: String) -> int:
	var result:=0
	for item in items:
		if item.get("kind")==kind:result+=int(item.count)
	return result
func run():
	folder="user://room_save_unit_"+str(Time.get_ticks_usec())
	var a=Model.new();a.add_player(1,"owner")
	var store=Store.new();var path:=folder+"/a.json"
	check(store.begin(a,path,"owner_a")==OK,"new owner creates a durable room")
	a.add_player(12,"guest")
	check(store.admit(a,12,"guest_x")==OK,"new guest receives one initial profile")
	a.state.players[12].hunger=0
	a.command(12,"use",{"index":3});a.command(12,"use",{"index":3})
	a.command(1,"transfer",{"from":"stash","index":5,"to":"bag"})
	a.state.players[12].magazines[a.state.players[12].equipment.weapon.uid]=7
	a.state.players[12].ammo=7
	check(store.checkpoint(a)==OK,"consumed food and host stash changes save together")
	check(count(a.state.players[12].bag,"canned_food")==0 and count(a.state.players[1].stash,"water")==0,"fixture consumes full stack and removes stash stack")
	check(store.detach(a,12)==OK,"disconnect saves the leaving guest before removal")
	a.remove_player(12);a.add_player(55,"changed display name")
	check(store.admit(a,55,"guest_x")==OK and count(a.state.players[55].bag,"canned_food")==0,"same account with different peer ID and name restores empty food stack")
	check(a.state.players[55].ammo==7,"loaded magazine remains seven rounds")
	a.add_player(66,"duplicate")
	check(store.admit(a,66,"guest_x")==ERR_UNAUTHORIZED,"same account cannot own two simultaneous inventory copies")
	a.remove_player(66)
	check(store.checkpoint(a)==OK,"atomic replacement can update an existing Windows file")
	var restarted=Model.new();restarted.add_player(1,"owner")
	var restored=Store.new()
	check(restored.begin(restarted,path,"owner_a")==OK and count(restarted.state.players[1].stash,"water")==0,"fresh host instance restores changed base warehouse")
	restarted.add_player(99,"guest")
	check(restored.admit(restarted,99,"guest_x")==OK and count(restarted.state.players[99].bag,"canned_food")==0,"room restart retains absent guest inventory")
	var seen: Dictionary={};var unique:=true
	for player in restarted.state.players.values():
		for items in [player.bag,player.stash,player.equipment.values()]:
			for item in items:
				if item.is_empty():continue
				if seen.has(item.uid):unique=false
				seen[item.uid]=true
	check(unique,"restored host and guest have collision-free item UIDs")
	var b=Model.new();b.add_player(1,"other owner");b.add_player(77,"guest")
	var other=Store.new()
	check(other.begin(b,folder+"/b.json","owner_b")==OK and other.admit(b,77,"guest_x")==OK and count(b.state.players[77].bag,"canned_food")==2,"same guest in another host room has an independent profile")
	var migrated=Model.new();migrated.add_player(1,"legacy owner");migrated.command(1,"use",{"index":2})
	var legacy:=folder+"/legacy.json";migrated.save_profile(legacy)
	var legacy_bytes:=FileAccess.get_file_as_string(legacy)
	var fresh=Model.new();fresh.add_player(1,"new")
	var migration=Store.new()
	check(migration.begin(fresh,folder+"/migrated.json","legacy_owner",legacy)==OK and count(fresh.state.players[1].bag,"water")==1,"first room preserves existing host personal save")
	check(FileAccess.get_file_as_string(legacy)==legacy_bytes,"migration retains original legacy file unchanged")
	fresh.state.players[1].thirst=0
	fresh.command(1,"use",{"index":2});migration.checkpoint(fresh)
	var again=Model.new();again.add_player(1,"new")
	check(Store.new().begin(again,folder+"/migrated.json","legacy_owner",legacy)==OK and count(again.state.players[1].bag,"water")==0,"subsequent room creation never reimports stale legacy inventory")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("broken");file.close()
	var original: Dictionary=restarted.state.duplicate(true)
	check(Store.new().begin(restarted,path,"owner_a")==ERR_FILE_CORRUPT and restarted.state==original and FileAccess.get_file_as_string(path)=="broken","corrupt room neither refreshes inventory nor overwrites evidence")
	check(Store.new().begin(restarted,folder+"/b.json","wrong_owner")==ERR_FILE_CORRUPT,"different owner cannot open another room file")
	var bad_legacy:=folder+"/bad_legacy.json"
	file=FileAccess.open(bad_legacy,FileAccess.WRITE);file.store_string("broken legacy");file.close()
	check(Store.new().begin(restarted,folder+"/not_created.json","fresh_owner",bad_legacy)==ERR_FILE_CORRUPT and not FileAccess.file_exists(folder+"/not_created.json"),"corrupt legacy migration cannot create a fresh starter room")
	await main_flow()
	print("ROOM_SAVE_TEST ",checks," checks; ",failures," failures; isolated saves ",folder)
	quit(1 if failures else 0)
func main_flow():
	var main=Main.new();main.room_save_root=folder+"/main";main.legacy_profile_path="";main.profile_path=folder+"/solo.json"
	root.add_child(main);main.sound.muted=true;main.set_process(false);main.set_physics_process(false)
	main.steam_service.free()
	var api=FakeSteam.new();var svc=Service.new();svc.steam=api;svc.peer_factory=func():return FakePeer.new()
	main.steam_service=svc;main.add_child(svc);svc.set_process(false)
	svc.transport_ready.connect(main._on_steam_transport);svc.failed.connect(main._on_steam_failure)
	main._on_action("steam_host",{});api.emit_created(109775243000000001);main.session.set_physics_process(false)
	check(main.in_game and not main.session.room_store.path.is_empty(),"real Main Steam host wires a room save")
	api.rooms[109775243000000001].members.append(api.FRIEND_ID)
	check(svc.peer_identity(12)=="steam_"+str(api.FRIEND_ID) and svc.peer_identity(13).is_empty(),"Steam identity comes from transport mapping and authorized lobby membership")
	main.session._on_peer_connected(12)
	main.session.model.state.players[12].hunger=0
	main.session.model.command(12,"use",{"index":3});main.session.model.command(12,"use",{"index":3})
	main.session._on_peer_disconnected(12)
	main._on_action("use",{"index":3})
	main._on_action("transfer",{"from":"stash","index":5,"to":"bag"})
	var saved_path: String=main.session.room_store.path
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(saved_path))
	check(count(saved.profiles[main.session.room_store.owner].bag,"canned_food")==1 and count(saved.profiles[main.session.room_store.owner].stash,"water")==0,"real UI intent immediately checkpoints consumption and host warehouse")
	main._return_menu()
	main._on_action("steam_host",{});api.emit_created(109775243000000099);main.session.set_physics_process(false)
	check(main.session.room_store.path==saved_path and count(main.session.model.state.players[1].bag,"canned_food")==1 and count(main.session.model.state.players[1].stash,"water")==0,"new Steam lobby ID resumes the same host room save through real Main")
	api.rooms[109775243000000099].members.append(api.FRIEND_ID)
	main.session._peer.steam_map[21]=api.FRIEND_ID
	main.session._on_peer_connected(21)
	check(main.session.room_store.members[21]=="steam_"+str(api.FRIEND_ID) and count(main.session.model.state.players[21].bag,"canned_food")==0,"actual Steam admission restores the authorized guest across lobby and peer changes")
	main._return_menu()
	main.session.model.save_profile(main.profile_path,1)
	var solo_before:=FileAccess.get_file_as_string(main.profile_path)
	main.session.mode="client";main._enter_base()
	main.session._on_server_disconnected()
	main._save(false);main._return_menu()
	check(FileAccess.get_file_as_string(main.profile_path)==solo_before,"unexpected guest disconnect cannot overwrite the separate local personal save")
	main.free();await process_frame
