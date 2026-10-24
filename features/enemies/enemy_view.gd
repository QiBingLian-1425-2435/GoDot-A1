extends Node3D
## Local-only visual for confirmed hostile state. No physics or damage here.
const G=preload("res://features/geometry/geometry.gd")
var rig:Node3D
var feet:Array[Node3D]=[]
var wings:Array[Node3D]=[]
var title:Label3D
var clock:=0.0
var initialized:=false
var last_attack:=0
var swing:=0.0
func _ready():
	rig=Node3D.new();add_child(rig)
	G.sphere(rig,Vector3(0,.65,.07),Vector3(.85,.95,.75),Color("566653"))
	G.sphere(rig,Vector3(0,1.19,-.18),Vector3(.73,.66,.72),Color("85926a"))
	G.sphere(rig,Vector3(0,1.05,-.57),Vector3(.50,.16,.38),Color("b78950"))
	G.box(rig,Vector3(0,1.01,-.66),Vector3(.40,.045,.20),Color("291c20"))
	for side in [-1,1]:
		G.sphere(rig,Vector3(side*.23,1.25,-.48),Vector3(.10,.08,.06),Color("eb5942"))
		G.box(rig,Vector3(side*.22,1.32,-.46),Vector3(.23,.06,.06),Color("303a2a"))
		G.box(rig,Vector3(side*.16,.98,-.72),Vector3(.055,.11,.06),Color("eee1b5"))
		var foot:=Node3D.new();rig.add_child(foot);foot.position=Vector3(side*.23,.17,.04);feet.append(foot)
		G.sphere(foot,Vector3.ZERO,Vector3(.22,.18,.45),Color("a48452"))
		var wing:=Node3D.new();rig.add_child(wing);wing.position=Vector3(side*.42,.85,-.02);wings.append(wing)
		G.sphere(wing,Vector3(0,-.18,0),Vector3(.24,.52,.31),Color("697457"))
		for claw in [-1,0,1]:G.rod(wing,Vector3(claw*.06,-.34,-.06),Vector3(claw*.08,-.52,-.18),.025,Color("e2d2a7"))
	G.box(rig,Vector3(0,.80,-.33),Vector3(.53,.27,.08),Color("692d2d"))
	title=G.text(self,"狂化鸭",Vector3(0,1.8,0),22,Color("ed9a83"))
	title.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	title.outline_size=4
func update_enemy(data:Dictionary,delta:float):
	clock+=delta
	var target:=Vector3(data.pos.x,data.height,data.pos.y)
	position=position.lerp(target,1-exp(-delta*18)) if initialized and position.distance_to(target)<5 else target
	initialized=true
	var aim:Vector2=data.aim
	if aim.length_squared()>.01:rotation.y=lerp_angle(rotation.y,atan2(-aim.x,-aim.y),1-exp(-delta*18))
	var moving:float=minf(1,Vector2(data.velocity).length()/4.6)
	if data.hp<=0:
		rig.rotation.z=lerp_angle(rig.rotation.z,1.5,1-exp(-delta*9));rig.position.y=lerpf(rig.position.y,.55,1-exp(-delta*9))
		title.text="狂化鸭 · 已击倒";return
	if int(data.attack_seq)!=last_attack:last_attack=int(data.attack_seq);swing=.3
	swing=maxf(0,swing-delta)
	var charge:float=1.0-float(data.timer)/.45 if data.mode=="windup" else 0.0
	rig.rotation.x=-.18*moving-.3*charge+.55*sin(swing/.3*PI)
	rig.position.y=absf(sin(clock*13))*.055*moving
	for i in feet.size():feet[i].rotation.x=sin(clock*13+i*PI)*.65*moving
	for i in wings.size():wings[i].rotation.x=-.6*charge-1.5*sin(swing/.3*PI)+sin(clock*13+i*PI)*.25*moving
	title.text="狂化鸭  %d / 100%s"%[data.hp,"  !" if data.mode=="windup" else ""]
	title.modulate=Color("ff694f") if data.mode=="windup" else Color.WHITE
