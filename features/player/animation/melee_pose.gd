extends RefCounted
## Actor-space grip targets; imported hand bones carry the visible weapon.
const Rules=preload("res://features/combat/melee_system.gd")
const Sweep=preload("res://features/combat/melee_sweep.gd")
const Slash=preload("res://features/player/animation/melee_slash.gd")
var actor:Node3D
var holder:Node3D
var models:Dictionary={}
var kind:=""
var pose_weight:=0.0
var right_weight:=0.0
var pose:=Transform3D.IDENTITY
var active:=false
var attacking:=false
var sound_sequence:=-1
var slash:Node3D
const RIGHT_WRIST=Vector3(.055,-.015,.015)
const LEFT_WRIST=Vector3(-.055,.105,.015)

func configure(owner:Node3D)->void:
	actor=owner;holder=Node3D.new();holder.name="MeleeWeapon";actor.add_child(holder);holder.visible=false
	slash=Slash.new();actor.add_child(slash)

func prepare(data:Dictionary,dt:float)->void:
	kind=actor.weapon_kind;active=Rules.is_melee(kind)
	holder.visible=active and not data.get("dancing",false) and float(data.get("hp",100))>0
	if not active:pose_weight=0.0;right_weight=0.0;attacking=false;slash.visible=false;return
	if not models.has(kind):
		var model:Node3D=load("res://assets/weapons/melee/"+kind+".glb").instantiate()
		# Source cutting edges/hooks face +Z; turn them toward the actor's -Z front.
		model.rotation.y=PI
		holder.add_child(model);models[kind]=model
	for key in models:models[key].visible=key==kind
	var duration:float=maxf(.01,actor._event_duration)
	var phase:float=clampf(actor._event_time/duration,0,1)
	attacking=actor._event_action=="melee_swing" and actor._event_time<duration
	var aim:Vector2=data.get("aim",Vector2.UP)
	slash.rotation.y=atan2(-aim.x,-aim.y)-actor.rotation.y
	slash.update_slash(kind,phase,attacking and holder.visible and not data.get("roll",{}).get("active",false),data.get("crouch",false))
	var desired:float=maxf(actor._aim_blend,1.0 if attacking else 0.0)*(1.0-actor._visual_action_weight)
	pose_weight=move_toward(pose_weight,desired,dt*12)
	# Keep the original hanging arm/wrist at rest; raise it only for guard or attack.
	right_weight=pose_weight
	var carry:=Transform3D(Basis.from_euler(Vector3(-PI/2,0,0)),Vector3(.30,.88,-.20))
	var right:=Transform3D(Basis.from_euler(Vector3(-.30,0,-.20)),Vector3(.24,1.08,-.26))
	var target:=carry.interpolate_with(right,actor._aim_blend)
	if attacking:
		var direction:=Vector3(sin(Sweep.angle(phase)),0,-cos(Sweep.angle(phase)))
		var sweep_pose:=Transform3D(Basis(Quaternion(Vector3.UP,direction)),Vector3(0,1.04,-.05)+direction*.25)
		if phase<Sweep.START:target=right.interpolate_with(sweep_pose,smoothstep(0,Sweep.START,phase))
		elif phase<=Sweep.END:target=sweep_pose
		else:target=sweep_pose.interpolate_with(right,smoothstep(Sweep.END,1.0,phase))
		var twist:float=lerpf(-.16,.23,smoothstep(Sweep.START,Sweep.END,phase))
		actor._rotate("Spine",Vector3(0,twist*sin(PI*phase)*pose_weight,0))
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
	var origin:Vector3=(hand.origin+Vector3(0,-.07,-.01)).lerp(hand.origin-pose.basis*RIGHT_WRIST,right_weight)
	holder.transform=Transform3D(pose.basis,origin)
