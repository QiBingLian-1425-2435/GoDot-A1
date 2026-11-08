extends SceneTree
const Sound=preload("res://features/audio/base_sound.gd")
const Controller=preload("res://features/player/base_input.gd")
var failures:=0
var checks:=0
var heard:Array[String]=[]

func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func run()->void:
	var sound=Sound.new();root.add_child(sound)
	sound.sound_played.connect(func(kind:String):heard.append(kind))
	check(sound.step_samples.size()==5,"all recorded footstep variants restored")
	for stream in sound.step_samples:
		check(stream is AudioStreamWAV and stream.get_length()>.08 and stream.get_length()<.2,"short recorded step loaded")
	var previous:AudioStream=null
	for i in range(30):
		sound.play("step")
		check(sound.sounds.step.stream!=previous,"no consecutive repeated recording")
		check(sound.sounds.step.pitch_scale>=.97 and sound.sounds.step.pitch_scale<=1.03,"subtle pitch variation")
		previous=sound.sounds.step.stream
		await create_timer(.03).timeout
	heard.clear();sound.step_clock=0
	for i in range(120):
		sound.step(1.0/60.0,true,false)
		await process_frame
	var walking:int=heard.size()
	check(walking in [5,6],"original walking cadence retained")
	var walk_volume:float=sound.sounds.step.volume_db
	heard.clear();sound.step_clock=0
	for i in range(120):
		sound.step(1.0/60.0,true,true)
		await process_frame
	check(heard.size() in [8,9] and heard.size()>walking,"original running cadence retained")
	check(sound.sounds.step.volume_db>walk_volume,"run slightly stronger than walking")
	heard.clear();sound.muted=true;sound.step_clock=0;sound.step(.5,true,false)
	check(heard.is_empty(),"muting suppresses step events")
	sound.muted=false
	for motion in [{"velocity":Vector2.RIGHT*2,"crouch":true},{"velocity":Vector2.RIGHT*2,"crouch":true,"sprint":true},{"velocity":Vector2.ZERO},{"velocity":Vector2.RIGHT*2,"life":"soul"}]:
		var state:Dictionary=Controller._footstep_state(motion)
		sound.step(.5,state.moving,state.sprint)
	check(heard.is_empty(),"crouch, stationary and soul remain silent through input filter")
	sound.sounds.step.stop()
	await create_timer(.1).timeout
	if "--preview" in OS.get_cmdline_user_args():
		var recorder:=AudioEffectRecord.new();AudioServer.add_bus_effect(0,recorder)
		recorder.set_recording_active(true)
		# Actual AudioStreamPlayer output: walk, pause, run, pause, crouch.
		for sprint in [false,true]:
			sound.step_clock=0
			for i in range(8):
				sound.step(.39 if not sprint else .24,true,sprint)
				await create_timer(.39 if not sprint else .24).timeout
			await create_timer(.6).timeout
		var state:Dictionary=Controller._footstep_state({"velocity":Vector2.RIGHT,"crouch":true})
		for i in range(3):sound.step(.4,state.moving,state.sprint);await create_timer(.4).timeout
		recorder.set_recording_active(false)
		var recording:=recorder.get_recording()
		check(recording!=null and recording.data.size()>44100,"audio output captured")
		if recording!=null:recording.save_to_wav("res://artifacts/footstep_audio_preview.wav")
		AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	print("FOOTSTEP_AUDIO checks=%d failures=%d"%[checks,failures])
	previous=null;sound.queue_free()
	await process_frame
	quit(1 if failures else 0)
