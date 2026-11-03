extends Node3D
const Texts=preload("res://features/localization/game_text.gd")
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
	var model=load("res://assets/characters/sick_ghost/sick_ghost.glb").instantiate()
	rig.add_child(model)
	title=G.text(self,Texts.resolve("⟦enemy.name⟧"),Vector3(0,1.8,0),22,Color("ed9a83"))
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
	var stagger:bool=data.mode=="stagger"
	if stagger:moving=0.0
	if data.hp<=0:
		rig.rotation.z=lerp_angle(rig.rotation.z,1.5,1-exp(-delta*9));rig.position.y=lerpf(rig.position.y,.55,1-exp(-delta*9))
		Texts.bind(title,"⟦enemy.dead⟧");return
	if int(data.attack_seq)!=last_attack:last_attack=int(data.attack_seq);swing=.3
	swing=maxf(0,swing-delta)
	var charge:float=1.0-float(data.timer)/.45 if data.mode=="windup" else 0.0
	rig.rotation.x=-.18*moving-.3*charge+.55*sin(swing/.3*PI)
	if stagger:
		var recoil:Vector3=global_basis.inverse()*Vector3(data.velocity.x,0,data.velocity.y)
		rig.rotation.x=clampf(recoil.z*.055,-.28,.28)
		rig.rotation.z=clampf(-recoil.x*.055,-.28,.28)
	else:rig.rotation.z=lerp_angle(rig.rotation.z,0,1-exp(-delta*18))
	rig.position.y=absf(sin(clock*13))*.055*moving
	for i in feet.size():feet[i].rotation.x=sin(clock*13+i*PI)*.65*moving
	for i in wings.size():wings[i].rotation.x=-.6*charge-1.5*sin(swing/.3*PI)+sin(clock*13+i*PI)*.25*moving
	Texts.bind(title,Texts.format("⟦enemy.health⟧",[data.hp,"  !" if data.mode=="windup" else ""]))
	title.modulate=Color("ff694f") if data.mode=="windup" else Color.WHITE
