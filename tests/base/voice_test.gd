extends SceneTree
const Rules=preload("res://features/voice/voice_rules.gd")
const Voice=preload("res://features/voice/proximity_voice.gd")
const Session=preload("res://app/network/session.gd")
const Main=preload("res://app/main.gd")
class Codec extends RefCounted:
	var starts:=0
	var stops:=0
	var captured: Dictionary={"result":3}
	var decoded: Dictionary={"result":5}
	func startVoiceRecording():starts+=1
	func stopVoiceRecording():stops+=1
	func getVoice(_size=65536):var value=captured;captured={"result":3};return value
	func decompressVoice(_bytes,_rate,_size):return decoded
class Service extends Node:
	var initialized:=true
	var steam=Codec.new()
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool, label: String):
	checks+=1;print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	var s=Session.new();root.add_child(s);s.set_physics_process(false)
	s.mode="host";s._session_token=55;s.model.add_player(2,"near");s.model.add_player(3,"far")
	s.model.state.players[1].pos=Vector2.ZERO;s.model.state.players[2].pos=Vector2(2,0);s.model.state.players[3].pos=Vector2(21,0)
	var players: Dictionary=s.model.state.players
	check(Rules.gain(players,2,1)==1.0,"nearby full volume")
	players[2].pos=Vector2(12,0);check(Rules.gain(players,2,1)>0 and Rules.gain(players,2,1)<1,"distance attenuation")
	players[2].height=22;check(Rules.gain(players,2,1)==0,"vertical distance counts")
	players[2].height=0;players[2].pos=Vector2(2,0)
	check(Rules.gain(players,3,1)==0 and Rules.gain(players,1,1)==0,"far voice and self echo excluded")
	var revision:=int(s.model.state.world_revision)
	var data:=PackedByteArray([1,2,3])
	check(not s._accept_voice(2,data,1,54,revision),"old room token rejected")
	check(not s._accept_voice(2,data,1,55,revision-1),"old world rejected")
	check(not s._accept_voice(99,data,1,55,revision),"nonmember rejected")
	var big:=PackedByteArray();big.resize(8193)
	check(not s._accept_voice(2,big,1,55,revision),"oversize compressed packet rejected")
	check(s._accept_voice(2,data,1,55,revision) and not s._accept_voice(2,data,1,55,revision),"duplicates/reordering rejected")
	var accepted:=0
	for seq in range(2,100):
		if s._accept_voice(2,data,seq,55,revision):accepted+=1
	check(accepted==79,"packet flood is bounded")
	s._voice_sequences.clear();s._voice_limits.clear()
	var received:Array=[];s.voice_received.connect(func(id,bytes):received.append([id,bytes]))
	s._route_voice(2,data,1,55,revision);s._route_voice(3,data,1,55,revision)
	check(received.size()==1 and received[0][0]==2,"host hears nearby teammate only")
	var service=Service.new();root.add_child(service)
	var voice=Voice.new();root.add_child(voice);voice.configure(s,service)
	voice.update(true,true,0.016);voice.update(true,true,0.016)
	check(voice.recording and service.steam.starts==1,"open mic starts capture once")
	service.steam.captured={"result":0,"size":3,"buffer":PackedByteArray([1,2,3,99])}
	voice.update(true,true,0.016)
	check(s._voice_limits.get(1,{}).get("bytes",0)==3,"capture sends only the SDK-reported byte count")
	voice.update(true,false,0.016)
	check(not voice.recording and service.steam.stops==1,"focus/transition blocker stops capture")
	voice.update(true,true,0.016);voice.stop();voice.stop()
	check(service.steam.stops==2,"capture disable stops once and repeated cleanup is safe")
	var sequence:int=voice._sequence
	service.steam.captured={"result":0,"size":3,"buffer":data};voice.update(false,true,.016)
	check(voice._sequence==sequence,"microphone tail after capture closes is discarded")
	voice.update(true,true,0.016);voice.set_muted(true)
	check(not voice.recording,"mute disables microphone")
	voice.set_muted(false);voice.update(false,true,0.016)
	var pcm:=PackedByteArray();pcm.resize(3200)
	for i in range(1600):pcm.encode_s16(i*2,int(sin(float(i)*TAU*440/16000)*8000))
	service.steam.decoded={"result":0,"size":3200,"uncompressed":pcm}
	voice.receive(2,data)
	check(voice._speakers.has(2),"decoded PCM reaches audio generator")
	for i in range(10):voice.play_pcm(2,pcm)
	var item: Dictionary=voice._speakers[2]
	check(int(item.capacity)-item.player.get_stream_playback().get_frames_available()<=4000,"audio bursts remain bounded to 250ms without active clear_buffer")
	voice.receive(3,data);check(not voice._speakers.has(3),"receiver also rejects out-of-range speaker")
	voice.receive(2,PackedByteArray());check(voice._speakers.is_empty(),"stop packet clears buffered playback")
	service.steam.decoded={"result":5,"size":3200,"uncompressed":pcm};voice.receive(2,data)
	check(voice._speakers.is_empty(),"failed decode never plays allocated buffer")
	service.steam.decoded={"result":0,"size":3202,"uncompressed":pcm};voice.receive(2,data)
	check(voice._speakers.is_empty(),"invalid decoded size rejected")
	service.steam.decoded={"result":0,"size":3200,"uncompressed":pcm};voice.receive(2,data)
	voice.set_muted(true);check(voice._speakers.is_empty(),"mute clears received audio")
	voice.set_muted(false);voice.receive(2,data)
	voice._speakers[2].time=Time.get_ticks_msec()-500;voice.update(false,true,0.016)
	check(voice._speakers.is_empty(),"lost stop packet expires within 400ms")
	voice.update(true,true,0.016);s.model.state.world_revision+=1;voice.update(false,true,0.016)
	check(not voice.recording and voice._speakers.is_empty(),"world transition resets capture and playback")
	voice.update(true,true,.016);service.initialized=false;voice.stop()
	check(not voice.recording and service.steam.stops>=4,"Steam login loss still stops an already active microphone")
	service.initialized=true
	voice.update(true,true,.016);service.steam.captured={"result":2};voice._record_started=Time.get_ticks_msec()-600
	voice.update(true,true,.016)
	check(not voice.recording and voice._error_latched,"missing microphone reports a capture error")
	s.offline();voice.update(true,true,0.016);check(not voice.recording,"offline has no open microphone")
	var disconnected=Session.new();root.add_child(disconnected);disconnected.set_physics_process(false)
	disconnected.join("127.0.0.1",29958);disconnected._session_token=55;disconnected._peer.close()
	disconnected.send_voice(data,1);disconnected.send_voice(PackedByteArray(),2)
	check(disconnected._voice_sequences.is_empty(),"closed transport safely drops microphone and stop packets")
	disconnected.offline();disconnected.queue_free()
	voice.queue_free();service.queue_free();s.queue_free();await process_frame
	var main=Main.new();main.smoke=true;main.elapsed=-10000;root.add_child(main);main.sound.muted=true
	main._start_solo();main.ui._open_settings()
	var button=main.ui._dialog.find_child("VoiceMute",true,false)
	check(button!=null,"settings expose voice mute")
	if button!=null:
		button.button_pressed=true;button.toggled.emit(true)
	check(main.voice.muted,"settings intent reaches voice controller")
	if button!=null:
		button.button_pressed=false;button.toggled.emit(false)
	check(not main.voice.muted,"settings can reopen microphone and team playback")
	main.ui._close_dialog();main.ui._dialog_panel("搜索测试箱",Vector2(600,400))
	check(main.ui.is_blocking() and main._voice_context_allows_capture(),"container/item panels do not block open mic")
	main.ui._close_dialog();main.ui._open_help()
	check(main.ui._dialog.find_child("VoiceMute",true,false)==null,"help opens without changing voice setting")
	check(main.ui._dialog.size.y>=712,"help fits Q binding without clipping")
	if DisplayServer.get_name()!="headless":
		main.ui._close_dialog();main.ui.set_voice_status("正在说话 · 附近20米 · 正在说话：测试队友")
		await process_frame;await process_frame
		var path:=OS.get_environment("A1_TEST_ARTIFACTS")
		if path.is_empty():path=ProjectSettings.globalize_path("res://artifacts")
		DirAccess.make_dir_recursive_absolute(path)
		check(root.get_texture().get_image().save_png(path+"/voice_hud.png")==OK,"visible HUD screenshot saved")
	main.queue_free();await process_frame;await process_frame
	print("VOICE_TEST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
