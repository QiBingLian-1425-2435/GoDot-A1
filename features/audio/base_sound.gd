extends Node
signal sound_played(kind:String)
var sounds:Dictionary={}
var step_clock:=0.0
var muted:=false
func _ready()->void:
	for kind in ["fire","pistol","impact","reload","step","pickup","ui"]:
		var player:=AudioStreamPlayer.new()
		player.stream=_synth(kind)
		player.volume_db=-15 if kind=="fire" else (-19 if kind=="pistol" else (-17 if kind=="reload" else -23))
		add_child(player)
		sounds[kind]=player
func _synth(kind:String)->AudioStreamWAV:
	var rate:=22050
	var duration:=0.16 if kind=="fire" else (0.26 if kind=="reload" else 0.09)
	var data:=PackedByteArray()
	var rng:=RandomNumberGenerator.new()
	rng.seed=42
	for i in range(int(rate*duration)):
		var t:=float(i)/rate
		var fade:=1.0 if kind=="reload" else exp(-t*(35 if kind=="fire" else 55))
		var value:=sin(TAU*t*620)*0.4
		match kind:
			"fire": value=(rng.randf_range(-1,1)*0.7+sin(TAU*t*90)*0.4)
			"pistol": value=rng.randf_range(-1,1)*0.55+sin(TAU*t*175)*0.4
			"impact": value=rng.randf_range(-1,1)*0.3+sin(TAU*t*2200)*0.2
			"step": value=rng.randf_range(-1,1)*0.3
			"reload":
				value=(rng.randf_range(-1,1)*0.42+sin(TAU*t*1050)*0.18)*exp(-t*48)
				if t>=0.13:
					var second_t:=t-0.13
					value+=(rng.randf_range(-1,1)*0.52+sin(TAU*second_t*760)*0.24)*exp(-second_t*58)
			"pickup": value=sin(TAU*t*(800+t*4000))*0.4
		var pcm:=int(clampf(value*fade,-1,1)*32760)
		data.append(pcm&255)
		data.append((pcm>>8)&255)
	var wav:=AudioStreamWAV.new()
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate=rate
	wav.data=data
	return wav
func play(kind:String)->void:
	if not muted and sounds.has(kind):
		sound_played.emit(kind)
		sounds[kind].play()
func step(delta:float,moving:bool,sprint:bool)->void:
	step_clock-=delta
	if moving and step_clock<=0:
		play("step")
		step_clock=0.24 if sprint else 0.39
