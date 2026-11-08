extends Node
signal sound_played(kind:String)
var sounds:Dictionary={}
var step_clock:=0.0
var muted:=false
var step_samples:Array[AudioStream]=[]
var last_step:=-1
var step_sprint:=false
var step_rng:=RandomNumberGenerator.new()
func _ready()->void:
	step_rng.randomize()
	for i in range(5):
		var path:="res://assets/audio/footsteps/concrete_%02d.wav"%i
		if ResourceLoader.exists(path):step_samples.append(load(path) as AudioStream)
	if step_samples.is_empty():push_warning("Restore footstep audio with tools/prepare_footstep_audio.py")
	for kind in ["fire","pistol","impact","reload","step","pickup","ui","swing","enemy_hit","enemy_slash"]:
		var player:=AudioStreamPlayer.new()
		player.stream=(step_samples[0] if not step_samples.is_empty() else null) if kind=="step" else _synth(kind)
		player.volume_db=-15 if kind=="fire" else (-19 if kind=="pistol" else (-17 if kind in ["reload","enemy_hit","enemy_slash"] else -23))
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
			"enemy_hit":value=sin(TAU*t*(135-t*450))*.7+rng.randf_range(-1,1)*.24
			"enemy_slash":value=sin(TAU*t*95)*.5+rng.randf_range(-1,1)*.6
			"swing":value=rng.randf_range(-1,1)*.48*sin(PI*float(i)/float(rate*duration))
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
		if kind=="step":
			if step_samples.is_empty():return
			var index:=step_rng.randi_range(0,step_samples.size()-2) if last_step>=0 and step_samples.size()>1 else step_rng.randi_range(0,step_samples.size()-1)
			if last_step>=0 and step_samples.size()>1 and index>=last_step:index+=1
			last_step=index
			sounds.step.stream=step_samples[index]
			sounds.step.pitch_scale=step_rng.randf_range(.97,1.03)
			sounds.step.volume_db=(-14.0 if step_sprint else -17.0)+step_rng.randf_range(-.6,.6)
		sound_played.emit(kind)
		sounds[kind].play()
func step(delta:float,moving:bool,sprint:bool)->void:
	step_sprint=sprint
	step_clock-=delta
	if moving and step_clock<=0:
		play("step")
		step_clock=0.24 if sprint else 0.39
