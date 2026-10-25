extends Node3D

const G = preload("res://features/geometry/geometry.gd")
const Duck = preload("res://features/player/base_actor.gd")
const CONCRETE := Color("666d70")
const WALL := Color("5c656b")
const STEEL := Color("35464c")
const OLIVE := Color("67705a")
const YELLOW := Color("c5a962")
const PURPLE := Color("71617e")
var _blocks: Array = []
var _points: Array = [
	{"id":"camp_management","title":"营地管理 · 建设与强化","pos":Vector2(-1,-1.9),"kind":"camp_management"},
	{"id":"stash","title":"仓库 · 整理物资","pos":Vector2(9,-5.3),"kind":"stash"},
	{"id":"workbench","title":"工作台 · 选择配方制作道具","pos":Vector2(-9,2.2),"kind":"workbench"},
	{"id":"medical","title":"医疗站 · 治疗","pos":Vector2(-10,-5.2),"kind":"medical"},
	{"id":"exit","title":"地下出口 · 准备出发","pos":Vector2(0,-8.2),"kind":"exit"},
	{"id":"range","title":"训练场 · 重置全部训练靶","pos":Vector2(9,4.2),"kind":"range"},
	{"id":"ammo_supply","title":"弹药补给箱 · 免费补至120发备用弹，R装填","pos":Vector2(7.2,2.7),"kind":"ammo_supply"},
	{"id":"trader","title":"商人 · 购买补给 / 回收物资","pos":Vector2(-5,-2.6),"kind":"trader"}
]
var target_nodes: Dictionary = {}
var lamps: Array[OmniLight3D] = []

func obstacles() -> Array:
	return _blocks

func interactions() -> Array:
	return _points

func spawn_position() -> Vector2:
	return Vector2(0,3)

func _ready() -> void:
	_build_floor()
	_build_shell()
	# The reference enforced the perimeter with a rectangle bound only.
	# Engine-driven movement also needs colliders for these four visible walls.
	_solid(Vector2(0, -11), Vector2(30, 0.4))
	_solid(Vector2(0, 11), Vector2(30, 0.4))
	_solid(Vector2(-15, 0), Vector2(0.4, 22))
	_solid(Vector2(15, 0), Vector2(0.4, 22))
	_build_bedroom()
	_build_workshop()
	_build_storage()
	_build_range()
	_build_operations()
	_build_exit()
	_build_clutter()

func _solid(at: Vector2, size: Vector2) -> void:
	_blocks.append(Rect2(at-size*.5,size))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = Vector3(at.x, 0.9, at.y)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 1.8, size.y)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _floor_label(value: String, at: Vector2, size: int = 48, color: Color = Color("a3aaa1")) -> void:
	var label := G.text(self,value,Vector3(at.x,.026,at.y),size,color)
	label.rotation_degrees.x = -90
	label.pixel_size = .012

