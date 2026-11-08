extends RefCounted
## Actor-space grip targets; imported hand bones carry the visible weapon.
const Rules=preload("res://features/combat/melee_system.gd")
var actor:Node3D
var holder:Node3D
var models:Dictionary={}
var kind:=""
var pose_weight:=0.0
var pose:=Transform3D.IDENTITY
var active:=false
var attacking:=false
var sound_sequence:=-1
const RIGHT_WRIST=Vector3(.055,-.015,.015)
const LEFT_WRIST=Vector3(-.055,.105,.015)

func configure(owner:Node3D)->void:
	actor=owner;holder=Node3D.new();holder.name="MeleeWeapon";actor.add_child(holder);holder.visible=false

func prepare(data:Dictionary,dt:float)->void:
	kind=actor.weapon_kind;active=Rules.is_melee(kind)
	holder.visible=active and not data.get("dancing",false) and float(data.get("hp",100))>0
	if not active:pose_weight=0.0;attacking=false;return
	if not models.has(kind):
		var model:Node3D=load("res://assets/weapons/melee/"+kind+".glb").instantiate()
		holder.add_child(model);models[kind]=model
	for key in models:models[key].visible=key==kind
	var duration:float=maxf(.01,actor._event_duration)
	var phase:float=clampf(actor._event_time/duration,0,1)
	attacking=actor._event_action in ["melee_forward","melee_back"] and actor._event_time<duration
	var desired:float=maxf(actor._aim_blend,1.0 if attacking else 0.0)*(1.0-actor._visual_action_weight)
	pose_weight=move_toward(pose_weight,desired,dt*12)
	var right:=Transform3D(Basis.from_euler(Vector3(-.30,0,-.20)),Vector3(.24,1.08,-.26))
	var middle:=Transform3D(Basis.from_euler(Vector3(-1.55,0,.05)),Vector3(.10,1.04,-.43))
	var left:=Transform3D(Basis.from_euler(Vector3(-1.60,0,.85)),Vector3(-.18,1.00,-.35))
	var target:=right
	if attacking:
		var u:float=smoothstep(.10,.80,phase)
		if actor._event_action=="melee_back":u=1.0-u
		target=right.interpolate_with(middle,u*2.0) if u<.5 else middle.interpolate_with(left,(u-.5)*2.0)
		actor._rotate("Spine",Vector3(0,lerpf(-.10,.14,u)*pose_weight,0))
	target.origin.y-=.43*actor._crouch_blend
	pose=pose.interpolate_with(target,1.0-exp(-dt*28)) if pose!=Transform3D.IDENTITY else target

func hand_target(side:String)->Vector3:
	return pose*(LEFT_WRIST if side=="L" else RIGHT_WRIST)

func hand_basis(side:String,rest_basis:Basis)->Basis:
	return pose.basis*Basis.from_euler(Vector3(0,0,PI/2 if side=="L" else -PI/2))*rest_basis

func attach(skin:Skeleton3D,space:Transform3D)->void:
	if not active:return
	var index:int=skin.find_bone("R_Hand")
	if index<0:return
	var hand:Transform3D=space*skin.get_bone_global_pose(index)
	var relaxed:=Basis.from_euler(Vector3(-2.65,.10,-.13))
	var origin:Vector3=(hand.origin+Vector3(0,-.07,-.01)).lerp(hand.origin-pose.basis*RIGHT_WRIST,pose_weight)
	holder.transform=Transform3D(relaxed.slerp(pose.basis,pose_weight),origin)
