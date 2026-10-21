extends SceneTree
const FakeSteam = preload("res://tests/base/fake_steam.gd")
const FakePeer = preload("res://tests/base/fake_peer.gd")
const Service = preload("res://app/network/steam_service.gd")
const ROOM_A := 109775243000000001
const ROOM_B := 109775243000000002
var assertions:=0
var errors:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
    assertions+=1
    if not ok:
        errors.append(message)
        print("FAIL: ",message)
func run() -> void:
    var main=load("res://app/main.tscn").instantiate()
    main.smoke=true
    root.add_child(main)
    main.sound.muted=true
    main.set_process(false)
    main.set_physics_process(false)
    check(Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer"),"native addon still loads when auto Steam init disabled")
    check(not main.steam_service.initialized and not main.steam_service._api_initialized,"headless smoke/no-steam never auto initializes SDK")
    main.steam_service.free()
    var api=FakeSteam.new()
    var svc=Service.new()
    svc.steam=api
    var peers:Array=[]
    svc.peer_factory=func():
        var p=FakePeer.new()
        peers.append(p)
        return p
    main.steam_service=svc
    main.add_child(svc)
    svc.set_process(false)
    svc.transport_ready.connect(main._on_steam_transport)
    svc.join_requested.connect(main._on_steam_join_requested)
    svc.failed.connect(main._on_steam_failure)
    main._on_action("steam_host",{})
    check(not main.in_game and api.created.size()==1,"main waits for Steam creation before entering world")
    api.emit_created(ROOM_A)
    check(main.in_game and main.session.mode=="host" and main.session.transport=="steam","host callback enters world through Session")
    check(main.session.model.state.players[1].name==api.getPersonaName(),"host world uses Steam display name")
    check(not svc.info().pending,"host entry leaves no pending service operation")
    var crouch_before:bool=main.crouched
    svc.overlay_active=true
    var key:=InputEventKey.new()
    key.physical_keycode=KEY_C
    key.pressed=true
    main._unhandled_input(key)
    check(main.crouched==crouch_before,"Steam overlay blocks keyboard gameplay actions")
    svc.overlay_active=false
    main._return_menu()
    check(not main.in_game and main.session.mode=="offline" and svc.lobby_id==0,"return menu tears down both Steam service and Session")
    api.populate(ROOM_B,Service.GAME_KEY,Service.PROTOCOL)
    main._on_action("steam_join",{"lobby_id":str(ROOM_B)})
    api.lobby_data_update.emit(1,ROOM_B,ROOM_B)
    api.emit_joined(ROOM_B)
    check(main.joining and not main.in_game and main.session.transport=="steam","client lobby does not prematurely enter game")
    var client=peers.back()
    client.status=MultiplayerPeer.CONNECTION_CONNECTED
    main.session.local_id=client.uid
    main.session.model.add_player(client.uid,"加入鸭")
    main.session._session_token=234
    main._process(0.1)
    check(main.in_game and not main.joining and not svc.info().pending,"client world snapshot enters base and clears pending connect")
    api.online=false
    svc._process(1.1)
    check(not main.in_game and main.session.mode=="offline" and svc.lobby_id==0,"Steam offline failure returns full main flow to menu")
    main._on_action("solo",{})
    check(main.in_game and main.session.mode=="offline" and main.session.model.state.players.size()==1,"single player remains usable after Steam failure")
    main._return_menu()
    main.free()
    check(api.shutdown_calls==1,"main teardown shuts injected Steam SDK down once")
    print("STEAM_MAIN_MOCK_INTEGRATION: ",assertions," assertions, ",errors.size()," failed")
    quit(0 if errors.is_empty() else 1)
