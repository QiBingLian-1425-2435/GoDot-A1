extends Node3D
## Authored skin/animations only. Confirmed AI mode supplies combat timing.
var model:Node3D
var animation:AnimationPlayer
var clips:Dictionary={}
var elapsed:=0.0
var current:=""

func _ready()->void:
	model=load("res://assets/characters/zombie/zombie.glb").instantiate();add_child(model)
	for node in model.find_children("*","AnimationPlayer",true,false):animation=node
	if animation==null:return
	animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in animation.get_animation_list():
		for kind in ["idle","walk","attack","hit","death"]:
			if kind in name:clips[kind]=name

func update_pose(data:Dictionary,dt:float)->void:
	if animation==null:return
	var mode:String=data.mode
	var kind:String="death" if data.hp<=0 else "hit" if mode=="stagger" else "attack" if mode in ["windup","recover"] else "walk" if Vector2(data.velocity).length()>.1 else "idle"
	if not clips.has(kind):return
	if current!=kind:animation.play(clips[kind]);elapsed=0.0;current=kind
	elapsed+=dt
	var time:float=elapsed
	if kind=="walk":time=elapsed*clampf(Vector2(data.velocity).length()/2.0,.25,1.3)
	elif kind=="attack":time=.45-float(data.timer) if mode=="windup" else .45+.85-float(data.timer)
	elif kind=="hit":time=.25-float(data.timer)
	var length:float=animation.get_animation(clips[kind]).length
	time=fposmod(time,maxf(length,.001)) if kind in ["walk","idle"] else clampf(time,0,maxf(0,length-.001))
	animation.seek(time,true)
