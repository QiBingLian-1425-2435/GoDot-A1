extends RefCounted
## Small additive upper-body flinch; never changes legs, actions or physics.
var sequence:=-1
var relocation:=-1
var time:=1.0
const DURATION=.24

func observe(data:Dictionary,dt:float)->void:
	var current:int=data.get("hurt_seq",0)
	var moved:int=data.get("relocation_seq",0)
	if sequence<0 or moved!=relocation:sequence=current;relocation=moved;time=1.0
	elif sequence!=current:sequence=current;time=0.0
	time+=dt
	if float(data.get("hp",100))<=0:time=1.0

func apply(poses:Array[Transform3D],skin:Skeleton3D)->void:
	if time>=DURATION:return
	var index:int=skin.find_bone("Spine01")
	if index<0:return
	var pivot:Vector3=poses[index].origin
	var envelope:float=sin(PI*time/DURATION)*exp(-time*3)
	var twitch:float=sin(time*65)*envelope
	var basis:=Basis.from_euler(Vector3(-.15*envelope,.045*twitch,.12*twitch))
	for i in skin.get_bone_count():
		var name:String=skin.get_bone_name(i)
		if name.begins_with("Spine") or name.begins_with("Neck") or name=="Head" or "arm" in name or "Hand" in name or "Clavicle" in name:
			poses[i]=Transform3D(basis*poses[i].basis,pivot+basis*(poses[i].origin-pivot))
