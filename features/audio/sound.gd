extends Node
## Original procedural sound set. Add as child; call play("pickup") etc.

const CUE_NAMES: Array[String] = ["pickup", "down", "rescue", "extract", "step", "danger"]
const AUDIO_ROOT := "res://assets/audio/"

var muted := false
var ambient_player: AudioStreamPlayer
var _cue_players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next_player := 0
var _last_step_ms := -1000


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "Ambience"
	ambient_player.volume_db = -27.0
	add_child(ambient_player)
	var ambient_source := load(AUDIO_ROOT + "ambient.wav") as AudioStreamWAV
	if ambient_source != null:
		var looping_ambient := ambient_source.duplicate() as AudioStreamWAV
		looping_ambient.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looping_ambient.loop_begin = 0
		looping_ambient.loop_end = int(round(looping_ambient.get_length() * looping_ambient.mix_rate))
		ambient_player.stream = looping_ambient
		ambient_player.play()
		ambient_player.stream_paused = muted
	for cue_name in CUE_NAMES:
		_streams[cue_name] = load(AUDIO_ROOT + cue_name + ".wav")
	for index in 6:
		var player := AudioStreamPlayer.new()
		player.name = "Cue%d" % index
		player.volume_db = -14.0
		add_child(player)
		_cue_players.append(player)


func play(cue: String) -> void:
	if muted or not _streams.has(cue) or _cue_players.is_empty():
		return
	var player := _cue_players[_next_player]
	_next_player = (_next_player + 1) % _cue_players.size()
	player.stream = _streams[cue] as AudioStream
	player.volume_db = -22.0 if cue == "step" else -14.0
	player.pitch_scale = randf_range(0.91, 1.09) if cue == "step" else 1.0
	player.play()


func footstep() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_step_ms < 330:
		return
	_last_step_ms = now
	play("step")


func set_muted(value: bool) -> void:
	muted = value
	if is_instance_valid(ambient_player):
		ambient_player.stream_paused = muted
	if muted:
		for player in _cue_players:
			player.stop()

func _exit_tree() -> void:
	if is_instance_valid(ambient_player):
		ambient_player.stop()
		ambient_player.stream = null
	for player in _cue_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_streams.clear()
