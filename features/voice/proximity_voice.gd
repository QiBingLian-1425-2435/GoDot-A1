extends Node
## Steam owns capture/codec; this node owns only local PTT and bounded audio playback.
const Rules=preload("res://features/voice/voice_rules.gd")
var session: Node
var service: Node
var recording:=false
var muted:=false
var volume:=1.0
var status:="Q 按住说话 · 附近20米"
var _sequence:=0
var _context:=""
var _speakers: Dictionary={}
var _error_latched:=false
var _draining:=false
var _record_started:=0

func configure(network: Node, steam_service: Node) -> void:
	session=network;service=steam_service
	session.voice_received.connect(receive)

func available() -> bool:
	return is_instance_valid(service) and service.initialized and service.steam!=null and service.steam.has_method("getVoice")

func update(held: bool, allowed: bool, _delta: float) -> void:
	var context:="%s:%s:%s"%[session.mode,session._session_token,session.model.state.get("world_revision",0)]
	if context!=_context:
		stop();clear_playback();_context=context
	var connected: bool=session.mode in ["host","client"] and session.local_id>0 and session._session_token>0 and session.model.state.players.has(session.local_id) and session.model.world_ready
	var wanted:=held and allowed and connected and available() and not muted
	if not held:_error_latched=false
	if wanted and not recording and not _error_latched:
		# Steam may still have trailing data after StopVoiceRecording. Drain before a new press.
		service.steam.getVoice(65536)
		service.steam.startVoiceRecording();recording=true;_record_started=Time.get_ticks_msec()
	elif not wanted:stop()
	if recording:
		var result: Dictionary=service.steam.getVoice(65536)
		var code:=int(result.get("result",2))
		if code==0:
			var bytes: PackedByteArray=result.get("buffer",PackedByteArray())
			var count:=int(result.get("size",0))
			if count>0 and count<=Rules.MAX_PACKET and count<=bytes.size():
				_sequence+=1;session.send_voice(bytes.slice(0,count),_sequence)
		elif code not in [2,3] or (code==2 and Time.get_ticks_msec()-_record_started>500):
			stop();_error_latched=true
			status="语音不可用：检查 Steam 麦克风 / Windows 麦克风权限"
	elif _draining and available():
		# Discard the SDK's post-stop tail; never transmit audio after releasing Q.
		var tail: Dictionary=service.steam.getVoice(65536)
		if int(tail.get("result",2))==2:_draining=false
	if not _error_latched:
		status="语音已静音" if muted else ("正在说话 · 附近20米" if recording else ("Q 按住说话 · 附近20米" if available() else "语音需登录 Steam · 检查麦克风设置"))
	for id in _speakers.keys():
		var item: Dictionary=_speakers[id]
		var gain:=Rules.gain(session.model.state.players,int(id),session.local_id)
		if not connected or muted or gain<=0 or Time.get_ticks_msec()-int(item.time)>400:
			_remove(int(id));continue
		item.player.volume_db=linear_to_db(maxf(0.0001,gain*volume))

func stop() -> void:
	if not recording:return
	recording=false
	if is_instance_valid(service) and service.steam!=null and service.steam.has_method("stopVoiceRecording"):
		service.steam.stopVoiceRecording();_draining=true
	_sequence+=1
	if is_instance_valid(session):session.send_voice(PackedByteArray(),_sequence)

func set_muted(value: bool) -> void:
	muted=value
	if value:stop();clear_playback()

func receive(speaker: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty():_remove(speaker);return
	if muted or not available() or Rules.gain(session.model.state.players,speaker,session.local_id)<=0:return
	var decoded: Dictionary=service.steam.decompressVoice(bytes,Rules.RATE,32000)
	if int(decoded.get("result",5))!=0:return
	var pcm: PackedByteArray=decoded.get("uncompressed",PackedByteArray())
	var size:=int(decoded.get("size",0))
	if size<=0 or size>16000 or size>pcm.size() or size%2!=0:return
	play_pcm(speaker,pcm.slice(0,size))

func play_pcm(speaker: int, pcm: PackedByteArray) -> void:
	if pcm.is_empty() or pcm.size()>16000 or pcm.size()%2!=0:return
	if not _speakers.has(speaker):
		var player:=AudioStreamPlayer.new()
		var generator:=AudioStreamGenerator.new()
		generator.mix_rate=Rules.RATE;generator.buffer_length=0.3
		player.stream=generator;add_child(player);player.play()
		_speakers[speaker]={"player":player,"time":Time.get_ticks_msec(),"capacity":player.get_stream_playback().get_frames_available()}
	var item: Dictionary=_speakers[speaker]
	item.time=Time.get_ticks_msec()
	var playback: AudioStreamGeneratorPlayback=item.player.get_stream_playback()
	var count:=mini(pcm.size()/2,4000)
	# Keep at most 250 ms; dropped network/audio frames never build an unbounded delay.
	if int(item.capacity)-playback.get_frames_available()+count>4000:
		# Godot forbids clear_buffer while active. Restart to discard old audio safely.
		item.player.stop();item.player.play();playback=item.player.get_stream_playback()
	var frames:=PackedVector2Array();frames.resize(count)
	var offset:=pcm.size()/2-count
	for i in range(count):
		var sample:=float(pcm.decode_s16((offset+i)*2))/32768.0
		frames[i]=Vector2(sample,sample)
	item.player.volume_db=linear_to_db(maxf(0.0001,Rules.gain(session.model.state.players,speaker,session.local_id)*volume))
	playback.push_buffer(frames)

func speaking_names() -> String:
	var names:=PackedStringArray()
	for id in _speakers:
		names.append(str(session.model.state.players.get(id,{}).get("name","队友")))
	return " · 正在说话："+", ".join(names) if not names.is_empty() else ""

func _remove(speaker: int) -> void:
	if not _speakers.has(speaker):return
	_speakers[speaker].player.stop();_speakers[speaker].player.queue_free();_speakers.erase(speaker)

func clear_playback() -> void:
	for id in _speakers.keys():_remove(int(id))

func _exit_tree() -> void:
	stop();clear_playback()
