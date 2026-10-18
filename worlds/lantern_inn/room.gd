extends Node3D
## Single-floor, cutaway alchemist inn. All gameplay remains on y = 0.
## Decorative geometry is deliberately separate from gameplay collision.

var _built := false
var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _flames: Array[MeshInstance3D] = []
var _clock := 0.0

const WOOD = Color("805033")
const HONEY = Color("bc8550")
const DARK_WOOD = Color("48332b")
const GOLD = Color("d5ad61")
const TEAL = Color("407b7c")
const STONE = Color("46536a")
const CREAM = Color("eedab0")
const INK = Color("273943")

static func obstacles() -> Array[Rect2]:
	return [
		Rect2(-10.7, -7.75, 8.2, 1.35),
		Rect2(-10.7, -5.5, 1.1, 4.7),
		Rect2(-7.6, -2.9, 3.0, 1.4),
		Rect2(-4.3, 0.5, 3.6, 1.6),
		Rect2(-9.5, 5.45, 5.6, 1.3),
		Rect2(3.3, -7.7, 3.1, 1.5),
		Rect2(6.7, -6.6, 3.8, 1.4),
		Rect2(9.5, -3.7, 1.2, 3.0),
		Rect2(3.35, -3.75, 1.9, 1.9),
		Rect2(2.15, 2.6, 1.7, 1.4),
		Rect2(-10.6, 2.2, 1.4, 2.2),
	]

func _ready() -> void:
	build()
	build_collision()
	if get_tree().current_scene == self:
		var preview = load("res://worlds/lantern_inn/raid_view.gd").new()
		add_child(preview)
		preview.setup_environment()
		preview.create_extraction()

func build_collision() -> void:
	var regions := obstacles()
	regions.append_array([
		Rect2(-11.75, -8.75, 1.0, 17.5), Rect2(10.75, -8.75, 1.0, 17.5),
		Rect2(-11.75, -8.75, 23.5, 1.0), Rect2(-11.75, 7.75, 23.5, 1.0)])
	for rect in regions:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 2
		var shape := BoxShape3D.new()
		shape.size = Vector3(rect.size.x, 2.0, rect.size.y)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.position = Vector3(rect.get_center().x, 1.0, rect.get_center().y)
		body.add_child(collider)
		add_child(body)

func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 17636
	build_floor()
	build_walls()
	_build_library()
	_build_alchemy()
	_build_tavern()
	_build_entrance()
	_build_scatter()
	_batch_static_meshes()

func _batch_static_meshes() -> void:
	# Keep the hand-built detail, but submit one static mesh per shared material.
	var batches: Dictionary = {}
	var materials: Dictionary = {}
	for child in get_children():
		if not child is MeshInstance3D or child in _flames:
			continue
		var instance := child as MeshInstance3D
		if instance.mesh is ImmediateMesh:
			continue
		var material := instance.material_override
		var key := material.get_instance_id()
		if not batches.has(key):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = surface
			materials[key] = material
		var batch: SurfaceTool = batches[key]
		batch.append_from(instance.mesh,0,instance.transform)
		instance.free()
	for key in batches:
		var batch: SurfaceTool = batches[key]
		var instance := MeshInstance3D.new()
		instance.mesh = batch.commit()
		instance.material_override = materials[key]
		add_child(instance)

func _process(delta: float) -> void:
	_clock += delta
	for i in _flames.size():
		var f := _flames[i]
		f.scale.y = 1.0 + sin(_clock * 4.0 + float(i) * 1.9) * 0.09

func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := str(color) + ":" + str(glow)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.88
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m

