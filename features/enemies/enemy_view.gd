extends Node3D
const Texts=preload("res://features/localization/game_text.gd")
## Local-only visual for confirmed hostile state. No physics or damage here.
const G=preload("res://features/geometry/geometry.gd")
var model:Node3D
var skeleton:Skeleton3D
var sick_visual:=false
var cough_cloud:MeshInstance3D
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
	title=G.text(self,Texts.resolve("⟦enemy.name⟧"),Vector3(0,1.8,0),22,Color("ed9a83"))
	title.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	title.outline_size=4
func update_enemy(data:Dictionary,delta:float):
	if data.get("kind","")=="sick_ghost" and not sick_visual:
		sick_visual=true
		for child in rig.get_children():child.queue_free()
		feet.clear();wings.clear()
		model=load("res://assets/characters/sick_ghost/sick_ghost.glb").instantiate();rig.add_child(model)
		# Imported GLB faces +Z; enemy aim and cough use -Z.
		model.rotation.y=PI
		for node in model.find_children("*","Skeleton3D",true,false):skeleton=node
		cough_cloud=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.3;sphere.height=.6;cough_cloud.mesh=sphere
		var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.55,.65,.12,.35);cough_cloud.material_override=material
		rig.add_child(cough_cloud);cough_cloud.position=Vector3(0,1.35,-.65)
	clock+=delta
	var target:=Vector3(data.pos.x,data.height,data.pos.y)
	position=position.lerp(target,1-exp(-delta*18)) if initialized and position.distance_to(target)<5 else target
	initialized=true
	var aim:Vector2=data.aim
	if aim.length_squared()>.01:rotation.y=lerp_angle(rotation.y,atan2(-aim.x,-aim.y),1-exp(-delta*18))
	var moving:float=minf(1,Vector2(data.velocity).length()/(2.0 if sick_visual else 4.6))
	var stagger:bool=data.mode=="stagger"
	if stagger:moving=0.0
	if data.hp<=0:
		rig.rotation.z=lerp_angle(rig.rotation.z,1.5,1-exp(-delta*9));rig.position.y=lerpf(rig.position.y,.55,1-exp(-delta*9))
		Texts.bind(title,"⟦enemy.dead⟧");return
	if int(data.attack_seq)!=last_attack:last_attack=int(data.attack_seq);swing=.3
	swing=maxf(0,swing-delta)
	var charge:float=1.0-float(data.timer)/(.8 if sick_visual else .45) if data.mode=="windup" else 0.0
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

	if sick_visual:
		Texts.bind(title,"⟦enemy.sick.invulnerable⟧")
		cough_cloud.visible=swing>0
		cough_cloud.scale=Vector3.ONE*(1.0+(1.0-swing/.3)*3.0)
		if skeleton:
			for i in range(2):
				var side:String="left" if i==0 else "right"
				var phase:float=clock*7+i*PI
				for part in ["thigh","shin"]:
					var bone:int=skeleton.find_bone(side+"_"+part)
					if bone>=0:
						var angle:float=sin(phase)*.30 if part=="thigh" else maxf(0,-sin(phase))*.42
						skeleton.set_bone_pose_rotation(bone,skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,angle*moving))