func _build_floor() -> void:
	G.box(self,Vector3(0,-.36,0),Vector3(30.8,.7,22.8),Color("222c33"))
	G.box(self,Vector3(0,-.07,0),Vector3(30,.16,22),Color("3b444b"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 49025
	for x in range(-15,15,2):
		for z in range(-11,11,2):
			var c := CONCRETE.darkened(rng.randf_range(.04,.18))
			G.box(self,Vector3(x+1,-.009,z+1),Vector3(1.971,.04,1.971),c)
	# A continuous drainage channel gives the room a believable underground utility spine.
	for z in range(-10,11):
		G.box(self,Vector3(2.7,.022,z),Vector3(.28,.025,.94),Color("28363d"),.5)
		for k in range(4):
			G.box(self,Vector3(2.7,.04,z-.35+k*.22),Vector3(.23,.022,.035),Color("717d7d"),.5)
	for x in [-3.4,3.4]:
		for z in range(-8,9,2):
			G.box(self,Vector3(x,.018,z),Vector3(.06,.018,1.2),YELLOW.darkened(.20))
	_floor_label("B1  /  SHELTER",Vector2(0,5.5),54,Color("a9b2a1"))
	_floor_label("AUTHORIZED PERSONNEL",Vector2(0,6.4),18,Color("89958f"))
	# Small inset utility plates and worn edges, rather than a perfectly pristine grid.
	for at in [Vector2(-3,1),Vector2(4,-6),Vector2(-3,-8),Vector2(5,8)]:
		G.box(self,Vector3(at.x,.025,at.y),Vector3(.75,.025,.62),Color("47565b"),.5)
		for sx in [-1,1]:
			for sz in [-1,1]:
				G.cylinder(self,Vector3(at.x+sx*.30,.045,at.y+sz*.24),.025,.018,Color("9ba49d"),-1,.8)

func _build_shell() -> void:
	# Tall back walls and low cutaway foreground keep every walking lane visible.
	_wall(Vector2(0,-11),Vector2(30,.4),2.85)
	_wall(Vector2(-15,0),Vector2(.4,22),2.85)
	_wall(Vector2(15,0),Vector2(.4,22),.72)
	_wall(Vector2(0,11),Vector2(30,.4),.52)
	for x in range(-14,15,4):
		G.box(self,Vector3(x,1.42,-10.72),Vector3(.29,2.85,.18),Color("4b565c"))
		G.box(self,Vector3(x,2.9,-10.96),Vector3(.55,.13,.58),STEEL,.4)
	# Block joints and mauve lower paint are characteristic of the bedroom's concrete bunker.
	for x in range(-14,15,2):
		for y in [.48,1.02,1.56,2.10,2.64]:
			G.box(self,Vector3(x + (.5 if int(y*10)%2==0 else 0),y,-10.775),Vector3(1.985,.018,.012),Color("414c54"))
	for z in range(-10,11,2):
		G.box(self,Vector3(-14.775,1.15,z),Vector3(.016,.035,1.98),Color("404a51"))
	G.box(self,Vector3(0,.81,-10.765),Vector3(29.9,.41,.035),PURPLE)
	G.box(self,Vector3(-14.765,.81,0),Vector3(.035,.41,21.9),PURPLE)
	for z in [-1.5,7.8]:
		for x in [-5.8,5.8]:
			G.box(self,Vector3(x,1.45,z),Vector3(.42,2.9,.42),Color("626c71"))
			G.box(self,Vector3(x,.28,z),Vector3(.49,.56,.49),Color("494c51"))
			for k in range(3):
				G.box(self,Vector3(x-.215,.45+k*.18,z),Vector3(.025,.085,.40),YELLOW.darkened(.25)).rotation.z = -.18
			_solid(Vector2(x,z),Vector2(.65,.65))
	# Cutaway dividing walls retain rooms while permitting an unobstructed isometric view.
	for entry in [Vector4(-10,-1.5,8,.23),Vector4(-10,7.8,8,.23),Vector4(10,-1.5,8,.23)]:
		_wall(Vector2(entry.x,entry.y),Vector2(entry.z,entry.w),.68)
		_solid(Vector2(entry.x,entry.y),Vector2(entry.z,entry.w+.18))
	# High pipes snake along the back wall, with collars and wall brackets.
	for pipe_y in [2.36,2.61]:
		G.rod(self,Vector3(-14.6,pipe_y,-10.42),Vector3(14.4,pipe_y,-10.42),.07,Color("697b7b"),.6)
		for x in range(-14,15,3):
			G.rod(self,Vector3(x,pipe_y,-10.48),Vector3(x,pipe_y,-10.34),.102,Color("45565e"),.6)
	G.rod(self,Vector3(-14.45,2.4,-10.4),Vector3(-14.45,2.4,9.8),.13,Color("716b5d"),.4)
	for z in range(-9,10,3):
		G.box(self,Vector3(-14.51,2.36,z),Vector3(.3,.3,.10),STEEL,.5)
	# Surface-mount fluorescent fixtures make the cutaway perimeter feel inhabited.
	for x in [-10,-4,5,12]:
		G.box(self,Vector3(x,2.50,-10.47),Vector3(1.35,.16,.25),Color("303e46"),.4)
		G.box(self,Vector3(x,2.46,-10.30),Vector3(1.1,.07,.04),Color("b5d0c8"),0,1.1)
		_light(Vector3(x,2.15,-9.3),Color("9bbdc8"),.55,5.0)

func _wall(at: Vector2, size: Vector2, height: float) -> void:
	G.box(self,Vector3(at.x,height*.5,at.y),Vector3(size.x,height,size.y),WALL)
	G.box(self,Vector3(at.x,height+.025,at.y),Vector3(size.x+.08,.07,size.y+.08),Color("87908c"))
	G.box(self,Vector3(at.x,.14,at.y),Vector3(size.x+.04,.24,size.y+.04),Color("454b53"))

func _build_bedroom() -> void:
	# The original safe-room motif: paired pale beds, blue pillows, mauve paint and a pink lamp.
	for x in range(16):
		G.box(self,Vector3(-14.2+x*.48,.035,-6.1),Vector3(.465,.06,8.6),Color("626360").lightened((x%3)*.025))
	for z in [-10.2,-7.4,-4.5,-1.9]:
		G.box(self,Vector3(-10.6,.07,z),Vector3(7.65,.01,.018),Color("434d51"))
	_bed(Vector2(-12.5,-7.8))
	_bed(Vector2(-8.3,-7.8))
	_table(Vector2(-10.4,-9.4),Vector2(1.35,.85),.69,Color("8b8f86"))
	G.box(self,Vector3(-10.4,.95,-9.37),Vector3(.52,.33,.25),Color("656074"),.2)
	G.box(self,Vector3(-10.4,.97,-9.22),Vector3(.42,.20,.035),Color("b08ca2"),0,.8)
	for x in [-10.55,-10.35]:
		G.cylinder(self,Vector3(x,1.17,-9.35),.033,.10,Color("d2c2ad"),-1,.3)
	_desk_lamp(Vector3(-10.8,.73,-9.35),Color("e9a7d7"))
	_light(Vector3(-10.6,1.5,-8.7),Color("d195d4"),1.25,5)
	# White medicine cabinet with a raised red cross and small sink to the left.
	G.box(self,Vector3(-14.05,1.53,-4.2),Vector3(.58,1.05,1.0),Color("adb3ae"),.2)
	G.box(self,Vector3(-13.74,1.53,-4.2),Vector3(.025,.58,.16),Color("9b5e69"))
	G.box(self,Vector3(-13.72,1.53,-4.2),Vector3(.025,.16,.58),Color("9b5e69"))
	G.box(self,Vector3(-13.8,.68,-5.6),Vector3(1.10,.12,.78),Color("babeb5"))
	G.box(self,Vector3(-13.8,.75,-5.6),Vector3(.64,.045,.48),Color("596975"),.4)
	G.rod(self,Vector3(-14.1,.75,-5.6),Vector3(-14.1,1.08,-5.6),.034,Color("aeb7b0"),.8)
	G.rod(self,Vector3(-14.1,1.08,-5.6),Vector3(-13.9,1.08,-5.6),.034,Color("aeb7b0"),.8)
	_solid(Vector2(-13.8,-4.9),Vector2(1.2,2.2))
	_floor_label("01  /  QUARTERS",Vector2(-10.5,-2.6),29,Color("b4bcad"))
	_npc(Vector2(-12.0,-4.0),Color("97a8b0"),"医生",Vector2(1,.2),false)
	_sign("MEDICAL / 01",Vector3(-10.4,2.03,-10.70),Color("d0bacb"))

func _bed(at: Vector2) -> void:
	var base := Node3D.new()
	base.position = Vector3(at.x,0,at.y)
	add_child(base)
	for x in [-.61,.61]:
		for z in [-1.03,1.03]:
			G.cylinder(base,Vector3(x,.27,z),.046,.54,Color("7e8b89"),-1,.5)
	G.box(base,Vector3(0,.42,0),Vector3(1.35,.13,2.26),Color("465961"),.4)
	G.box(base,Vector3(0,.57,0),Vector3(1.31,.20,2.19),Color("adb8b3"))
	G.box(base,Vector3(0,.70,.27),Vector3(1.33,.10,1.62),Color("c5cdc2"))
	G.box(base,Vector3(0,.76,-.71),Vector3(.94,.16,.43),Color("697f95"))
	for x in [-.62,.62]:
		G.rod(base,Vector3(x,.45,-1.08),Vector3(x,1.12,-1.08),.04,Color("82908d"),.5)
	G.rod(base,Vector3(-.62,1.12,-1.08),Vector3(.62,1.12,-1.08),.045,Color("82908d"),.5)
	G.box(base,Vector3(0,.735,.71),Vector3(1.35,.028,.055),Color("889c9c"))
	_solid(at,Vector2(1.65,2.5))

func _build_workshop() -> void:
	_table(Vector2(-10.7,.3),Vector2(5.4,1.15),.92,Color("706e5b"))
	G.box(self,Vector3(-10.7,1.55,-.31),Vector3(5.2,1.12,.1),Color("495b61"),.4)
	for x in range(15):
		for y in range(3):
			G.sphere(self,Vector3(-13.0+x*.33,1.25+y*.28,-.24),Vector3(.029,.029,.025),Color("82918b"))
	# Silhouetted tools hang over the bench.
	for x in [-12.5,-11.9,-10.3,-9.7,-8.7]:
		G.box(self,Vector3(x,1.52,-.17),Vector3(.065,.43,.065),Color("b0b4a1"),.6).rotation.z = .15
		G.box(self,Vector3(x+.07,1.72,-.16),Vector3(.20,.08,.08),Color("9ba89d"),.6)
	_desk_lamp(Vector3(-12.8,.99,.4),Color("f4cf85"))
	G.box(self,Vector3(-10.5,1.04,.2),Vector3(1.2,.05,.55),Color("34544f"))
	_gun_display(Vector3(-10.5,1.10,.2),.65)
	G.box(self,Vector3(-8.75,1.15,.2),Vector3(.51,.37,.50),Color("526568"),.5)
	G.box(self,Vector3(-8.75,1.37,.20),Vector3(.68,.08,.17),Color("92988a"),.7)
	G.rod(self,Vector3(-9.1,1.15,.2),Vector3(-8.4,1.15,.2),.035,Color("b7b9a2"),.7)
	_light(Vector3(-10.4,2.25,.9),Color("efc588"),1.4,6.5)
	# Generator: cast chassis, radiator, copper tubes, exhaust and status indicators.
	var gen := Node3D.new()
	gen.position = Vector3(-12.3,0,5.0)
	add_child(gen)
	G.box(gen,Vector3(0,.16,0),Vector3(2.7,.25,1.8),Color("35434a"),.5)
	G.box(gen,Vector3(0,.79,0),Vector3(2.3,1.05,1.38),Color("657269"),.3)
	G.box(gen,Vector3(-.6,1.34,0),Vector3(.70,.14,1.1),Color("727f70"),.3)
	for z in [-.71,.71]:
		for x in range(10):
			G.box(gen,Vector3(-.96+x*.21,.80,z),Vector3(.09,.65,.025),Color("2e3d43"))
	G.box(gen,Vector3(.7,1.05,.75),Vector3(.54,.49,.08),Color("263b40"))
	G.box(gen,Vector3(.7,1.14,.802),Vector3(.34,.12,.02),Color("9abfa7"),0,.7)
	for x in [.56,.80]:
		G.sphere(gen,Vector3(x,.95,.813),Vector3(.065,.065,.025),Color("cf9a5a"))
	G.rod(gen,Vector3(-.9,1.2,0),Vector3(-.9,2.0,0),.11,Color("726c5d"),.7)
	G.rod(gen,Vector3(-.9,2.0,0),Vector3(-1.8,2.0,0),.11,Color("726c5d"),.7)
	_solid(Vector2(-12.3,5),Vector2(2.9,2.0))
	G.text(gen,"DIESEL  /  24 kW",Vector3(0,.75,.72),20,Color("cad0b5"))
	_floor_label("02  /  WORKSHOP",Vector2(-10,6.9),29,Color("c7b48c"))
	_npc(Vector2(-11.8,2.0),Color("9c906b"),"技师",Vector2(.2,-1),true)
	_wire_fence(Vector2(-5.8,5.2),3.5)
	# Yellow coiled hose on the floor.
	for k in range(20):
		var a := k*TAU/20.0
		var b := (k+1)*TAU/20.0
		G.rod(self,Vector3(-8+.55*cos(a),.07,5+.55*sin(a)),Vector3(-8+.55*cos(b),.07,5+.55*sin(b)),.045,Color("ae945f"))

func _build_storage() -> void:
	for x in [7.0,8.5,10.0,11.5,13.0]:
		_locker(Vector2(x,-9.4))
	_rack(Vector2(13.3,-5.5),true)
	_rack(Vector2(7.1,-7.3),false)
	for entry in [Vector3(11.5,.38,-6.9),Vector3(12.3,.38,-6.9),Vector3(11.9,1.05,-6.9),Vector3(7.1,.38,-3.5)]:
		_crate(entry,Vector3(.78,.69,.65))
	_solid(Vector2(11.9,-6.9),Vector2(1.7,1.0))
	_solid(Vector2(7.1,-3.5),Vector2(1.0,1.0))
	# Large shared storage trunk; player's prompt is centered in the clear lane in front.
	G.box(self,Vector3(9,.40,-6.8),Vector3(2.15,.80,1.15),Color("647263"),.3)
	G.box(self,Vector3(9,.83,-6.8),Vector3(2.24,.13,1.22),Color("7c866d"),.3)
	for x in [8.25,9.75]:
		G.box(self,Vector3(x,.50,-6.19),Vector3(.09,.54,.028),Color("343f3c"),.6)
		G.box(self,Vector3(x,.68,-6.16),Vector3(.16,.13,.045),Color("bdac7c"),.6)
	G.text(self,"SHARED STORAGE",Vector3(9,.48,-6.185),21,Color("d1d3af"))
	_solid(Vector2(9,-6.8),Vector2(2.4,1.5))
	_floor_label("03  /  STORAGE",Vector2(10,-2.6),29,Color("9db6b5"))
	_sign("LOGISTICS / 03",Vector3(10,2.03,-10.70),Color("baccc6"))
	_light(Vector3(9.5,2.3,-6),Color("a6c8d1"),1.1,6)

func _locker(at: Vector2) -> void:
	G.box(self,Vector3(at.x,1.0,at.y),Vector3(1.25,2.0,.85),Color("455b63"),.4)
	for side in [-1,1]:
		var x: float = at.x+side*.30
		G.box(self,Vector3(x,1.02,at.y+.443),Vector3(.58,1.89,.04),Color("637b7d"),.35)
		for y in [.55,.66,.77,1.54,1.65,1.76]:
			G.box(self,Vector3(x,y,at.y+.47),Vector3(.35,.022,.018),Color("32464d"))
		G.box(self,Vector3(x+side*.16,1.09,at.y+.49),Vector3(.045,.22,.05),Color("adb5a7"),.7)
		G.box(self,Vector3(x,1.30,at.y+.476),Vector3(.21,.09,.008),Color("b5b99f"))
	_solid(at,Vector2(1.4,1.1))

func _rack(at: Vector2, rotate: bool) -> void:
	var rack := Node3D.new()
	rack.position = Vector3(at.x,0,at.y)
	if rotate:
		rack.rotation.y = PI/2
	add_child(rack)
	for x in [-1.2,1.2]:
		for z in [-.42,.42]:
			G.box(rack,Vector3(x,1.1,z),Vector3(.085,2.2,.085),Color("73867f"),.5)
	for y in [.18,.85,1.52,2.17]:
		G.box(rack,Vector3(0,y,0),Vector3(2.5,.085,.94),Color("727d71"),.3)
	for x in [-.72,.1,.78]:
		for y in [.45,1.12,1.79]:
			G.box(rack,Vector3(x,y,0),Vector3(.56,.46,.65),Color("8b876e").darkened((x+.72)*.10))
			G.box(rack,Vector3(x,y,-.333),Vector3(.16,.44,.014),Color("b4a88a"))
	_solid(at,Vector2(1.2,2.8) if rotate else Vector2(2.8,1.2))

func _build_range() -> void:
	# Three firing lanes, ballistic backstop, painted safety line and brass on the concrete.
	for x in [7,9,11,13]:
		G.box(self,Vector3(x,.031,7.4),Vector3(.065,.021,5.1),YELLOW.darkened(.16))
	G.box(self,Vector3(10,.032,4.6),Vector3(6.25,.022,.12),YELLOW)
	for x in range(12):
		G.box(self,Vector3(7.2+x*.5,.04,4.88),Vector3(.25,.025,.30),Color("353d3c")).rotation.y = -.4
	G.box(self,Vector3(10,.58,10.1),Vector3(6.8,1.15,.48),Color("35454c"),.3)
	for x in range(14):
		G.box(self,Vector3(6.8+x*.49,.59,9.8),Vector3(.38,1.1,.12),Color("4c5d5e"),.4).rotation.y = -.16
	for i in range(3):
		var target_pos := Vector2(8+i*2,8.8)
		_target(target_pos,i)
	_table(Vector2(7.2,2.7),Vector2(1.7,.9),.88,Color("626952"))
	G.box(self,Vector3(7.2,1.06,2.7),Vector3(.81,.30,.55),Color("68744f"),.2)
	G.box(self,Vector3(7.2,1.23,2.7),Vector3(.86,.065,.59),Color("829067"),.2)
	G.text(self,"AMMO",Vector3(7.2,1.05,3.0),22,Color("cec8a1"))
	G.text(self,"弹药补给 · E 免费领取",Vector3(7.2,1.65,2.7),22,YELLOW)
	for i in range(22):
		var x := 8.0+fmod(i*1.79,4.8)
		var z := 5.5+fmod(i*.63,1.8)
		G.rod(self,Vector3(x,.055,z),Vector3(x+.10,.055,z+.02),.018,Color("b4a16c"),.7)
	_floor_label("04  /  FIRING RANGE",Vector2(10,1.7),29,Color("b6b8a0"))
	_floor_label("KEEP BEHIND THE LINE",Vector2(10,3.9),19,YELLOW)
	_solid(Vector2(10,10.1),Vector2(7.0,.7))
	_light(Vector3(10,2.5,7.5),Color("c2c5b0"),.8,5.5)

func _target(at: Vector2, index: int) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(at.x,0,at.y)
	add_child(holder)
	G.box(holder,Vector3(0,.07,0),Vector3(.9,.14,.9),Color("303c40"),.4)
	G.box(holder,Vector3(0,.76,0),Vector3(.075,1.45,.075),Color("88938b"),.6)
	var board := Node3D.new()
	holder.add_child(board)
	G.box(board,Vector3(0,1.46,0),Vector3(.93,1.02,.10),Color("a99979"))
	G.sphere(board,Vector3(0,1.96,0),Vector3(.47,.42,.10),Color("a99979"))
	# Targets face -Z towards the firing line; concentric metallic discs read from above.
	for entry in [Vector3(.32,.025,0),Vector3(.23,.031,1),Vector3(.13,.038,0)]:
		var disc := G.cylinder(board,Vector3(0,1.48,-.065-entry.y),entry.x,.015,Color("3f494a") if entry.z==0 else Color("bdae89"))
		disc.rotation.x = PI/2
		var back_disc := G.cylinder(board,Vector3(0,1.48,.065+entry.y),entry.x,.015,Color("3f494a") if entry.z==0 else Color("bdae89"))
		back_disc.rotation.x = PI/2
	G.sphere(board,Vector3(0,1.48,-.115),Vector3(.09,.09,.025),Color("c68a70"))
	G.sphere(board,Vector3(0,1.48,.115),Vector3(.09,.09,.025),Color("c68a70"))
	G.text(board,"0"+str(index+1),Vector3(0,1.01,.064),16,Color("3a4545"))
	target_nodes[index] = board

func update_targets(targets: Array) -> void:
	for i in range(mini(targets.size(),target_nodes.size())):
		var hp := float(targets[i].get("hp",100))
		target_nodes[i].rotation.x = -.65 if hp <= 0 else 0.0

func _build_operations() -> void:
	# Central map table leaves the spawn and all station approaches open.
	_table(Vector2(-1.0,-3.7),Vector2(3.1,1.85),.90,Color("757c6c"))
	G.box(self,Vector3(-1.0,.967,-3.7),Vector3(2.52,.035,1.40),Color("bbb9a0"))
	for entry in [Vector4(-1.4,-3.9,.7,.35),Vector4(-.4,-3.4,.5,.5),Vector4(-1.9,-3.25,.3,.25)]:
		G.box(self,Vector3(entry.x,.99,entry.y),Vector3(entry.z,.012,entry.w),Color("81978a"))
	for i in range(7):
		G.box(self,Vector3(-2.1+i*.36,1.004,-3.7),Vector3(.018,.012,1.2),Color("8c9382"))
	for z in [-4.1,-3.7,-3.3]:
		G.box(self,Vector3(-1,1.006,z),Vector3(2.3,.012,.018),Color("8c9382"))
	for at in [Vector2(-1.5,-3.6),Vector2(-.3,-4.0)]:
		G.cylinder(self,Vector3(at.x,1.07,at.y),.046,.12,Color("ba7769"))
	G.box(self,Vector3(.1,1.08,-3.1),Vector3(.42,.19,.24),Color("344d56"),.3)
	G.rod(self,Vector3(.2,1.17,-3.1),Vector3(.2,1.63,-3.1),.014,Color("5b777c"),.6)
	_desk_lamp(Vector3(-2.25,.98,-4.25),Color("e7c890"))
	_light(Vector3(-1.0,2.3,-3.5),Color("e4c28e"),.9,4.0)
	_floor_label("CAMP UPGRADES",Vector2(-.6,-1.9),26,Color("afb9a7"))
	# Trading booth between quarters and the operations table.
	_table(Vector2(-6.6,-3.8),Vector2(1.3,2.4),.9,Color("6c7969"))
	G.box(self,Vector3(-6.6,1.08,-4.3),Vector3(.52,.30,.46),Color("3a4f55"),.2)
	G.box(self,Vector3(-6.6,1.37,-4.3),Vector3(.56,.34,.08),Color("344b52"),.4)
	G.box(self,Vector3(-6.6,1.37,-4.25),Vector3(.46,.25,.015),Color("9bad8b"),0,.6)
	G.box(self,Vector3(-6.6,1.02,-3.15),Vector3(.64,.11,.46),Color("baad87"))
	_npc(Vector2(-7.7,-4),Color("9b8762"),"商人",Vector2(1,.2),false)
	# Hanging notice board mounted on a post, with layered paper missions.
	G.box(self,Vector3(-3.7,1.22,-7.8),Vector3(.1,2.4,.1),STEEL,.5)
	G.box(self,Vector3(-3.7,1.76,-7.8),Vector3(2.2,1.36,.11),Color("4d6164"),.3)
	for i in range(5):
		G.box(self,Vector3(-4.4+(i%3)*.64,1.98-floori(i/3.0)*.59,-7.72),Vector3(.46,.50,.02),Color("c7c0a5").darkened(i*.025)).rotation.z = (i-2)*.045
		G.box(self,Vector3(-4.4+(i%3)*.64,2.17-floori(i/3.0)*.59,-7.70),Vector3(.08,.055,.015),Color("a86668"))
	G.text(self,"TASK BOARD",Vector3(-3.7,2.55,-7.78),27,Color("c2c9b8"))
	_solid(Vector2(-3.7,-7.8),Vector2(2.3,.4))

func _build_exit() -> void:
	# Heavy blast hatch and a short ladder identify the way back to the surface.
	G.box(self,Vector3(0,1.45,-10.58),Vector3(3.35,2.9,.30),Color("2e424c"),.5)
	G.box(self,Vector3(0,1.35,-10.36),Vector3(2.85,2.5,.22),Color("667d80"),.5)
	for x in [-1.13,1.13]:
		G.box(self,Vector3(x,1.35,-10.20),Vector3(.14,2.30,.1),Color("92a09a"),.6)
	G.box(self,Vector3(0,1.35,-10.21),Vector3(.035,2.35,.04),Color("283d46"))
	G.box(self,Vector3(0,2.34,-10.15),Vector3(2.7,.15,.06),YELLOW)
	G.box(self,Vector3(0,.29,-10.15),Vector3(2.7,.15,.06),YELLOW)
	for i in range(8):
		G.box(self,Vector3(-1.2+i*.34,2.35,-10.11),Vector3(.13,.16,.018),Color("3e4a4b")).rotation.z = -.36
	G.cylinder(self,Vector3(.57,1.24,-10.1),.22,.08,Color("b7b8a2"),-1,.6).rotation.x = PI/2
	G.box(self,Vector3(.57,1.24,-10.02),Vector3(.32,.045,.05),Color("46575b"),.5)
	G.box(self,Vector3(0,2.89,-10.42),Vector3(1.3,.32,.16),Color("345e5c"))
	G.text(self,"EXIT ↑",Vector3(0,2.89,-10.31),32,Color("c2e3c2"))
	_light(Vector3(0,2.4,-9.0),Color("90cbb9"),1,4)
	for x in [2.0,2.55]:
		G.rod(self,Vector3(x,.05,-10.18),Vector3(x,3.42,-10.18),.045,Color("8c9a90"),.6)
	for y in range(9):
		G.rod(self,Vector3(2,.25+y*.35,-10.16),Vector3(2.55,.25+y*.35,-10.16),.038,Color("a5aca0"),.6)
	G.box(self,Vector3(3.4,1.37,-10.38),Vector3(.53,.87,.3),Color("52696f"),.4)
	G.box(self,Vector3(3.4,1.53,-10.20),Vector3(.36,.20,.018),Color("9bc5a6"),0,.4)
	G.sphere(self,Vector3(3.4,1.20,-10.19),Vector3(.16,.16,.08),Color("c68c74"))
	_floor_label("SURFACE ACCESS",Vector2(0,-8.4),25,Color("b2bdab"))

func _build_clutter() -> void:
	# Emergency equipment and utility supplies fill the cutaway edges without blocking paths.
	for at in [Vector2(13.5,1),Vector2(-13.8,9.2),Vector2(13.5,-2.6)]:
		G.cylinder(self,Vector3(at.x,.51,at.y),.38,1.02,Color("47605f"),-1,.3)
		for y in [.18,.84]:
			G.cylinder(self,Vector3(at.x,y,at.y),.397,.055,Color("829086"),-1,.6)
		G.cylinder(self,Vector3(at.x+.17,1.04,at.y),.067,.04,Color("9ba18b"),-1,.6)
		_solid(at,Vector2(.9,.9))
	for at in [Vector2(-3.9,8.9),Vector2(-2.7,9.2),Vector2(3.8,9.0)]:
		_crate(Vector3(at.x,.35,at.y),Vector3(1.0,.7,.85))
		_solid(at,Vector2(1.15,1.0))
	# Rolled tarps on a low trolley.
	G.box(self,Vector3(4.6,.20,-8.7),Vector3(1.3,.14,1.3),Color("546c6c"),.4)
	for x in [4.2,4.8]:
		G.cylinder(self,Vector3(x,.50,-8.7),.24,1.0,Color("8c8d6c")).rotation.x = PI/2
	_solid(Vector2(4.6,-8.7),Vector2(1.5,1.5))
	G.cylinder(self,Vector3(-14.6,.62,.7),.15,.80,Color("a95d5b"),-1,.3)
	G.rod(self,Vector3(-14.6,1.04,.7),Vector3(-14.6,1.23,.7),.028,Color("d0bb99"),.7)
	G.box(self,Vector3(-14.6,.65,.86),Vector3(.20,.28,.01),Color("dbcab4"))
	# A wall clock, service placard, framed evacuation plan and taped floor wiring.
	G.cylinder(self,Vector3(-7.0,2.16,-10.50),.32,.08,Color("a8b2a8"),-1,.5).rotation.x = PI/2
	G.cylinder(self,Vector3(-7.0,2.16,-10.45),.27,.02,Color("d7d5bc")).rotation.x = PI/2
	G.rod(self,Vector3(-7,2.16,-10.42),Vector3(-7,2.36,-10.42),.012,Color("384d57"))
	G.rod(self,Vector3(-7,2.16,-10.42),Vector3(-6.85,2.10,-10.42),.012,Color("384d57"))
	for i in range(5):
		G.rod(self,Vector3(-13.8+i*.7,.06,6.6),Vector3(-13.1+i*.7,.06,6.6+sin(i)*.08),.022,Color("343b3b"))
	# Scattered scraps, chipped concrete and hairline cracks make scale and wear legible.
	for i in range(24):
		var x := -4.7+fmod(i*2.918,9.7)
		var z := -9.2+fmod(i*1.613,18.2)
		var chip := G.box(self,Vector3(x,.035,z),Vector3(.10+fmod(i*.037,.2),.014,.055),Color("87928c").darkened((i%4)*.04))
		chip.rotation.y = i*1.27
	for at in [Vector2(-3.2,4.4),Vector2(3.8,-1.1),Vector2(4.5,6.7),Vector2(-.7,8.6)]:
		G.rod(self,Vector3(at.x,.035,at.y),Vector3(at.x+.28,.035,at.y+.31),.008,Color("37474e"))
		G.rod(self,Vector3(at.x+.28,.035,at.y+.31),Vector3(at.x+.54,.035,at.y+.38),.007,Color("37474e"))
		G.rod(self,Vector3(at.x+.28,.035,at.y+.31),Vector3(at.x+.18,.035,at.y+.53),.005,Color("37474e"))

func _wire_fence(at: Vector2, length: float) -> void:
	var color := Color("718483")
	for z in [at.y-length*.5,at.y+length*.5]:
		G.rod(self,Vector3(at.x,0,z),Vector3(at.x,1.68,z),.045,color,.5)
	for y in [.18,1.60]:
		G.rod(self,Vector3(at.x,y,at.y-length*.5),Vector3(at.x,y,at.y+length*.5),.033,color,.5)
	var start_z := at.y-length*.5
	for i in range(25):
		var z0 := start_z-.9+i*.22
		for direction in [-1,1]:
			var bottom := Vector2(z0,.18)
			var top := Vector2(z0+direction*.86,1.60)
			var low: float = maxf(start_z,minf(bottom.x,top.x))
			var high: float = minf(start_z+length,maxf(bottom.x,top.x))
			if low >= high:
				continue
			var y1 := lerpf(bottom.y,top.y,(low-bottom.x)/(top.x-bottom.x))
			var y2 := lerpf(bottom.y,top.y,(high-bottom.x)/(top.x-bottom.x))
			G.rod(self,Vector3(at.x,y1,low),Vector3(at.x,y2,high),.009,color,.3)
	_solid(at,Vector2(.23,length+.1))

func _table(at: Vector2, size: Vector2, height: float, color: Color) -> void:
	G.box(self,Vector3(at.x,height,at.y),Vector3(size.x,.14,size.y),color)
	G.box(self,Vector3(at.x,height-.11,at.y),Vector3(size.x-.1,.10,size.y-.1),STEEL,.5)
	for x in [-1,1]:
		for z in [-1,1]:
			G.box(self,Vector3(at.x+x*(size.x*.5-.12),height*.5,at.y+z*(size.y*.5-.12)),Vector3(.09,height,.09),Color("5a6a65"),.5)
	_solid(at,size+Vector2(.15,.15))

func _desk_lamp(at: Vector3, color: Color) -> void:
	G.cylinder(self,at+Vector3(0,.04,0),.16,.06,Color("3a4e4c"),-1,.4)
	G.rod(self,at+Vector3(0,.06,0),at+Vector3(0,.49,-.06),.025,Color("9aa089"),.6)
	G.rod(self,at+Vector3(0,.49,-.06),at+Vector3(.26,.67,-.06),.025,Color("9aa089"),.6)
	G.cylinder(self,at+Vector3(.26,.65,-.06),.14,.17,Color("64765e"),.07,.3)
	G.cylinder(self,at+Vector3(.26,.56,-.06),.12,.016,color)
	_light(at+Vector3(.26,.48,-.06),color,.7,2.6)

func _crate(at: Vector3, size: Vector3) -> void:
	G.box(self,at,size,Color("7d7d63"))
	for x in [-1,1]:
		G.box(self,at+Vector3(x*size.x*.30,0,0),Vector3(.065,size.y+.025,size.z+.035),Color("a49a77"))
	G.box(self,at+Vector3(0,0,size.z*.5+.01),Vector3(size.x*.37,size.y*.31,.02),Color("c5bda0"))
	G.box(self,at+Vector3(0,size.y*.5+.015,0),Vector3(size.x+.025,.04,size.z+.025),Color("8d8c6d"))

func _gun_display(at: Vector3, angle: float) -> void:
	var gun := Node3D.new()
	gun.position = at
	gun.rotation.y = angle
	add_child(gun)
	G.box(gun,Vector3.ZERO,Vector3(.15,.13,.7),Color("303d40"),.6)
	G.rod(gun,Vector3(0,0,-.3),Vector3(0,0,-.75),.025,Color("65736c"),.6)
	G.box(gun,Vector3(0,0,.44),Vector3(.13,.11,.26),Color("796951"))
	G.box(gun,Vector3(.1,.015,.05),Vector3(.19,.06,.12),Color("576556"))

func _npc(at: Vector2, tint: Color, title: String, aim: Vector2, gear: bool) -> void:
	var duck := Duck.new()
	add_child(duck)
	duck.setup(tint,title)
	duck.update_actor({"pos":at,"aim":aim},.016)
	duck.weapon.visible = false
	duck.backpack.visible = false
	if not gear:
		duck.helmet.visible = false
	duck.enable_idle({"pos":at,"aim":aim,"equipment":{"weapon":{},"backpack":{},"helmet":{"kind":"helmet"} if gear else {},"armor":{"kind":"armor"}}})
	duck.scale = Vector3.ONE*.92
	_solid(at,Vector2(.7,.7))

func _sign(value: String, at: Vector3, color: Color) -> void:
	G.box(self,at-Vector3(0,0,.04),Vector3(3.2,.42,.08),Color("34454e"),.3)
	G.text(self,value,at+Vector3(0,0,.02),29,color)

func _light(at: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.35
	light.shadow_enabled = false
	add_child(light)
	lamps.append(light)