func _mesh(mesh: Mesh, pos: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _material(color, glow)
	n.position = pos
	add_child(n)
	return n

func _box(pos: Vector3, size: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, pos, color, glow)

func _cyl(pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0, vertices: int = 12, glow: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = vertices
	mesh.rings = 1
	return _mesh(mesh, pos, color, glow)

func _sphere(pos: Vector3, radius: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _mesh(mesh, pos, color, glow)

func _ring(pos: Vector3, inner: float, outer: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 6
	return _mesh(mesh, pos, color)

func _beam(a: Vector3, b: Vector3, width: float, color: Color) -> MeshInstance3D:
	var n := _box((a+b)*0.5, Vector3(width,a.distance_to(b),width),color)
	if abs((b-a).normalized().dot(Vector3.FORWARD)) > 0.98:
		n.look_at_from_position(n.position,b,Vector3.RIGHT)
	else:
		n.look_at_from_position(n.position,b,Vector3.FORWARD)
	n.rotate_object_local(Vector3.RIGHT,PI*0.5)
	return n

func build_floor() -> void:
	# The blue plinth and a continuous dark subfloor make the whole level read as a diorama.
	_box(Vector3(0,-0.57,0),Vector3(22.6,1.08,16.6),Color("273a50"))
	_box(Vector3(0,-0.08,0),Vector3(22.1,0.12,16.1),DARK_WOOD)
	for row in range(25):
		var z := -7.7 + float(row)*0.64
		var stagger := 1.44 if row%2==1 else 0.0
		for col in range(9):
			var start := -11.0 + float(col)*2.9 - stagger
			var end := minf(start+2.88,11.0)
			start = maxf(start,-11.0)
			if end-start < 0.02:
				continue
			var tone := Color("b78049").lerp(Color("d5a363"),snappedf(_rng.randf()*0.85,0.17))
			_box(Vector3((start+end)/2.0,-0.015,z),Vector3(end-start,0.10,0.611),tone)
			if col%2==0 and row%3==0:
				_box(Vector3((start+end)/2.0,0.039,z+0.18),Vector3((end-start)*0.55,0.003,0.012),tone.darkened(0.12))
			if end-start>0.5 and row%2==0:
				for x in [start+0.12,end-0.12]:
					_cyl(Vector3(x,0.043,z+0.19),0.018,0.008,DARK_WOOD, -1,6)
	# Broad timbers divide the library, study, and taproom without raised floors.
	for x in [-10.8,-1.3,10.8]:
		_box(Vector3(x,0.052,0),Vector3(0.16,0.055,16.1),WOOD)
	for z in [-7.8,-0.1,7.7]:
		_box(Vector3(0,0.054,z),Vector3(22.1,0.055,0.15),WOOD)
	for i in range(15):
		var x := -10.5 + float(i)*1.5
		_box(Vector3(x,-0.5,8.23),Vector3(1.43,0.83,0.35),STONE.lightened(snappedf(_rng.randf()*0.11,0.05)))
		_box(Vector3(x,-0.5,-8.23),Vector3(1.43,0.83,0.35),STONE)
	for i in range(11):
		var z := -7.5 + float(i)*1.5
		_box(Vector3(11.23,-0.5,z),Vector3(0.35,0.83,1.43),STONE)
		_box(Vector3(-11.23,-0.5,z),Vector3(0.35,0.83,1.43),STONE)
	_box(Vector3(0,-0.03,8.18),Vector3(22.65,0.17,0.35),Color("826443"))
	_box(Vector3(11.18,-0.03,0),Vector3(0.35,0.17,16.65),Color("826443"))
	_rug(Vector3(-6.05,0.07,-2.2),Vector2(5.3,4.8),Color("365c65"),GOLD)
	_rug(Vector3(-2.4,0.07,1.3),Vector2(5.2,3.5),Color("8e3d3a"),Color("ce9c5c"))
	_rug(Vector3(4.2,0.07,-2.8),Vector2(4.3,4.0),Color("454f65"),Color("ba9c64"))
	_rug(Vector3(7.65,0.07,5.5),Vector2(4.6,3.5),Color("98453d"),Color("d0ae66"))

func _rug(pos: Vector3, size: Vector2, main: Color, edge: Color) -> void:
	_box(pos,Vector3(size.x,0.025,size.y),edge)
	_box(pos+Vector3(0,0.016,0),Vector3(size.x-0.15,0.015,size.y-0.15),main)
	_box(pos+Vector3(0,0.027,0),Vector3(size.x-0.44,0.009,size.y-0.44),edge.darkened(0.15))
	_box(pos+Vector3(0,0.035,0),Vector3(size.x-0.51,0.009,size.y-0.51),main)
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var n := _box(pos+Vector3(sx*(size.x/2.0-0.52),0.045,sz*(size.y/2.0-0.52)),Vector3(0.23,0.012,0.23),edge)
			n.rotation.y=PI/4.0
	for i in range(int(size.x/0.13)):
		var x := -size.x*0.5 + float(i)*0.13
		for sign_z in [-1,1]:
			_box(pos+Vector3(x,0.004,sign_z*(size.y*0.5+0.065)),Vector3(0.045,0.013,0.13),edge)

func build_walls() -> void:
	# Only the north and west sides are full height; the near sides are cut away.
	_box(Vector3(0,2.0,-8.0),Vector3(22.2,4.0,0.28),Color("527b78"))
	_box(Vector3(-11.0,2.0,-2.1),Vector3(0.28,4.0,11.8),Color("658d82"))
	_box(Vector3(0,0.55,-7.80),Vector3(22.1,1.10,0.14),WOOD)
	_box(Vector3(-10.79,0.55,-2.1),Vector3(0.14,1.1,11.8),WOOD)
	for x in range(-10,11):
		_box(Vector3(float(x),0.55,-7.69),Vector3(0.045,0.96,0.05),HONEY)
	for z in range(-7,4):
		_box(Vector3(-10.70,0.55,float(z)),Vector3(0.04,0.96,0.045),HONEY)
	for y in [0.14,1.12,3.98]:
		_box(Vector3(0,y,-7.77),Vector3(22.4,0.18,0.35),DARK_WOOD)
		_box(Vector3(-10.81,y,-2.15),Vector3(0.35,0.18,12.1),DARK_WOOD)
	for x in [-10.85,-7.8,-2.5,2.5,6.55,10.85]:
		_box(Vector3(x,2.08,-7.75),Vector3(0.28,4.25,0.4),DARK_WOOD)
		_box(Vector3(x,1.05,-7.51),Vector3(0.39,0.16,0.42),HONEY)
		_box(Vector3(x,3.75,-7.51),Vector3(0.4,0.18,0.42),HONEY)
	for z in [-7.75,-4.6,-0.3,3.7]:
		_box(Vector3(-10.78,2.05,z),Vector3(0.4,4.2,0.28),DARK_WOOD)
		_box(Vector3(-10.55,1.06,z),Vector3(0.4,0.16,0.4),HONEY)
	# Slim timber braces frame the rooms; they do not create another floor.
	for x in [-10.65,-2.5,2.5,10.65]:
		_beam(Vector3(x,3.95,-7.45),Vector3(x+0.75,3.15,-7.45),0.16,WOOD)
	for z in [-4.6,-0.3,3.6]:
		_beam(Vector3(-10.45,3.95,z),Vector3(-10.45,3.10,z+0.9),0.16,WOOD)
	# Small cutaway side masonry gives a finished silhouette without hiding characters.
	for z in [-7.4,-6.6,-5.8,-5.0,-4.2]:
		_box(Vector3(10.97,0.31,z),Vector3(0.36,0.64,0.75),STONE.lightened(snappedf(_rng.randf()*0.09,0.05)))
	_round_window(Vector3(0.0,2.55,-7.61),1.08)
	_banner(Vector3(-2.82,2.92,-7.40),TEAL)
	_banner(Vector3(2.79,2.92,-7.40),Color("6a394c"))
	for p in [Vector3(-8.0,2.5,-7.25),Vector3(2.5,2.6,-7.25),Vector3(9.9,2.6,-7.2),Vector3(-10.3,2.5,2.7)]:
		_lantern(p,true)

func _round_window(pos: Vector3, radius: float) -> void:
	var disk := _cyl(pos,radius,0.08,Color("192d49"),-1,32)
	disk.rotation.x=PI*0.5
	for i in range(12):
		var a := TAU*float(i)/12.0
		var b := TAU*float(i+1)/12.0
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.surface_add_vertex(Vector3(0,0,0))
		mesh.surface_add_vertex(Vector3(cos(a)*radius*0.88,sin(a)*radius*0.88,0))
		mesh.surface_add_vertex(Vector3(cos(b)*radius*0.88,sin(b)*radius*0.88,0))
		mesh.surface_end()
		var c: Color = [Color("97b7a4"),Color("d7c48d"),Color("529094"),Color("bc7861")][i%4]
		var glass := _mesh(mesh,pos+Vector3(0,0,0.06),c,0.30)
		glass.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam(pos+Vector3(0,0,0.08),pos+Vector3(cos(a)*radius*0.92,sin(a)*radius*0.92,0.08),0.045,DARK_WOOD)
	var ring := _ring(pos+Vector3(0,0,0.08),radius*0.91,radius*1.08,WOOD)
	ring.rotation.x=PI*0.5
	var gold_ring := _ring(pos+Vector3(0,0,0.13),radius*0.89,radius*0.93,GOLD)
	gold_ring.rotation.x=PI*0.5
	var center := _cyl(pos+Vector3(0,0,0.14),radius*0.25,0.05,GOLD,-1,16,0.25)
	center.rotation.x=PI*0.5
	_box(pos+Vector3(0,-radius-0.13,0.13),Vector3(radius*2.5,0.15,0.4),HONEY)

func _banner(pos: Vector3,color: Color) -> void:
	_box(pos,Vector3(0.64,1.35,0.06),color)
	_box(pos+Vector3(0,0.71,0),Vector3(0.85,0.09,0.1),GOLD)
	_box(pos+Vector3(0,-0.63,0.035),Vector3(0.56,0.04,0.04),GOLD)
	var mark := _box(pos+Vector3(0,-0.05,0.045),Vector3(0.23,0.23,0.02),GOLD)
	mark.rotation.z=PI/4.0

func _build_library() -> void:
	_shelf(Vector3(-6.65,0,-7.0),Vector2(7.7,0.95),3.25,true)
	# West shelving turns a quiet reading corner into a distinct room.
	_shelf_side(Vector3(-10.05,0,-3.15),4.2)
	_table(Vector3(-6.1,0,-2.2),Vector2(3.0,1.4),1.07)
	_open_book(Vector3(-6.5,1.19,-2.3),0.65,0.18)
	_book_stack(Vector3(-5.2,1.21,-2.35),3)
	_candle(Vector3(-7.1,1.18,-2.4),0.33)
	_bottle(Vector3(-5.6,1.19,-2.6),Color("6aa295"),0.62)
	_inkpot(Vector3(-6.0,1.20,-1.8))
	_stool(Vector3(-6.3,0,-3.25),0.7)
	_stool(Vector3(-6.4,0,-1.18),0.7)
	# Rolled maps and a brass armillary are recognizable at game distance.
	for i in range(4):
		var roll := _cyl(Vector3(-3.35+float(i)*0.13,1.34,-6.62),0.075,0.55,CREAM,-1,8)
		roll.rotation.x=PI*0.5
	_armillary(Vector3(-4.0,2.28,-6.72),0.42)
	_lantern(Vector3(-6.8,2.1,-0.4),false)

func _shelf(pos: Vector3,size: Vector2,height: float,books: bool) -> void:
	_box(pos+Vector3(0,height*0.5,-size.y*0.41),Vector3(size.x,height,0.15),DARK_WOOD)
	for x in [-size.x*0.5,size.x*0.5]:
		_box(pos+Vector3(x,height*0.5,0),Vector3(0.16,height+0.12,size.y),WOOD)
	for y in [0.16,0.95,1.75,2.55,height]:
		_box(pos+Vector3(0,y,0),Vector3(size.x+0.18,0.12,size.y+0.06),HONEY)
		_box(pos+Vector3(0,y-0.05,size.y*0.48),Vector3(size.x+0.20,0.13,0.08),WOOD)
	for x in [-size.x*0.165,size.x*0.165]:
		_box(pos+Vector3(x,height*0.5,0),Vector3(0.12,height,size.y),WOOD)
	var palette: Array[Color] = [Color("7d363e"),Color("487873"),Color("354d67"),Color("c5a567"),Color("91705c")]
	for row in range(4):
		var y := 0.23 + float(row)*0.8
		var x := -size.x*0.5+0.23
		while x < size.x*0.5-0.2:
			var width := _rng.randf_range(0.13,0.25)
			if books and _rng.randf() > 0.16:
				var h := _rng.randf_range(0.41,0.63)
				var c := palette[_rng.randi_range(0,palette.size()-1)]
				_box(pos+Vector3(x,y+h*0.5,size.y*0.10),Vector3(width,h,size.y*0.57),c)
				for yy in [y+0.09,y+h-0.09]:
					_box(pos+Vector3(x,yy,size.y*0.40),Vector3(width*0.8,0.022,0.018),GOLD)
				x += width + _rng.randf_range(0.03,0.08)
			else:
				_bottle(pos+Vector3(x,y,size.y*0.11),palette[_rng.randi_range(0,palette.size()-1)].lightened(0.15),0.64)
				x += 0.42

func _shelf_side(pos: Vector3,length: float) -> void:
	_box(pos+Vector3(-0.4,1.55,0),Vector3(0.12,3.1,length),DARK_WOOD)
	for z in [-length*0.5,0.0,length*0.5]:
		_box(pos+Vector3(0,1.55,z),Vector3(0.9,3.1,0.13),WOOD)
	for y in [0.16,0.95,1.75,2.55,3.1]:
		_box(pos+Vector3(0,y,0),Vector3(1.0,0.12,length+0.12),HONEY)
	for row in range(4):
		for j in range(11):
			var y := 0.24 + float(row)*0.80
			var z := -length*0.5+0.25+float(j)*0.35
			if j%4==0:
				_bottle(pos+Vector3(0.09,y,z),Color("719c8b"),0.66)
			else:
				var h := _rng.randf_range(0.42,0.60)
				var c: Color = [Color("855c48"),Color("57726c"),Color("9a5848")][j%3]
				_box(pos+Vector3(0.07,y+h*0.5,z),Vector3(0.56,h,0.22),c)
				_box(pos+Vector3(0.36,y+0.12,z),Vector3(0.02,0.028,0.18),GOLD)

func _build_alchemy() -> void:
	_fireplace(Vector3(4.85,0,-6.95))
	_table(Vector3(8.6,0,-5.9),Vector2(3.8,1.4),1.2)
	_box(Vector3(8.6,1.31,-5.9),Vector3(3.9,0.12,1.5),Color("738576"))
	for i in range(6):
		_bottle(Vector3(7.2+float(i)*0.48,1.4,-6.1),[Color("70b19a"),Color("a26d99"),Color("d2a458")][i%3],_rng.randf_range(0.72,1.15))
	_alembic(Vector3(8.9,1.4,-5.7))
	_open_book(Vector3(7.7,1.4,-5.45),0.50,-0.18)
	_shelf(Vector3(8.7,1.8,-7.2),Vector2(3.5,0.55),1.8,false)
	# Long side cabinet is waist high, preserving the east-side view.
	_box(Vector3(10.1,0.65,-2.2),Vector3(1.1,1.3,3.0),WOOD)
	_box(Vector3(10.1,1.34,-2.2),Vector3(1.3,0.15,3.15),Color("a8784a"))
	for z in [-3.2,-2.2,-1.2]:
		_box(Vector3(9.52,0.68,z),Vector3(0.035,0.88,0.86),HONEY)
		_sphere(Vector3(9.48,0.82,z),0.055,GOLD)
		_bottle(Vector3(10.05,1.42,z),Color("8da18d"),1.0)
	_cauldron(Vector3(4.3,0,-2.8))
	_candle(Vector3(9.9,1.42,-1.65),0.36)
	for x in [6.9,10.2]:
		_herbs(Vector3(x,3.7,-7.15))
	_barrel(Vector3(10.1,0,-4.3),0.48,0.95)

func _fireplace(pos: Vector3) -> void:
	_box(pos+Vector3(0,0.12,0.24),Vector3(3.08,0.24,1.88),STONE)
	_box(pos+Vector3(0,1.4,-0.35),Vector3(2.8,2.65,0.6),Color("796e61"))
	_box(pos+Vector3(0,0.98,0.02),Vector3(1.75,1.8,0.15),Color("25252c"))
	for side in [-1.0,1.0]:
		for row in range(5):
			_box(pos+Vector3(side*1.07,0.40+float(row)*0.35,0.25),Vector3(0.51,0.31,0.85),Color("9b8d76").lightened(float(row%2)*0.06))
	for i in range(7):
		var angle := PI*float(i)/6.0
		var n := _box(pos+Vector3(cos(angle)*0.98,1.65+sin(angle)*0.60,0.25),Vector3(0.43,0.4,0.88),Color("b0a084"))
		n.rotation.z=angle-PI*0.5
	_box(pos+Vector3(0,2.50,0.08),Vector3(3.10,0.23,1.05),WOOD)
	_box(pos+Vector3(0,3.30,-0.35),Vector3(1.85,1.35,0.7),Color("ad9c81"))
	for row in range(4):
		_box(pos+Vector3(0,2.78+float(row)*0.32,0.012),Vector3(1.8,0.025,0.025),Color("897d6d"))
	for x in [-0.49,0.35]:
		var log := _cyl(pos+Vector3(x,0.34,0.30),0.17,1.1,DARK_WOOD,-1,9)
		log.rotation.z=PI*0.5
		log.rotation.y=0.3 if x<0 else -0.35
	for i in range(5):
		var x := -0.56+float(i)*0.28
		var flame := _sphere(pos+Vector3(x,0.7+_rng.randf()*0.13,0.32),0.23,Color("ffb548"),1.4)
		flame.scale=Vector3(0.75,1.7,0.70)
		_flames.append(flame)
		_cyl(pos+Vector3(x,0.95,0.32),0.19,0.6,Color("ffd382"),0.02,7,1.2)
	_local_light(pos+Vector3(0,1.1,1.1),Color("ff9b45"),2.8,5.0)
	_candle(pos+Vector3(-1.1,2.64,0.15),0.35)
	_candle(pos+Vector3(1.1,2.64,0.15),0.45)

func _cauldron(pos: Vector3) -> void:
	_cyl(pos+Vector3(0,0.12,0),0.92,0.24,STONE,-1,12)
	for i in range(8):
		var a := TAU*float(i)/8.0
		var block := _box(pos+Vector3(cos(a)*0.76,0.30,sin(a)*0.76),Vector3(0.5,0.32,0.36),Color("776855"))
		block.rotation.y=-a
	_cyl(pos+Vector3(0,0.78,0),0.65,0.85,Color("594b3e"),0.82,16)
	_ring(pos+Vector3(0,1.19,0),0.73,0.88,Color("9b7751"))
	_cyl(pos+Vector3(0,1.17,0),0.74,0.025,Color("8bc3a2"),-1,20,0.35)
	for i in range(7):
		var a := TAU*float(i)/7.0
		_sphere(pos+Vector3(cos(a)*0.43,1.20,sin(a)*0.43),0.055+_rng.randf()*0.04,Color("b7e5af"),0.25)
	for side in [-1.0,1.0]:
		var handle := _ring(pos+Vector3(side*0.88,0.9,0),0.15,0.21,Color("a78254"))
		handle.rotation.x=PI*0.5
	var spoon := _cyl(pos+Vector3(0.40,1.48,0.05),0.055,1.15,WOOD,-1,8)
	spoon.rotation.z=-0.40
	_wood_bucket(pos+Vector3(1.18,0,-0.4))

func _build_tavern() -> void:
	_table(Vector3(-2.5,0,1.3),Vector2(3.6,1.6),0.98)
	for p in [Vector3(-3.5,0,0.22),Vector3(-1.4,0,0.22),Vector3(-3.5,0,2.42),Vector3(-1.4,0,2.42)]:
		_stool(p,0.65)
	for p in [Vector3(-3.5,1.1,0.95),Vector3(-1.4,1.1,1.65)]:
		_plate(p)
	_mug(Vector3(-3.0,1.10,1.6))
	_mug(Vector3(-1.0,1.10,1.1))
	_bottle(Vector3(-2.7,1.1,1.2),Color("6c8c72"),0.84)
	_candle(Vector3(-2.2,1.1,1.55),0.34)
	_bread(Vector3(-1.8,1.14,0.98))
	# Front counter has framed panels and a foot rail, low enough to see behind.
	_box(Vector3(-6.7,0.64,6.1),Vector3(5.6,1.28,1.30),WOOD)
	_box(Vector3(-6.7,1.32,6.1),Vector3(5.88,0.20,1.52),Color("ac7548"))
	_box(Vector3(-6.7,1.43,6.1),Vector3(5.82,0.03,1.46),HONEY)
	for i in range(5):
		var x := -8.94+float(i)*1.12
		_box(Vector3(x,0.64,6.765),Vector3(0.98,0.96,0.07),DARK_WOOD)
		_box(Vector3(x,0.64,6.81),Vector3(0.82,0.80,0.05),Color("966744"))
		var n := _box(Vector3(x,0.64,6.85),Vector3(0.20,0.20,0.025),GOLD.darkened(0.1))
		n.rotation.z=PI/4.0
	_beam(Vector3(-9.35,0.30,7.04),Vector3(-4.05,0.30,7.04),0.08,GOLD)
	for x in [-9.15,-4.3]:
		_beam(Vector3(x,0.15,6.72),Vector3(x,0.30,7.06),0.07,GOLD)
	for i in range(4):
		_mug(Vector3(-8.3+float(i)*0.49,1.46,5.85))
	_plate(Vector3(-5.0,1.46,6.2))
	_bread(Vector3(-5.1,1.49,6.15))
	_candle(Vector3(-8.9,1.45,6.13),0.30)
	_bottle(Vector3(-6.0,1.46,6.25),Color("789b7c"),1.0)
	_barrel(Vector3(-9.97,0,5.6),0.56,1.15)
	_barrel(Vector3(-9.97,0,6.9),0.56,1.15)
	_table(Vector3(3.0,0,3.3),Vector2(1.7,1.4),0.88)
	_plate(Vector3(3.3,1.0,3.35))
	_mug(Vector3(2.7,1.0,3.0))
	_candle(Vector3(3.1,1.0,2.95),0.30)
	_stool(Vector3(2.0,0,3.2),0.6)
	_stool(Vector3(4.0,0,3.3),0.6)

func _build_entrance() -> void:
	# The threshold and stone arch hint at the next street while leaving the view open.
	_box(Vector3(8.0,0.03,7.78),Vector3(3.8,0.10,0.8),Color("b6a481"))
	for x in [6.0,10.0]:
		for row in range(3):
			_box(Vector3(x,0.2+float(row)*0.38,7.73),Vector3(0.65,0.35,0.65),STONE.lightened(0.15+float(row)*0.03))
		_cyl(Vector3(x,1.35,7.73),0.31,0.20,Color("adb0a0"),-1,8)
	_lantern(Vector3(10.05,2.0,7.73),true)
	# Carved compass inlay guides the eye towards the extraction rug; no gameplay glow.
	for i in range(8):
		var a := TAU*float(i)/8.0
		var marker := _box(Vector3(7.9+sin(a)*1.07,0.13,5.55+cos(a)*1.07),Vector3(0.09,0.012,0.35),GOLD)
		marker.rotation.y=a
	var compass := _ring(Vector3(7.9,0.13,5.55),0.64,0.68,Color("caa05e"))
	compass.scale.y=0.15
	# Empty side bench and mail shelf avoid obstructing the extraction circle.
	_box(Vector3(10.0,0.48,3.0),Vector3(1.10,0.15,2.4),WOOD)
	for z in [2.1,3.9]:
		_box(Vector3(10.0,0.24,z),Vector3(0.8,0.48,0.16),DARK_WOOD)
	_book_stack(Vector3(10.0,0.57,2.3),2)

func _build_scatter() -> void:
	_crate(Vector3(-9.95,0,2.85),Vector3(1.2,0.95,1.15))
	_crate(Vector3(-9.85,0.97,2.85),Vector3(0.94,0.75,0.91))
	_crate(Vector3(-9.95,0,3.9),Vector3(1.20,0.72,0.87))
	_bottle(Vector3(-9.95,1.76,2.8),Color("a37686"),0.65)
	# Planters on wall ledges and a faded wall map add narrative texture.
	_planter(Vector3(-10.15,1.15,0.55),0.46)
	_box(Vector3(-10.64,2.63,1.1),Vector3(0.07,1.25,1.70),DARK_WOOD)
	_box(Vector3(-10.59,2.63,1.1),Vector3(0.04,1.10,1.53),Color("d0bd8b"))
	for i in range(6):
		var line := _box(Vector3(-10.56,2.25+float(i)*0.14,1.1),Vector3(0.02,0.028,1.1-_rng.randf()*0.4),Color("a48f68"))
		line.rotation.x=_rng.randf_range(-0.18,0.18)
	for p in [Vector3(-8.8,0.12,-0.2),Vector3(-0.2,0.12,-5.8),Vector3(6.5,0.12,2.2)]:
		var paper := _box(p,Vector3(0.43,0.012,0.59),CREAM.darkened(0.08))
		paper.rotation.y=_rng.randf_range(-0.4,0.4)
	# Rear transom sign, brass corners, and suspended twine.
	_box(Vector3(-6.4,3.72,-7.22),Vector3(2.65,0.59,0.11),DARK_WOOD)
	_box(Vector3(-6.4,3.72,-7.14),Vector3(2.43,0.43,0.06),Color("b88a51"))
	for x in [-7.47,-5.33]:
		_sphere(Vector3(x,3.72,-7.08),0.06,GOLD)
	# A stylized gilded open-book crest instead of tiny unreadable lettering.
	var a := _box(Vector3(-6.68,3.72,-7.08),Vector3(0.45,0.27,0.03),CREAM)
	a.rotation.z=0.12
	var b := _box(Vector3(-6.20,3.72,-7.08),Vector3(0.45,0.27,0.03),CREAM)
	b.rotation.z=-0.12

func _table(pos: Vector3,size: Vector2,height: float) -> void:
	for x in [-size.x*0.38,size.x*0.38]:
		for z in [-size.y*0.32,size.y*0.32]:
			_box(pos+Vector3(x,height*0.47,z),Vector3(0.15,height*0.94,0.15),DARK_WOOD)
	_box(pos+Vector3(0,height*0.78,0),Vector3(size.x-0.10,0.22,size.y-0.10),WOOD)
	for i in range(4):
		_box(pos+Vector3(0,height,float(i)*size.y/4.0-size.y*0.375),Vector3(size.x+0.14,0.16,size.y/4.0-0.015),HONEY.lightened(float(i%2)*0.05))
	for x in [-size.x*0.45,size.x*0.45]:
		for z in [-size.y*0.36,size.y*0.36]:
			_cyl(pos+Vector3(x,height+0.084,z),0.027,0.01,DARK_WOOD,-1,6)

func _stool(pos: Vector3,height: float) -> void:
	for i in range(3):
		var a := TAU*float(i)/3.0
		_beam(pos+Vector3(cos(a)*0.26,0.03,sin(a)*0.26),pos+Vector3(cos(a)*0.2,height,sin(a)*0.2),0.10,DARK_WOOD)
	_cyl(pos+Vector3(0,height,0),0.38,0.13,HONEY,-1,12)
	_ring(pos+Vector3(0,height*0.43,0),0.21,0.25,WOOD)

func _bottle(pos: Vector3,color: Color,scale_factor: float=1.0) -> void:
	var s := scale_factor
	_cyl(pos+Vector3(0,0.18*s,0),0.16*s,0.36*s,color,0.135*s,10)
	_cyl(pos+Vector3(0,0.39*s,0),0.135*s,0.11*s,color,0.060*s,10)
	_cyl(pos+Vector3(0,0.51*s,0),0.060*s,0.16*s,color,-1,8)
	_cyl(pos+Vector3(0,0.60*s,0),0.065*s,0.06*s,Color("ab8b63"),-1,8)
	_box(pos+Vector3(0,0.19*s,0.146*s),Vector3(0.16*s,0.16*s,0.016),CREAM)
	_box(pos+Vector3(0,0.19*s,0.16*s),Vector3(0.055*s,0.06*s,0.009),color.darkened(0.26))

func _candle(pos: Vector3,height: float) -> void:
	_cyl(pos+Vector3(0,0.025,0),0.15,0.05,GOLD,-1,12)
	_cyl(pos+Vector3(0,height*0.5+0.05,0),0.07,height,CREAM,-1,10)
	var f := _sphere(pos+Vector3(0,height+0.12,0),0.068,Color("ffe0a1"),1.2)
	f.scale=Vector3(0.65,1.7,0.65)
	_flames.append(f)

func _lantern(pos: Vector3,light: bool) -> void:
	_box(pos+Vector3(0,0.24,0),Vector3(0.44,0.1,0.44),DARK_WOOD)
	_box(pos+Vector3(0,-0.22,0),Vector3(0.44,0.1,0.44),DARK_WOOD)
	_box(pos,Vector3(0.32,0.40,0.32),Color("ffd38c"),0.85)
	for x in [-0.18,0.18]:
		for z in [-0.18,0.18]:
			_box(pos+Vector3(x,0,z),Vector3(0.04,0.48,0.04),Color("745636"))
	_cyl(pos+Vector3(0,0.36,0),0.34,0.20,Color("836647"),0.09,4)
	var ring := _ring(pos+Vector3(0,0.55,0),0.075,0.11,GOLD)
	ring.rotation.x=PI*0.5
	if light:
		_local_light(pos+Vector3(0,-0.15,0.25),Color("ffd394"),1.6,4.3)

func _local_light(pos: Vector3,color: Color,energy: float,distance: float) -> void:
	var light := OmniLight3D.new()
	light.position=pos
	light.light_color=color
	light.light_energy=energy
	light.omni_range=distance
	light.omni_attenuation=1.8
	light.shadow_enabled=false
	add_child(light)

func _barrel(pos: Vector3,radius: float,height: float) -> void:
	_cyl(pos+Vector3(0,height*0.5,0),radius*0.86,height,WOOD,radius*0.86,14)
	_cyl(pos+Vector3(0,height*0.5,0),radius,height*0.65,HONEY,radius,14)
	for y in [height*0.16,height*0.48,height*0.84]:
		_ring(pos+Vector3(0,y,0),radius*0.91,radius*1.02,INK)
	_cyl(pos+Vector3(0,height+0.005,0),radius*0.86,0.035,Color("a7794e"),-1,14)
	for i in range(4):
		_box(pos+Vector3(0,height+0.026,(float(i)-1.5)*radius*0.36),Vector3(radius*1.5,0.005,0.018),WOOD)

func _crate(pos: Vector3,size: Vector3) -> void:
	_box(pos+Vector3(0,size.y*0.5,0),size,Color("8c6848"))
	for x in [-size.x*0.43,size.x*0.43]:
		for z in [-size.z*0.51,size.z*0.51]:
			_box(pos+Vector3(x,size.y*0.5,z),Vector3(0.14,size.y+0.04,0.08),HONEY)
	for y in [0.08,size.y-0.08]:
		_box(pos+Vector3(0,y,size.z*0.52),Vector3(size.x,0.15,0.08),HONEY)
	_beam(pos+Vector3(-size.x*0.4,0.1,size.z*0.54),pos+Vector3(size.x*0.4,size.y-0.1,size.z*0.54),0.12,HONEY)
	for j in range(3):
		_box(pos+Vector3(0,size.y+0.018,(float(j)-1)*size.z*0.3),Vector3(size.x,0.035,size.z*0.28),HONEY)

func _open_book(pos: Vector3,size: float,angle: float) -> void:
	var cover := _box(pos,Vector3(size*1.8,0.045,size*1.25),Color("623e3a"))
	cover.rotation.y=angle
	for side in [-1.0,1.0]:
		var page := _box(pos+Vector3(side*size*0.43,0.045,0),Vector3(size*0.82,0.04,size*1.13),CREAM)
		page.rotation.z=-side*0.06
		page.rotation.y=angle
		for i in range(4):
			_box(pos+Vector3(side*size*0.43,0.072,float(i)*size*0.18-size*0.3),Vector3(size*0.56,0.007,0.017),Color("9d9276"))

func _book_stack(pos: Vector3,count: int) -> void:
	for i in range(count):
		var c: Color = [Color("6c3e45"),Color("3f6d6b"),Color("af9362")][i%3]
		var y := float(i)*0.13
		_box(pos+Vector3(0,y+0.03,0),Vector3(0.55,0.035,0.39),c)
		_box(pos+Vector3(0,y+0.08,0),Vector3(0.50,0.08,0.35),CREAM.darkened(0.13))
		_box(pos+Vector3(0,y+0.13,0),Vector3(0.55,0.03,0.39),c)

func _plate(pos: Vector3) -> void:
	_cyl(pos+Vector3(0,0.025,0),0.28,0.045,CREAM,-1,18)
	_ring(pos+Vector3(0,0.051,0),0.22,0.27,Color("afc8bc"))

func _mug(pos: Vector3) -> void:
	_cyl(pos+Vector3(0,0.13,0),0.12,0.26,Color("b3c5b9"),0.14,10)
	_cyl(pos+Vector3(0,0.265,0),0.115,0.01,Color("583b29"),-1,10)
	var handle := _ring(pos+Vector3(0.14,0.14,0),0.055,0.09,Color("b3c5b9"))
	handle.rotation.x=PI*0.5

func _bread(pos: Vector3) -> void:
	var loaf := _sphere(pos+Vector3(0,0.12,0),0.24,Color("c89251"))
	loaf.scale=Vector3(1.35,0.55,0.76)
	for i in range(3):
		var mark := _box(pos+Vector3(-0.15+float(i)*0.15,0.235,0),Vector3(0.035,0.015,0.20),Color("f0c684"))
		mark.rotation.y=-0.25

func _inkpot(pos: Vector3) -> void:
	_cyl(pos+Vector3(0,0.08,0),0.10,0.16,INK,0.085,8)
	var feather := _box(pos+Vector3(0.10,0.30,0),Vector3(0.045,0.45,0.015),CREAM)
	feather.rotation.z=-0.45

func _armillary(pos: Vector3,radius: float) -> void:
	_cyl(pos+Vector3(0,0.06,0),radius*0.5,0.12,WOOD,-1,12)
	_cyl(pos+Vector3(0,radius*0.55,0),0.06,radius,GOLD,-1,8)
	var center := pos+Vector3(0,radius*1.4,0)
	for i in range(3):
		var ring := _ring(center,radius*0.91,radius,GOLD)
		ring.rotation=Vector3(0.45+float(i)*0.6,float(i)*0.8,float(i)*0.2)
	_sphere(center,radius*0.3,Color("638c8d"))

func _alembic(pos: Vector3) -> void:
	_sphere(pos+Vector3(0,0.29,0),0.28,Color("b98c5a"))
	_cyl(pos+Vector3(0,0.62,0),0.12,0.48,Color("cfaa72"),0.07,10)
	_beam(pos+Vector3(0,0.86,0),pos+Vector3(0.58,0.48,0),0.09,Color("cfaa72"))
	_bottle(pos+Vector3(0.58,0,0),Color("71aaa2"),0.8)
	for x in [-0.19,0.19]:
		_beam(pos+Vector3(x,0.04,0),pos+Vector3(x,0.35,0),0.05,INK)

func _herbs(pos: Vector3) -> void:
	_beam(pos,pos-Vector3(0,0.50,0),0.025,CREAM)
	for i in range(5):
		var a := TAU*float(i)/5.0
		var leaf := _sphere(pos+Vector3(cos(a)*0.12,-0.55-_rng.randf()*0.20,sin(a)*0.12),0.12,Color("7b9868"))
		leaf.scale=Vector3(0.8,2.0,0.8)

func _planter(pos: Vector3,radius: float) -> void:
	_cyl(pos+Vector3(0,0.25,0),radius*0.7,0.5,Color("ad6f50"),radius,10)
	_cyl(pos+Vector3(0,0.51,0),radius,0.06,DARK_WOOD,-1,10)
	for i in range(7):
		var a := TAU*float(i)/7.0
		var leaf := _sphere(pos+Vector3(sin(a)*radius*0.48,0.7+_rng.randf()*0.25,cos(a)*radius*0.48),radius*0.36,Color("78916b"))
		leaf.scale=Vector3(0.7,2.0,0.8)
		leaf.rotation.z=sin(a)*0.45

func _wood_bucket(pos: Vector3) -> void:
	_cyl(pos+Vector3(0,0.23,0),0.24,0.46,HONEY,0.30,10)
	_ring(pos+Vector3(0,0.39,0),0.275,0.31,INK)
	_cyl(pos+Vector3(0,0.47,0),0.26,0.02,Color("577f7c"),-1,10)
