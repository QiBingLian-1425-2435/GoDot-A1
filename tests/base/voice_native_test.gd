extends SceneTree
## Opt-in: records for one second, discards all microphone bytes after decoding.
const Voice=preload("res://features/voice/proximity_voice.gd")
const Session=preload("res://app/network/session.gd")
class RecordingSession extends Session:
	var packets: Array=[]
	func send_voice(bytes: PackedByteArray, _sequence: int) -> void:
		if not bytes.is_empty():packets.append(bytes)
class Service extends Node:
	var initialized:=false
	var steam: Object
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
func run():
	if not "--steam-live-test" in OS.get_cmdline_user_args():
		print("SKIP: native microphone check requires --steam-live-test and logged-in Steam");quit();return
	var service=Service.new();root.add_child(service);service.steam=Engine.get_singleton("Steam")
	var result: Dictionary=service.steam.steamInitEx(480,false)
	service.initialized=int(result.get("status",-1))==0
	check(service.initialized,"native Steam API initializes")
	if not service.initialized:service.queue_free();quit(1);return
	var session=RecordingSession.new();root.add_child(session);session.set_physics_process(false)
	session.mode="host";session._session_token=1;session.model.add_player(2,"voice test")
	session.model.state.players[2].pos=session.model.state.players[1].pos
	var voice=Voice.new();root.add_child(voice);voice.configure(session,service)
	voice.update(true,true,.016);check(voice.recording,"native startVoiceRecording runs")
	var deadline:=Time.get_ticks_msec()+1000
	while Time.get_ticks_msec()<deadline:
		voice.update(true,true,.016);await create_timer(.016).timeout
	voice.update(false,true,.016);check(not voice.recording,"native stopVoiceRecording runs after Q release")
	var total:=0;var decoded:=0
	for bytes in session.packets:
		total+=bytes.size()
		voice.receive(2,bytes)
		if voice._speakers.has(2):decoded+=1
	print("NATIVE_VOICE captured_packets=",session.packets.size()," compressed_bytes=",total," decoded_packets=",decoded)
	if total>0:check(decoded>0,"native captured voice decompresses and reaches generator")
	else:print("UNVERIFIED: no speech data produced; microphone audibility remains a manual check")
	voice.clear_playback();session.packets.clear()
	# Verify audible sample delivery through Godot's actual mixer with synthetic, non-private PCM.
	var capture:=AudioEffectCapture.new();AudioServer.add_bus_effect(0,capture)
	var pcm:=PackedByteArray();pcm.resize(6400)
	for i in range(3200):pcm.encode_s16(i*2,int(sin(float(i)*TAU*440/16000)*8000))
	voice.play_pcm(2,pcm);await create_timer(.25).timeout
	var frames:=capture.get_buffer(capture.get_frames_available());var peak:=0.0
	for frame in frames:peak=maxf(peak,absf(frame.x))
	check(peak>.01,"synthetic PCM is nonzero after AudioServer mix")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	voice.queue_free();await process_frame;session.offline();session.queue_free();service.queue_free();await process_frame
	print("VOICE_NATIVE failures=",failures);quit(1 if failures else 0)
